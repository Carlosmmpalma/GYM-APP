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

  Future<String> getDownloadUrl(String path);

  Future<void> deleteFile(String path);
}
