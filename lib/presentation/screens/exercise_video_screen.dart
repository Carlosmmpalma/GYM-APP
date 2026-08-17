import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';

/// Fase 8 (UC03/UC15) — reproduz o vídeo demonstrativo de um
/// exercício. Resolve a URL de download em runtime
/// (`StorageRepository.getDownloadUrl`, nunca guardada — pode expirar/
/// depender de token, `videoPath` é a única coisa persistida).
class ExerciseVideoScreen extends ConsumerStatefulWidget {
  const ExerciseVideoScreen({super.key, required this.exercise});

  final Exercise exercise;

  @override
  ConsumerState<ExerciseVideoScreen> createState() =>
      _ExerciseVideoScreenState();
}

class _ExerciseVideoScreenState extends ConsumerState<ExerciseVideoScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final url = await ref
          .read(storageRepositoryProvider)
          .getDownloadUrl(widget.exercise.videoPath!);
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller..play());
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar o vídeo: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.exercise.name)),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              )
            : _controller == null
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
      ),
      floatingActionButton: _controller == null
          ? null
          : FloatingActionButton(
              onPressed: () => setState(() {
                _controller!.value.isPlaying
                    ? _controller!.pause()
                    : _controller!.play();
              }),
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
    );
  }
}
