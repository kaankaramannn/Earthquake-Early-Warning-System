import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home/home_screen.dart';

/// Uygulamanin geri kalaniyla AYNI renk paleti — kendi placeholder renkleri
/// icat etmek yerine main.dart'taki tema (lacivert 0xFF0E2456) ve
/// home_screen.dart'taki mevcut "canli alarm kirmizisi" (0xFFFF3B30, crowd
/// deprem uyarilarinda kullanilan renk) ile birebir eslesir.
class EarthquakeAlertColors {
  EarthquakeAlertColors._();

  static const Color alertColor = Color(0xFFFF3B30); // home_screen.dart'taki canli alarm kirmizisi
  static const Color darkBackgroundColor = Color(0xFF0E2456); // main.dart'taki ikon laciverti
  static const Color textColor = Colors.white;
  static const Color subtitleTextColor = Colors.white70;
  static const Color statusBarIconColor = Colors.white;
}

/// Kritik deprem uyarisi icin tam ekran overlay.
///
/// FastAPI backend'in push/WebSocket ile kritik bir deprem bildirdiginde
/// (bkz. bildirim.dart -> PushDepremUyarisi, home_screen.dart -> _pushMesajiGeldi)
/// tam ekran acilir.
class EarthquakeAlertScreen extends StatefulWidget {
  const EarthquakeAlertScreen({
    super.key,
    required this.magnitude,
    required this.distanceKm,
    this.onNextStep,
  });

  final double magnitude;
  final double distanceKm;
  final VoidCallback? onNextStep;

  @override
  State<EarthquakeAlertScreen> createState() => _EarthquakeAlertScreenState();
}

class _EarthquakeAlertScreenState extends State<EarthquakeAlertScreen> {
  @override
  void initState() {
    super.initState();
    // Gercek sistem status bar'ini gizle ki _FakeStatusBar ile ust uste
    // binmesin — mockup'taki gibi tek, simule edilmis bir seri gorunsun.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // KRITIK: ekran kapanirken geri getirilmezse, uygulamanin geri kalani
    // (ve diger ekranlar) da yanlislikla immersive modda kalir.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Buton icin varsayilan davranis: cagiran ozel bir aksiyon vermediyse,
  /// bu ekrani kapatip kullaniciyi uygulamanin kendisine (altta duran ekrana) dondurur.
  void _uygulamayiAc() {
    if (widget.onNextStep != null) {
      widget.onNextStep!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // Alarm ekrani uygulamanin ILK ekrani olarak acilmissa (ör. soguk
      // baslatmada dogrudan bildirimden), geri donulecek bir ekran yoktur —
      // bu durumda ana ekrana geciyoruz.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EarthquakeAlertColors.darkBackgroundColor,
      body: Column(
        children: [
          const _FakeStatusBar(),
          Expanded(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  _AlertHeader(
                    magnitude: widget.magnitude,
                    distanceKm: widget.distanceKm,
                  ),
                  Expanded(
                    child: _SafetyGuide(),
                  ),
                  _AlertFooter(onNextStep: _uygulamayiAc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simule edilmis status bar satiri (saat / sinyal / wifi / batarya).
/// Gercek cihaz durumunu okumaz, sadece referans tasarimdaki gorunumu taklit eder.
class _FakeStatusBar extends StatelessWidget {
  const _FakeStatusBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              '9:30',
              style: TextStyle(
                color: EarthquakeAlertColors.statusBarIconColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Text(
                  '5G',
                  style: TextStyle(
                    color: EarthquakeAlertColors.statusBarIconColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.signal_cellular_alt,
                  color: EarthquakeAlertColors.statusBarIconColor,
                  size: 16,
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.wifi,
                  color: EarthquakeAlertColors.statusBarIconColor,
                  size: 16,
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.battery_full,
                  color: EarthquakeAlertColors.statusBarIconColor,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertHeader extends StatelessWidget {
  const _AlertHeader({
    required this.magnitude,
    required this.distanceKm,
  });

  final double magnitude;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: EarthquakeAlertColors.alertColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: EarthquakeAlertColors.textColor,
            size: 28,
          ),
          const SizedBox(height: 16),
          const Text(
            'Deprem',
            style: TextStyle(
              color: EarthquakeAlertColors.textColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tahmini büyüklük ${magnitude.toStringAsFixed(1)}',
            style: const TextStyle(
              color: EarthquakeAlertColors.textColor,
              fontSize: 16,
            ),
          ),
          Text(
            '${distanceKm.toStringAsFixed(0)} km uzaklıkta',
            style: const TextStyle(
              color: EarthquakeAlertColors.textColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // AFAD'in resmi Turkce deprem guvenlik talimati: Cok - Kapan - Tutun.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          _SafetyStepRow(
            label: 'Çök',
            icon: Icons.arrow_downward_rounded,
          ),
          SizedBox(height: 32),
          _SafetyStepRow(
            label: 'Kapan',
            icon: Icons.table_bar_rounded,
          ),
          SizedBox(height: 32),
          _SafetyStepRow(
            label: 'Tutun',
            icon: Icons.back_hand_rounded,
          ),
        ],
      ),
    );
  }
}

class _SafetyStepRow extends StatelessWidget {
  const _SafetyStepRow({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: EarthquakeAlertColors.textColor,
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        Icon(
          icon,
          color: EarthquakeAlertColors.textColor,
          size: 40,
        ),
      ],
    );
  }
}

class _AlertFooter extends StatelessWidget {
  const _AlertFooter({this.onNextStep});

  final VoidCallback? onNextStep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          const Text(
            'Deprem Uyarı Sistemi',
            style: TextStyle(
              color: EarthquakeAlertColors.subtitleTextColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: EarthquakeAlertColors.alertColor,
                foregroundColor: EarthquakeAlertColors.textColor,
                disabledBackgroundColor: EarthquakeAlertColors.alertColor,
                disabledForegroundColor: EarthquakeAlertColors.textColor,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
              child: const Text(
                'Uygulamayı Aç',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
