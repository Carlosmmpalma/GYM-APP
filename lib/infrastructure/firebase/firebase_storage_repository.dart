import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../repositories/storage_repository.dart';

class FirebaseStorageRepository implements StorageRepository {
  FirebaseStorageRepository(this._storage, this._tenantId);

  final FirebaseStorage _storage;
  final String _tenantId;

  @override
  Future<void> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    // O nome do ficheiro original é preservado só pela extensão — a
    // `resizeAvatar` lê os bytes, não confia no nome. O que importa é
    // NÃO se chamar `avatar.jpg`: esse é o nome do ficheiro reduzido, e
    // escrever nele faria a função disparar sobre o seu próprio
    // resultado, em ciclo.
    final safe = fileName.contains('.') ? fileName.split('.').last : 'img';
    await _storage
        .ref('tenants/$_tenantId/avatars/$userId/original.$safe')
        .putData(bytes, SettableMetadata(contentType: 'image/$safe'));
  }

  @override
  Future<void> deleteAvatar(String userId) async {
    // Só o ficheiro. Quem limpa o `photoPath` no documento da pessoa é
    // a Cloud Function `clearAvatarOnDelete`, pelo mesmo motivo que é
    // ela a escrevê-lo: um aluno não pode escrever no seu próprio
    // documento (as Rules limitam os campos que ele toca), e duplicar a
    // escrita no cliente obrigaria a abrir isso.
    //
    // Pode não existir — nunca teve foto, ou a redução falhou a meio.
    // Apagar o que não está lá não é um erro que interesse a ninguém.
    await _storage
        .ref('tenants/$_tenantId/avatars/$userId/avatar.jpg')
        .delete()
        .catchError((_) {});
  }

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
