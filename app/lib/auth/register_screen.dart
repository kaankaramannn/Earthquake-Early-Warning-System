import 'package:flutter/material.dart';

import '../core/api_client.dart';

/// Kayıt ekranı — JSON POST /auth/register/ ile yeni kullanıcı oluşturur.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _kullaniciAdiController = TextEditingController();
  final _emailController = TextEditingController();
  final _sifreController = TextEditingController();

  final _api = ApiClient();
  bool _yukleniyor = false;

  @override
  void dispose() {
    _kullaniciAdiController.dispose();
    _emailController.dispose();
    _sifreController.dispose();
    super.dispose();
  }

  Future<void> _kayitOl() async {
    final kullaniciAdi = _kullaniciAdiController.text.trim();
    final email = _emailController.text.trim();
    final sifre = _sifreController.text;
    if (kullaniciAdi.isEmpty || email.isEmpty || sifre.isEmpty) {
      _mesajGoster('Tüm alanlar doldurulmalı', hata: true);
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      await _api.kayitOl(kullaniciAdi, email, sifre);
      if (!mounted) return;
      _mesajGoster('Kayıt başarılı! Şimdi giriş yapabilirsin.');
      Navigator.of(context).pop(); // login ekranina geri don
    } catch (hata) {
      if (!mounted) return;
      _mesajGoster(hata.toString().replaceFirst('Exception: ', ''), hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _mesajGoster(String mesaj, {bool hata = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj),
        backgroundColor: hata ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar'li ekran push ile acilinca geri oku otomatik gelir (Navigator nimetlerinden)
      appBar: AppBar(title: const Text('Kayıt Ol')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _kullaniciAdiController,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı adı (en az 3 karakter)',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress, // klavye @ tusuyla acilir
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _sifreController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre (en az 6 karakter)',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _yukleniyor ? null : _kayitOl,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _yukleniyor
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kayıt Ol'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
