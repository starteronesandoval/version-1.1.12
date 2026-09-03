import 'dart:ui';

import 'package:flutter/material.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF130B2B), Color(0xFF2E1760), Color(0xFF0B2447)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -90,
              right: -80,
              child: _Glow(color: Color(0xFF9F67FF), size: 280),
            ),
            const Positioned(
              bottom: 40,
              left: -120,
              child: _Glow(color: Color(0xFF20C9B5), size: 300),
            ),
            child,
          ],
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
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
                color: color.withValues(alpha: .24),
                blurRadius: 100,
                spreadRadius: 38)
          ],
        ),
      );
}

class GlassCard extends StatelessWidget {
  const GlassCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18),
      this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: Colors.white.withValues(alpha: .10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            ),
            child: InkWell(
                onTap: onTap, child: Padding(padding: padding, child: child)),
          ),
        ),
      );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(
      {super.key,
      this.url,
      required this.fallback,
      this.radius = 48,
      this.onTap});
  final String? url;
  final String fallback;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                LinearGradient(colors: [Color(0xFFC29BFF), Color(0xFF53E0D0)]),
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFF241642),
            backgroundImage: url == null ? null : NetworkImage(url!),
            child: url == null
                ? Text(fallback.isEmpty ? '?' : fallback[0].toUpperCase(),
                    style: TextStyle(
                        fontSize: radius * .7,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))
                : null,
          ),
        ),
      );
}
