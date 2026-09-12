import 'package:equatable/equatable.dart';

/// Fase 8 (UC15 fechado) — "biblioteca partilhada por todos os
/// instrutores": `tenants/{tenantId}/exercises/{exerciseId}`, tenant-
/// wide, sem dono/instrutor associado (ao contrário do que aconteceria
/// se fosse por instrutor) — qualquer Instrutor/Gestor pode
/// criar/editar qualquer exercício da biblioteca, mesmo espírito de
/// `Service`/`Modality`. [videoPath] é o caminho no Firebase Storage
/// (não a URL de download, que expira/depende de token — resolvida em
/// runtime pelo repository), `null` quando o exercício ainda não tem
/// vídeo ("Sem vídeo" no mockup).
class Exercise extends Equatable {
  const Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.videoPath,
  });

  final String id;
  final String name;
  final String description;

  /// Como o estúdio arruma a biblioteca — ver [ExerciseCategory].
  ///
  /// Chamava-se `muscleGroup` e vinha de um dropdown fechado no código.
  /// Duas coisas mudaram: a lista passou a ser do estúdio, e o nome
  /// passou a "categoria" porque "Hyrox" nunca foi um músculo — a
  /// palavra tinha ficado pequena antes de alguém dar por isso.
  ///
  /// O campo antigo não é lido: a biblioteca em produção é a que o
  /// `seed-content.mjs` semeou, e uma nova passagem do seed reescreve
  /// os 61 exercícios com o campo novo. Sem utilizadores reais ainda,
  /// não valia a pena carregar uma leitura dupla para sempre.
  ///
  /// Guarda o TEXTO, não uma referência: os ecrãs do aluno mostram-no
  /// ao lado do exercício, e resolver um id custaria leituras num
  /// caminho que foi optimizado precisamente para as evitar. O preço é
  /// que renomear uma categoria tem de propagar — ver
  /// `ExerciseCategoryRepository.rename`.
  final String category;
  final String? videoPath;

  bool get hasVideo => videoPath != null;

  @override
  List<Object?> get props => [id, name, description, category, videoPath];
}
