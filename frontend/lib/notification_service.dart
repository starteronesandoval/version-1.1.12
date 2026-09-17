import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'widgets/notification_inbox.dart';

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

const _options = FirebaseOptions(
  apiKey: _apiKey,
  appId: _appId,
  messagingSenderId: _senderId,
  projectId: _projectId,
);

@pragma('vm:entry-point')
Future<void> garibaldiBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: _options);
  // Android displays notification payloads while the app is in background.
}

class GaribaldiNotifications {
  GaribaldiNotifications(this.api, this.navigatorKey);

  final ApiService api;
  final GlobalKey<NavigatorState> navigatorKey;
  final FlutterLocalNotificationsPlugin local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _pendingOpen = false;
  String? _installationId;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      && _apiKey.isNotEmpty && _appId.isNotEmpty
      && _senderId.isNotEmpty && _projectId.isNotEmpty;

  Future<void> activate() async {
    if (!supported) return;
    try {
      if (!_ready) {
        await Firebase.initializeApp(options: _options);
        FirebaseMessaging.onBackgroundMessage(garibaldiBackgroundMessage);
        await local.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('garibaldi_mark'),
          ),
          onDidReceiveNotificationResponse: (_) => openInbox(),
        );
        await local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
            const AndroidNotificationChannel(
              'garibaldi_alerts', 'Avisos de Garibaldi',
              description: 'Contrataciones, mensajes, pagos y actividad social',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
        FirebaseMessaging.onMessage.listen(_showForeground);
        FirebaseMessaging.onMessageOpenedApp.listen((_) => openInbox());
        FirebaseMessaging.instance.onTokenRefresh.listen((token) {
          unawaited(_registerToken(token).catchError((Object error) {
            debugPrint('No se pudo actualizar el token de avisos: $error');
          }));
        });
        _ready = true;
      }
      final prefs = await SharedPreferences.getInstance();
      _installationId = prefs.getString('garibaldi_installation_id');
      if (_installationId == null) {
        final random = Random.secure();
        _installationId = List.generate(24, (_) =>
          random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await prefs.setString('garibaldi_installation_id', _installationId!);
      }
      if (prefs.getBool('garibaldi_notification_permission_asked') != true) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true,
        );
        await prefs.setBool('garibaldi_notification_permission_asked', true);
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openInbox();
      if (_pendingOpen) openInbox();
    } catch (error) {
      debugPrint('Avisos de Garibaldi: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    final installationId = _installationId;
    if (installationId == null || await api.token == null) return;
    await api.put('/api/notifications/devices', {
      'installation_id': installationId, 'token': token,
    });
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await local.show(
      id: message.messageId.hashCode & 0x7fffffff,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'garibaldi_alerts', 'Avisos de Garibaldi',
          channelDescription: 'Contrataciones, mensajes, pagos y actividad social',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.private,
        ),
      ),
      payload: message.data['notification_id']?.toString(),
    );
  }

  void openInbox() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingOpen = true;
      return;
    }
    _pendingOpen = false;
    navigator.push(MaterialPageRoute(
      builder: (_) => NotificationInboxScreen(api: api),
    ));
  }

  Future<void> deactivate() async {
    final installationId = _installationId;
    if (installationId == null) return;
    try {
      await api.put('/api/notifications/devices/$installationId/disable', {});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Logging out locally still succeeds if the device is offline.
    }
  }
}
