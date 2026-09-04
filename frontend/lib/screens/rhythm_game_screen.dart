import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/glass_ui.dart';

class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({super.key});

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen> {
  static const _bpm = 80;
  static const _beatMilliseconds = 60000 / _bpm;
  static const _notes = <_RhythmNote>[
    _RhythmNote('Redonda', '𝅝', 4),
    _RhythmNote('Blanca', '𝅗𝅥', 2),
    _RhythmNote('Negra', '♩', 1),
    _RhythmNote('Corchea', '♪', .5),
    _RhythmNote('Semicorchea', '♬', .25),
  ];

  final _random = math.Random();
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _nextRoundTimer;
  late _RhythmNote _current;
  int _score = 0;
  int _streak = 0;
  int _lives = 3;
  int _round = 1;
  int _elapsedMilliseconds = 0;
  bool _holding = false;
  bool _waitingForNext = false;
  String _feedback = 'Mantén presionado para saltar';
  Color _feedbackColor = Colors.white70;

  @override
  void initState() {
    super.initState();
    _current = _notes[_random.nextInt(_notes.length)];
  }

  int get _targetMilliseconds => (_current.beats * _beatMilliseconds).round();

  double get _holdRatio =>
      _targetMilliseconds == 0 ? 0 : _elapsedMilliseconds / _targetMilliseconds;

  void _startHold() {
    if (_holding || _waitingForNext || _lives == 0) return;
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      setState(() => _elapsedMilliseconds = _stopwatch.elapsedMilliseconds);
    });
    setState(() {
      _holding = true;
      _elapsedMilliseconds = 0;
      _feedback = '¡En el aire! Suelta al completar los tiempos';
      _feedbackColor = const Color(0xFF7DE8D8);
    });
  }

  void _endHold() {
    if (!_holding) return;
    _stopwatch.stop();
    _ticker?.cancel();
    final elapsed = _stopwatch.elapsedMilliseconds;
    final error = (elapsed - _targetMilliseconds).abs();
    final relativeError = error / _targetMilliseconds;
    final minimumTolerance = _current.beats <= .5 ? 90 : 0;
    final perfectTolerance = math.max(
      (_targetMilliseconds * .12).round(),
      minimumTolerance,
    );
    final goodTolerance = math.max(
      (_targetMilliseconds * .25).round(),
      minimumTolerance + 55,
    );

    var points = 0;
    var message = '';
    var color = Colors.white;
    if (error <= perfectTolerance) {
      _streak++;
      points = 100 + (_streak * 10);
      message = '¡Ritmo perfecto! +$points';
      color = const Color(0xFF67E8D2);
    } else if (error <= goodTolerance || relativeError <= .25) {
      _streak++;
      points = 60 + (_streak * 5);
      message = '¡Buen salto! +$points';
      color = const Color(0xFFFFD166);
    } else {
      _streak = 0;
      _lives--;
      message = elapsed < _targetMilliseconds
          ? 'Soltaste demasiado pronto'
          : 'Mantuviste el salto demasiado tiempo';
      color = const Color(0xFFFF8190);
    }

    setState(() {
      _holding = false;
      _waitingForNext = true;
      _elapsedMilliseconds = elapsed;
      _score += points;
      _feedback = message;
      _feedbackColor = color;
    });

    if (_lives > 0) {
      _nextRoundTimer = Timer(const Duration(milliseconds: 900), _nextRound);
    }
  }

  void _nextRound() {
    if (!mounted) return;
    var next = _notes[_random.nextInt(_notes.length)];
    if (_notes.length > 1) {
      while (next == _current) {
        next = _notes[_random.nextInt(_notes.length)];
      }
    }
    setState(() {
      _current = next;
      _round++;
      _elapsedMilliseconds = 0;
      _waitingForNext = false;
      _feedback = 'Mantén presionado para saltar';
      _feedbackColor = Colors.white70;
    });
  }

  void _restart() {
    _ticker?.cancel();
    _nextRoundTimer?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    setState(() {
      _score = 0;
      _streak = 0;
      _lives = 3;
      _round = 1;
      _elapsedMilliseconds = 0;
      _holding = false;
      _waitingForNext = false;
      _current = _notes[_random.nextInt(_notes.length)];
      _feedback = 'Mantén presionado para saltar';
      _feedbackColor = Colors.white70;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _nextRoundTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String _formatMilliseconds(int value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)} s';
    return '$value ms';
  }

  String _formatBeats(double value) {
    if (value == 4) return '4 tiempos';
    if (value == 2) return '2 tiempos';
    if (value == 1) return '1 tiempo';
    if (value == .5) return '½ tiempo';
    return '¼ de tiempo';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _holdRatio.clamp(0.0, 1.0);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Salto musical',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Entrena tu ritmo',
                style: TextStyle(fontSize: 12, color: Color(0xFFC8B5EE))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cómo jugar',
            onPressed: _showInstructions,
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                _scoreBar(),
                const SizedBox(height: 12),
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _pill(Icons.speed_rounded, '$_bpm BPM'),
                            Text('Ronda $_round',
                                style: const TextStyle(
                                    color: Color(0xFFCDB7F7),
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (_, constraints) => Stack(
                              alignment: Alignment.center,
                              children: [
                                const Positioned.fill(
                                    child: CustomPaint(
                                        painter: _MusicTrackPainter())),
                                Positioned(
                                  right: constraints.maxWidth * .12,
                                  top: constraints.maxHeight * .31,
                                  child: _TargetNote(note: _current),
                                ),
                                Positioned(
                                  left: constraints.maxWidth * .08,
                                  bottom: 34 +
                                      _jumpHeight(
                                          constraints.maxHeight, progress),
                                  child: const _Musician(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          _feedback,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _feedbackColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        _timingMeter(progress),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_lives == 0)
                  FilledButton.icon(
                    onPressed: _restart,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(64)),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text('Jugar otra vez • $_score puntos'),
                  )
                else
                  Listener(
                    onPointerDown: (_) => _startHold(),
                    onPointerUp: (_) => _endHold(),
                    onPointerCancel: (_) => _endHold(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 72,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          colors: _holding
                              ? const [Color(0xFF28BFA9), Color(0xFF2385D0)]
                              : const [Color(0xFF9A62F5), Color(0xFF6A3BC1)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_holding
                                    ? const Color(0xFF38D9C2)
                                    : const Color(0xFF9A62F5))
                                .withValues(alpha: .35),
                            blurRadius: 24,
                            spreadRadius: _holding ? 4 : 0,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_holding
                                ? Icons.keyboard_double_arrow_up_rounded
                                : Icons.touch_app_rounded),
                            const SizedBox(width: 10),
                            Text(
                              _waitingForNext
                                  ? 'PREPÁRATE…'
                                  : _holding
                                      ? 'MANTÉN Y SUELTA'
                                      : 'MANTÉN PARA SALTAR',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _jumpHeight(double availableHeight, double progress) {
    if (!_holding && !_waitingForNext) return 0;
    final safeHeight = math.min(availableHeight * .32, 100.0);
    final arcProgress = progress.clamp(0.0, 1.0);
    return math.sin(arcProgress * math.pi) * safeHeight;
  }

  Widget _scoreBar() => Row(
        children: [
          Expanded(child: _statCard(Icons.stars_rounded, '$_score', 'Puntos')),
          const SizedBox(width: 8),
          Expanded(
              child: _statCard(
                  Icons.local_fire_department_rounded, 'x$_streak', 'Racha')),
          const SizedBox(width: 8),
          Expanded(
            child: _statCard(
              Icons.favorite_rounded,
              '♥' * _lives + '♡' * (3 - _lives),
              'Vidas',
            ),
          ),
        ],
      );

  Widget _statCard(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: const Color(0xFFD2B7FF)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(value,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: .58))),
          ],
        ),
      );

  Widget _pill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF78E2D2)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _timingMeter(double progress) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatMilliseconds(_elapsedMilliseconds),
                  style: const TextStyle(fontFeatures: [
                    FontFeature.tabularFigures(),
                  ])),
              Text('Meta: ${_formatMilliseconds(_targetMilliseconds)}',
                  style: const TextStyle(
                      color: Color(0xFFCDB7F7), fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 12,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: .1),
              color: _holdRatio > 1.25
                  ? const Color(0xFFFF6578)
                  : const Color(0xFF61DDCB),
            ),
          ),
        ],
      );

  Future<void> _showInstructions() => showModalBottomSheet<void>(
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
                  'Mantén presionado el botón durante el valor de la figura y suelta justo al completar sus tiempos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .7)),
                ),
                const SizedBox(height: 14),
                for (final note in _notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 38,
                            child: Text(note.symbol,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 25))),
                        Expanded(child: Text(note.name)),
                        Text(_formatBeats(note.beats),
                            style: const TextStyle(
                                color: Color(0xFF7DE8D8),
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _RhythmNote {
  const _RhythmNote(this.name, this.symbol, this.beats);

  final String name;
  final String symbol;
  final double beats;
}

class _TargetNote extends StatelessWidget {
  const _TargetNote({required this.note});

  final _RhythmNote note;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 86,
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFD16A), Color(0xFFB979F7)]),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFC861).withValues(alpha: .38),
                    blurRadius: 28,
                    spreadRadius: 3),
              ],
            ),
            child: Text(note.symbol,
                style: const TextStyle(
                    color: Color(0xFF211037),
                    fontSize: 48,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 6),
          Text(note.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      );
}

class _Musician extends StatelessWidget {
  const _Musician();

  @override
  Widget build(BuildContext context) => Container(
        width: 82,
        height: 82,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF241343),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF75E2D1), width: 2),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF5DD8C6).withValues(alpha: .32),
                blurRadius: 18),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Image.asset(
            'assets/avatars/jaguar_guitar.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded,
                size: 48, color: Color(0xFF75E2D1)),
          ),
        ),
      );
}

class _MusicTrackPainter extends CustomPainter {
  const _MusicTrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: .14)
      ..strokeWidth = 1.4;
    final glowPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF62DCCB), Color(0xFF9D6AF4)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 3;
    final baseY = size.height - 26;
    canvas.drawLine(Offset(8, baseY), Offset(size.width - 8, baseY), glowPaint);
    final staffTop = size.height * .34;
    for (var i = 0; i < 5; i++) {
      final y = staffTop + (i * 14);
      canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), linePaint);
    }
    final starPaint = Paint()..color = Colors.white.withValues(alpha: .2);
    for (var i = 0; i < 12; i++) {
      final x = (i * 47.0 + 17) % math.max(size.width, 1);
      final y = (i * 31.0 + 12) % math.max(size.height * .65, 1);
      canvas.drawCircle(Offset(x, y), i.isEven ? 1.8 : 1.1, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
