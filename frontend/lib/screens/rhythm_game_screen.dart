import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../widgets/glass_ui.dart';

class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({super.key});

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen>
    with SingleTickerProviderStateMixin {
  static const _pitches = <_Pitch>[
    _Pitch('DO', Color(0xFFFF6680)),
    _Pitch('RE', Color(0xFFFF9B57)),
    _Pitch('MI', Color(0xFFFFD166)),
    _Pitch('FA', Color(0xFF62D99F)),
    _Pitch('SOL', Color(0xFF55CDE1)),
    _Pitch('LA', Color(0xFF788BFF)),
    _Pitch('SI', Color(0xFFC879F4)),
  ];
  // Nueve posiciones, leídas de derecha a izquierda sobre las cinco líneas.
  static const _staffPositions = <int>[2, 3, 4, 5, 6, 0, 1, 2, 3];

  final _random = math.Random();
  final _audioPlayer = AudioPlayer();
  late final AnimationController _fallController;
  Timer? _feedbackTimer;
  Timer? _buttonTimer;
  int _positionIndex = 0;
  int? _pressedPitch;
  int _score = 0;
  int _streak = 0;
  int _lives = 3;
  int _round = 1;
  bool _answered = false;
  String _feedback = '';
  Color _feedbackColor = Colors.transparent;

  int get _pitchIndex => _staffPositions[_positionIndex];
  int get _fallMilliseconds => math.max(850, 2800 - ((_round - 1) * 75));
  double get _speedMultiplier => 2800 / _fallMilliseconds;

  @override
  void initState() {
    super.initState();
    _positionIndex = _random.nextInt(_staffPositions.length);
    _fallController =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: _fallMilliseconds),
          )
          ..addStatusListener(_fallStatus)
          ..forward();
  }

  void _fallStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _lives == 0) {
      return;
    }
    if (!_answered) _bad();
    if (_lives > 0) _nextRound();
  }

  void _pressPitch(int index) {
    if (_answered || _lives == 0) return;
    final entryDifference = (1 - _fallController.value).abs();
    if (index != _pitchIndex || entryDifference > .30) {
      _bad(index);
      return;
    }
    if (_speedMultiplier >= 1.8 && _streak >= 4 && entryDifference <= .07) {
      _result(index, 'GENIO', const Color(0xFFFFE066), 180);
    } else if (entryDifference <= .10) {
      _result(index, 'EXCELENTE', const Color(0xFF65F1CC), 120);
    } else {
      _result(index, 'BIEN', const Color(0xFF70C8FF), 70);
    }
  }

  void _result(int pressedPitch, String label, Color color, int points) {
    _streak++;
    setState(() {
      _answered = true;
      _pressedPitch = pressedPitch;
      _score += points + (_streak * 10);
      _feedback = label;
      _feedbackColor = color;
    });
    unawaited(
      _playRetroSound(
        label == 'GENIO'
            ? const [880, 1175, 1568]
            : label == 'EXCELENTE'
            ? const [660, 880]
            : const [520, 660],
      ),
    );
    _scheduleVisualReset();
  }

  void _bad([int? pressedPitch]) {
    if (_answered || _lives == 0) return;
    setState(() {
      _pressedPitch = pressedPitch;
      _answered = true;
      _streak = 0;
      _lives--;
      _feedback = 'MAL';
      _feedbackColor = const Color(0xFFFF6578);
    });
    unawaited(_playRetroSound(const [190, 125], stepMilliseconds: 105));
    _scheduleVisualReset();
  }

  Future<void> _playRetroSound(
    List<int> frequencies, {
    int stepMilliseconds = 75,
  }) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(
        BytesSource(
          _squareWave(frequencies, stepMilliseconds),
          mimeType: 'audio/wav',
        ),
      );
    } catch (_) {
      // El audio mejora la experiencia, pero nunca debe interrumpir el juego.
    }
  }

  Uint8List _squareWave(List<int> frequencies, int stepMilliseconds) {
    const sampleRate = 11025;
    final samplesPerStep = sampleRate * stepMilliseconds ~/ 1000;
    final sampleCount = samplesPerStep * frequencies.length;
    final bytes = Uint8List(44 + sampleCount);
    final header = ByteData.sublistView(bytes);

    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + sampleCount, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate, Endian.little);
    header.setUint16(32, 1, Endian.little);
    header.setUint16(34, 8, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, sampleCount, Endian.little);

    var output = 44;
    for (final frequency in frequencies) {
      final period = sampleRate / frequency;
      for (var sample = 0; sample < samplesPerStep; sample++) {
        bytes[output++] = sample % period < period / 2 ? 220 : 36;
      }
    }
    return bytes;
  }

  void _scheduleVisualReset() {
    _feedbackTimer?.cancel();
    _buttonTimer?.cancel();
    _buttonTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _pressedPitch = null);
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 620), () {
      if (mounted) {
        setState(() {
          _feedback = '';
          _feedbackColor = Colors.transparent;
        });
      }
    });
  }

  void _nextRound() {
    if (!mounted) return;
    final oldPosition = _positionIndex;
    do {
      _positionIndex = _random.nextInt(_staffPositions.length);
    } while (_positionIndex == oldPosition);
    _round++;
    _fallController.duration = Duration(milliseconds: _fallMilliseconds);
    _fallController
      ..reset()
      ..forward();
    setState(() {
      _pressedPitch = null;
      _answered = false;
    });
  }

  void _restart() {
    _feedbackTimer?.cancel();
    _buttonTimer?.cancel();
    _positionIndex = _random.nextInt(_staffPositions.length);
    _round = 1;
    _fallController.duration = Duration(milliseconds: _fallMilliseconds);
    _fallController
      ..reset()
      ..forward();
    setState(() {
      _pressedPitch = null;
      _score = 0;
      _streak = 0;
      _lives = 3;
      _answered = false;
      _feedback = '';
      _feedbackColor = Colors.transparent;
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _buttonTimer?.cancel();
    unawaited(_audioPlayer.dispose());
    _fallController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pentagrama Balam',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Etapa 1 · Identifica la nota negra',
            style: TextStyle(fontSize: 12, color: Color(0xFFFFC270)),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Cómo jugar',
          onPressed: _instructions,
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ],
    ),
    body: GlassBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Column(
            children: [
              _scoreBar(),
              const SizedBox(height: 8),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _pill(Icons.school_rounded, 'ETAPA 1'),
                          Text(
                            'Velocidad ×${_speedMultiplier.toStringAsFixed(1)}',
                            style: const TextStyle(
                              color: Color(0xFFFFD7A3),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Ronda $_round',
                            style: const TextStyle(
                              color: Color(0xFFFFC270),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(child: _gameBoard()),
                    ],
                  ),
                ),
              ),
              if (_lives == 0) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _restart,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                  ),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text('Jugar otra vez • $_score puntos'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _gameBoard() => LayoutBuilder(
    builder: (_, constraints) {
      final controlsWidth = constraints.maxWidth < 340 ? 64.0 : 76.0;
      final staffRight = controlsWidth + 8;
      final staffWidth = constraints.maxWidth - staffRight;
      final noteSize = constraints.maxWidth < 340 ? 58.0 : 66.0;
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF100B07).withValues(alpha: .38),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: staffRight,
            top: 0,
            bottom: 0,
            child: CustomPaint(painter: const _VerticalStaffPainter()),
          ),
          AnimatedBuilder(
            animation: _fallController,
            builder: (_, child) {
              final start = -noteSize - 8;
              final end = constraints.maxHeight - noteSize - 18;
              final top = start + ((end - start) * _fallController.value);
              return Positioned(
                left: _staffPitchX(_positionIndex, staffWidth) - (noteSize / 2),
                top: top,
                width: noteSize,
                height: noteSize,
                child: child!,
              );
            },
            child: _FallingNote(
              color: _pitches[_pitchIndex].color,
              monochrome: _score >= 300,
            ),
          ),
          Positioned(
            left: 4,
            right: staffRight + 4,
            bottom: 0,
            height: 26,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF65F1CC).withValues(alpha: 0),
                    const Color(0xFF65F1CC).withValues(alpha: .35),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            right: 0,
            width: controlsWidth,
            top: 0,
            bottom: 0,
            child: _pitchCircles(),
          ),
          Positioned(
            left: 0,
            right: staffRight,
            top: 0,
            bottom: 0,
            child: Center(child: _feedbackBadge()),
          ),
        ],
      );
    },
  );

  Widget _pitchCircles() => LayoutBuilder(
    builder: (_, constraints) {
      final circleSize = math.min(54.0, (constraints.maxHeight / 7) - 5);
      return Column(
        children: [
          for (var i = 0; i < _pitches.length; i++)
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _pressPitch(i),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: circleSize,
                    height: circleSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          _pressedPitch == i
                              ? _pitches[i].color
                              : const Color(0xFF201008),
                      border: Border.all(
                        color: _pitches[i].color,
                        width: _pressedPitch == i ? 4 : 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _pitches[i].color.withValues(
                            alpha: _pressedPitch == i ? .75 : .35,
                          ),
                          blurRadius: _pressedPitch == i ? 20 : 10,
                          spreadRadius: _pressedPitch == i ? 3 : 0,
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Transform.rotate(
                          angle: -math.pi / 2,
                          child: Text(
                            _pitches[i].name,
                            style: TextStyle(
                              color:
                                  _pressedPitch == i
                                      ? const Color(0xFF171008)
                                      : _pitches[i].color,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  double _staffPitchX(int positionFromRight, double width) {
    const margin = 32.0;
    final usableWidth = math.max(80.0, width - (margin * 2));
    final lineSpacing = usableWidth / 4;
    return width - margin - (positionFromRight * lineSpacing / 2);
  }

  Widget _feedbackBadge() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    transitionBuilder:
        (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: animation, child: child),
        ),
    child:
        _feedback.isEmpty
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Container(
              key: ValueKey(_feedback),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF100B07).withValues(alpha: .9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _feedbackColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _feedbackColor.withValues(alpha: .48),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Text(
                _feedback,
                style: TextStyle(
                  color: _feedbackColor,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
            ),
  );

  Widget _scoreBar() => Row(
    children: [
      Expanded(child: _stat(Icons.stars_rounded, '$_score', 'Puntos')),
      const SizedBox(width: 6),
      Expanded(
        child: _stat(Icons.local_fire_department_rounded, 'x$_streak', 'Racha'),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: _stat(
          Icons.favorite_rounded,
          '♥' * _lives + '♡' * (3 - _lives),
          'Vidas',
        ),
      ),
    ],
  );

  Widget _stat(IconData icon, String value, String label) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: const Color(0xFFFFC270)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: .58),
          ),
        ),
      ],
    ),
  );

  Widget _pill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFFFA000)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Future<void> _instructions() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF17110B),
    showDragHandle: true,
    builder:
        (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cómo jugar',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gira el teléfono 90° hacia la derecha. Cuando la nota negra llegue a la zona verde, toca su nombre en los círculos que quedarán abajo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .7)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'De derecha a izquierda:',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'MI · FA · SOL · LA · SI · DO · RE · MI · FA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFA000),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
  );
}

class _Pitch {
  const _Pitch(this.name, this.color);
  final String name;
  final Color color;
}

class _FallingNote extends StatelessWidget {
  const _FallingNote({required this.color, required this.monochrome});

  final Color color;
  final bool monochrome;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 100),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors:
            monochrome
                ? const [Color(0xFFF4F4F4), Color(0xFFBEBEBE)]
                : [color.withValues(alpha: .72), color],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .85), width: 2),
      boxShadow: [
        BoxShadow(
          color: (monochrome ? Colors.white : color).withValues(alpha: .5),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    alignment: Alignment.center,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Transform.rotate(
          angle: math.pi / 2,
          child: const Text(
            '♩',
            style: TextStyle(
              color: Color(0xFF171008),
              fontSize: 38,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ),
  );
}

class _VerticalStaffPainter extends CustomPainter {
  const _VerticalStaffPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 32.0;
    final lineSpacing = math.max(20.0, (size.width - (margin * 2)) / 4);
    final paint =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xFFFFB24A), Color(0xFFFF6D00)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
          ..strokeWidth = 2;
    for (var i = 0; i < 5; i++) {
      final x = margin + (i * lineSpacing);
      canvas.drawLine(Offset(x, 12), Offset(x, size.height - 12), paint);
    }

    final beatPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: .06)
          ..strokeWidth = 1;
    for (var y = 42.0; y < size.height; y += 58) {
      canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), beatPaint);
    }

    final clef = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(color: Color(0xFFFFC270), fontSize: 44, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clef.paint(canvas, Offset(size.width - clef.width - 4, 8));
  }

  @override
  bool shouldRepaint(covariant _VerticalStaffPainter oldDelegate) => false;
}
