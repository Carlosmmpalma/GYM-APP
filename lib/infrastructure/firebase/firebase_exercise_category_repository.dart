import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/exercise_category.dart';
import '../../repositories/exercise_category_repository.dart';

ExerciseCategory _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? const {};
  return ExerciseCategory(
    id: doc.id,
    name: data['name'] as String? ?? '',
    active: data['active'] as bool? ?? false,
  );
}

class FirebaseExerciseCategoryRepository implements ExerciseCategoryRepository {
  FirebaseExerciseCategoryRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> get _tenant =>
      _firestore.collection('tenants').doc(_tenantId);

  CollectionReference<Map<String, dynamic>> get _categories =>
      _tenant.collection('exerciseCategories');

  CollectionReference<Map<String, dynamic>> get _exercises =>
      _tenant.collection('exercises');

  @override
  Stream<List<ExerciseCategory>> watchCategories() {
    return _categories.snapshots().map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(
                  b.name.toLowerCase(),
                )),
        );
  }

  @override
  Future<String> createCategory({required String name}) async {
    final ref = await _categories.add({
      'name': name.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> setCategoryActive({
    required String categoryId,
    required bool active,
  }) async {
    await _categories.doc(categoryId).update({'active': active});
  }

  @override
  Future<int> rename({
    required String categoryId,
    required String newName,
  }) async {
    final snapshot = await _categories.doc(categoryId).get();
    final oldName = (snapshot.data()?['name'] as String? ?? '').trim();
    final trimmed = newName.trim();
    if (oldName == trimmed) return 0;

    // Os exercícios guardam o TEXTO da categoria, não uma referência
    // (ver `exercise_category.dart`). Sem esta parte, mudar o nome
    // deixava-os numa categoria fantasma: visível na biblioteca,
    // impossível de voltar a escolher.
    final affected =
        await _exercises.where('category', isEqualTo: oldName).get();

    final batch = _firestore.batch();
    batch.update(_categories.doc(categoryId), {'name': trimmed});
    for (final doc in affected.docs) {
      batch.update(doc.reference, {'category': trimmed});
    }
    await batch.commit();

    return affected.size;
  }

  @override
  Future<Set<String>> namesInUse() async {
    final snapshot = await _exercises.get();
    return snapshot.docs
        .map((doc) => (doc.data()['category'] as String? ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet();
  }
}
