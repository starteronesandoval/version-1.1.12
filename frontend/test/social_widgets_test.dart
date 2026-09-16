import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balam_app/api_service.dart';
import 'package:balam_app/widgets/social_widgets.dart';

class SocialApi extends ApiService {
  bool reacted = false, shared = false;
  final calls = <String>[];
  @override
  Future<dynamic> get(String path, {Duration? timeout}) async => {
    'count': reacted ? 1 : 0,
    'active': reacted,
    'shared': shared,
  };
  @override
  Future<dynamic> put(String path, Map<String, dynamic> data) async {
    calls.add(path);
    if (path.endsWith('/share')) {
      shared = data['active'] as bool;
    } else {
      reacted = data['active'] as bool;
    }
    return get(path);
  }
}

void main() {
  testWidgets('Ajua toggles and sharing requires an explicit confirmation', (
    tester,
  ) async {
    final api = SocialApi();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AjuaActions(api: api, mediaId: 7))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajua · 0'));
    await tester.pumpAndSettle();
    expect(find.text('Ajua · 1'), findsOneWidget);
    await tester.tap(find.text('Ajua · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ajua · 0'), findsOneWidget);
    await tester.tap(find.text('Compartir en mi perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.shared, isFalse);
    await tester.tap(find.text('Compartir en mi perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();
    expect(api.shared, isTrue);
    expect(find.text('Quitar de mi perfil'), findsOneWidget);
    await tester.tap(find.text('Quitar de mi perfil'));
    await tester.pumpAndSettle();
    expect(api.shared, isFalse);
    expect(api.calls.where((path) => path.endsWith('/share')).length, 2);
  });
}
