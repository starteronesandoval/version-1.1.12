import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api_service.dart';
import '../widgets/glass_ui.dart';
import '../widgets/google_sign_in_button_stub.dart'
    if (dart.library.html) '../widgets/google_sign_in_button_web.dart';

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
  bool passwordVisible = false;
  bool googleReady = false;
  bool googleResultHandled = false;
  String? googleError;
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    _initializeGoogle();
  }

  Future<void> _initializeGoogle() async {
    const webClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue:
          '882316037020-3tgmqu1p4vn8g187aam0svvo8cmr1l0g.apps.googleusercontent.com',
    );
    const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    if (webClientId.isEmpty) return;
    try {
      _googleSignIn = GoogleSignIn(
        clientId:
            kIsWeb
                ? webClientId
                : defaultTargetPlatform == TargetPlatform.iOS &&
                    iosClientId.isNotEmpty
                ? iosClientId
                : null,
        serverClientId: kIsWeb ? null : webClientId,
      );
      if (mounted) setState(() => googleReady = true);
    } catch (error) {
      _handleGoogleError(error);
    }
  }

  Future<void> _completeGoogleSignIn(GoogleSignInAccount account) async {
    if (busy || googleResultHandled) return;
    googleResultHandled = true;
    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      googleResultHandled = false;
      _showMessage(
        'Google no entregó una credencial válida. Inténtalo de nuevo.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      String? selectedRole;
      if (registerMode) {
        selectedRole = await _chooseGoogleRole();
        if (selectedRole == null) {
          googleResultHandled = false;
          await _googleSignIn.signOut();
          return;
        }
      }
      final signedInRole = await widget.api.googleAuth(
        idToken,
        createAccount: registerMode,
        selectedRole: selectedRole,
      );
      widget.onSignedIn(signedInRole);
    } on ApiException catch (error) {
      googleResultHandled = false;
      debugPrint(
        'Backend rechazó el acceso Google (${error.statusCode}): ${error.message}',
      );
      if (mounted) {
        setState(() {
          googleError =
              'Balam rechazó el acceso (${error.statusCode}): ${error.message}';
        });
      }
      await _googleSignIn.signOut();
      _showMessage(error.message);
    } catch (error, stackTrace) {
      googleResultHandled = false;
      debugPrint('Error enviando acceso Google a Balam: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          googleError = 'No se pudo conectar con Balam: $error';
        });
      }
      await _googleSignIn.signOut();
      _showMessage('No se pudo conectar con Balam: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _chooseGoogleRole() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('¿Cómo usarás Balam?'),
            content: const Text(
              'Esta cuenta de Google es nueva. Elige la modalidad con la que '
              'quieres crear tu perfil.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'client'),
                icon: const Icon(Icons.person_outline),
                label: const Text('Cliente'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'musician'),
                icon: const Icon(Icons.groups_outlined),
                label: const Text('Agrupación'),
              ),
            ],
          ),
    );
  }

  void _handleGoogleError(Object error) {
    if (error is PlatformException && error.code == 'sign_in_canceled') {
      if (mounted) {
        setState(() {
          googleError =
              'Google canceló el acceso. Elige una cuenta para continuar.';
        });
      }
      return;
    }
    debugPrint('Error de acceso Google: $error');
    final detail =
        error is PlatformException
            ? '${error.code}: ${error.message ?? "sin detalle"}'
            : error.toString();
    if (mounted) setState(() => googleError = detail);
    _showMessage('No se pudo iniciar sesión con Google ($detail).');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startGoogleSignIn() async {
    if (!googleReady) {
      _showMessage(
        'Configura GOOGLE_WEB_CLIENT_ID para habilitar el acceso con Google.',
      );
      return;
    }
    try {
      googleResultHandled = false;
      if (mounted) setState(() => googleError = null);
      final account = await _googleSignIn.signIn();
      if (account == null) return;
      await _completeGoogleSignIn(account);
    } catch (error) {
      _handleGoogleError(error);
    }
  }

  Future<void> forgotPassword() async {
    final identifier = email.text.trim();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!validEmail.hasMatch(identifier)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe primero un correo electrónico válido'),
        ),
      );
      return;
    }
    try {
      final devCode = await widget.api.requestPasswordReset(identifier);
      if (!mounted) return;
      final code = TextEditingController(text: devCode ?? '');
      final newPassword = TextEditingController();
      var newPasswordVisible = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => StatefulBuilder(
              builder:
                  (dialogContext, setDialogState) => AlertDialog(
                    title: const Text('Recuperar contraseña'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          devCode == null
                              ? 'Escribe el código de 6 dígitos que recibiste.'
                              : 'Código de desarrollo: $devCode',
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Código',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                        TextField(
                          controller: newPassword,
                          obscureText: !newPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'Nueva contraseña',
                            prefixIcon: const Icon(Icons.lock_reset),
                            suffixIcon: IconButton(
                              tooltip:
                                  newPasswordVisible
                                      ? 'Ocultar contraseña'
                                      : 'Mostrar contraseña',
                              onPressed:
                                  () => setDialogState(
                                    () =>
                                        newPasswordVisible =
                                            !newPasswordVisible,
                                  ),
                              icon: Icon(
                                newPasswordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          try {
                            await widget.api.confirmPasswordReset(
                              identifier,
                              code.text.trim(),
                              newPassword.text,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } on ApiException catch (error) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            }
                          }
                        },
                        child: const Text('Cambiar contraseña'),
                      ),
                    ],
                  ),
            ),
      );
      code.dispose();
      newPassword.dispose();
      if (confirmed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contraseña actualizada. Ya puedes iniciar sesión.'),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> submit() async {
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!validEmail.hasMatch(email.text.trim()) || password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un correo válido y tu contraseña'),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (registerMode) {
        await widget.api.register(email.text.trim(), password.text, role);
      } else {
        await widget.api.login(email.text.trim(), password.text);
        role = await widget.api.role ?? 'client';
      }
      widget.onSignedIn(role);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo conectar con Balam. Verifica que el servidor esté encendido.',
            ),
          ),
        );
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
    body: _LoginBackground(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              MediaQuery.sizeOf(context).height * .23,
              22,
              22,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassCard(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      registerMode
                          ? '¡Conecta, contrata y disfruta!'
                          : 'Qué bueno tenerte de vuelta',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      registerMode
                          ? 'Conéctate con las agrupaciones con mejor ranking de tu zona.'
                          : 'Entra para continuar con tu comunidad.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                      ),
                    ),
                    const SizedBox(height: 26),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      obscureText: !passwordVisible,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip:
                              passwordVisible
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                          onPressed:
                              () => setState(
                                () => passwordVisible = !passwordVisible,
                              ),
                          icon: Icon(
                            passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (!registerMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy ? null : forgotPassword,
                          child: const Text('Olvidé mi contraseña'),
                        ),
                      ),
                    if (registerMode) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Elige tu experiencia',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'client',
                            label: Text('Cliente'),
                            icon: Icon(Icons.person_outline),
                          ),
                          ButtonSegment(
                            value: 'musician',
                            label: Text('Agrupación'),
                            icon: Icon(Icons.groups_outlined),
                          ),
                        ],
                        selected: {role},
                        onSelectionChanged:
                            (value) => setState(() => role = value.first),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy
                            ? 'Conectando…'
                            : registerMode
                            ? 'Crear mi perfil'
                            : 'Entrar a Balam',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white24)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('o'),
                        ),
                        Expanded(child: Divider(color: Colors.white24)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (googleReady)
                      IgnorePointer(
                        ignoring: busy,
                        child: Opacity(
                          opacity: busy ? .55 : 1,
                          child: googleSignInButton(
                            busy ? null : _startGoogleSignIn,
                          ),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: busy ? null : _startGoogleSignIn,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Continuar con Google'),
                      ),
                    if (googleError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        googleError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFFB4AB)),
                      ),
                    ],
                    TextButton(
                      onPressed:
                          () => setState(() => registerMode = !registerMode),
                      child: Text(
                        registerMode
                            ? 'Ya tengo una cuenta'
                            : 'Quiero crear una cuenta',
                      ),
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

class _LoginBackground extends StatelessWidget {
  const _LoginBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF080D10), Color(0xFF160C04), Color(0xFF080D10)],
            stops: [0, .52, 1],
          ),
        ),
      ),
      const Positioned(
        top: -150,
        right: -110,
        child: _LoginGlow(color: Color(0xFFFF6D00), size: 310),
      ),
      const Positioned(
        top: 180,
        left: -150,
        child: _LoginGlow(color: Color(0xFFFFA000), size: 280),
      ),
      const SafeArea(
        child: IgnorePointer(
          child: Padding(
            padding: EdgeInsets.only(top: 34),
            child: Column(
              children: [
                Icon(Icons.pets_rounded, color: Color(0xFFFFA000), size: 44),
                SizedBox(height: 8),
                Text(
                  'GARIBALDI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'MÚSICA EN VIVO',
                  style: TextStyle(
                    color: Color(0xFFFFC270),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

class _LoginGlow extends StatelessWidget {
  const _LoginGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .22),
          blurRadius: 110,
          spreadRadius: 44,
        ),
      ],
    ),
  );
}
