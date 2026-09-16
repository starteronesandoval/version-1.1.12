import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balam_app/api_service.dart';
import 'package:balam_app/widgets/platinum_certificate.dart';

class CertificateApi extends ApiService {
  int issues = 0;
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    throw ApiException(
      'La agrupación no tiene una certificación Platino vigente',
      404,
    );
  }

  @override
  Future<dynamic> put(String path, Map<String, dynamic> data) async {
    issues++;
    return {};
  }
}

void main() {
  testWidgets(
    'The medal is only shown for certified groups and refreshes the certificate',
    (tester) async {
      final api = CertificateApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PlatinumBadge(api: api, group: {'id': 1})),
        ),
      );
      expect(find.text('Platino'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlatinumBadge(
              api: api,
              group: {
                'id': 1,
                'platinum_certificate': {'certificate_code': 'PLATINO-TEST'},
              },
            ),
          ),
        ),
      );
      expect(find.text('Platino'), findsOneWidget);
      await tester.tap(find.text('Platino'));
      await tester.pumpAndSettle();
      expect(
        find.text('La agrupación no tiene una certificación Platino vigente'),
        findsOneWidget,
      );
      expect(find.text('Agrupación Platino'), findsNothing);
    },
  );

  testWidgets('The administrator must confirm verification before issuing', (
    tester,
  ) async {
    final api = CertificateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: PlatinumEditorPage(
          api: api,
          group: {'id': 1, 'group_name': 'Grupo de prueba'},
        ),
      ),
    );
    final field = find.byType(TextFormField);
    await tester.ensureVisible(field);
    await tester.enterText(
      field,
      'Recomendación extensa de la administración. ' * 10,
    );
    final save = find.text('Confirmar Agrupación Platino');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.issues, 0);
    expect(
      find.text('Confirma los tres criterios antes de otorgar Platino.'),
      findsOneWidget,
    );
  });
}
