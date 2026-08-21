import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/payment_record.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_payment_repository.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

void main() {
  Future<FakeFirebaseFirestore> seedMember() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .set({'name': 'Rita Ferreira', 'memberNumber': '000001'});
    return firestore;
  }

  test(
      'setPaymentStatus do MÊS ATUAL grava o registo E denormaliza em members/{id}',
      () async {
    final firestore = await seedMember();
    final repository = FirebasePaymentRepository(firestore, _tenantId);
    final now = DateTime.now();

    await repository.setPaymentStatus(
      memberId: _memberId,
      year: now.year,
      month: now.month,
      status: PaymentStatus.overdue,
      changedBy: 'manager_1',
      amount: 35.5,
    );

    final recordId = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final recordSnap = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .collection('paymentRecords')
        .doc(recordId)
        .get();
    expect(recordSnap.data()?['status'], 'overdue');
    expect(recordSnap.data()?['amount'], 35.5);
    expect(recordSnap.data()?['changedBy'], 'manager_1');

    final memberSnap = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .get();
    expect(memberSnap.data()?['currentPaymentStatus'], 'overdue');
    expect(memberSnap.data()?['currentPaymentPeriod'], recordId);
  });

  test(
      'setPaymentStatus de um mês PASSADO grava o registo mas NÃO mexe em members/{id}',
      () async {
    final firestore = await seedMember();
    final repository = FirebasePaymentRepository(firestore, _tenantId);
    final now = DateTime.now();

    // Marca primeiro o mês atual como "paid" — para confirmar que a
    // correção do mês passado, a seguir, não o sobrescreve.
    await repository.setPaymentStatus(
      memberId: _memberId,
      year: now.year,
      month: now.month,
      status: PaymentStatus.paid,
      changedBy: 'manager_1',
    );

    // "2000-01" é sempre um mês passado, independentemente de quando
    // este teste corre.
    await repository.setPaymentStatus(
      memberId: _memberId,
      year: 2000,
      month: 1,
      status: PaymentStatus.overdue,
      changedBy: 'manager_1',
    );

    final pastRecordSnap = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .collection('paymentRecords')
        .doc('2000-01')
        .get();
    expect(pastRecordSnap.data()?['status'], 'overdue');

    // O denormalizado em members/{id} continua a refletir o MÊS ATUAL
    // ("paid"), nunca o registo de 2000 que acabou de ser corrigido.
    final memberSnap = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(_memberId)
        .get();
    expect(memberSnap.data()?['currentPaymentStatus'], 'paid');
  });

  test('watchPaymentHistory devolve os registos mais recentes primeiro',
      () async {
    final firestore = await seedMember();
    final repository = FirebasePaymentRepository(firestore, _tenantId);

    await repository.setPaymentStatus(
      memberId: _memberId,
      year: 2026,
      month: 5,
      status: PaymentStatus.paid,
      changedBy: 'manager_1',
    );
    await repository.setPaymentStatus(
      memberId: _memberId,
      year: 2026,
      month: 7,
      status: PaymentStatus.paidLate,
      changedBy: 'manager_1',
    );
    await repository.setPaymentStatus(
      memberId: _memberId,
      year: 2026,
      month: 6,
      status: PaymentStatus.overdue,
      changedBy: 'manager_1',
    );

    final history = await repository.watchPaymentHistory(_memberId).first;

    expect(history.map((r) => r.month).toList(), [7, 6, 5]);
  });
}
