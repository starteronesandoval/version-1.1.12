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
          final controlsWidth = constraints.maxWidth < 340 ? 64.0 : 76.0;
          final staffLeft = controlsWidth + 8;
          final staffWidth = constraints.maxWidth - staffLeft;
          final noteSize = constraints.maxWidth < 340 ? 58.0 : 66.0;
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
                left: staffLeft,
                right: 0,
                top: 0,
                bottom: 0,
                child: CustomPaint(
                  painter: const _VerticalStaffPainter(),
                ),
              ),
              AnimatedBuilder(
                animation: _fallController,
                builder: (_, child) {
                  final start = -noteSize - 8;
                  final end = constraints.maxHeight - noteSize - 18;
                  final top = start + ((end - start) * _fallController.value);
                  return Positioned(
                    left: staffLeft +
                        _staffPitchX(_pitchIndex, staffWidth) -
                        (noteSize / 2),
                    top: top,
                    width: noteSize,
                    height: noteSize,
                    child: child!,
                  );
                },
                child: _FallingNote(
                  figure: _figure,
                  color: _pitches[_pitchIndex].color,
                  holding: _holding,
                ),
              ),
              Positioned(
                left: staffLeft + 4,
                right: 4,
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
                left: 0,
                width: controlsWidth,
                top: 0,
                bottom: 0,
                child: _pitchCircles(),
              ),
              Positioned(
                left: staffLeft,
                right: 0,
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
                    onPointerUp: (_) => _releasePitch(i),
                    onPointerCancel: (_) => _releasePitch(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: circleSize,
                        height: circleSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _pressedPitch == i
                              ? _pitches[i].color
                              : const Color(0xFF20123D),
                          border: Border.all(
                            color: _pitches[i].color,
                            width: _pressedPitch == i ? 4 : 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _pitches[i].color.withValues(
                                  alpha: _pressedPitch == i ? .75 : .35),
                              blurRadius: _pressedPitch == i ? 20 : 10,
                              spreadRadius: _pressedPitch == i ? 3 : 0,
                            ),
                          ],
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              _pitches[i].name,
                              style: TextStyle(
                                color: _pressedPitch == i
                                    ? const Color(0xFF170C2C)
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
            ],
          );
        },
      );

  double _staffPitchX(int index, double width) {
    const margin = 32.0;
    final usableWidth = math.max(80.0, width - (margin * 2));
    final lineSpacing = usableWidth / 4;
    return margin + (index * lineSpacing / 2);
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
                  'El pentagrama permanece fijo. Cuando la figura llegue a la zona verde, mantén presionado su círculo de la izquierda durante el valor indicado.',
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

class _FallingNote extends StatelessWidget {
  const _FallingNote({
    required this.figure,
    required this.color,
    required this.holding,
  });

  final _RhythmFigure figure;
  final Color color;
  final bool holding;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: .72), color],
          ),
          border:
              Border.all(color: Colors.white.withValues(alpha: .85), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: holding ? .7 : .38),
              blurRadius: holding ? 28 : 15,
              spreadRadius: holding ? 4 : 1,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              figure.symbol,
              style: const TextStyle(
                color: Color(0xFF170C2C),
                fontSize: 38,
                fontWeight: FontWeight.w900,
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
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xFF61DDCB), Color(0xFF9A62F5)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 2;
    for (var i = 0; i < 5; i++) {
      final x = margin + (i * lineSpacing);
      canvas.drawLine(Offset(x, 12), Offset(x, size.height - 12), paint);
    }

    final beatPaint = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    for (var y = 42.0; y < size.height; y += 58) {
      canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), beatPaint);
    }

    final clef = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(color: Color(0xFFD5BDFF), fontSize: 44, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clef.paint(canvas, Offset(size.width - clef.width - 4, 8));
  }

  @override
  bool shouldRepaint(covariant _VerticalStaffPainter oldDelegate) => false;
}
