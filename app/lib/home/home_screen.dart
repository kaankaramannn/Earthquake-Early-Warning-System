import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:geolocator/geolocator.dart';

import 'package:latlong2/latlong.dart';

import '../notify/bildirim.dart';
import '../core/api_client.dart';
import '../location/konum_servisi.dart';
import '../tremor/sarsinti_servisi.dart';
import '../auth/login_screen.dart';
import '../map/map_screen.dart';
import '../ml/veri_toplama_ekrani.dart';
import '../alert/earthquake_alert_screen.dart';
import '../settings/ayarlar_ekrani.dart';

/// Ana ekran — üstte kullanıcı özeti, gövdede bildirim listesi.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient();

  Map<String, dynamic>? _kullanici;
  List<Bildirim>? _bildirimler; // null = henuz yuklenmedi, [] = yuklendi ama bos
  String? _hataMesaji;

  Timer? _zamanlayici;
  bool _yenilemeDevamEdiyor = false; // ust uste binme korumasi

  final _konumServisi = KonumServisi();
  Position? _konum; // null = henuz alinamadi
  String? _konumHatasi;

  // --- Ivmeolcer canli gostergesi (Faz 3 Parca 2/4) ---
  // NOT: algilama+rapor gonderme mantigi artik BURADA degil, arka plan servisinde
  // (sarsinti_servisi.dart'taki SarsintiTaskHandler) — bu ekran SADECE onun yayinladigi
  // veriyi izleyip gosteriyor (tek-kaynak tasarimi, Asama 4).
  double _netIvme = 0; // servisten gelen son net ivme degeri
  DateTime? _sonSarsintiZamani; // "SARSINTI!" yazisini bir sure ekranda tutmak icin

  bool get _sarsintiVar =>
      _sonSarsintiZamani != null &&
      DateTime.now().difference(_sonSarsintiZamani!) < const Duration(seconds: 3);

  // --- Arka plan izleme anahtari (Faz 3 Parca 4) ---
  // Anahtarin kendisi (UI + degistirme) artik ayarlar_ekrani.dart'ta —
  // burada sadece uygulama acilirken tercihi okuyup servisi sessizce
  // yeniden baslatiyoruz (Android tarafindan oldurulmus olabilir) ve
  // cikis yaparken durdurabilmek icin son durumu tutuyoruz.
  final _kasa = const FlutterSecureStorage();
  bool _arkaPlanIzlemeAktif = false;

  StreamSubscription<String>? _fcmTokenAboneligi;
  StreamSubscription<RemoteMessage>? _onMessageAboneligi;
  StreamSubscription<RemoteMessage>? _onMessageAcilisAboneligi;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
    _konumuYukle();
    FlutterForegroundTask.addTaskDataCallback(_servisVerisiGeldi);
    _arkaPlanIzlemeDurumunuYukle();
    _pushHazirla();
    // Polling artik sadece EMNIYET AGI (ana kanal = FCM push, asagida onMessage):
    // 30 saniyede bir sessiz tazeleme — push kacarsa/aksarsa liste yine guncellenir.
    _zamanlayici = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _verileriYukle(),
    );
    // Uygulama ON PLANDAYKEN push gelirse Android bildirim cubugu GOSTERMEZ;
    // onMessage akisina duser — biz de listeyi ANINDA tazeleriz (SnackBar zaten var)
    // VE data payload'i kritik deprem uyarisiysa full-screen alarmi acariz.
    _onMessageAboneligi = FirebaseMessaging.onMessage.listen(_pushMesajiGeldi);
    // Uygulama ARKA PLANDAYKEN (kapali degil) bildirime dokunulup ac(l)ilirsa bu akis tetiklenir.
    _onMessageAcilisAboneligi =
        FirebaseMessaging.onMessageOpenedApp.listen(_pushMesajiGeldi);
    // Uygulama TAMAMEN KAPALIYKEN bildirime dokunularak acildiysa (cold start),
    // o mesaji burdan yakalariz — initState calistiginda henuz kacirilmis olabilir.
    FirebaseMessaging.instance.getInitialMessage().then((mesaj) {
      if (mesaj != null) _pushMesajiGeldi(mesaj);
    });
  }

  @override
  void dispose() {
    // KRITIK: timer iptal edilmezse ekran kapansa da istek atmaya devam eder
    // (kaynak sizintisi + kapali ekranda setState -> cokme).
    _zamanlayici?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_servisVerisiGeldi);
    _fcmTokenAboneligi?.cancel();
    _onMessageAboneligi?.cancel();
    _onMessageAcilisAboneligi?.cancel();
    super.dispose();
  }

  /// Her push (foreground onMessage / arka plandan acilan onMessageOpenedApp /
  /// soguk baslatan getInitialMessage) BURADAN gecer. Once liste her zaman
  /// tazelenir; ustune, data payload'i kritik deprem uyarisiysa full-screen
  /// EarthquakeAlertScreen acilir (bildirim_dart -> PushDepremUyarisi.fromFcmData).
  void _pushMesajiGeldi(RemoteMessage mesaj) {
    _verileriYukle();

    final uyari = PushDepremUyarisi.fromFcmData(mesaj.data);
    if (uyari == null || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EarthquakeAlertScreen(
          magnitude: uyari.magnitude,
          distanceKm: uyari.distanceKm,
          onNextStep: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// Arka plan servisinin (sarsinti_servisi.dart) `sendDataToMain` ile yayinladigi veriyi
  /// isler — TEK veri kaynagi burasi, bu ekran kendi accelerometer dinleyicisini calistirmiyor.
  void _servisVerisiGeldi(Object data) {
    if (data is! Map) return;
    final net = (data['netIvme'] as num?)?.toDouble();
    final sarsinti = data['sarsinti'] as bool? ?? false;
    if (net == null || !mounted) return;
    setState(() {
      _netIvme = net;
      if (sarsinti) _sonSarsintiZamani = DateTime.now();
    });
  }

  /// Onceki oturumdan hatirlanan anahtar tercihini okur; acikken servisi (Android tarafindan
  /// oldurulmus olabilecegi ihtimaline karsi) yeniden baslatir. Anahtarin kendisi artik
  /// ayarlar_ekrani.dart'ta degistiriliyor — burada sadece SESSIZCE geri yukluyoruz.
  Future<void> _arkaPlanIzlemeDurumunuYukle() async {
    final deger = await _kasa.read(key: arkaPlanTercihAnahtari);
    final aktif = deger == 'true';
    if (!mounted) return;
    _arkaPlanIzlemeAktif = aktif; // sadece cikis yaparken durdurma karari icin
    if (aktif) await sarsintiServisiniBaslat();
  }

  Future<void> _verileriYukle() async {
    if (_yenilemeDevamEdiyor) return; // onceki istek bitmeden yenisini baslatma
    _yenilemeDevamEdiyor = true;
    try {
      final kullanici = await _api.meGetir();
      final bildirimler = await _api.bildirimleriGetir();
      // En yeni bildirim en ustte gorunsun (tarihe gore tersten sirala).
      bildirimler.sort((a, b) => b.olusturulmaZamani.compareTo(a.olusturulmaZamani));
      if (!mounted) return;

      // Onceki sayiyla karsilastir: arttiysa kullaniciya haber ver (demo icin onemli).
      final oncekiSayi = _bildirimler?.length;
      if (oncekiSayi != null && bildirimler.length > oncekiSayi) {
        final yeni = bildirimler.length - oncekiSayi;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$yeni yeni bildirim!'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      setState(() {
        _kullanici = kullanici;
        _bildirimler = bildirimler;
        _hataMesaji = null;
      });
    } catch (hata) {
      if (!mounted) return;
      // Liste zaten doluysa gecici ag hatasi ekrani BOZMASIN (sessiz gec);
      // ilk yuklemede ise hatayi goster.
      if (_bildirimler == null) {
        setState(() => _hataMesaji = hata.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _yenilemeDevamEdiyor = false;
    }
  }

  /// FCM hazirligi: bildirim izni iste -> cihaz token'ini al -> backend'e kaydet.
  /// Token Firebase tarafindan yenilenirse (onTokenRefresh) tekrar kaydedilir.
  Future<void> _pushHazirla() async {
    try {
      // Android 13+ calisma ani bildirim izni (sistem dialogu acilir).
      await FirebaseMessaging.instance.requestPermission();

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        debugPrint('[FCM] token alinamadi (Play Services yok mu?)');
        return;
      }
      debugPrint('[FCM] cihaz token: ${fcmToken.substring(0, 20)}...');
      await _api.fcmTokenKaydet(fcmToken);
      debugPrint('[FCM] token backend\'e kaydedildi');

      // Token nadiren de olsa yenilenir; yenilenince otomatik tekrar kaydet.
      _fcmTokenAboneligi = FirebaseMessaging.instance.onTokenRefresh.listen(
        (yeniToken) => _api.fcmTokenKaydet(yeniToken),
      );
    } catch (hata) {
      debugPrint('[FCM] hazirlik hatasi: $hata'); // push olmadan da uygulama calisir
    }
  }

  Future<void> _konumuYukle() async {
    try {
      final konum = await _konumServisi.konumAl();
      if (!mounted) return;
      setState(() {
        _konum = konum;
        _konumHatasi = null;
      });

      // KONUM SENKRONU: bildirim alma konumu = telefonun gercek konumu —
      // AMA SADECE 'gps' modundaysa. Kullanici ayarlar_ekrani.dart'tan haritadan
      // sabit bir konum sectiyse ('manuel'), burasi onun UZERINE YAZMAMALI.
      final konumModu = await _kasa.read(key: konumModuAnahtari);
      if (konumModu == konumModuManuel) return;

      // Basarisiz olursa sessiz gec (gosterge yine calisir, senkron sonra denenir).
      try {
        await _api.konumTercihiGuncelle(konum.latitude, konum.longitude);
        debugPrint('Konum tercihi senkronlandi: ${konum.latitude}, ${konum.longitude}');
      } catch (_) {/* sessiz */}
    } catch (hata) {
      if (!mounted) return;
      setState(() => _konumHatasi = hata.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cikisYap() async {
    // Oturum kapaninca token gecersiz kalacagi icin anlamsiz arka plan raporlamasini onle.
    if (_arkaPlanIzlemeAktif) await sarsintiServisiniDurdur();
    await _api.cikisYap();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deprem Uyarı Sistemi'),
        actions: [
          // GEÇİCİ (Aşama 7): ANN veri toplama ekranına erişim — kayıt tamamlanınca
          // bu buton + import + ml/veri_toplama_ekrani.dart kaldırılacak.
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VeriToplamaEkrani()),
              );
            },
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Veri toplama (geçici)',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MapScreen(
                    baslangicKonumu: _konum != null
                        ? LatLng(_konum!.latitude, _konum!.longitude)
                        : null,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map),
            tooltip: 'Deprem haritası',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AyarlarEkrani()),
              );
            },
            icon: const Icon(Icons.tune),
            tooltip: 'Bildirim ayarları',
          ),
          IconButton(
            onPressed: _cikisYap,
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış yap',
          ),
        ],
      ),
      body: _icerikOlustur(),
    );
  }

  Widget _icerikOlustur() {
    if (_hataMesaji != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_hataMesaji!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cikisYap,
                child: const Text('Giriş ekranına dön'),
              ),
            ],
          ),
        ),
      );
    }

    if (_kullanici == null || _bildirimler == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Ust bilgi seridi: beyaz yuzey — buz mavisi zeminden ayrissin
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person),
                  const SizedBox(width: 8),
                  Text(
                    _kullanici!['username'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Chip(label: Text('${_bildirimler!.length} bildirim')),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _konum != null
                          ? 'Konum: ${_konum!.latitude.toStringAsFixed(4)}, '
                              '${_konum!.longitude.toStringAsFixed(4)}'
                          : (_konumHatasi ?? 'Konum alınıyor...'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  // Konum degisince elle tazelemek icin kucuk buton
                  IconButton(
                    onPressed: _konumuYukle,
                    icon: const Icon(Icons.refresh, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Konumu yenile',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Canli ivme gostergesi: bar + deger + sarsinti durumu
              Row(
                children: [
                  Icon(Icons.vibration, size: 16,
                      color: _sarsintiVar ? Colors.red : Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_netIvme / 10).clamp(0.0, 1.0), // 0-10 m/s2 -> 0-1 bar
                      backgroundColor: Colors.grey.shade300,
                      // ikon paleti: normalde turuncu, sarsintida kirmizi
                      color: _sarsintiVar ? Colors.red : const Color(0xFFFF7233),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: Text(
                      _sarsintiVar
                          ? 'SARSINTI!'
                          : '${_netIvme.toStringAsFixed(1)} m/s²',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _sarsintiVar ? FontWeight.bold : FontWeight.normal,
                        color: _sarsintiVar ? Colors.red : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Expanded: Column icinde kalan TUM dikey alani listeye ver
        Expanded(child: _listeOlustur()),
      ],
    );
  }

  Widget _listeOlustur() {
    // RefreshIndicator: listeyi asagi cekince _verileriYukle calisir (pull-to-refresh).
    return RefreshIndicator(
      onRefresh: _verileriYukle,
      child: _bildirimler!.isEmpty
          // Bos durumda da "cekilebilir" olmasi icin kaydirilabilir bir yapi gerekir
          // (kaydirilamayan icerik asagi cekilemez).
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                Center(
                  child: Text(
                    'Henüz bildirim yok.\nBir deprem tespit edildiğinde burada görünecek.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            )
          // ListView.builder: SADECE ekranda gorunen kartlari cizer.
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _bildirimler!.length,
              itemBuilder: (context, index) => _bildirimKarti(_bildirimler![index]),
            ),
    );
  }

  Widget _bildirimKarti(Bildirim b) {
    // UC kaynak stili: crowd uyarisi KIRMIZI, Kandilli teyidi MAVI,
    // uzak bilgilendirme ("BILGI:" ile baslar) TURUNCU unlem.
    // EK KONUM (ev/isyeri gibi, birincil konumdan bagimsiz) mesajlari kendi
    // onekiyle geliyor — "BILGI"/"Kandilli"/vb. iceriyor olsalar bile ONCE
    // bu kontrol edilir, aksi halde alt turlerden biriyle karisirlar.
    final ekKonumMu = b.mesaj.startsWith('EK KONUM');
    final bilgiMi = !ekKonumMu && b.mesaj.startsWith('BILGI');
    final renk = ekKonumMu
        ? const Color(0xFF9C27B0) // mor — ek konum (ev/isyeri)
        : bilgiMi
            ? const Color(0xFFFF7233) // ikon turuncusu — bilgilendirme
            : b.kaynakCrowdMu
                ? const Color(0xFFFF3B30) // canli alarm kirmizisi
                : const Color(0xFF2979FF); // canli mavi
    final ikon = ekKonumMu
        ? Icons.home_outlined
        : bilgiMi
            ? Icons.priority_high // unlem: dikkat ama alarm degil
            : b.kaynakCrowdMu
                ? Icons.warning_amber_rounded
                : Icons.verified;
    final etiket = ekKonumMu
        ? _ekKonumEtiketiCikar(b.mesaj)
        : bilgiMi
            ? 'Bilgilendirme'
            : b.kaynakCrowdMu
                ? 'Erken Uyarı'
                : 'Kandilli';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: renk,
          child: Icon(ikon, color: Colors.white),
        ),
        title: Text(b.mesaj),
        subtitle: Text(
          '$etiket • ${_zamanBicimle(b.olusturulmaZamani)} • haritada gör',
          style: TextStyle(color: renk, fontWeight: FontWeight.w500, fontSize: 12),
        ),
        // Liste -> harita koprusu: karta dokununca ilgili olaya odaklanmis harita acilir.
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MapScreen(
                baslangicKonumu: _konum != null
                    ? LatLng(_konum!.latitude, _konum!.longitude)
                    : null,
                odakTespitId: b.detectionEventId,
                odakDepremId: b.earthquakeId,
              ),
            ),
          );
        },
      ),
    );
  }

  /// "EK KONUM (Ev): ..." -> "Ek Konum: Ev" (backend'deki mesaj onekinden etiketi cikarir).
  String _ekKonumEtiketiCikar(String mesaj) {
    final eslesme = RegExp(r'^EK KONUM \(([^)]*)\)').firstMatch(mesaj);
    return eslesme != null ? 'Ek Konum: ${eslesme.group(1)}' : 'Ek Konum';
  }

  /// 2026-07-14T09:05:00 -> "14.07 09:05" (padLeft: "9" -> "09")
  String _zamanBicimle(DateTime z) {
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${iki(z.day)}.${iki(z.month)} ${iki(z.hour)}:${iki(z.minute)}';
  }
}
