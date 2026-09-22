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

// Android does not allow an app to raise the importance of an existing channel.
// Keep this value in sync with AndroidManifest.xml and notifications.py.  The
// versioned channel restores heads-up alerts for installations that first
// created the old channel as silent.
const _alertChannelId = 'garibaldi_alerts_v2';
const _alertChannelName = 'Avisos urgentes de Garibaldi';
const _alertChannelDescription =
    'Mensajes, contrataciones, pagos y actividad social';

@pragma('vm:entry-point')
Future<void> garibaldiBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
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

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> activate() async {
    if (!supported) return;
    try {
      if (!_ready) {
        await Firebase.initializeApp();
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
              _alertChannelId, _alertChannelName,
              description: _alertChannelDescription,
              importance: Importance.high,
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
      final notificationSettings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (notificationSettings.authorizationStatus != AuthorizationStatus.authorized &&
          notificationSettings.authorizationStatus != AuthorizationStatus.provisional) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true,
        );
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
          _alertChannelId, _alertChannelName,
          channelDescription: _alertChannelDescription,
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
