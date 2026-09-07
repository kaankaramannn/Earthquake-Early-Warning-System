import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../notify/bildirim.dart';
import 'earthquake_alert_screen.dart';

/// Kritik deprem alarmini (crowd erken uyarisi) BILDIRIME DOKUNMAYA GEREK
/// KALMADAN tam ekran acan servis — gercek "Android Earthquake Alerts"
/// sisteminin yaptigi gibi, full-screen-intent bildirimi kullanir.
///
/// Neden ayri bir yerel bildirim (flutter_local_notifications) ve backend'in
/// data-only push'u: Android, full-screen intent'i SADECE kendi olusturdugumuz
/// bir bildirim uzerinden (setFullScreenIntent) tetikleyebilir — FCM'in
/// otomatik gosterdigi `notification` bloklu bildirimler bunu DESTEKLEMEZ.
/// Bu yuzden kritik uyari icin backend `notification` blogunu ATLAR (bkz.
/// push_gonder(..., sistem_bildirimi_olustur=False)); ekrani SADECE bu servis
/// acar — cift bildirim (biri FCM'den, biri buradan) olmasin diye.
///
/// Ekran hangi durumda otomatik acilir: cihaz KILITLI/EKRAN KAPALIYKEN Android
/// full-screen intent'i dogrudan baslatir (arama/alarm uygulamalari gibi).
/// Ekran ACIK ve kullanici baska bir uygulamadayken Android BILINCLI OLARAK
/// zorla on plana gecirmez (kullanici deneyimini korumak icin) — bu durumda
/// sadece yuksek onemli bir banner/heads-up bildirim gorunur, dokununca acilir.
/// Bu, Google'in kendi deprem uyari sisteminin de uydugu platform kisidir.
class KritikBildirimServisi {
  KritikBildirimServisi._();
  static final KritikBildirimServisi instance = KritikBildirimServisi._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const _kanalId = 'kritik_deprem_alarmi';
  static const _kanalAdi = 'Kritik Deprem Alarmı';
  static const _kanalAciklama =
      'Bölgenizde olası deprem tespit edildiğinde tam ekran açılan kritik uyarı.';
  static const _bildirimId = 1001; // sabit: ust uste gelen alarmlar birbirini GUNCELLER, yigilmaz.

  GlobalKey<NavigatorState>? _navigatorKey;

  /// Ana izolat (uygulama acikken/arka plandayken canliyken) icin tam kurulum:
  /// plugin + kanal + izinler + dokununca navigasyon.
  Future<void> baslat(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    await _pluginuHazirla(
      onTikla: (yanit) => _payloadiIsle(yanit.payload),
    );

    final androidEklenti = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidEklenti?.createNotificationChannel(const AndroidNotificationChannel(
      _kanalId,
      _kanalAdi,
      description: _kanalAciklama,
      importance: Importance.max,
    ));
    await androidEklenti?.requestNotificationsPermission();
    // Android 14+: full-screen intent artik otomatik verilmiyor, ayrica istenmeli.
    await androidEklenti?.requestFullScreenIntentPermission();
  }

  /// FirebaseMessaging.onBackgroundMessage izolati icin HAFIF kurulum — bu
  /// izolatta navigasyon yapilamaz (Navigator yok), sadece bildirim gosterme
  /// yetisi yeter. Kanal/izinler kalicidir, tekrar istenmesine gerek yok.
  Future<void> arkaPlanIcinHazirla() => _pluginuHazirla();

  Future<void> _pluginuHazirla({
    void Function(NotificationResponse yanit)? onTikla,
  }) async {
    const androidBaslatma = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidBaslatma),
      onDidReceiveNotificationResponse: onTikla == null ? null : (yanit) => onTikla(yanit),
    );
  }

  String _payloadOlustur(PushDepremUyarisi uyari) =>
      jsonEncode({'magnitude': uyari.magnitude, 'distance_km': uyari.distanceKm});

  // Android, ekran ACIK ve kilitsizken full-screen-intent'i HICBIR ZAMAN otomatik
  // acmaz (sadece ekran kapali/kilitliyken) — bu, hicbir uygulamanin (bizimki dahil)
  // asamayacagi, kullaniciyi korumaya yonelik platform kisidi. O durumda elimizdeki
  // tek arac: heads-up banner'i olabildigince goze carpar/ayirt edilir yapmak —
  // uzun/belirgin titresim deseni + ses + alarm rengiyle "colorized" kart + genisletilmis metin.
  static final Int64List _titresimDeseni =
      Int64List.fromList([0, 500, 200, 500, 200, 500]);

  /// Kritik alarmi tam-ekran-intent bildirimi olarak gosterir. Cihaz
  /// kilitli/ekran kapaliysa Android EarthquakeAlertScreen'i OTOMATIK acar;
  /// acik ve baska bir uygulama kullaniliyorsa yuksek oncelikli, goze carpan
  /// bir banner gosterir (bkz. yukaridaki not — bu durumda dokunmak gerekir).
  Future<void> depremAlarmiGoster(PushDepremUyarisi uyari) async {
    final govde = 'Tahmini büyüklük ${uyari.magnitude.toStringAsFixed(1)} - '
        '${uyari.distanceKm.toStringAsFixed(0)} km uzaklıkta';
    await _plugin.show(
      _bildirimId,
      'Deprem',
      govde,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kanalId,
          _kanalAdi,
          channelDescription: _kanalAciklama,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          ongoing: false,
          ticker: 'Deprem Uyarısı!',
          // Alarm rengiyle "colorized" kart: heads-up banner'da normal bir
          // bildirimden acikca ayrisir, kritik oldugu ilk bakista anlasilir.
          color: EarthquakeAlertColors.alertColor,
          colorized: true,
          playSound: true,
          enableVibration: true,
          vibrationPattern: _titresimDeseni,
          styleInformation: BigTextStyleInformation(
            govde,
            summaryText: 'Dokunun: Çök - Kapan - Tutun',
          ),
        ),
      ),
      payload: _payloadOlustur(uyari),
    );
  }

  /// Uygulama TAMAMEN KAPALIYKEN bu bildirimle (dokunarak ya da full-screen
  /// intent'in otomatik acmasiyla) baslatildiysa, o alarmi hemen acar.
  /// main.dart'ta runApp SONRASI (ilk frame'den sonra) cagrilmali.
  Future<void> baslangicUyarisiniKontrolEt() async {
    final detay = await _plugin.getNotificationAppLaunchDetails();
    if (detay?.didNotificationLaunchApp ?? false) {
      _payloadiIsle(detay?.notificationResponse?.payload);
    }
  }

  void _payloadiIsle(String? payload) {
    if (payload == null) return;
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    try {
      final veri = jsonDecode(payload) as Map<String, dynamic>;
      final magnitude = (veri['magnitude'] as num).toDouble();
      final distanceKm = (veri['distance_km'] as num).toDouble();
      navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => EarthquakeAlertScreen(magnitude: magnitude, distanceKm: distanceKm),
        ),
      );
    } catch (_) {
      // Bozuk/eski payload — sessiz gec, uygulama normal acilsin.
    }
  }
}
