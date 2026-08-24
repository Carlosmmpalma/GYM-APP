import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../repositories/storage_repository.dart';

class FirebaseStorageRepository implements StorageRepository {
  FirebaseStorageRepository(this._storage, this._tenantId);

  final FirebaseStorage _storage;
  final String _tenantId;

  @override
  Future<String> uploadExerciseVideo({
    required String exerciseId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    // Nome fixo ("video") em vez do nome original do ficheiro —
    // simplifica substituir o vídeo de um exercício sem deixar
    // ficheiros órfãos no Storage (mesmo path, sobrescreve sempre).
    final path = 'tenants/$_tenantId/exercises/$exerciseId/video';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        // O item que mais dinheiro custa nesta app não são as leituras
        // do Firestore — é o TRÁFEGO destes vídeos. Cada aluno que
        // abre um exercício descarrega o ficheiro inteiro, e sem
        // `Cache-Control` o browser volta a descarregá-lo na vez
        // seguinte. Um vídeo de 40 MB visto três vezes por 150 alunos
        // são 18 GB; com cache, são 6 GB.
        //
        // 30 dias é seguro apesar de o caminho ser sempre o mesmo:
        // substituir o vídeo gera um token de download novo, e portanto
        // um URL novo, que a cache antiga não serve.
        cacheControl: 'public, max-age=2592000',
      ),
    );
    return path;
  }

  @override
  Future<String> getDownloadUrl(String path) {
    return _storage.ref(path).getDownloadURL();
  }

  @override
  Future<void> deleteFile(String path) {
    return _storage.ref(path).delete();
  }
}
