import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';

const _muscleGroups = [
  'Pernas',
  'Costas',
  'Peito',
  'Ombros',
  'Braços',
  'Core',
  'Full body',
  'Hyrox',
];

/// Fase 8 (UC15 fechado) — "Novo exercício"/editar: nome, descrição,
/// grupo muscular, vídeo demonstrativo (opcional). O upload em si fica
/// isolado em `StorageRepository` (Platform Foundation §19) — este
/// ecrã só escolhe o ficheiro e mostra progresso/erro.
class ExerciseFormScreen extends ConsumerStatefulWidget {
  const ExerciseFormScreen({super.key, this.exercise});

  final Exercise? exercise;

  @override
  ConsumerState<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends ConsumerState<ExerciseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController =
      TextEditingController(text: widget.exercise?.name ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.exercise?.description ?? '');
  late String _muscleGroup =
      widget.exercise?.muscleGroup ?? _muscleGroups.first;

  bool _saving = false;
  bool _uploadingVideo = false;
  String? _error;

  bool get _isEditing => widget.exercise != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(exerciseRepositoryProvider);
      if (_isEditing) {
        await repository.updateExercise(
          exerciseId: widget.exercise!.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          muscleGroup: _muscleGroup,
        );
      } else {
        await repository.createExercise(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          muscleGroup: _muscleGroup,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Não foi possível guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// UC15 — "Formato ou tamanho inválido é rejeitado com indicação do
  /// requisito". Validação client-side (feedback imediato) + a mesma
  /// regra aplicada a sério em `storage.rules` (contentType/size), não
  /// só aqui.
  Future<void> _uploadVideo() async {
    final exerciseId = widget.exercise?.id;
    if (exerciseId == null) {
      setState(() => _error = 'Guarda o exercício antes de carregar o vídeo.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Não foi possível ler o ficheiro escolhido.');
      return;
    }
    if (bytes.lengthInBytes > 100 * 1024 * 1024) {
      setState(() => _error = 'Vídeo demasiado grande (máximo 100MB).');
      return;
    }

    setState(() {
      _uploadingVideo = true;
      _error = null;
    });
    try {
      final path =
          await ref.read(storageRepositoryProvider).uploadExerciseVideo(
                exerciseId: exerciseId,
                bytes: bytes,
                contentType: 'video/mp4',
              );
      await ref.read(exerciseRepositoryProvider).setVideoPath(
            exerciseId: exerciseId,
            videoPath: path,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vídeo carregado.')),
      );
    } catch (e) {
      setState(() => _error = 'Não foi possível carregar o vídeo: $e');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Editar exercício' : 'Novo exercício')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Descrição'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _muscleGroup,
                decoration: const InputDecoration(labelText: 'Grupo muscular'),
                items: _muscleGroups
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _muscleGroup = v!),
              ),
              const SizedBox(height: 16),
              if (_isEditing) ...[
                OutlinedButton.icon(
                  onPressed: _uploadingVideo ? null : _uploadVideo,
                  icon: _uploadingVideo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: Text(
                    widget.exercise!.hasVideo
                        ? 'Substituir vídeo demonstrativo'
                        : 'Carregar vídeo demonstrativo (mp4)',
                  ),
                ),
                const SizedBox(height: 16),
              ] else
                const Text(
                  'Guarda o exercício primeiro para poderes carregar o vídeo.',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar exercício'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
