import 'package:balam_app/api_service.dart';
import 'package:balam_app/main.dart';
import 'package:balam_app/screens/auth_screen.dart';
import 'package:balam_app/screens/rhythm_game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _BrokenStorageApi extends ApiService {
  @override
  Future<String?> get role => Future<String?>.error(Exception('storage'));
}

void main() {
  testWidgets('el arranque continúa si falla el almacenamiento seguro', (
    tester,
  ) async {
    await tester.pumpWidget(BalamApp(api: _BrokenStorageApi()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('muestra el registro y las dos modalidades', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(api: ApiService(), onSignedIn: (_) {})),
    );

    expect(find.text('¡Conecta, contrata y disfruta!'), findsOneWidget);
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Agrupación'), findsOneWidget);
  });

  testWidgets('la primera etapa usa una nota negra y siete controles', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RhythmGameScreen()));

    expect(find.text('Pentagrama Balam'), findsOneWidget);
    expect(find.textContaining('nota negra'), findsOneWidget);
    expect(find.textContaining('Velocidad ×'), findsOneWidget);
    expect(find.text('DO'), findsOneWidget);
    expect(find.text('RE'), findsOneWidget);
    expect(find.text('MI'), findsOneWidget);
    expect(find.text('FA'), findsOneWidget);
    expect(find.text('SOL'), findsOneWidget);
    expect(find.text('LA'), findsOneWidget);
    expect(find.text('SI'), findsOneWidget);

    await tester.tap(find.byTooltip('Cómo jugar'));
    await tester.pumpAndSettle();

    expect(
      find.text('MI · FA · SOL · LA · SI · DO · RE · MI · FA'),
      findsOneWidget,
    );
    expect(find.text('4 tiempos'), findsNothing);
    expect(find.text('Redonda'), findsNothing);
  });
}
