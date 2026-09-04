import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/glass_ui.dart';

class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({super.key});

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen>
    with SingleTickerProviderStateMixin {
  static const _bpm = 80;
  static const _beatMilliseconds = 60000 / _bpm;
  static const _figures = <_RhythmFigure>[
    _RhythmFigure('Redonda', '𝅝', 4),
    _RhythmFigure('Blanca', '𝅗𝅥', 2),
    _RhythmFigure('Negra', '♩', 1),
    _RhythmFigure('Corchea', '♪', .5),
    _RhythmFigure('Semicorchea', '♬', .25),
  ];
  static const _pitches = <_Pitch>[
    _Pitch('DO', Color(0xFFFF6680)),
    _Pitch('RE', Color(0xFFFF9B57)),
    _Pitch('MI', Color(0xFFFFD166)),
    _Pitch('FA', Color(0xFF62D99F)),
    _Pitch('SOL', Color(0xFF55CDE1)),
    _Pitch('LA', Color(0xFF788BFF)),
    _Pitch('SI', Color(0xFFC879F4)),
  ];

  final _random = math.Random();
  final _holdWatch = Stopwatch();
  late final AnimationController _fallController;
  Timer? _nextTimer;
  Timer? _missTimer;
  late _RhythmFigure _figure;
  int _pitchIndex = 0;
  int? _pressedPitch;
  int _score = 0;
  int _streak = 0;
  int _lives = 3;
  int _round = 1;
  bool _holding = false;
  bool _waiting = false;
  bool _perfectEntry = false;
  String _feedback = '';
  Color _feedbackColor = Colors.transparent;

  int get _targetMilliseconds => (_figure.beats * _beatMilliseconds).round();

  @override
  void initState() {
    super.initState();
    _figure = _figures[_random.nextInt(_figures.length)];
    _pitchIndex = _random.nextInt(_pitches.length);
    _fallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )
      ..addStatusListener(_fallStatus)
      ..forward();
  }

  void _fallStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        _holding ||
        _waiting ||
        _lives == 0) {
      return;
    }
    _missTimer?.cancel();
    _missTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_holding && !_waiting) _bad();
    });
  }

  void _pressPitch(int index) {
    if (_holding || _waiting || _lives == 0) return;
    _missTimer?.cancel();
    final entryDifference = (1 - _fallController.value).abs();
    if (index != _pitchIndex || entryDifference > .28) {
      _bad();
      return;
    }
    _fallController.stop();
    _holdWatch
      ..reset()
      ..start();
    setState(() {
      _holding = true;
      _pressedPitch = index;
      _perfectEntry = entryDifference <= .1;
      _feedback = '';
    });
  }

  void _releasePitch(int index) {
    if (!_holding || _pressedPitch != index) return;
    _holdWatch.stop();
    final error = (_holdWatch.elapsedMilliseconds - _targetMilliseconds).abs();
    final perfectTolerance = math.max(
      (_targetMilliseconds * .12).round(),
      _figure.beats <= .5 ? 90 : 0,
    );
    final goodTolerance = math.max(
      (_targetMilliseconds * .25).round(),
      _figure.beats <= .5 ? 145 : 0,
    );
    if (_perfectEntry && error <= perfectTolerance) {
      _result('PERFECTO', const Color(0xFF65F1CC), 120);
    } else if (error <= goodTolerance) {
      _result('BIEN', const Color(0xFFFFD166), 70);
    } else {
      _bad();
    }
  }

  void _result(String label, Color color, int points) {
    _holdWatch.stop();
    _missTimer?.cancel();
    _streak++;
    setState(() {
      _holding = false;
      _pressedPitch = null;
      _waiting = true;
      _score += points + (_streak * 10);
      _feedback = label;
      _feedbackColor = color;
    });
    _nextTimer = Timer(const Duration(milliseconds: 900), _nextRound);
  }

  void _bad() {
    if (_waiting || _lives == 0) return;
    _holdWatch.stop();
    _missTimer?.cancel();
    _fallController.stop();
    setState(() {
      _holding = false;
      _pressedPitch = null;
      _waiting = true;
      _streak = 0;
      _lives--;
      _feedback = 'MAL';
      _feedbackColor = const Color(0xFFFF6578);
    });
    if (_lives > 0) {
      _nextTimer = Timer(const Duration(milliseconds: 900), _nextRound);
    }
  }

  void _nextRound() {
    if (!mounted) return;
    final oldFigure = _figure;
    final oldPitch = _pitchIndex;
    do {
      _figure = _figures[_random.nextInt(_figures.length)];
      _pitchIndex = _random.nextInt(_pitches.length);
    } while (_figure == oldFigure && _pitchIndex == oldPitch);
    _fallController
      ..reset()
      ..forward();
    setState(() {
      _round++;
      _waiting = false;
      _feedback = '';
      _feedbackColor = Colors.transparent;
    });
  }

  void _restart() {
    _nextTimer?.cancel();
    _missTimer?.cancel();
    _holdWatch
      ..stop()
      ..reset();
    _figure = _figures[_random.nextInt(_figures.length)];
    _pitchIndex = _random.nextInt(_pitches.length);
    _fallController
      ..reset()
      ..forward();
    setState(() {
      _pressedPitch = null;
      _score = 0;
      _streak = 0;
      _lives = 3;
      _round = 1;
      _holding = false;
      _waiting = false;
      _feedback = '';
      _feedbackColor = Colors.transparent;
    });
  }

  @override
  void dispose() {
    _nextTimer?.cancel();
    _missTimer?.cancel();
    _fallController.dispose();
    _holdWatch.stop();
    super.dispose();
  }

  String _beats(double value) {
    if (value == 4) return '4 tiempos';
    if (value == 2) return '2 tiempos';
    if (value == 1) return '1 tiempo';
    if (value == .5) return '½ tiempo';
    return '¼ de tiempo';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pentagrama Balam',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              Text('Identifica y sostén la nota',
                  style: TextStyle(fontSize: 12, color: Color(0xFFC8B5EE))),
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
                              _pill(Icons.speed_rounded, '$_bpm BPM'),
                              Text('${_figure.name} · ${_beats(_figure.beats)}',
                                  style: const TextStyle(
                                      color: Color(0xFFD8C5F5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              Text('Ronda $_round',
                                  style: const TextStyle(
                                      color: Color(0xFFCDB7F7),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
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
                          minimumSize: const Size.fromHeight(58)),
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
          final controlsWidth = constraints.maxWidth < 340 ? 58.0 : 68.0;
          final fallingWidth = constraints.maxWidth - controlsWidth - 10;
          final cardHeight = (74 + (_figure.beats * 13)).clamp(78.0, 126.0);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF120A27).withValues(alpha: .38),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              Positioned(
                left: fallingWidth + 4,
                right: 0,
                top: 0,
                bottom: 0,
                child: CustomPaint(
                  painter: _ReferenceStaffPainter(_pitches),
                ),
              ),
              AnimatedBuilder(
                animation: _fallController,
                builder: (_, child) {
                  final start = -cardHeight - 8;
                  final end = constraints.maxHeight - cardHeight - 12;
                  final top = start + ((end - start) * _fallController.value);
                  return Positioned(
                    left: 8,
                    top: top,
                    width: fallingWidth - 12,
                    height: cardHeight,
                    child: child!,
                  );
                },
                child: _FallingStaff(
                  pitchIndex: _pitchIndex,
                  figure: _figure,
                  color: _pitches[_pitchIndex].color,
                  holding: _holding,
                ),
              ),
              Positioned(
                left: 6,
                width: fallingWidth - 8,
                bottom: 0,
                height: 22,
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
                left: fallingWidth + 4,
                width: controlsWidth - 4,
                top: 0,
                bottom: 0,
                child: _pitchCircles(),
              ),
              Positioned(
                left: 0,
                width: fallingWidth,
                top: 0,
                bottom: 0,
                child: Center(child: _feedbackBadge()),
              ),
            ],
          );
        },
      );

  Widget _pitchCircles() => LayoutBuilder(
        builder: (_, constraints) => Stack(
          children: [
            for (var i = 0; i < _pitches.length; i++)
              Positioned(
                right: 3,
                top: _pitchY(i, constraints.maxHeight) - 18,
                width: 44,
                height: 36,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _pressPitch(i),
                  onPointerUp: (_) => _releasePitch(i),
                  onPointerCancel: (_) => _releasePitch(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _pressedPitch == i
                          ? _pitches[i].color
                          : const Color(0xFF20123D),
                      border: Border.all(
                        color: _pitches[i].color,
                        width: _pressedPitch == i ? 3 : 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _pitches[i]
                              .color
                              .withValues(alpha: _pressedPitch == i ? .7 : .3),
                          blurRadius: _pressedPitch == i ? 18 : 8,
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _pitches[i].name,
                        style: TextStyle(
                          color: _pressedPitch == i
                              ? const Color(0xFF170C2C)
                              : _pitches[i].color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  double _pitchY(int index, double height) {
    final lineSpacing = math.min(58.0, (height - 38) / 5.0);
    final bottomLine = height - lineSpacing - 18;
    return bottomLine - ((index - 2) * lineSpacing / 2);
  }

  Widget _feedbackBadge() => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _feedback.isEmpty
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Container(
                key: ValueKey(_feedback),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF160D2B).withValues(alpha: .9),
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
              child: _stat(
                  Icons.local_fire_department_rounded, 'x$_streak', 'Racha')),
          const SizedBox(width: 6),
          Expanded(
              child: _stat(Icons.favorite_rounded,
                  '♥' * _lives + '♡' * (3 - _lives), 'Vidas')),
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
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 15, color: const Color(0xFFD2B7FF)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(value,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: Colors.white.withValues(alpha: .58))),
          ],
        ),
      );

  Widget _pill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: const Color(0xFF78E2D2)),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Future<void> _instructions() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1C1235),
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Cómo jugar',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  'Lee la nota del pentagrama que cae. Cuando llegue a la zona verde, mantén presionado su círculo de la derecha durante el valor de la figura.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .7)),
                ),
                const SizedBox(height: 14),
                for (final figure in _figures)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                          width: 38,
                          child: Text(figure.symbol,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 25))),
                      Expanded(child: Text(figure.name)),
                      Text(_beats(figure.beats),
                          style: const TextStyle(
                              color: Color(0xFF7DE8D8),
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _RhythmFigure {
  const _RhythmFigure(this.name, this.symbol, this.beats);
  final String name;
  final String symbol;
  final double beats;
}

class _Pitch {
  const _Pitch(this.name, this.color);
  final String name;
  final Color color;
}

class _FallingStaff extends StatelessWidget {
  const _FallingStaff({
    required this.pitchIndex,
    required this.figure,
    required this.color,
    required this.holding,
  });

  final int pitchIndex;
  final _RhythmFigure figure;
  final Color color;
  final bool holding;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: const Color(0xFF271548).withValues(alpha: .96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: holding ? .7 : .38),
              blurRadius: holding ? 28 : 15,
              spreadRadius: holding ? 4 : 1,
            ),
          ],
        ),
        child: CustomPaint(
          painter: _MiniStaffPainter(pitchIndex, figure, color),
        ),
      );
}

class _MiniStaffPainter extends CustomPainter {
  const _MiniStaffPainter(this.pitchIndex, this.figure, this.color);
  final int pitchIndex;
  final _RhythmFigure figure;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = math.min(12.0, size.height / 7);
    final top = (size.height - (spacing * 4)) / 2;
    final left = math.min(46.0, size.width * .25);
    final right = size.width - 10;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .45)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      final y = top + (i * spacing);
      canvas.drawLine(Offset(left, y), Offset(right, y), line);
    }
    final clef = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(color: Color(0xFFD9C5FF), fontSize: 48, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clef.paint(canvas, Offset(2, top - 10));

    final bottomLine = top + (spacing * 4);
    final y = bottomLine - ((pitchIndex - 2) * spacing / 2);
    final x = left + ((right - left) * .62);
    final note = Paint()..color = color;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-.2);
    canvas.drawOval(const Rect.fromLTWH(-10, -6, 20, 12), note);
    canvas.restore();
    canvas.drawLine(
        Offset(x + 9, y), Offset(x + 9, y - 27), note..strokeWidth = 2.5);
    if (pitchIndex == 0) {
      canvas.drawLine(Offset(x - 14, y), Offset(x + 14, y), line);
    }
    final symbol = TextPainter(
      text: TextSpan(
        text: figure.symbol,
        style:
            TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    symbol.paint(canvas, Offset(size.width - symbol.width - 8, 3));
  }

  @override
  bool shouldRepaint(covariant _MiniStaffPainter oldDelegate) =>
      oldDelegate.pitchIndex != pitchIndex || oldDelegate.figure != figure;
}

class _ReferenceStaffPainter extends CustomPainter {
  const _ReferenceStaffPainter(this.pitches);
  final List<_Pitch> pitches;

  @override
  void paint(Canvas canvas, Size size) {
    final lineSpacing = math.min(58.0, (size.height - 38) / 5.0);
    final bottomLine = size.height - lineSpacing - 18;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .22)
      ..strokeWidth = 1.1;
    for (var i = 0; i < 5; i++) {
      final y = bottomLine - (i * lineSpacing);
      canvas.drawLine(Offset(0, y), Offset(size.width - 2, y), paint);
    }
    final clef = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(color: Color(0xFFBCA0EE), fontSize: 34, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clef.paint(canvas, Offset(0, bottomLine - (lineSpacing * 3.8)));
    final cY = bottomLine + lineSpacing;
    canvas.drawLine(Offset(4, cY), Offset(size.width - 4, cY), paint);
  }

  @override
  bool shouldRepaint(covariant _ReferenceStaffPainter oldDelegate) => false;
}
