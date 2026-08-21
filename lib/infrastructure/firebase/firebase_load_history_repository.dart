import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/load_history_entry.dart';
import '../../repositories/load_history_repository.dart';

LoadHistoryEntry _fromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return LoadHistoryEntry(
    id: doc.id,
    memberId: memberId,
    exerciseId: data['exerciseId'] as String,
    load: (data['load'] as num).toDouble(),
    reps: (data['reps'] as num? ?? 0).toInt(),
    recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    recordedBy: data['recordedBy'] as String? ?? '',
  );
}

const _loadHistoryLimit = 200;

class FirebaseLoadHistoryRepository implements LoadHistoryRepository {
  FirebaseLoadHistoryRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> _history(String memberId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(memberId)
          .collection('loadHistory');

  @override
  Stream<List<LoadHistoryEntry>> watchHistory({
    required String memberId,
    required String exerciseId,
  }) {
    return _history(memberId)
        .where('exerciseId', isEqualTo: exerciseId)
        .orderBy('recordedAt', descending: true)
        // Fase 10 — cresce a CADA treino registado, sem fim. Como vem
        // ordenado do mais recente para o mais antigo, cortar aqui dá
        // exatamente o que o gráfico de evolução mostra; sem isto, um
        // aluno com dois anos de treino puxava centenas de documentos
        // sempre que abria o ecrã.
        .limit(_loadHistoryLimit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => _fromDoc(memberId, doc)).toList());
  }

  @override
  Future<void> addEntry({
    required String memberId,
    required String exerciseId,
    required double load,
    required int reps,
    required String recordedBy,
  }) async {
    await _history(memberId).add({
      'exerciseId': exerciseId,
      'load': load,
      'reps': reps,
      'recordedBy': recordedBy,
      'recordedAt': FieldValue.serverTimestamp(),
    });
  }
}
