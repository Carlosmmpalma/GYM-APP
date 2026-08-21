import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/training_plan_entry.dart';
import '../../domain/entities/training_workout.dart';
import '../../repositories/training_plan_repository.dart';

TrainingPlanEntry _fromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return TrainingPlanEntry(
    id: doc.id,
    memberId: memberId,
    exerciseId: data['exerciseId'] as String,
    sets: (data['sets'] as num? ?? 0).toInt(),
    // Fase 11 — `reps` passou de número para texto ("8-12", "45s"). As
    // entradas antigas têm lá um número; convertê-lo para texto na
    // leitura evita ter de migrar dados e não perde nada.
    reps: switch (data['reps']) {
      final String value => value,
      final num value => value.toInt().toString(),
      _ => '',
    },
    currentLoad: (data['currentLoad'] as num?)?.toDouble(),
    workoutId: data['workoutId'] as String?,
    position: (data['position'] as num? ?? 0).toInt(),
    restSeconds: (data['restSeconds'] as num?)?.toInt(),
    notes: data['notes'] as String? ?? '',
  );
}

TrainingWorkout _workoutFromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return TrainingWorkout(
    id: doc.id,
    memberId: memberId,
    name: data['name'] as String? ?? '(sem nome)',
    notes: data['notes'] as String? ?? '',
    position: (data['position'] as num? ?? 0).toInt(),
    active: data['active'] as bool? ?? true,
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

  CollectionReference<Map<String, dynamic>> _workouts(String memberId) =>
      _memberDoc(memberId).collection('workouts');

  CollectionReference<Map<String, dynamic>> _loadHistory(String memberId) =>
      _memberDoc(memberId).collection('loadHistory');

  @override
  Stream<List<TrainingPlanEntry>> watchPlan(String memberId) {
    return _planEntries(memberId).snapshots().map(
      (snapshot) {
        final entries =
            snapshot.docs.map((doc) => _fromDoc(memberId, doc)).toList();
        // Ordenar aqui e não no Firestore: `position` só existe desde a
        // Fase 11 e as entradas antigas têm 0, o que um `orderBy` no
        // servidor deixaria em ordem arbitrária entre si. Em memória
        // podemos desempatar pelo id e ter uma ordem estável.
        entries.sort((a, b) {
          final byPosition = a.position.compareTo(b.position);
          return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
        });
        return entries;
      },
    );
  }

  @override
  Stream<List<TrainingWorkout>> watchWorkouts(String memberId) {
    return _workouts(memberId).snapshots().map(
      (snapshot) {
        final workouts =
            snapshot.docs.map((doc) => _workoutFromDoc(memberId, doc)).toList();
        workouts.sort((a, b) {
          final byPosition = a.position.compareTo(b.position);
          return byPosition != 0 ? byPosition : a.name.compareTo(b.name);
        });
        return workouts;
      },
    );
  }

  @override
  Future<String> addWorkout({
    required String memberId,
    required String name,
    String notes = '',
    required int position,
  }) async {
    final ref = _workouts(memberId).doc();
    await ref.set({
      'name': name,
      'notes': notes,
      'position': position,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updateWorkout({
    required String memberId,
    required String workoutId,
    String? name,
    String? notes,
    int? position,
    bool? active,
  }) async {
    await _workouts(memberId).doc(workoutId).update({
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
      if (position != null) 'position': position,
      if (active != null) 'active': active,
    });
  }

  @override
  Future<void> removeWorkout({
    required String memberId,
    required String workoutId,
  }) async {
    // Os exercícios do treino não são apagados — ficam sem treino
    // atribuído, e o editor mostra-os agrupados para o instrutor os
    // arrumar. Apagá-los em cascata perderia a prescrição e deixaria o
    // histórico de cargas sem contexto.
    final entries = await _planEntries(memberId)
        .where('workoutId', isEqualTo: workoutId)
        .get();
    final batch = _firestore.batch();
    for (final doc in entries.docs) {
      batch.update(doc.reference, {'workoutId': null});
    }
    batch.delete(_workouts(memberId).doc(workoutId));
    await batch.commit();
  }

  @override
  Future<String> addEntry({
    required String memberId,
    required String exerciseId,
    required int sets,
    required String reps,
    double? initialLoad,
    required String recordedBy,
    String? workoutId,
    int position = 0,
    int? restSeconds,
    String notes = '',
  }) async {
    final entryRef = _planEntries(memberId).doc();
    final batch = _firestore.batch();
    batch.set(entryRef, {
      'exerciseId': exerciseId,
      'sets': sets,
      'reps': reps,
      'currentLoad': initialLoad,
      'workoutId': workoutId,
      'position': position,
      'restSeconds': restSeconds,
      'notes': notes,
    });
    if (initialLoad != null) {
      batch.set(_loadHistory(memberId).doc(), {
        'exerciseId': exerciseId,
        'load': initialLoad,
        // O histórico regista o que foi MESMO feito, e isso é sempre
        // contável. Uma prescrição de "8-12" não dá um número — nesse
        // caso fica 0, que se lê como "não registado".
        'reps': int.tryParse(reps) ?? 0,
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
    required String reps,
    int? restSeconds,
    String? notes,
  }) async {
    await _planEntries(memberId).doc(entryId).update({
      'sets': sets,
      'reps': reps,
      if (restSeconds != null) 'restSeconds': restSeconds,
      if (notes != null) 'notes': notes,
    });
  }

  @override
  Future<void> moveEntry({
    required String memberId,
    required String entryId,
    required String? workoutId,
    required int position,
  }) async {
    await _planEntries(memberId).doc(entryId).update({
      'workoutId': workoutId,
      'position': position,
    });
  }

  @override
  Future<void> reorderEntries({
    required String memberId,
    required List<String> orderedEntryIds,
  }) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedEntryIds.length; i++) {
      batch.update(
          _planEntries(memberId).doc(orderedEntryIds[i]), {'position': i});
    }
    await batch.commit();
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
    //
    // Fase 11 — deixou de escrever `reps` na entrada. As repetições da
    // ENTRADA são a prescrição do instrutor ("8-12"); as do histórico
    // são o que o aluno fez hoje. Antes, registar uma carga sobrescrevia
    // a prescrição com o número feito naquele dia.
    final batch = _firestore.batch();
    batch.update(_planEntries(memberId).doc(entryId), {'currentLoad': load});
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
