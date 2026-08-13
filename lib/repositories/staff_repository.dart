import '../domain/entities/staff_summary.dart';

/// Gap encontrado a comparar com `Functional/nxt-studio-screens.html`:
/// nunca existiu nenhum repository para staff no Flutter, só
/// `MemberRepository`. `createStaff.ts` (Fase 1) escreve o documento;
/// isto é só a leitura/gestão do lado da app.
abstract class StaffRepository {
  Stream<List<StaffSummary>> watchStaff();

  /// Desativar, nunca eliminar — mesmo padrão de
  /// `MemberRepository.setMemberActive`.
  Future<void> setStaffActive({
    required String staffId,
    required bool active,
  });
}
