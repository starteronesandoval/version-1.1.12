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
          spreadRadius: 38,
        ),
      ],
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.theme = 'classic',
    this.light = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String theme;
  final bool light;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(26),
    child: Stack(
      children: [
        if (groupThemeAsset(theme) case final asset?)
          Positioned.fill(child: Image.asset(asset, fit: BoxFit.cover)),
        Positioned.fill(
          child: ColoredBox(
            color: (light ? Colors.white : const Color(0xFF071018)).withValues(
              alpha: light ? .86 : (theme == 'classic' ? .42 : .20),
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: theme == 'classic' ? 16 : 3,
            sigmaY: theme == 'classic' ? 16 : 3,
          ),
          child: Material(
            color: Colors.white.withValues(
              alpha: light ? .68 : (theme == 'classic' ? .07 : .03),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: BorderSide(
                color: Colors.white.withValues(alpha: light ? 1 : .78),
                width: 1.4,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ],
    ),
  );
}

const groupThemeLabels = <String, String>{
  'classic': 'Glass clásico',
  'norteno': 'Norteño · acordeón y bajo quinto',
  'mariachi': 'Mariachi · guitarrón y trompetas',
  'rock': 'Rock · guitarras y escenario',
  'banda': 'Banda · tuba y tambora',
  'sonora': 'Sonora · metales y percusión tropical',
  'sierreno': 'Sierreño · requinto, guitarra y bajo',
};

String? groupThemeAsset(String theme) =>
    const {
      'norteno': 'assets/themes/norteno.png',
      'mariachi': 'assets/themes/mariachi.png',
      'rock': 'assets/themes/rock.png',
      'banda': 'assets/themes/banda.png',
      'sonora': 'assets/themes/sonora.png',
      'sierreno': 'assets/themes/sierreno.png',
    }[theme];

String resolveGroupTheme({
  required String? selected,
  String? groupType,
  String? musicalStyle,
}) {
  if (selected != null &&
      selected != 'classic' &&
      groupThemeAsset(selected) != null) {
    return selected;
  }
  final description = '${groupType ?? ''} ${musicalStyle ?? ''}'
      .toLowerCase()
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n');
  if (description.contains('mariachi')) return 'mariachi';
  if (description.contains('sierreno')) return 'sierreno';
  if (description.contains('sonora')) return 'sonora';
  if (description.contains('banda')) return 'banda';
  if (description.contains('norteno')) return 'norteno';
  if (description.contains('rock')) return 'rock';
  return 'classic';
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.url,
    required this.fallback,
    this.preset = 'musician_singer_black',
    this.color = '#8B5CF6',
    this.radius = 48,
    this.onTap,
  });
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
          gradient: LinearGradient(
            colors: [Color(0xFFC29BFF), Color(0xFF53E0D0)],
          ),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: avatarColor(color),
          backgroundImage: image,
          child:
              image == null
                  ? Icon(
                    avatarIcon(preset),
                    size: radius * .92,
                    color: Colors.white,
                  )
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
  'musician_tuba_burgundy',
  'musician_trumpet_black',
  'musician_accordion_black',
  'musician_singer_black',
  'musician_accordion_red',
  'musician_drums_cowboy',
  'musician_guitar_white_hat',
  'musician_guitar_black_cap',
  'musician_singer_black_cap',
  'musician_bass_black_jacket',
  'musician_guitar_sunset',
  'musician_accordion_blue',
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
    builder:
        (sheetContext) => StatefulBuilder(
          builder:
              (_, setSheetState) => Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Crea tu avatar',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Elige un símbolo y un color que te representen.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ProfileAvatar(
                      fallback: 'A',
                      preset: preset,
                      color: color,
                      radius: 52,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 350,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
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
                                color:
                                    item == preset
                                        ? Colors.white.withValues(alpha: .18)
                                        : Colors.white.withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color:
                                      item == preset
                                          ? const Color(0xFFC7ACFF)
                                          : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  avatarAsset(item)!,
                                  fit: BoxFit.cover,
                                ),
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
                                  color:
                                      item == color
                                          ? Colors.white
                                          : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed:
                          () => Navigator.pop(
                            sheetContext,
                            AvatarSelection(preset, color),
                          ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Usar este avatar'),
                    ),
                  ],
                ),
              ),
        ),
  );
}
