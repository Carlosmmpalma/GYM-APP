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
    required this.muscleGroup,
    this.videoPath,
  });

  final String id;
  final String name;
  final String description;

  /// Texto livre restrito pela UI a um dropdown fechado (ex.:
  /// "Pernas"/"Costas"/"Full body"/"Hyrox" — mesmo espírito de
  /// `forcaMS` em `Assessment`, não um enum persistido).
  final String muscleGroup;
  final String? videoPath;

  bool get hasVideo => videoPath != null;

  @override
  List<Object?> get props => [id, name, description, muscleGroup, videoPath];
}
