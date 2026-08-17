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
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
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
