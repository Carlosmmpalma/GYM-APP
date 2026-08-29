import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/exercise.dart';
import '../../repositories/exercise_repository.dart';

Exercise _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return Exercise(
    id: doc.id,
    name: data['name'] as String? ?? '',
    description: data['description'] as String? ?? '',
    muscleGroup: data['muscleGroup'] as String? ?? '',
    videoPath: data['videoPath'] as String?,
  );
}

class FirebaseExerciseRepository implements ExerciseRepository {
  FirebaseExerciseRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _exercises =>
      _firestore.collection('tenants').doc(_tenantId).collection('exercises');

  @override
  Stream<List<Exercise>> watchExercises() {
    return _exercises
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<List<Exercise>> getExercisesByIds(Set<String> ids) async {
    if (ids.isEmpty) return const [];

    final ordered = ids.toList();
    final results = <Exercise>[];
    for (var i = 0; i < ordered.length; i += 30) {
      final chunk = ordered.sublist(
        i,
        i + 30 > ordered.length ? ordered.length : i + 30,
      );
      final snapshot =
          await _exercises.where(FieldPath.documentId, whereIn: chunk).get();
      results.addAll(snapshot.docs.map(_fromDoc));
    }
    return results;
  }

  @override
  Future<String> createExercise({
    required String name,
    required String description,
    required String muscleGroup,
  }) async {
    final ref = await _exercises.add({
      'name': name,
      'description': description,
      'muscleGroup': muscleGroup,
      'videoPath': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updateExercise({
    required String exerciseId,
    required String name,
    required String description,
    required String muscleGroup,
  }) async {
    await _exercises.doc(exerciseId).update({
      'name': name,
      'description': description,
      'muscleGroup': muscleGroup,
    });
  }

  @override
  Future<void> setVideoPath({
    required String exerciseId,
    required String? videoPath,
  }) async {
    await _exercises.doc(exerciseId).update({'videoPath': videoPath});
  }
}
