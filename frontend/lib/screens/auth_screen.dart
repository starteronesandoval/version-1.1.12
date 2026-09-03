import 'dart:ui';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../widgets/glass_ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.onSignedIn});
  final ApiService api;
  final ValueChanged<String> onSignedIn;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  String role = 'client';
  bool registerMode = true;
  bool busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      if (registerMode) {
        await widget.api.register(email.text.trim(), password.text, role);
      } else {
        await widget.api.login(email.text.trim(), password.text);
        role = await widget.api.role ?? 'client';
      }
      widget.onSignedIn(role);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: GlassBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: GlassCard(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 104,
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ImageFiltered(
                                  imageFilter:
                                      ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                  child: Opacity(
                                    opacity: .22,
                                    child: Image.asset(
                                      'assets/branding/balam_corp.png',
                                      width: 224,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.white,
                                      Colors.white,
                                      Colors.transparent,
                                    ],
                                    stops: [0, .16, .84, 1],
                                  ).createShader(bounds),
                                  child: ShaderMask(
                                    blendMode: BlendMode.dstIn,
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.white,
                                        Colors.white,
                                        Colors.transparent,
                                      ],
                                      stops: [0, .2, .8, 1],
                                    ).createShader(bounds),
                                    child: ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                          sigmaX: .45, sigmaY: .45),
                                      child: Opacity(
                                        opacity: .86,
                                        child: Image.asset(
                                          'assets/branding/balam_corp.png',
                                          width: 214,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('BALAM',
                            style: TextStyle(
                                letterSpacing: 5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFBFA1FF))),
                        const SizedBox(height: 8),
                        Text(
                            registerMode
                                ? '¡Conecta, contrata y disfruta!'
                                : 'Qué bueno tenerte de vuelta',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                            registerMode
                                ? 'Conéctate con las agrupaciones con mejor ranking de tu zona.'
                                : 'Entra para continuar con tu comunidad.',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .68))),
                        const SizedBox(height: 26),
                        TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                prefixIcon: Icon(Icons.alternate_email))),
                        const SizedBox(height: 14),
                        TextField(
                            controller: password,
                            obscureText: true,
                            decoration: const InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: Icon(Icons.lock_outline))),
                        if (registerMode) ...[
                          const SizedBox(height: 20),
                          const Text('Elige tu experiencia',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'client',
                                  label: Text('Cliente'),
                                  icon: Icon(Icons.person_outline)),
                              ButtonSegment(
                                  value: 'musician',
                                  label: Text('Agrupación'),
                                  icon: Icon(Icons.groups_outlined)),
                            ],
                            selected: {role},
                            onSelectionChanged: (value) =>
                                setState(() => role = value.first),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54)),
                          onPressed: busy ? null : submit,
                          child: Text(busy
                              ? 'Conectando…'
                              : registerMode
                                  ? 'Crear mi perfil'
                                  : 'Entrar a Balam'),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => registerMode = !registerMode),
                          child: Text(registerMode
                              ? 'Ya tengo una cuenta'
                              : 'Quiero crear una cuenta'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
