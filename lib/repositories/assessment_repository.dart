import '../domain/entities/assessment.dart';

/// Fase 8 (UC04/UC14) — avaliações físicas de um membro. Escrita
/// direta do cliente (Instrutor/Gestor): documento isolado, sem
/// invariante cross-documento (ao contrário de booking/usage), não
/// precisa de Cloud Function — mesmo raciocínio de `AttendanceRepository`
/// desde a Fase 6.
abstract class AssessmentRepository {
  /// UC04 — "lista, mais recente primeiro". O próprio membro (leitura)
  /// ou o Instrutor/Gestor a rever o histórico de alguém.
  Stream<List<Assessment>> watchAssessments(String memberId);

  Future<String> createAssessment({
    required String memberId,
    required String instructorId,
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  });

  /// UC04/UC14 (fechado) — "o Instrutor pode corrigir uma avaliação já
  /// registada". Nunca cria um documento novo (isso é
  /// [createAssessment], para uma avaliação NOVA histórica) — atualiza
  /// os campos deste id e marca `updatedAt`/`updatedBy`.
  Future<void> updateAssessment({
    required String memberId,
    required String assessmentId,
    required String updatedBy,
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  });
}
