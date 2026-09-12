import 'package:flutter/material.dart';

Widget googleSignInButton(VoidCallback? onPressed) => OutlinedButton.icon(
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    backgroundColor: Colors.white,
    foregroundColor: const Color(0xFF1F1F1F),
  ),
  onPressed: onPressed,
  icon: const Text(
    'G',
    style: TextStyle(
      color: Color(0xFF4285F4),
      fontSize: 20,
      fontWeight: FontWeight.w800,
    ),
  ),
  label: const Text('Continuar con Google'),
);
