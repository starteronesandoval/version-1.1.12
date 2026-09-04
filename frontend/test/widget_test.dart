import 'package:balam_app/api_service.dart';
import 'package:balam_app/screens/auth_screen.dart';
import 'package:balam_app/screens/rhythm_game_screen.dart';
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

  testWidgets('el juego explica las cinco duraciones musicales',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RhythmGameScreen()),
    );

    expect(find.text('Pentagrama Balam'), findsOneWidget);
    expect(find.text('DO'), findsOneWidget);
    expect(find.text('RE'), findsOneWidget);
    expect(find.text('MI'), findsOneWidget);
    expect(find.text('FA'), findsOneWidget);
    expect(find.text('SOL'), findsOneWidget);
    expect(find.text('LA'), findsOneWidget);
    expect(find.text('SI'), findsOneWidget);

    await tester.tap(find.byTooltip('Cómo jugar'));
    await tester.pumpAndSettle();

    expect(find.text('Redonda'), findsAtLeastNWidgets(1));
    expect(find.text('4 tiempos'), findsOneWidget);
    expect(find.text('Blanca'), findsAtLeastNWidgets(1));
    expect(find.text('2 tiempos'), findsOneWidget);
    expect(find.text('Negra'), findsAtLeastNWidgets(1));
    expect(find.text('1 tiempo'), findsOneWidget);
    expect(find.text('Corchea'), findsAtLeastNWidgets(1));
    expect(find.text('½ tiempo'), findsOneWidget);
    expect(find.text('Semicorchea'), findsAtLeastNWidgets(1));
    expect(find.text('¼ de tiempo'), findsOneWidget);
  });
}
