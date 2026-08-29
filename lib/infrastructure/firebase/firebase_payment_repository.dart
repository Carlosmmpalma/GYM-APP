import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/payment_record.dart';
import '../../repositories/payment_repository.dart';

PaymentRecord _fromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return PaymentRecord(
    memberId: memberId,
    year: (data['year'] as num).toInt(),
    month: (data['month'] as num).toInt(),
    status: PaymentStatus.fromValue(data['status'] as String? ?? 'overdue'),
    changedAt: (data['changedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    changedBy: data['changedBy'] as String? ?? '',
    amount: (data['amount'] as num?)?.toDouble(),
    subscriptionId: data['subscriptionId'] as String?,
  );
}

const _paymentHistoryLimit = 36;

class FirebasePaymentRepository implements PaymentRepository {
  FirebasePaymentRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> _memberDoc(String memberId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(memberId);

  CollectionReference<Map<String, dynamic>> _records(String memberId) =>
      _memberDoc(memberId).collection('paymentRecords');

  @override
  Stream<List<PaymentRecord>> watchPaymentHistory(String memberId) {
    return _records(memberId)
        .orderBy('year', descending: true)
        .orderBy('month', descending: true)
        // Três anos de histórico. Um registo por mês, por isso o limite
        // é generoso e o ecrã continua a mostrar o passado todo que
        // interessa a uma conversa sobre mensalidades.
        .limit(_paymentHistoryLimit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => _fromDoc(memberId, doc)).toList());
  }

  @override
  Future<Map<String, PaymentRecord>> getRecordsForPeriod({
    required Iterable<String> memberIds,
    required String period,
  }) async {
    final ids = memberIds.toList();
    if (ids.isEmpty) return const {};

    // Uma leitura por membro, em paralelo. A alternativa seria um
    // `collectionGroup('paymentRecords')` filtrado por ano/mês, mas
    // isso atravessa tenants e exigia um índice de grupo de coleção
    // novo para poupar pouco: o número de membros de um estúdio é o
    // número de leituras, e é conhecido.
    final snapshots = await Future.wait(
      ids.map((id) => _records(id).doc(period).get()),
    );

    final result = <String, PaymentRecord>{};
    for (var i = 0; i < ids.length; i++) {
      final snapshot = snapshots[i];
      if (snapshot.exists) result[ids[i]] = _fromDoc(ids[i], snapshot);
    }
    return result;
  }

  @override
  Future<void> deletePaymentRecord({
    required String memberId,
    required String period,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_records(memberId).doc(period));

    // A cópia denormalizada em `members/{id}` existe para a lista de
    // mensalidades e para o bloqueio de login não custarem uma query
    // por membro. Apagar o registo sem a limpar deixava o membro a
    // aparecer "em atraso" (ou "pago") por um mês que já não existe.
    if (period == paymentPeriodKey(DateTime.now())) {
      batch.update(_memberDoc(memberId), {
        'currentPaymentStatus': FieldValue.delete(),
        'currentPaymentPeriod': FieldValue.delete(),
      });
    }

    await batch.commit();
  }

  @override
  Future<void> setPaymentStatus({
    required String memberId,
    required int year,
    required int month,
    required PaymentStatus status,
    required String changedBy,
    double? amount,
    String? subscriptionId,
  }) async {
    final periodKey =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final batch = _firestore.batch();

    batch.set(_records(memberId).doc(periodKey), {
      'memberId': memberId,
      'year': year,
      'month': month,
      'status': status.name,
      'amount': amount,
      'subscriptionId': subscriptionId,
      'changedAt': FieldValue.serverTimestamp(),
      'changedBy': changedBy,
    });

    // Só denormaliza para `members/{id}` quando é o MÊS ATUAL — ver
    // nota em `PaymentRepository.setPaymentStatus`. Corrigir Junho
    // enquanto Agosto está em curso nunca pode fazer o `members/{id}`
    // "esquecer" o estado de Agosto.
    if (periodKey == paymentPeriodKey(DateTime.now())) {
      batch.update(_memberDoc(memberId), {
        'currentPaymentStatus': status.name,
        'currentPaymentPeriod': periodKey,
      });
    }

    await batch.commit();
  }
}
