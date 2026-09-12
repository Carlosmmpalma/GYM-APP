import 'dart:typed_data';

/// Fase 8 (Platform Foundation §19: "a camada de Storage deve ser
/// abstraída sempre que a aplicação tiver necessidade de suportar
/// infraestrutura alternativa") — fronteira de upload de ficheiros. A
/// camada acima nunca importa `firebase_storage` diretamente, só esta
/// interface, mesmo princípio já aplicado a `AuthRepository`.
abstract class StorageRepository {
  /// Devolve o CAMINHO no Storage (não a URL de download — essa
  /// resolve-se em runtime via [getDownloadUrl], porque pode expirar/
  /// depender de token). [bytes] em vez de `dart:io File`: só assim
  /// funciona sem ramificação por plataforma em Flutter Web, onde não
  /// há sistema de ficheiros local.
  Future<String> uploadExerciseVideo({
    required String exerciseId,
    required Uint8List bytes,
    required String contentType,
  });

  /// Envia a foto de perfil de alguém, tal como ela vem.
  ///
  /// Não é redimensionada aqui: é a Cloud Function `resizeAvatar` que a
  /// reduz e apaga o original. Foi decisão de produto manter isso do
  /// lado do servidor — a garantia de que nada grande chega a ser
  /// servido deixa de depender de a app estar atualizada.
  ///
  /// Não devolve caminho nenhum: o que a app passa a conhecer é o
  /// `photoPath` que a função escreve no documento da pessoa, e só
  /// depois de o ficheiro reduzido existir.
  Future<void> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  });

  /// Remove a foto de perfil de alguém.
  ///
  /// Apaga o ficheiro E limpa o `photoPath` no documento da pessoa. As
  /// duas coisas: sem a segunda a app continuava a pedir um ficheiro que
  /// já não existe e o avatar ficava partido; sem a primeira ficava a
  /// cara de alguém no bucket depois de a pessoa a mandar tirar.
  Future<void> deleteAvatar(String userId);

  Future<String> getDownloadUrl(String path);

  Future<void> deleteFile(String path);
}
