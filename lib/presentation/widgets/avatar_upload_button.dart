import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firebase_error_text.dart';

/// Escolher a foto de perfil de alguém.
///
/// A foto vai tal como está no telemóvel — não é reduzida aqui. Quem a
/// reduz é a Cloud Function `resizeAvatar`, que a corta a 160px e apaga
/// o original. Foi decisão de produto manter isso do lado do servidor:
/// a garantia de que nada grande chega a ser servido deixa de depender
/// de a app estar atualizada.
///
/// Isso tem uma consequência visível: entre o envio terminar e a foto
/// aparecer passam alguns segundos, enquanto a função reduz a imagem e
/// escreve o `photoUrl` no documento da pessoa. O botão só espera pelo
/// ENVIO — não pela redução — e por isso a mensagem diz "Aparece dentro
/// de instantes" em vez de fingir que já está.
///
/// (Este comentário já descreveu o contrário: dizia que o botão ficava
/// em "a preparar…" até o documento ganhar o `photoPath`. Nunca fez
/// isso. Um comentário que descreve o que se queria ter feito é pior do
/// que nenhum, porque quem o lê deixa de ir ver.)
///
/// Quem o usa é o GESTOR, nas fichas de aluno e de staff. A foto de
/// perfil é do estúdio e não da pessoa — é a cara que o instrutor vê na
/// tira da turma para reconhecer quem tem à frente — e as Security
/// Rules dizem o mesmo, não só a ausência do botão noutros ecrãs.
class AvatarUploadButton extends ConsumerStatefulWidget {
  const AvatarUploadButton({
    super.key,
    required this.userId,
    required this.hasPhoto,
    this.label = 'Mudar foto',
  });

  final String userId;

  /// Se a pessoa já tem foto — muda o texto e destranca o "remover".
  final bool hasPhoto;

  final String label;

  @override
  ConsumerState<AvatarUploadButton> createState() => _AvatarUploadButtonState();
}

class _AvatarUploadButtonState extends ConsumerState<AvatarUploadButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // `Wrap` e não `Row`: são dois botões de texto lado a lado, e com o
    // tamanho de letra do sistema a 1.3× já não cabem na coluna onde
    // vivem (33 px a mais; 118 a 2.0×). Numa `Row` isso corta o
    // "Remover"; num `Wrap` ele passa para a linha de baixo e continua
    // a ser tocável.
    //
    // Botões lado a lado são sempre um `Wrap` à espera de acontecer: a
    // largura deles vem do texto, que é do utilizador, não nossa.
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _pick,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_camera_outlined, size: 18),
          label: Text(
            _busy
                ? 'A preparar…'
                : widget.hasPhoto
                    ? widget.label
                    : 'Adicionar foto',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (widget.hasPhoto && !_busy)
          TextButton(
            onPressed: _remove,
            child: const Text(
              'Remover',
              style: TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
      ],
    );
  }

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      // `withData` porque na web não há caminho de ficheiro — e o
      // upload precisa dos bytes de qualquer forma.
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(storageRepositoryProvider).uploadAvatar(
            userId: widget.userId,
            bytes: bytes,
            fileName: file!.name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto enviada. Aparece dentro de instantes.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              userFacingError(e, fallback: 'Não foi possível enviar a foto.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(storageRepositoryProvider).deleteAvatar(widget.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              userFacingError(e, fallback: 'Não foi possível remover a foto.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
