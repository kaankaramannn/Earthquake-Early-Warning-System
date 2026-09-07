import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../notify/bildirim.dart';
import '../map/deprem.dart';
import '../map/tespit.dart';
import '../settings/ek_konum.dart';

/// Backend ile konuşan TEK merkez. Tüm ekranlar istekleri buradan atar.
/// (Backend'deki routers/ gibi: ağ işleri tek yerde toplanır, ekranlar temiz kalır.)
class ApiClient {
  // Emulatorden PC'deki FastAPI'ye erisim adresi. Tek yerde tanimli —
  // gercek sunucuya gecince SADECE bu satir degisir.
  static const String baseUrl = 'http://10.0.2.2:8000';

  static const _zamanAsimi = Duration(seconds: 8);

  // Token'i sifreli saklayan kasa (Android Keystore kullanir).
  final _kasa = const FlutterSecureStorage();

  /// Giriş: form-encoded POST /auth/login/ → başarılıysa token'ı kasaya yazar.
  /// Başarısızsa Türkçe mesajlı Exception fırlatır (ekran, catch ile yakalar).
  Future<void> girisYap(String kullaniciAdi, String sifre) async {
    final http.Response cevap;
    try {
      cevap = await http.post(
        Uri.parse('$baseUrl/auth/login/'),
        // http paketi, body'ye Map verilince otomatik form-encoded gonderir —
        // backend'in OAuth2PasswordRequestForm bekledigi format tam olarak bu.
        body: {'username': kullaniciAdi, 'password': sifre},
      ).timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı. Sunucu açık mı?');
    }

    if (cevap.statusCode == 200) {
      // Turkce karakterler icin bodyBytes + utf8.decode (body dogrudan kullanilirsa bozulabilir)
      final veri = jsonDecode(utf8.decode(cevap.bodyBytes)) as Map<String, dynamic>;
      await _kasa.write(key: 'token', value: veri['access_token'] as String);
    } else if (cevap.statusCode == 400 || cevap.statusCode == 401) {
      throw Exception('Kullanıcı adı veya şifre hatalı');
    } else {
      throw Exception('Sunucu hatası: ${cevap.statusCode}');
    }
  }

  /// Kayıt: JSON POST /auth/register/ (login'in aksine form degil JSON — backend oyle bekliyor).
  Future<void> kayitOl(String kullaniciAdi, String email, String sifre) async {
    final http.Response cevap;
    try {
      cevap = await http
          .post(
            Uri.parse('$baseUrl/auth/register/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': kullaniciAdi,
              'email': email,
              'password': sifre,
            }),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı. Sunucu açık mı?');
    }

    if (cevap.statusCode == 200 || cevap.statusCode == 201) return;
    if (cevap.statusCode == 409) {
      throw Exception('Bu email zaten kayıtlı');
    }
    if (cevap.statusCode == 422) {
      throw Exception('Bilgiler geçersiz: kullanıcı adı ≥3, şifre ≥6 karakter, email geçerli olmalı');
    }
    throw Exception('Sunucu hatası: ${cevap.statusCode}');
  }

  /// Aktif kullanıcı bilgisi: Bearer token'lı GET /user/me/
  Future<Map<String, dynamic>> meGetir() async {
    final token = await tokenGetir();
    if (token == null) {
      throw Exception('Oturum bulunamadı, tekrar giriş yapın');
    }

    final http.Response cevap;
    try {
      cevap = await http.get(
        Uri.parse('$baseUrl/user/me/'),
        // Korumali endpoint'lerin anahtari: Authorization basligi.
        // Swagger'daki "Authorize" kilidinin programatik hali.
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı. Sunucu açık mı?');
    }

    if (cevap.statusCode == 200) {
      return jsonDecode(utf8.decode(cevap.bodyBytes)) as Map<String, dynamic>;
    }
    if (cevap.statusCode == 401) {
      throw Exception('Oturum süresi doldu, tekrar giriş yapın'); // token 30 dk gecerli
    }
    throw Exception('Sunucu hatası: ${cevap.statusCode}');
  }

  /// Kullanıcının bildirimleri: Bearer'lı GET /user/notifications/ → `List<Bildirim>`
  Future<List<Bildirim>> bildirimleriGetir() async {
    final token = await tokenGetir();
    if (token == null) {
      throw Exception('Oturum bulunamadı, tekrar giriş yapın');
    }

    final http.Response cevap;
    try {
      cevap = await http.get(
        Uri.parse('$baseUrl/user/notifications/'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı. Sunucu açık mı?');
    }

    if (cevap.statusCode == 200) {
      // Cevap bu kez tek nesne degil LISTE: once List'e ac, sonra her ogeyi
      // fromJson ile Bildirim'e cevir. Python karsiligi:
      //   [Bildirim(**item) for item in response.json()]
      final liste = jsonDecode(utf8.decode(cevap.bodyBytes)) as List<dynamic>;
      return liste
          .map((oge) => Bildirim.fromJson(oge as Map<String, dynamic>))
          .toList();
    }
    if (cevap.statusCode == 401) {
      throw Exception('Oturum süresi doldu, tekrar giriş yapın');
    }
    throw Exception('Sunucu hatası: ${cevap.statusCode}');
  }

  /// Konum tercihini gunceller: kullanicinin "bildirim alma konumu" = telefonun konumu.
  /// PATCH /user/preferences/ (JSON; sadece gonderilen alanlar degisir).
  Future<void> konumTercihiGuncelle(double lat, double lon) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .patch(
            Uri.parse('$baseUrl/user/preferences/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'pref_latitude': lat, 'pref_longitude': lon}),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Konum tercihi güncellenemedi: ${cevap.statusCode}');
    }
  }

  /// Bildirim tercihlerini gunceller (yaricap + minimum buyukluk esigi).
  /// PATCH /user/preferences/ — backend siniri: radiusKm [0,1000], minMagnitude [0,10].
  Future<void> bildirimTercihleriniGuncelle({
    required double radiusKm,
    required double minMagnitude,
  }) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .patch(
            Uri.parse('$baseUrl/user/preferences/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'pref_radius_km': radiusKm,
              'pref_min_magnitude': minMagnitude,
            }),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Tercihler güncellenemedi: ${cevap.statusCode}');
    }
  }

  /// Ek konumlarimi (ev/isyeri gibi, birincil GPS/manuel konumdan bagimsiz)
  /// listeler — Bearer'li GET /user/locations/
  Future<List<EkKonum>> ekKonumlariGetir() async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http.get(
        Uri.parse('$baseUrl/user/locations/'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Ek konumlar alınamadı: ${cevap.statusCode}');
    }
    final liste = jsonDecode(utf8.decode(cevap.bodyBytes)) as List<dynamic>;
    return liste.map((o) => EkKonum.fromJson(o as Map<String, dynamic>)).toList();
  }

  /// Yeni ek konum ekler — POST /user/locations/
  Future<void> ekKonumEkle({
    required String etiket,
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    double minMagnitude = 3.0,
  }) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .post(
            Uri.parse('$baseUrl/user/locations/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'etiket': etiket,
              'latitude': latitude,
              'longitude': longitude,
              'radius_km': radiusKm,
              'min_magnitude': minMagnitude,
            }),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Ek konum eklenemedi: ${cevap.statusCode}');
    }
  }

  /// Ek konumu siler — DELETE /user/locations/{id}/
  Future<void> ekKonumSil(int id) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .delete(
            Uri.parse('$baseUrl/user/locations/$id/'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Ek konum silinemedi: ${cevap.statusCode}');
    }
  }

  /// Titresim raporu: POST /tremor-reports/ (JSON; intensity 0-10).
  /// 60 sn icindeki tekrar backend'de SESSIZ GUNCELLEME olur (yeni satir acilmaz).
  Future<void> titresimBildir(double lat, double lon, double intensity) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .post(
            Uri.parse('$baseUrl/tremor-reports/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'latitude': lat,
              'longitude': lon,
              'intensity': intensity,
            }),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200 && cevap.statusCode != 201) {
      throw Exception('Rapor gönderilemedi: ${cevap.statusCode}');
    }
  }

  /// Cihazin FCM push adresini backend'e kaydeder (PATCH /user/fcm-token/).
  Future<void> fcmTokenKaydet(String fcmToken) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .patch(
            Uri.parse('$baseUrl/user/fcm-token/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'fcm_token': fcmToken}),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('FCM token kaydedilemedi: ${cevap.statusCode}');
    }
  }

  /// Son 24 saatteki tespitler (harita) — Bearer'li GET /detections/aktif/
  Future<List<Tespit>> aktifTespitleriGetir() async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http.get(
        Uri.parse('$baseUrl/detections/aktif/'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Tespitler alınamadı: ${cevap.statusCode}');
    }
    final liste = jsonDecode(utf8.decode(cevap.bodyBytes)) as List<dynamic>;
    return liste.map((o) => Tespit.fromJson(o as Map<String, dynamic>)).toList();
  }

  /// "Hissettim mi?" geri bildirimi: POST /detections/{id}/geri-bildirim (JSON).
  /// Ayni kullanici aynı tespite tekrar gonderirse backend'de GUNCELLENIR (cift oy olmaz).
  Future<void> gonderGeriBildirim(int detectionId, bool hissettiMi, int siddet) async {
    final token = await tokenGetir();
    if (token == null) throw Exception('Oturum bulunamadı');

    final http.Response cevap;
    try {
      cevap = await http
          .post(
            Uri.parse('$baseUrl/detections/$detectionId/geri-bildirim'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'hissetti_mi': hissettiMi, 'siddet': siddet}),
          )
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200 && cevap.statusCode != 201) {
      throw Exception('Geri bildirim gönderilemedi: ${cevap.statusCode}');
    }
  }

  /// Resmi depremler (harita) — halka açık GET /earthquakes/
  Future<List<Deprem>> depremleriGetir() async {
    final http.Response cevap;
    try {
      cevap = await http
          .get(Uri.parse('$baseUrl/earthquakes/'))
          .timeout(_zamanAsimi);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamadı');
    }
    if (cevap.statusCode != 200) {
      throw Exception('Depremler alınamadı: ${cevap.statusCode}');
    }
    final liste = jsonDecode(utf8.decode(cevap.bodyBytes)) as List<dynamic>;
    return liste.map((o) => Deprem.fromJson(o as Map<String, dynamic>)).toList();
  }

  /// Kayitli token'i okur (yoksa null). Bearer istekler bunu kullanir.
  Future<String?> tokenGetir() => _kasa.read(key: 'token');

  /// Cikis: token'i kasadan siler.
  Future<void> cikisYap() => _kasa.delete(key: 'token');
}
