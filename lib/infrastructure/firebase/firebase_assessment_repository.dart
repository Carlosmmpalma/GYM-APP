import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/assessment.dart';
import '../../repositories/assessment_repository.dart';

Assessment _fromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return Assessment(
    id: doc.id,
    memberId: memberId,
    instructorId: data['instructorId'] as String? ?? '',
    createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    updatedBy: data['updatedBy'] as String?,
    idade: (data['idade'] as num? ?? 0).toInt(),
    peso: (data['peso'] as num? ?? 0).toDouble(),
    altura: (data['altura'] as num? ?? 0).toDouble(),
    percentMassaGorda: (data['percentMassaGorda'] as num? ?? 0).toDouble(),
    massaMuscular: (data['massaMuscular'] as num? ?? 0).toDouble(),
    gorduraVisceral: (data['gorduraVisceral'] as num? ?? 0).toDouble(),
    metabolismoBasal: (data['metabolismoBasal'] as num? ?? 0).toDouble(),
    percentAgua: (data['percentAgua'] as num? ?? 0).toDouble(),
    idadeMetabolica: (data['idadeMetabolica'] as num? ?? 0).toInt(),
    pressaoArterial: data['pressaoArterial'] as String? ?? '',
    perimetroCintura: (data['perimetroCintura'] as num? ?? 0).toDouble(),
    perimetroAbdominal: (data['perimetroAbdominal'] as num? ?? 0).toDouble(),
    forcaMS: data['forcaMS'] as String? ?? '',
    forcaMI: data['forcaMI'] as String? ?? '',
    forcaCore: data['forcaCore'] as String? ?? '',
    flexibilidade: data['flexibilidade'] as String? ?? '',
    resistencia: data['resistencia'] as String? ?? '',
  );
}

const _assessmentsLimit = 100;

class FirebaseAssessmentRepository implements AssessmentRepository {
  FirebaseAssessmentRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> _assessments(String memberId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(memberId)
          .collection('assessments');

  @override
  Stream<List<Assessment>> watchAssessments(String memberId) {
    return _assessments(memberId)
        .orderBy('createdAt', descending: true)
        // Ordenado da mais recente para a mais antiga: o corte tira as
        // mais antigas, que é o que a lista quer mostrar por último.
        .limit(_assessmentsLimit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => _fromDoc(memberId, doc)).toList(),
        );
  }

  Map<String, dynamic> _fields({
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  }) {
    return {
      'idade': idade,
      'peso': peso,
      'altura': altura,
      'percentMassaGorda': percentMassaGorda,
      'massaMuscular': massaMuscular,
      'gorduraVisceral': gorduraVisceral,
      'metabolismoBasal': metabolismoBasal,
      'percentAgua': percentAgua,
      'idadeMetabolica': idadeMetabolica,
      'pressaoArterial': pressaoArterial,
      'perimetroCintura': perimetroCintura,
      'perimetroAbdominal': perimetroAbdominal,
      'forcaMS': forcaMS,
      'forcaMI': forcaMI,
      'forcaCore': forcaCore,
      'flexibilidade': flexibilidade,
      'resistencia': resistencia,
    };
  }

  @override
  Future<String> createAssessment({
    required String memberId,
    required String instructorId,
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  }) async {
    final ref = await _assessments(memberId).add({
      'instructorId': instructorId,
      'createdAt': FieldValue.serverTimestamp(),
      ..._fields(
        idade: idade,
        peso: peso,
        altura: altura,
        percentMassaGorda: percentMassaGorda,
        massaMuscular: massaMuscular,
        gorduraVisceral: gorduraVisceral,
        metabolismoBasal: metabolismoBasal,
        percentAgua: percentAgua,
        idadeMetabolica: idadeMetabolica,
        pressaoArterial: pressaoArterial,
        perimetroCintura: perimetroCintura,
        perimetroAbdominal: perimetroAbdominal,
        forcaMS: forcaMS,
        forcaMI: forcaMI,
        forcaCore: forcaCore,
        flexibilidade: flexibilidade,
        resistencia: resistencia,
      ),
    });
    return ref.id;
  }

  @override
  Future<void> deleteAssessment({
    required String memberId,
    required String assessmentId,
  }) async {
    await _assessments(memberId).doc(assessmentId).delete();
  }

  @override
  Future<void> updateAssessment({
    required String memberId,
    required String assessmentId,
    required String updatedBy,
    required int idade,
    required double peso,
    required double altura,
    required double percentMassaGorda,
    required double massaMuscular,
    required double gorduraVisceral,
    required double metabolismoBasal,
    required double percentAgua,
    required int idadeMetabolica,
    required String pressaoArterial,
    required double perimetroCintura,
    required double perimetroAbdominal,
    required String forcaMS,
    required String forcaMI,
    required String forcaCore,
    required String flexibilidade,
    required String resistencia,
  }) async {
    await _assessments(memberId).doc(assessmentId).update({
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
      ..._fields(
        idade: idade,
        peso: peso,
        altura: altura,
        percentMassaGorda: percentMassaGorda,
        massaMuscular: massaMuscular,
        gorduraVisceral: gorduraVisceral,
        metabolismoBasal: metabolismoBasal,
        percentAgua: percentAgua,
        idadeMetabolica: idadeMetabolica,
        pressaoArterial: pressaoArterial,
        perimetroCintura: perimetroCintura,
        perimetroAbdominal: perimetroAbdominal,
        forcaMS: forcaMS,
        forcaMI: forcaMI,
        forcaCore: forcaCore,
        flexibilidade: flexibilidade,
        resistencia: resistencia,
      ),
    });
  }
}
