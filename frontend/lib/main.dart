import 'package:flutter/material.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'screens/auth_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/client_home.dart';
import 'screens/musician_profile_screen.dart';
import 'widgets/garibaldi_splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BalamApp());
}

class BalamApp extends StatefulWidget {
  const BalamApp({super.key, this.api});

  final ApiService? api;

  @override
  State<BalamApp> createState() => _BalamAppState();
}

class _BalamAppState extends State<BalamApp> {
  late final ApiService api;
  final navigatorKey = GlobalKey<NavigatorState>();
  late final GaribaldiNotifications notifications;
  String? role;
  bool loading = true;
  bool _restoreFinished = false;
  bool _introFinished = false;
  String? startupError;

  @override
  void initState() {
    super.initState();
    api = widget.api ?? ApiService();
    notifications = GaribaldiNotifications(api, navigatorKey);
    _restore();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      _introFinished = true;
      if (_restoreFinished) setState(() => loading = false);
    });
  }

  Future<void> _restore() async {
    if (mounted) {
      setState(() {
        loading = true;
        _restoreFinished = false;
        startupError = null;
      });
    }
    try {
      role = await api.role;
      if (role != null) {
        await api.get('/api/users/me');
        if (widget.api == null) notifications.activate();
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.logout();
        role = null;
      } else {
        startupError = error.message;
      }
    } catch (_) {
      // El almacenamiento seguro puede no estar disponible durante el primer
      // arranque o después de una actualización. La app debe seguir permitiendo
      // iniciar sesión en vez de quedarse bloqueada en la pantalla de carga.
      final savedRole = await api.role.catchError((_) => null);
      if (savedRole == null) {
        role = null;
      } else {
        role = savedRole;
        startupError =
            'No pudimos conectar con Balam. Revisa tu conexión e inténtalo de nuevo.';
      }
    } finally {
      _restoreFinished = true;
      if (mounted && _introFinished) setState(() => loading = false);
    }
  }

  void _signedIn(String value) {
    // A Google credential or a notification may leave a transient route open.
    // Close it before replacing the app's root content so inherited widgets
    // are not deactivated while a dependent route is still mounted.
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      role = value;
      startupError = null;
    });
    if (widget.api == null) notifications.activate();
  }

  Future<void> _logout() async {
    if (widget.api == null) await notifications.deactivate();
    await api.logout();
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (mounted) {
      setState(() {
        role = null;
        startupError = null;
      });
    }
  }

  Widget _startupFailure() => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: Color(0xFFFFA000),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Balam no pudo iniciar',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  startupError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .72)),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
                TextButton(
                  onPressed: _logout,
                  child: const Text('Cerrar sesión y volver al acceso'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    title: 'Garibaldi',
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF8A00),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: garibaldiInk,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF080D10),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF17110B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFF8A00),
          foregroundColor: const Color(0xFF120B05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF17110B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x66FF8A00)),
        ),
      ),
    ),
    home: KeyedSubtree(
      key: ValueKey(
        loading
            ? 'loading'
            : startupError != null
            ? 'error'
            : role ?? 'auth',
      ),
      child:
          loading
              ? const GaribaldiSplash()
              : startupError != null
              ? _startupFailure()
              : role == null
              ? AuthScreen(api: api, onSignedIn: _signedIn)
              : role == 'admin'
              ? AdminDashboardScreen(api: api, onLogout: _logout)
              : role == 'musician'
              ? MusicianProfileScreen(api: api, onLogout: _logout)
              : ClientHome(api: api, onLogout: _logout),
    ),
  );
}
