import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/training_plan_entry.dart';
import '../../repositories/training_plan_repository.dart';

TrainingPlanEntry _fromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return TrainingPlanEntry(
    id: doc.id,
    memberId: memberId,
    exerciseId: data['exerciseId'] as String,
    sets: (data['sets'] as num? ?? 0).toInt(),
    reps: (data['reps'] as num? ?? 0).toInt(),
    currentLoad: (data['currentLoad'] as num?)?.toDouble(),
  );
}

class FirebaseTrainingPlanRepository implements TrainingPlanRepository {
  FirebaseTrainingPlanRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> _memberDoc(String memberId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(memberId);

  CollectionReference<Map<String, dynamic>> _planEntries(String memberId) =>
      _memberDoc(memberId).collection('planEntries');

  CollectionReference<Map<String, dynamic>> _loadHistory(String memberId) =>
      _memberDoc(memberId).collection('loadHistory');

  @override
  Stream<List<TrainingPlanEntry>> watchPlan(String memberId) {
    return _planEntries(memberId).snapshots().map(
          (snapshot) =>
              snapshot.docs.map((doc) => _fromDoc(memberId, doc)).toList(),
        );
  }

  @override
  Future<String> addEntry({
    required String memberId,
    required String exerciseId,
    required int sets,
    required int reps,
    double? initialLoad,
    required String recordedBy,
  }) async {
    final entryRef = _planEntries(memberId).doc();
    final batch = _firestore.batch();
    batch.set(entryRef, {
      'exerciseId': exerciseId,
      'sets': sets,
      'reps': reps,
      'currentLoad': initialLoad,
    });
    if (initialLoad != null) {
      batch.set(_loadHistory(memberId).doc(), {
        'exerciseId': exerciseId,
        'load': initialLoad,
        'reps': reps,
        'recordedBy': recordedBy,
        'recordedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return entryRef.id;
  }

  @override
  Future<void> updateSetsReps({
    required String memberId,
    required String entryId,
    required int sets,
    required int reps,
  }) async {
    await _planEntries(memberId)
        .doc(entryId)
        .update({'sets': sets, 'reps': reps});
  }

  @override
  Future<void> updateLoad({
    required String memberId,
    required String entryId,
    required String exerciseId,
    required double load,
    required int reps,
    required String recordedBy,
  }) async {
    // UC16 fechado — as duas escritas acontecem sempre juntas: o
    // `currentLoad` da entrada (o que o plano mostra) NUNCA fica à
    // frente do histórico que o justifica.
    final batch = _firestore.batch();
    batch.update(_planEntries(memberId).doc(entryId),
        {'currentLoad': load, 'reps': reps});
    batch.set(_loadHistory(memberId).doc(), {
      'exerciseId': exerciseId,
      'load': load,
      'reps': reps,
      'recordedBy': recordedBy,
      'recordedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  @override
  Future<void> removeEntry({
    required String memberId,
    required String entryId,
  }) async {
    await _planEntries(memberId).doc(entryId).delete();
  }
}
