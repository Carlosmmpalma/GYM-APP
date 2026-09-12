import 'package:flutter/material.dart';

import 'design_system.dart';

/// O avatar de uma pessoa: foto quando existe, iniciais com cor quando
/// não.
///
/// Separado de [Avatar] porque as iniciais são usadas em sítios que não
/// têm — nem devem ter — acesso a um `Ref`. Aqui é onde a foto entra.
///
/// A cor por baixo continua a ser a da pessoa: enquanto a imagem
/// carrega, e se falhar, o círculo é o mesmo que seria sem foto — nunca
/// um buraco cinzento.
///
/// Recebe o URL já feito, e não o caminho no Storage. A versão anterior
/// recebia o caminho e pedia o URL ao Storage (`getDownloadURL`), o que
/// era **um pedido de rede por pessoa**: numa lista de cinquenta eram
/// cinquenta, refeitos do zero sempre que se reentrava no ecrã. Hoje o
/// URL vem escrito no documento da pessoa, que a app já lê — ver
/// `resizeAvatar.ts`. Isto deixou de ser um `ConsumerWidget` por isso
/// mesmo: já não há nada para observar.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.size = 34,
  });

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return Avatar(name, size: size);
    }

    // A foto no Storage tem 160px de lado; aqui mostra-se a 34. Sem
    // isto, cada avatar é descodificado para memória no tamanho cheio —
    // numa lista de cinquenta são ~5 MB de bitmaps para desenhar
    // círculos de um centímetro.
    final pixels =
        (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 160);

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: pixels,
          cacheHeight: pixels,
          // Sem spinner: a bolinha a girar dentro de um círculo de 34px
          // é ruído, e numa lista de cinquenta pessoas são cinquenta. As
          // iniciais servem de marca de água até a foto chegar.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return Avatar(name, size: size);
          },
          errorBuilder: (_, __, ___) => Avatar(name, size: size),
        ),
      ),
    );
  }
}
