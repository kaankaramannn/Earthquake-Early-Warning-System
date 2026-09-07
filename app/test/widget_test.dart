import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deprem_app/auth/login_screen.dart';

void main() {
  testWidgets('Login ekrani acilir', (WidgetTester tester) async {
    // Uygulama acilisi artik SplashScreen (token kontrolu + ag istegi) oldugu
    // icin testte dogrudan LoginScreen'i kuruyoruz.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Deprem Uyarı Sistemi'), findsOneWidget);
    expect(find.text('Giriş Yap'), findsOneWidget);
    expect(find.text('Kullanıcı adı'), findsOneWidget);
  });
}
