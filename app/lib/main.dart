import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'firebase_options.dart';
import 'auth/splash_screen.dart';
import 'tremor/sarsinti_servisi.dart';
import 'notify/bildirim.dart';
import 'alert/kritik_bildirim_servisi.dart';

/// Navigator'a main() disindan (arka plan bildirim tiklamalari icin) erismek
/// icin global anahtar — MaterialApp'e verilir, KritikBildirimServisi bunu
/// kullanarak EarthquakeAlertScreen'i acar.
final navigatorKey = GlobalKey<NavigatorState>();

/// FCM data-only push'lar (kritik deprem alarmi) uygulama ARKA PLANDAYKEN
/// (kapali degil ama foreground da degil) buradan gecer. Ayri bir izolatta
/// calisir — kendi Firebase init'ini yapmak ZORUNDA, ana main()'deki state'e
/// erisemez. Top-level + @pragma('vm:entry-point') OLMAK ZORUNDA, yoksa
/// release modda tree-shaking'le silinir ve Android bu handler'i bulamaz.
@pragma('vm:entry-point')
Future<void> arkaPlanPushIsle(RemoteMessage mesaj) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final uyari = PushDepremUyarisi.fromFcmData(mesaj.data);
  if (uyari == null) return; // kritik alarm degil (Kandilli teyidi vb.) — bu izolatin isi bitti

  await KritikBildirimServisi.instance.arkaPlanIcinHazirla();
  await KritikBildirimServisi.instance.depremAlarmiGoster(uyari);
}

Future<void> main() async {
  // runApp'ten ONCE async is (Firebase init) yapacagimiz icin binding'i elle baslat.
  WidgetsFlutterBinding.ensureInitialized();
  // Arka plan servisiyle (sarsinti_servisi.dart) UI-isolate iletisim kanalini kurar
  // (once, initializeForegroundTask'tan da once cagrilmasi gerekiyor).
  FlutterForegroundTask.initCommunicationPort();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // flutterfire configure uretti
  );
  // Arka planda (uygulama kapaliyken de) sarsinti izleme servisini TANIMLAR, henuz
  // BASLATMAZ — baslatma home_screen.dart'taki anahtar/hatirlanan tercih ile olur.
  await initializeForegroundTask();

  // Kritik deprem alarmi altyapisi: kanal + izinler + (uygulama acikken/arka
  // planda canliyken) bildirime dokununca navigasyon.
  await KritikBildirimServisi.instance.baslat(navigatorKey);
  // Uygulama TAMAMEN KAPALIYKEN push gelirse bu izolat (arkaPlanPushIsle)
  // tam-ekran-intent bildirimini gosterir — runApp'ten ONCE kaydedilmeli.
  FirebaseMessaging.onBackgroundMessage(arkaPlanPushIsle);

  runApp(const DepremApp());

  // Uygulama, kritik alarm bildirimine dokunularak (ya da full-screen intent'in
  // otomatik acmasiyla) SOGUK baslatildiysa: ilk frame'den sonra o alarmi ac.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    KritikBildirimServisi.instance.baslangicUyarisiniKontrolEt();
  });
}

class DepremApp extends StatelessWidget {
  const DepremApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Deprem Uyarı',
      debugShowCheckedModeBanner: false, // sag ustteki DEBUG kusagini kaldir (sunum)
      theme: ThemeData(
        // Renkler uygulama ikonundan orneklendi: lacivert zemin + turuncu sismik dalga.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E2456), // ikon laciverti
          secondary: const Color(0xFFFF7233), // ikon turuncusu (vurgu)
        ),
        // Modern gorunum: bembeyaz yerine hafif buz mavisi zemin —
        // kartlar bu zeminde "yuzer" ve derinlik hissi olusur.
        scaffoldBackgroundColor: const Color(0xFFF2F5FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E2456), // ust bar = ikon laciverti
          foregroundColor: Colors.white, // baslik + ikonlar beyaz
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      // Acilis: token kontrolu (SplashScreen) -> ana ekran VEYA login.
      home: const SplashScreen(),
    );
  }
}
