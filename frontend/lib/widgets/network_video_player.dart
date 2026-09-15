import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class NetworkVideoPlayer extends StatefulWidget {
  const NetworkVideoPlayer({super.key, required this.url});

  final String url;

  @override
  State<NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<NetworkVideoPlayer> {
  late VideoPlayerController _controller;
  Future<void>? _initialization;
  Object? _error;
  double _volume = 1;
  double _volumeBeforeMute = 1;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(NetworkVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller.dispose();
      _createController();
    }
  }

  void _createController() {
    _error = null;
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialization = _controller
        .initialize()
        .then((_) async {
          await _controller.setLooping(false);
          await _controller.setVolume(_volume);
          if (mounted) setState(() {});
        })
        .catchError((Object error) {
          if (mounted) setState(() => _error = error);
        });
  }

  void _togglePlayback() {
    if (!_controller.value.isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  void _setVolume(double volume) {
    if (!_controller.value.isInitialized) return;
    final normalizedVolume = volume.clamp(0.0, 1.0).toDouble();
    if (normalizedVolume > 0) {
      _volumeBeforeMute = normalizedVolume;
    }
    setState(() => _volume = normalizedVolume);
    _controller.setVolume(normalizedVolume);
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1);
    }
  }

  IconData get _volumeIcon {
    if (_volume == 0) return Icons.volume_off_rounded;
    if (_volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ColoredBox(
        color: Colors.black,
        child: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (_error != null) {
              return SizedBox(
                height: 210,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white70),
                        const SizedBox(height: 8),
                        const Text(
                          'No se pudo reproducir este video.',
                          textAlign: TextAlign.center,
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _controller.dispose();
                            setState(_createController);
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done ||
                !_controller.value.isInitialized) {
              return const SizedBox(
                height: 210,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final ratio = _controller.value.aspectRatio;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _togglePlayback,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: ratio > 0 ? ratio : 16 / 9,
                        child: VideoPlayer(_controller),
                      ),
                      if (!_controller.value.isPlaying)
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                    ],
                  ),
                ),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF68DDCD),
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 14, 6),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _toggleMute,
                        tooltip: _volume == 0
                            ? 'Activar sonido'
                            : 'Silenciar',
                        icon: Icon(_volumeIcon, color: Colors.white),
                      ),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          onChanged: _setVolume,
                          activeColor: const Color(0xFF68DDCD),
                          inactiveColor: Colors.white24,
                          semanticFormatterCallback: (value) =>
                              'Volumen ${(value * 100).round()} por ciento',
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${(_volume * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
