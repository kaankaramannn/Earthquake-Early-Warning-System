import 'package:geolocator/geolocator.dart';

/// Kullanicinin "bildirim konumu" modunu FlutterSecureStorage'da sakladigi
/// anahtar — 'gps' (varsayilan, home_screen.dart cihaz konumunu otomatik
/// senkronlar) veya 'manuel' (ayarlar_ekrani.dart'ta haritadan secilen sabit
/// konum kullanilir, home_screen.dart bunun UZERINE YAZMAZ).
const String konumModuAnahtari = 'konum_modu';
const String konumModuGps = 'gps';
const String konumModuManuel = 'manuel';

/// Konum işlemleri tek merkezde (ApiClient deseninin konum karşılığı).
/// Faz 3 Parça 3'te otomatik titreşim raporu da burayı kullanacak.
class KonumServisi {
  /// Cihazın güncel konumunu döndürür.
  /// İzin akışı: servis açık mı? → izin var mı? → yoksa iste → yine yoksa hata.
  Future<Position> konumAl() async {
    // 1) Telefonun konum servisi (GPS) genel olarak acik mi?
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Konum servisi kapalı. Telefon ayarlarından açın.');
    }

    // 2) UYGULAMANIN izni var mi? (servis acik olsa da uygulama ayrica izin ister)
    var izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.denied) {
      // Kullaniciya sistem izin penceresi gosterilir (Android'in kendi dialogu).
      izin = await Geolocator.requestPermission();
    }
    if (izin == LocationPermission.denied ||
        izin == LocationPermission.deniedForever) {
      throw Exception('Konum izni verilmedi. Titreşim raporu için izin gerekli.');
    }

    // 3) Guncel konumu al (GPS fix'i birkac saniye surebilir).
    return Geolocator.getCurrentPosition();
  }
}
