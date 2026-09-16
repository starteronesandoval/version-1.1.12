import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balam_app/api_service.dart';
import 'package:balam_app/widgets/platinum_requests.dart';

class RequestApi extends ApiService {
  String status = 'not_requested';
  int submissions = 0, approvals = 0;
  Map<String, dynamic>? approved;
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => {
    'status': status,
    'message': 'Podemos recibir una visita.',
    'certificate':
        status == 'certified' ? {'certificate_code': 'PLATINO-TEST'} : null,
  };
  @override
  Future<dynamic> post(String path, Map<String, dynamic> data) async {
    submissions++;
    status = 'pending';
    return get(path);
  }

  @override
  Future<dynamic> put(String path, Map<String, dynamic> data) async {
    approvals++;
    approved = data;
    return {};
  }
}

void main() {
  testWidgets('A request stays pending until the administrator approves', (
    tester,
  ) async {
    final api = RequestApi();
    int changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatinumRequestCard(
            api: api,
            group: {'id': 1},
            onChanged: () => changes++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar Platino'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();
    expect(api.submissions, 1);
    expect(find.text('Solicitud enviada'), findsOneWidget);
    expect(find.text('Solicitar Platino'), findsNothing);
    expect(find.text('Platino'), findsNothing);
    api.status = 'certified';
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Platino'), findsOneWidget);
    expect(changes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Activating from the reviewed profile requires administrator confirmation',
    (tester) async {
      final api = RequestApi();
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/review',
          routes: {
            '/': (_) => const Scaffold(body: Text('Panel')),
            '/review':
                (_) => PlatinumReviewPage(
                  api: api,
                  group: {
                    'id': 1,
                    'group_name': 'Grupo de prueba',
                    'group_type': 'Banda',
                    'musical_style': 'Regional',
                    'member_count': 5,
                    'can_manage_platinum': true,
                  },
                ),
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar Platino'));
      await tester.pumpAndSettle();
      expect(api.approvals, 0);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(api.approvals, 0);
      await tester.tap(find.text('Activar Platino'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar y activar'));
      await tester.pumpAndSettle();
      expect(api.approvals, 1);
      expect(api.approved!['existence_confirmed'], isTrue);
      expect(api.approved!['recommendation'].length, greaterThanOrEqualTo(300));
      expect(find.text('Panel'), findsOneWidget);
    },
  );
}
