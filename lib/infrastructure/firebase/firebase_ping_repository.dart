import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/ping_result.dart';
import '../../repositories/ping_repository.dart';

/// Implementação concreta de [PingRepository] sobre Cloud Firestore.
///
/// Guarda o documento em `_diagnostics/hello_world` — fora de `tenants/`
/// de propósito: isto é uma sonda técnica de infraestrutura, não um dado
/// de negócio de um tenant (esse modelo só começa na Fase 1, ver
/// Technical/Firestore Data Model v1 §2-3).
class FirebasePingRepository implements PingRepository {
  FirebasePingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('_diagnostics').doc('hello_world');

  @override
  Future<PingResult> writePing(String message) async {
    final now = DateTime.now();
    await _doc.set(<String, dynamic>{
      'message': message,
      'recordedAt': Timestamp.fromDate(now),
    });
    return PingResult(id: _doc.id, message: message, recordedAt: now);
  }

  @override
  Future<PingResult?> readLastPing() async {
    final snapshot = await _doc.get();
    if (!snapshot.exists) {
      return null;
    }
    final data = snapshot.data()!;
    final recordedAt = (data['recordedAt'] as Timestamp).toDate();
    return PingResult(
      id: snapshot.id,
      message: data['message'] as String,
      recordedAt: recordedAt,
    );
  }
}
