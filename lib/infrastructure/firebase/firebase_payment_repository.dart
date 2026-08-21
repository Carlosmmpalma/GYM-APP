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
