import 'package:flutter/material.dart';

import 'api_service.dart';
import 'screens/auth_screen.dart';
import 'screens/client_home.dart';
import 'screens/musician_profile_screen.dart';

void main() => runApp(const BalamApp());

class BalamApp extends StatefulWidget {
  const BalamApp({super.key});
  @override
  State<BalamApp> createState() => _BalamAppState();
}

class _BalamAppState extends State<BalamApp> {
  final api = ApiService();
  String? role;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    role = await api.role;
    if (mounted) setState(() => loading = false);
  }

  void _signedIn(String value) => setState(() => role = value);
  Future<void> _logout() async {
    await api.logout();
    setState(() => role = null);
  }

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
            : role == null
                ? AuthScreen(api: api, onSignedIn: _signedIn)
                : role == 'musician'
                    ? MusicianProfileScreen(api: api, onLogout: _logout)
                    : ClientHome(api: api, onLogout: _logout),
      );
}
