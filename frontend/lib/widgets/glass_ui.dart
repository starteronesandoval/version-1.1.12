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
      this.preset = 'jaguar_guitar',
      this.color = '#8B5CF6',
      this.radius = 48,
      this.onTap});
  final String? url;
  final String fallback;
  final String preset;
  final String color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final generatedAsset = avatarAsset(preset);
    ImageProvider? image;
    if (url != null) {
      image = NetworkImage(url!);
    } else if (generatedAsset != null) {
      image = AssetImage(generatedAsset);
    }
    return GestureDetector(
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
          backgroundColor: avatarColor(color),
          backgroundImage: image,
          child: image == null
              ? Icon(avatarIcon(preset),
                  size: radius * .92, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

Color avatarColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  return Color(int.tryParse('FF$clean', radix: 16) ?? 0xFF8B5CF6);
}

IconData avatarIcon(String preset) =>
    const {
      'music': Icons.music_note_rounded,
      'microphone': Icons.mic_rounded,
      'guitar': Icons.music_video_rounded,
      'accordion': Icons.piano_rounded,
      'drums': Icons.album_rounded,
      'headphones': Icons.headphones_rounded,
      'star': Icons.star_rounded,
      'jaguar': Icons.pets_rounded,
    }[preset] ??
    Icons.music_note_rounded;

const avatarPresets = <String>[
  'jaguar_guitar',
  'jaguar_accordion',
  'jaguar_dj',
  'coyote_singer',
  'coyote_guitar',
  'coyote_drums',
  'owl_violin',
  'owl_keyboard',
  'owl_sax',
  'fox_bass',
  'fox_mariachi',
  'fox_singer',
  'bear_tuba',
  'bear_drums',
  'bear_accordion',
  'eagle_trumpet',
  'eagle_guitar',
  'eagle_dj',
  'rabbit_violin',
  'lion_trumpet',
  'lion_conductor',
  'lion_tuba',
  'axolotl_guitar',
  'axolotl_dj',
  'raccoon_bass',
  'deer_harp',
  'bull_trombone',
  'cat_violin',
  'elephant_cello',
  'turtle_flute',
];

String? avatarAsset(String preset) =>
    avatarPresets.contains(preset) ? 'assets/avatars/$preset.png' : null;

const avatarColors = <String>[
  '#8B5CF6',
  '#EC4899',
  '#0EA5E9',
  '#14B8A6',
  '#F59E0B',
  '#EF4444',
  '#6366F1',
  '#334155',
];

class AvatarSelection {
  const AvatarSelection(this.preset, this.color);
  final String preset;
  final String color;
}

Future<AvatarSelection?> showAvatarPicker(
  BuildContext context, {
  required String currentPreset,
  required String currentColor,
}) async {
  var preset = currentPreset;
  var color = currentColor;
  return showModalBottomSheet<AvatarSelection>(
    context: context,
    backgroundColor: const Color(0xFF1C1235),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, setSheetState) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Crea tu avatar',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Elige un símbolo y un color que te representen.',
                style: TextStyle(color: Colors.white.withValues(alpha: .62))),
            const SizedBox(height: 20),
            ProfileAvatar(
                fallback: 'A', preset: preset, color: color, radius: 52),
            const SizedBox(height: 22),
            SizedBox(
              height: 350,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: avatarPresets.length,
                itemBuilder: (_, index) {
                  final item = avatarPresets[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setSheetState(() => preset = item),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: item == preset
                            ? Colors.white.withValues(alpha: .18)
                            : Colors.white.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: item == preset
                                ? const Color(0xFFC7ACFF)
                                : Colors.transparent,
                            width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child:
                            Image.asset(avatarAsset(item)!, fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final item in avatarColors)
                  GestureDetector(
                    onTap: () => setSheetState(() => color = item),
                    child: Container(
                      width: item == color ? 34 : 28,
                      height: item == color ? 34 : 28,
                      decoration: BoxDecoration(
                        color: avatarColor(item),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: item == color
                                ? Colors.white
                                : Colors.transparent,
                            width: 3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: () =>
                  Navigator.pop(sheetContext, AvatarSelection(preset, color)),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Usar este avatar'),
            ),
          ],
        ),
      ),
    ),
  );
}
