import 'package:flutter/material.dart';

import 'api_service.dart';
import 'screens/auth_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/client_home.dart';
import 'screens/musician_profile_screen.dart';

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
  String? role;
  bool loading = true;
  String? startupError;

  @override
  void initState() {
    super.initState();
    api = widget.api ?? ApiService();
    _restore();
  }

  Future<void> _restore() async {
    if (mounted) {
      setState(() {
        loading = true;
        startupError = null;
      });
    }
    try {
      role = await api.role;
      if (role != null) {
        await api.get('/api/users/me');
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
      if (mounted) setState(() => loading = false);
    }
  }

  void _signedIn(String value) => setState(() {
        role = value;
        startupError = null;
      });
  Future<void> _logout() async {
    await api.logout();
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
                    const Icon(Icons.cloud_off_rounded,
                        size: 64, color: Color(0xFFFFC857)),
                    const SizedBox(height: 18),
                    const Text('Balam no pudo iniciar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(startupError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .72))),
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
        debugShowCheckedModeBanner: false,
        title: 'Balam',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B5CF6),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF130B2B),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withValues(alpha: .08),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .14)),
            ),
          ),
        ),
        home: loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : startupError != null
                ? _startupFailure()
                : role == null
                    ? AuthScreen(api: api, onSignedIn: _signedIn)
                    : role == 'admin'
                        ? AdminDashboardScreen(api: api, onLogout: _logout)
                        : role == 'musician'
                            ? MusicianProfileScreen(api: api, onLogout: _logout)
                            : ClientHome(api: api, onLogout: _logout),
      );
}
