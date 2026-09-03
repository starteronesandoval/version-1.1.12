import 'package:balam_app/api_service.dart';
import 'package:balam_app/screens/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el registro y las dos modalidades', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(api: ApiService(), onSignedIn: (_) {})),
    );

    expect(find.text('¡Conecta, contrata y disfruta!'), findsOneWidget);
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Agrupación'), findsOneWidget);
  });
}
