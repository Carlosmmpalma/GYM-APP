import '../domain/entities/studio_info.dart';

/// A escrita da informação pública do estúdio.
///
/// Separada de [PublicScheduleRepository], que só lê: a leitura funciona
/// sem sessão (é o que a vitrina usa) e a escrita passa obrigatoriamente
/// pela Cloud Function `updateStudioInfo`, porque
/// `tenants/{t}/public/{doc}` é lido por toda a gente e um documento
/// público com escrita direta do cliente é um convite a pôr lá o que não
/// devia.
abstract class StudioAdminRepository {
  Future<void> updateStudioInfo(StudioInfo info);
}
