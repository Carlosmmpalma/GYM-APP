import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/design_system.dart';

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

  /// O vídeo escolhido mas ainda não enviado. Fica em memória até
  /// gravar — é o que permite escolher antes de o exercício existir.
  Uint8List? _pendingVideoBytes;
  String? _pendingVideoName;
  String? _pendingVideoContentType;
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
        await _uploadPendingVideo(widget.exercise!.id);
      } else {
        final exerciseId = await repository.createExercise(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          muscleGroup: _muscleGroup,
        );
        // O exercício já existe: agora sim o vídeo tem onde ficar.
        await _uploadPendingVideo(exerciseId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = userFacingError(e,
          fallback: 'Não foi possível guardar. Tenta outra vez.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// UC15 — "Formato ou tamanho inválido é rejeitado com indicação do
  /// requisito". Validação client-side (feedback imediato) + a mesma
  /// regra aplicada a sério em `storage.rules` (contentType/size), não
  /// só aqui.
  /// Fase 11 — ESCOLHER o vídeo deixou de exigir que o exercício já
  /// exista.
  ///
  /// Antes, criar um exercício com vídeo era: preencher, gravar, voltar
  /// a abrir, carregar o vídeo. A app dizia "Guarda o exercício antes
  /// de carregar o vídeo", o que é a app a explicar uma limitação sua
  /// em vez de a resolver. Agora o ficheiro fica em memória e sobe
  /// junto com o resto, ao gravar.
  ///
  /// Aceita qualquer formato de vídeo, não só `.mp4`: um telemóvel
  /// grava `.mov`, e filtrar por extensão fazia o ficheiro nem aparecer
  /// no seletor — que se lê como "o carregamento não funciona".
  String? _videoWarning;

  /// A partir daqui avisa-se sobre o tamanho. Um clipe de demonstração
  /// de 20-30 segundos cabe folgadamente abaixo disto.
  static const _largeVideoMegabytes = 25;

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error =
          'Não foi possível ler o ficheiro. Tenta escolher outra vez.');
      return;
    }
    final megabytes = bytes.lengthInBytes / (1024 * 1024);
    if (megabytes > 100) {
      setState(() => _error = 'Vídeo demasiado grande '
          '(${megabytes.toStringAsFixed(0)} MB). O máximo são 100 MB.');
      return;
    }

    setState(() {
      _pendingVideoBytes = bytes;
      _pendingVideoName = file.name;
      _pendingVideoContentType = _contentTypeFor(file.name);
      _error = null;
      // Aviso, não bloqueio: o tamanho do ficheiro é o que cada aluno
      // descarrega para o ver, e ninguém no estúdio tem como adivinhar
      // isso ao escolher um ficheiro. Quem quiser mesmo carregar um
      // vídeo grande, carrega.
      _videoWarning = megabytes > _largeVideoMegabytes
          ? 'Este vídeo tem ${megabytes.toStringAsFixed(0)} MB. Cada aluno '
              'que o abrir descarrega-o inteiro — um clipe curto (menos de '
              '$_largeVideoMegabytes MB) chega para demonstrar o exercício '
              'e gasta menos dados a quem o vê.'
          : null;
    });
  }

  /// O `contentType` tem de bater certo com o ficheiro: `storage.rules`
  /// exige `video/*`, e etiquetar tudo como `video/mp4` — o que a app
  /// fazia — é mentira sempre que não é mp4.
  static String _contentTypeFor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return switch (extension) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      // Desconhecido mas escolhido num seletor de vídeo: `video/*`
      // satisfaz a regra sem afirmar um formato que não sabemos.
      _ => 'video/mp4',
    };
  }

  /// Sobe o vídeo escolhido, se houver. Corre depois de o exercício
  /// existir — na criação, logo a seguir a criá-lo.
  Future<void> _uploadPendingVideo(String exerciseId) async {
    final bytes = _pendingVideoBytes;
    if (bytes == null) return;

    setState(() => _uploadingVideo = true);
    try {
      final path =
          await ref.read(storageRepositoryProvider).uploadExerciseVideo(
                exerciseId: exerciseId,
                bytes: bytes,
                contentType: _pendingVideoContentType ?? 'video/mp4',
              );
      await ref.read(exerciseRepositoryProvider).setVideoPath(
            exerciseId: exerciseId,
            videoPath: path,
          );
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
                decoration: InputDecoration(labelText: requiredLabel('Nome')),
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
              // Fase 11 — escolher o vídeo já não exige que o exercício
              // exista. Antes era: preencher, gravar, voltar a abrir,
              // carregar. O ficheiro fica em memória e sobe ao gravar.
              const SectionLabel('Vídeo demonstrativo'),
              const SizedBox(height: 2),
              const Text(
                'Opcional. Qualquer formato de vídeo, até 100 MB — mas '
                'quanto mais curto, mais depressa abre para o aluno. Ele '
                'vê-o ao abrir o exercício no plano dele.',
                style:
                    TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
              ),
              if (_videoWarning != null) ...[
                const SizedBox(height: 8),
                AppBanner(text: _videoWarning!, tone: PillTone.warn),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _uploadingVideo ? null : _pickVideo,
                icon: _uploadingVideo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.video_file_outlined),
                label: Text(
                  _pendingVideoBytes != null
                      ? 'Escolher outro ficheiro'
                      : (widget.exercise?.hasVideo ?? false)
                          ? 'Substituir vídeo'
                          : 'Escolher vídeo',
                ),
              ),
              if (_pendingVideoName != null) ...[
                const SizedBox(height: 8),
                PanelCard(
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: AppColors.ok),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          // Dizer que ainda NÃO foi enviado evita a
                          // dúvida de quem escolhe e sai sem gravar.
                          '$_pendingVideoName — envia ao guardar',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _pendingVideoBytes = null;
                          _pendingVideoName = null;
                          _pendingVideoContentType = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ] else if (widget.exercise?.hasVideo ?? false) ...[
                const SizedBox(height: 8),
                const Text(
                  'Já tem vídeo. Escolher outro substitui o atual.',
                  style: TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              if (_error != null) ...[
                AppBanner(text: _error!, tone: PillTone.danger),
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
