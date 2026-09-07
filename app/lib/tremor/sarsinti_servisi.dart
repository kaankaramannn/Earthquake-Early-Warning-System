import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/api_client.dart';
import '../location/konum_servisi.dart';
import '../ml/ikinci_katman.dart';

/// Arka planda (uygulama kapalıyken de) çalışan sarsıntı algılama servisi (Faz 3 Parça 4).
/// İvmeölçer dinleme + otomatik rapor gönderme mantığı artık SADECE burada yaşıyor —
/// home_screen.dart kendi dinleyicisini çalıştırmıyor, bu servisin yayınladığı veriyi izliyor
/// (Aşama 4'te bağlanacak; bu dosya tek başına da başlatılıp test edilebilir).
///
/// Yanlış pozitif azaltma (eski Aşama 3): algılama TEK bir anlık ölçüme değil, son ~1 saniyelik
/// bir pencerede örneklerin ÇOĞUNLUĞUNUN eşiği geçmesine bakıyor (bkz. `_sarsintiKontrolEt`).
/// Böylece telefonun düşmesi/masaya vurulması gibi TEK VE KISA darbeler (pencerede 1-2 örnek)
/// gerçek, SÜREN bir sarsıntıdan (pencerenin çoğunluğu eşik üstü) ayrıştırılıyor.
///
/// P-dalgası hassasiyeti (yeni Aşama 3): "eşik üstü" artık SABİT bir ivme değeri değil,
/// STA/LTA ORANI — kısa vadeli enerji ortalamasının (STA), telefonun KENDİ ortam gürültüsünü
/// temsil eden uzun vadeli ortalamaya (LTA) göre kaç KAT arttığı. Bu, Google'ın Allen (1978)
/// STA/LTA tetikleyicisiyle aynı prensip — sabit bir eşiğin YAKALAYAMAYACAĞI kadar hafif
/// (P-dalgası seviyesinde) bir sinyali de, ortam sessizken RELATİF bir sıçrama olarak yakalar.
/// Ayrıca ham ivme yerine basit bir yüksek-geçiren filtreden geçirilmiş sinyal kullanılıyor
/// (eski "-9.81 çıkar" kaba düzeltmesinin yerini alıyor) ve örnekleme hızı artırıldı.
///
/// ANN ikinci katman onayı (Aşama 7.6): STA/LTA katmanı "şüpheli" dedikten SONRA, rapor
/// göndermeden ÖNCE, `ikinci_katman.dart`'taki (offline egitilmis, gercek STEAD+CSN+AFAD
/// depremleri + UCI HAR telefon gurultusu fuzyonuyla egitilmis Random Forest'in Dart
/// karsiligi) `ikinciKatmanOnayVer` fonksiyonu son bir onay ister — bkz. `_sarsintiKontrolEt`
/// cagrildigi yer. Ozellikler (STA/LTA orani, log enerji, sifir gecis orani, bant enerji
/// orani) egitimdekiyle AYNI tanimla, canli pencereden (`_pencere`) hesaplanir.

const String _bildirimKanaliId = 'sarsinti_izleme';
const int _sarsintiServisId = 300;

/// Kullanicinin "arka planda izleme" tercihini FlutterSecureStorage'da
/// sakladigi anahtar — hem ayarlar_ekrani.dart (anahtari degistirir) hem
/// home_screen.dart (uygulama acilirken tercihi okuyup servisi sessizce
/// yeniden baslatir) AYNI anahtari kullanmali, bu yuzden burada tek yerde.
const String arkaPlanTercihAnahtari = 'arka_plan_izleme_aktif';

/// main()'de, runApp'ten önce çağrılır: servisi TANIMLAR, henüz BAŞLATMAZ.
Future<void> initializeForegroundTask() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: _bildirimKanaliId,
      channelName: 'Deprem İzleme',
      channelDescription: 'Titreşim algılama arka planda çalışıyor.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Periyodik tick YOK: kendi sürekli accelerometer stream'imizi kullanıyoruz,
      // onRepeatEvent'e ihtiyacımız yok.
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false, // bilerek kapalı (bkz. plan: kapsam dışı, Aşama 4 notu)
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

/// Servisi başlatır (Aşama 4'te anahtar açılınca home_screen.dart'tan çağrılacak).
Future<void> sarsintiServisiniBaslat() {
  return FlutterForegroundTask.startService(
    serviceId: _sarsintiServisId,
    notificationTitle: 'Deprem izleme aktif',
    notificationText: 'Titreşim algılama arka planda çalışıyor',
    callback: _baslangicGeriCagrisi,
  );
}

/// Servisi durdurur (Aşama 4'te anahtar kapanınca / logout'ta çağrılacak).
Future<void> sarsintiServisiniDurdur() {
  return FlutterForegroundTask.stopService();
}

/// Arka plan isolate'inin giriş noktası — FlutterForegroundTask.startService bunu gerektirir.
@pragma('vm:entry-point')
void _baslangicGeriCagrisi() {
  FlutterForegroundTask.setTaskHandler(SarsintiTaskHandler());
}

/// Arka plan isolate'inde çalışan asıl mantık: ivmeölçeri dinle, eşik aşılınca rapor gönder.
class SarsintiTaskHandler extends TaskHandler {
  // --- Adaptif esik (yeni Aşama 3) ---
  // LTA (Uzun Vadeli Ortalama): telefonun KENDI ortam gurultusunun enerji (net²) ustel
  // hareketli ortalamasi (EMA), ORNEKLEME ARALIGINDAN BAGIMSIZ (gercek dt'ye gore alpha
  // hesaplanir). Esik, LTA'nin karekokunun (yani ortam GENLIGININ) belirli bir KATI olarak
  // ANLIK hesaplanir — "STA" (kisa vadeli ortalama) KASITLI OLARAK KULLANILMIYOR: STA'nin
  // kendi zaman sabiti, TEK bir kisa darbenin bile pencere suresine yakin bir sure boyunca
  // "supheli" gorunmesine (yanki birakmasina) yol aciyordu ve pencere+oran mekanizmasinin
  // "tek darbe/suren sarsinti" ayrimini bozuyordu (kendi testimde yakaladim, dogrulamaya
  // bakiniz). Bu yuzden her ornek, ONCEKI orneklerin "yanki"si olmadan, SADECE o anki
  // buyuklugunun LTA'ya gore ANLIK karsilastirmasiyla degerlendiriliyor — "hafiza" (suren mi
  // tek seferlik mi ayrimi) SADECE asagidaki pencere+oran mekanizmasinda yasiyor.
  static const double _ltaZamanSabitiSn = 25.0; // "ortam gurultusu" referansi ne kadar uzun
  static const double _esikKatsayisi = 4.0; // anlik ornek, ortam GENLIGININ bu KATINI gecince supheli
  static const double _ltaTabanDegeri = 0.0025; // LTA cok kucukken (sessiz ortam) esik patlamasin

  double _lta = _ltaTabanDegeri;
  DateTime? _sonOrnekZamani;

  // Basit tek-kutuplu yuksek-geciren filtre (yeni Aşama 3): "-9.81 çıkar" kaba duzeltmesi
  // yerine, her eksende yavas degisen bileseni (yercekimi + telefon orientasyon kaymasi)
  // ADAPTIF olarak suzer — sabit deger degil, telefonun O ANKI egimine gore dogru calisir.
  static const double _yuksekGecirenKatsayisi = 0.9;
  double _sonHamX = 0, _sonHamY = 0, _sonHamZ = 0;
  double _sonFiltreliX = 0, _sonFiltreliY = 0, _sonFiltreliZ = 0;

  // Hareket durumu filtresi (Aşama 2): telefon hızlı yürüyor/araçtaysa GPS hızı bunu
  // gösterir — Google'ın "sadece SABİT telefonları say" kuralının bizdeki karşılığı.
  // Yalnizca hiz TAM GÜVENİLİRKEN (speedAccuracy düşükken) uygulanır; belirsizken
  // (iç mekan/zayıf GPS) "filtrele" değil "güvenli tarafta kal, raporu gönder" seçilir.
  static const double _hareketEsigiMs = 3.0; // m/sn — hizli yuruyus/kosu ve ustu, arac dahil
  static const double _hizGuvenilirlikSiniriMs = 5.0; // bunun ustunde hiz TAHMİNİ guvenilmez

  // Kayan pencere + süreklilik oranı ayarları: BAŞLANGIÇ değerleri, gerçek cihazda
  // (yürüme, cep içi sallanma, masaya vurma gibi senaryolarla, AFAD verisiyle) kalibre
  // edilecek. Pencere artik "net > sabit esik" degil, "STA/LTA orani suphelendi mi"
  // (bkz. _staLtaOraniEsigi) sonucunu topluyor.
  static const Duration _pencereSuresi = Duration(milliseconds: 1000);
  static const int _minOrnekSayisi = 8; // pencere daha yeni dolmaya başlamışken erken karar verme
  static const double _oranEsigi = 0.6; // penceredeki örneklerin en az %60'ı süpheli olmali

  final ApiClient _api = ApiClient();
  final KonumServisi _konumServisi = KonumServisi();

  // (STA/LTA süpheli mi, ölçüm zamanı) çiftlerini tutan kuyruk — en yeni sona eklenir,
  // en eski baştan atılır.
  final Queue<_IvmeOrnegi> _pencere = Queue<_IvmeOrnegi>();

  StreamSubscription<AccelerometerEvent>? _ivmeAboneligi;

  // Rapor cooldown'u: sensor saniyede ~16 ölçüm üretir; sarsıntı sürerken
  // API'ye istek yağdırmamak için 60 saniyede en fazla 1 rapor gönderilir
  // (backend'in 60 sn sessiz güncelleme penceresiyle uyumlu — home_screen.dart'la aynı kural).
  DateTime? _sonRaporZamani;
  bool _raporGonderiliyor = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _ivmeAboneligi = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~20ms (~50 Hz) — eskiden ~60ms (~16 Hz)
    ).listen((olay) {
      final zaman = DateTime.now();

      // Yuksek-geciren filtre: her eksende yavas degisen bileseni (yercekimi + telefonun
      // O ANKI egimi) suzer. Sabit "-9.81 cikar" yerine ADAPTIF calisir.
      final fx = _yuksekGecirenUygula(olay.x, _sonHamX, _sonFiltreliX);
      final fy = _yuksekGecirenUygula(olay.y, _sonHamY, _sonFiltreliY);
      final fz = _yuksekGecirenUygula(olay.z, _sonHamZ, _sonFiltreliZ);
      _sonHamX = olay.x;
      _sonHamY = olay.y;
      _sonHamZ = olay.z;
      _sonFiltreliX = fx;
      _sonFiltreliY = fy;
      _sonFiltreliZ = fz;

      // Filtrelenmis sinyalin buyuklugu — artik yercekimi zaten suzuldugu icin ekstra
      // "-9.81 cikar" adimina gerek yok.
      final net = sqrt(fx * fx + fy * fy + fz * fz);

      final sarsinti = _sarsintiKontrolEt(net, fz, zaman);
      // UI açıksa (home_screen.dart bunu dinleyip canlı göstergeyi besliyor).
      FlutterForegroundTask.sendDataToMain({'netIvme': net, 'sarsinti': sarsinti});
      if (sarsinti) {
        // Aşama 7.6: STA/LTA "şüpheli" dedi ama rapor göndermeden ÖNCE ANN ikinci
        // katmanına son bir onay soruluyor — reddederse rapor GÖNDERİLMEZ.
        final ozellikler = _ikinciKatmanOzellikleriniHesapla();
        if (ikinciKatmanOnayVer(ozellikler)) {
          _sarsintiRaporuGonder(net); // otomatik rapor (cooldown'lu)
        }
      }
    });
  }

  /// Tek kutuplu yuksek-geciren filtre: y[n] = k * (y[n-1] + x[n] - x[n-1]).
  /// `_yuksekGecirenKatsayisi` (0.9) 1'e ne kadar yakinsa suzme o kadar guclu (yavas
  /// bilesenler o kadar cok bastirilir) — sabit yercekimi VE telefonun egimi degisimi
  /// gibi "DC'ye yakin" her sey buradan gecince sifira yakinsar.
  double _yuksekGecirenUygula(double ham, double sonHam, double sonFiltreli) {
    return _yuksekGecirenKatsayisi * (sonFiltreli + ham - sonHam);
  }

  /// Adaptif esik: LTA (ortam enerjisinin uzun vadeli ustel ortalamasi) ONCE guncellenir,
  /// SONRA o anki ornegin buyuklugu, LTA'nin karekokunun (ortam GENLIGI) `_esikKatsayisi`
  /// KATIYLA anlik olarak kiyaslanir — STA YOK, yani bu ornegin "supheli" olup olmadigi
  /// SADECE o anki degere bakar, onceki orneklerin yankisini TASIMAZ (bkz. yukaridaki not).
  /// `dt` (son ornekten bu yana gecen sure) ile alpha DINAMIK hesaplanir — sensor hizi
  /// dalgalansa bile zaman sabiti (25 sn) dogru kalir.
  bool _adaptifEsikGectiMi(double net, DateTime zaman) {
    final dtSn = _sonOrnekZamani == null
        ? 0.02 // ilk ornek: gameInterval'in beklenen degeriyle baslat
        : zaman.difference(_sonOrnekZamani!).inMicroseconds / 1e6;
    _sonOrnekZamani = zaman;

    final enerji = net * net;
    final ltaAlpha = 1 - exp(-dtSn / _ltaZamanSabitiSn);
    _lta = ltaAlpha * enerji + (1 - ltaAlpha) * _lta;
    if (_lta < _ltaTabanDegeri) _lta = _ltaTabanDegeri; // sessiz ortamda esik patlamasin

    final esik = _esikKatsayisi * sqrt(_lta);
    return net > esik;
  }

  /// Kayan pencere + süreklilik oranı: TEK bir anlık spike (telefon düşmesi/masaya
  /// vurulması gibi) ile SÜREN bir sarsıntıyı (gerçek deprem adayı) ayırt eder.
  ///
  /// Her yeni örnek için ÖNCE adaptif eşiğe bakılır ("bu örnek şüpheli mi" — bkz.
  /// `_adaptifEsikGectiMi`, ANLIK bir karar, hafızası yok), sonuç pencereye eklenir;
  /// pencere süresinden eski örnekler atılır; pencerede yeterli örnek birikmemişse erken
  /// karar VERİLMEZ; yeterince birikmişse, şüpheli örneklerin ORANI hesaplanıp _oranEsigi
  /// ile karşılaştırılır — TEK bir spike bu oranı geçemez (kuyrukta 1-2 örnek kalır),
  /// ardışık SÜREN bir sarsıntıda ise oran yüksek kalır. "Hafıza"/süreklilik ayrımı SADECE
  /// bu pencerede yaşıyor — adaptif eşiğin kendisi anlık olduğu için ikisi çakışmıyor.
  bool _sarsintiKontrolEt(double net, double z, DateTime zaman) {
    final supheli = _adaptifEsikGectiMi(net, zaman);
    _pencere.addLast(_IvmeOrnegi(supheli, net, z, zaman));
    while (_pencere.isNotEmpty &&
        zaman.difference(_pencere.first.zaman) > _pencereSuresi) {
      _pencere.removeFirst();
    }

    if (_pencere.length < _minOrnekSayisi) return false;

    final supheliSayisi = _pencere.where((ornek) => ornek.supheli).length;
    final oran = supheliSayisi / _pencere.length;
    return oran >= _oranEsigi;
  }

  /// ANN ikinci katman icin 4 ozelligi, AYNI `_pencere`den (offline egitimdeki 1sn'lik
  /// pencereyle AYNI tanim) hesaplar. Sira `ikinci_katman.dart`'in bekledigi sirayla
  /// AYNI olmali: [sta_lta_orani, log_enerji, sifir_gecis_orani, bant_enerji_orani].
  List<double> _ikinciKatmanOzellikleriniHesapla() {
    final netler = _pencere.map((o) => o.net).toList();
    final zler = _pencere.map((o) => o.z).toList();

    final pencereEnerjisi = netler.map((n) => n * n).reduce((a, b) => a + b) / netler.length;
    // Offline egitimde "pencere enerjisi / IZIN TUMUNUN ortalama enerjisi" idi - canli
    // akista "izin tumu" diye bir sey yok, bunun ONLINE karsiligi zaten surekli guncellenen
    // _lta (uzun vadeli ortalama enerji) - ayni referans rolunu oynuyor.
    final staLtaOrani = _lta > 1e-12 ? pencereEnerjisi / _lta : 0.0;
    final logEnerji = log(pencereEnerjisi + 1e-12) / log(10);
    final sifirGecisOrani = _sifirGecisOraniHesapla(zler);
    final bantEnerjiOrani = _bantEnerjiOraniHesapla(netler);

    return [staLtaOrani, logEnerji, sifirGecisOrani, bantEnerjiOrani];
  }

  /// Egitimdeki (07_ozellik_cikar.py) tanimla AYNI: Z ekseninde, pencere ortalamasina
  /// gore isaret degisim sayisi / pencere uzunlugu.
  double _sifirGecisOraniHesapla(List<double> z) {
    final ortalama = z.reduce((a, b) => a + b) / z.length;
    final isaretler = z.map((v) {
      final fark = v - ortalama;
      if (fark > 0) return 1;
      if (fark < 0) return -1;
      return 0;
    }).toList();
    var degisim = 0;
    for (var i = 1; i < isaretler.length; i++) {
      if (isaretler[i] != isaretler[i - 1]) degisim++;
    }
    return degisim / z.length;
  }

  /// Egitimdeki np.fft.rfft ile AYNI tanim (basit dogrudan-toplam DFT - pencere sadece
  /// ~50 ornek oldugu icin performans sorunu YOK): 1-10 Hz bandindaki enerjinin TOPLAM
  /// enerjiye orani. `etkinHz`, penceredeki GERCEK ornek sayisina gore turetilir (sensor
  /// zamanlaması hafif dalgalansa da frekans-bin eslesmesi dogru kalsin diye).
  double _bantEnerjiOraniHesapla(List<double> net) {
    final n = net.length;
    if (n < 4) return 0.0;
    const bantAltHz = 1.0;
    const bantUstHz = 10.0;
    final etkinHz = n / (_pencereSuresi.inMilliseconds / 1000.0);

    var toplamEnerji = 0.0;
    var bantEnerjisi = 0.0;
    for (var k = 0; k <= n ~/ 2; k++) {
      var reel = 0.0;
      var sanal = 0.0;
      for (var t = 0; t < n; t++) {
        final aci = -2 * pi * k * t / n;
        reel += net[t] * cos(aci);
        sanal += net[t] * sin(aci);
      }
      final genlikKare = reel * reel + sanal * sanal;
      toplamEnerji += genlikKare;
      final frekansHz = k * etkinHz / n;
      if (frekansHz >= bantAltHz && frekansHz <= bantUstHz) bantEnerjisi += genlikKare;
    }
    return toplamEnerji > 1e-12 ? bantEnerjisi / toplamEnerji : 0.0;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Kullanılmıyor: eventAction ForegroundTaskEventAction.nothing() olduğu için hiç çağrılmaz.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _ivmeAboneligi?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    // UI'dan servise gönderilen bir veri yok (tek yönlü: servis -> UI).
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}

  /// Sarsıntı algılanınca konum + ölçülen şiddetle backend'e OTOMATIK rapor atar.
  /// home_screen.dart'taki (eski) _sarsintiRaporuGonder ile AYNI mantık: cooldown + intensity.
  /// Buton yok — telefonun kendisi sensör (Google deprem uyarı sistemi modeli).
  Future<void> _sarsintiRaporuGonder(double netIvme) async {
    // Cooldown + eş zamanlı gönderim koruması:
    final simdi = DateTime.now();
    if (_raporGonderiliyor) return;
    if (_sonRaporZamani != null &&
        simdi.difference(_sonRaporZamani!) < const Duration(seconds: 60)) {
      return;
    }

    _raporGonderiliyor = true;
    try {
      final konum = await _konumServisi.konumAl();

      // Hareket durumu filtresi (Aşama 2): hız tahmini güvenilirse VE eşiği geçiyorsa,
      // bu sarsıntı muhtemelen yürüme/koşu/araç hareketi — yanlış pozitif riski yüksek,
      // rapor GÖNDERİLMEZ. Hız belirsizse (speedAccuracy yüksek) filtre uygulanmaz.
      final hizGuvenilir = konum.speedAccuracy <= _hizGuvenilirlikSiniriMs;
      if (hizGuvenilir && konum.speed > _hareketEsigiMs) {
        return;
      }

      // Ölçülen ivmeyi 0-10 intensity skalasına sıkıştır (basit doğrusal eşleme).
      final intensity = netIvme.clamp(0.0, 10.0);
      await _api.titresimBildir(konum.latitude, konum.longitude, intensity);
      _sonRaporZamani = DateTime.now();
    } catch (_) {
      // Arka planda gösterecek bir UI yok — konum/rapor hatası sessizce atlanır
      // (home_screen.dart'taki manuel akışta da konum yoksa rapor atılmıyordu).
    } finally {
      _raporGonderiliyor = false;
    }
  }
}

/// Kayan pencerede tutulan tek bir ölçüm: STA/LTA'ya göre "şüpheli mi" + ölçüm zamanı +
/// (Aşama 7.6) net büyüklük ve Z ekseni değeri — ikinci katman özellik hesaplaması bu
/// AYNI pencereyi (ekstra bir tampon açmadan) kullanır.
class _IvmeOrnegi {
  final bool supheli;
  final double net;
  final double z;
  final DateTime zaman;
  const _IvmeOrnegi(this.supheli, this.net, this.z, this.zaman);
}
