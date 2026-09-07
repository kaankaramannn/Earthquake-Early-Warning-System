import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

/// Açılış ekranı: kasadaki token'a bakar.
/// Token var + hâlâ geçerli -> direkt ana ekran (otomatik giriş).
/// Yok/geçersiz/süresi dolmuş  -> login ekranı.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _yonlendir();
  }

  Future<void> _yonlendir() async {
    var girisliMi = false;
    try {
      final token = await _api.tokenGetir();
      if (token != null) {
        // Token kasada var ama SURESI DOLMUS olabilir -> /user/me ile canli test.
        await _api.meGetir();
        girisliMi = true;
      }
    } catch (_) {
      girisliMi = false; // gecersiz/suresi dolmus token veya sunucu yok -> login
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => girisliMi ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Kontrol surerken kisa bir marka ekrani (genelde <1 sn gorunur).
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.crisis_alert,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
