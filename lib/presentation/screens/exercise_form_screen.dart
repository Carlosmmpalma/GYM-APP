import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/design_system.dart';

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

  /// `null` = ainda não escolhida. Começa no que o exercício já tinha.
  late String? _category = widget.exercise?.category.trim().isEmpty ?? true
      ? null
      : widget.exercise!.category;

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
    // O `DropdownButtonFormField` não faz parte do `Form`, por isso a
    // validação acima não o cobre. Sem isto, gravar sem escolher
    // rebentava num `null!`.
    if (_category == null) {
      setState(() => _error = 'Escolhe uma categoria para este exercício.');
      return;
    }

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
          category: _category!,
        );
        await _uploadPendingVideo(widget.exercise!.id);
      } else {
        final exerciseId = await repository.createExercise(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          category: _category!,
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
              _CategoryField(
                selected: _category,
                onChanged: (value) => setState(() => _category = value),
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

/// O seletor de categoria.
///
/// Era um dropdown com oito valores escritos no código. Um estúdio que
/// quisesse "Mobilidade" ou "Aquecimento" tinha de pedir a um
/// programador — o mesmo erro que `Service`, `Plan` e `Modality` já
/// evitavam desde o início.
///
/// Dois casos que a lista fixa nunca teve de resolver:
///
///  * **Não há categorias nenhumas.** Em vez de um dropdown vazio (que
///    não explica nada), diz onde se criam e deixa criar a primeira
///    sem sair do formulário.
///  * **A categoria deste exercício já não está na lista** — foi
///    desativada, ou o exercício é anterior à gestão de categorias.
///    Aparece na mesma, marcada, para não desaparecer em silêncio ao
///    gravar.
class _CategoryField extends ConsumerWidget {
  const _CategoryField({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(exerciseCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const [];

    final names = [
      for (final category in categories)
        if (category.active) category.name,
    ];
    // A que já está escolhida entra sempre, mesmo que já não seja
    // oferecida: gravar um exercício não pode ser a forma de lhe
    // apagar a categoria sem ninguém pedir.
    if (selected != null && !names.contains(selected)) {
      names.insert(0, selected!);
    }

    if (categoriesAsync.isLoading && names.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }

    if (names.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ainda não há categorias para arrumar os exercícios '
                '(Pernas, Costas, Mobilidade — o que fizer sentido aqui).',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _createInline(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Criar a primeira'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: names
                .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        IconButton(
          tooltip: 'Nova categoria',
          icon: const Icon(Icons.add),
          onPressed: () => _createInline(context, ref),
        ),
      ],
    );
  }

  /// Criar sem sair daqui.
  ///
  /// Obrigar a abandonar o exercício a meio, ir a outro ecrã e voltar é
  /// a diferença entre a lista ser gerível e ninguém lhe mexer.
  Future<void> _createInline(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await ref
          .read(exerciseCategoryRepositoryProvider)
          .createCategory(name: name);
      onChanged(name.trim());
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível criar a categoria.')),
        ),
      );
    }
  }
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova categoria'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nome',
          hintText: 'Pernas, Mobilidade, Hyrox…',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (value) => value.trim().isEmpty
            ? null
            : Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
