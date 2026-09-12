import '../domain/entities/public_schedule.dart';
import '../domain/entities/studio_info.dart';

/// O único acesso a dados desta app que funciona **sem sessão**.
///
/// Existe para a vitrina: quem instala a app antes de se inscrever, e
/// quem a revê na App Store, tem de conseguir ver o que o estúdio faz e
/// onde fica. Ver a regra `tenants/{t}/public/{doc}` em
/// `firestore.rules`.
///
/// A escrita não está aqui de propósito — passa pela Cloud Function
/// `updateStudioInfo`, porque um documento público com escrita direta do
/// cliente é um convite a pôr lá o que não devia.
abstract class PublicScheduleRepository {
  /// O mapa de aulas, derivado das séries ativas pelo cron diário.
  Future<PublicSchedule> getSchedule(String tenantId);

  /// Morada, contactos, horário e política de privacidade.
  Future<StudioInfo> getStudioInfo(String tenantId);
}
