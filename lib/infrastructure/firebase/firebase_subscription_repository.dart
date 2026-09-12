import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/subscription.dart';
import '../../repositories/subscription_repository.dart';

Subscription _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return Subscription(
    id: doc.id,
    memberId: data['memberId'] as String,
    planId: data['planId'] as String,
    status: SubscriptionStatus.fromValue(data['status'] as String? ?? 'active'),
    startDate: (data['startDate'] as Timestamp).toDate(),
    endDate: (data['endDate'] as Timestamp?)?.toDate(),
    agreedPrice: (data['agreedPrice'] as num).toDouble(),
    currency: data['currency'] as String? ?? 'EUR',
    activeServiceIds: ((data['activeServiceIds'] as List?) ?? const [])
        .map((e) => e as String)
        .toSet(),
  );
}

/// Nota de arquitetura (Fase 3): `createSubscription` é uma Cloud
/// Function (Admin SDK), ao contrário de `createBooking`/`cancelBooking`
/// (Fase 2), que são transações client-side.
///
/// Motivo: a regra "um membro não pode ter duas subscriptions ativas
/// que dão acesso ao mesmo serviço" (Domain Model v1 §15) precisa de
/// examinar TODAS as subscriptions ativas existentes do membro — um
/// número variável de documentos, não uma comparação de campos dentro
/// de UM documento como `isValidBookingCounterChange` na Fase 2. Não há
/// forma direta de exprimir "nenhum documento nesta subcoleção tem
/// `activeServiceIds` a intersetar com X" em Security Rules sem repetir
/// a mesma lógica em `get()`s dentro da própria regra, frágil e caro.
/// Uma Cloud Function com Admin SDK faz essa validação em código normal
/// (mesmo padrão de `createMember`/`createStaff`, Fase 1).
class FirebaseSubscriptionRepository implements SubscriptionRepository {
  FirebaseSubscriptionRepository(
    this._firestore,
    this._functions,
    this._tenantId,
  );

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _subscriptions => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('subscriptions');

  @override
  Stream<List<Subscription>> watchMemberSubscriptions(String memberId) {
    return _subscriptions
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<void> createSubscription({
    required String memberId,
    required String planId,
    required double agreedPrice,
    required String currency,
  }) async {
    try {
      await _functions.httpsCallable('createSubscription').call<void>({
        'memberId': memberId,
        'planId': planId,
        'agreedPrice': agreedPrice,
        'currency': currency,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        final details = e.details;
        final names =
            details is Map && details['conflictingServiceNames'] is List
                ? (details['conflictingServiceNames'] as List).cast<String>()
                : const <String>[];
        throw SubscriptionServiceConflictException(names);
      }
      rethrow;
    }
  }

  @override
  Future<bool> isEligibleForService({
    required String memberId,
    required String serviceId,
  }) async {
    final snapshot = await _subscriptions
        .where('memberId', isEqualTo: memberId)
        .where('status', isEqualTo: 'active')
        .where('activeServiceIds', arrayContains: serviceId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  @override
  Future<String?> getGrantingPlanId({
    required String memberId,
    required String serviceId,
  }) async {
    final snapshot = await _subscriptions
        .where('memberId', isEqualTo: memberId)
        .where('status', isEqualTo: 'active')
        .where('activeServiceIds', arrayContains: serviceId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data()['planId'] as String?;
  }

  @override
  Stream<Set<String>> watchEligibleMemberIds(String serviceId) {
    return _subscriptions
        .where('status', isEqualTo: 'active')
        .where('activeServiceIds', arrayContains: serviceId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data()['memberId'] as String)
              .toSet(),
        );
  }

  @override
  Stream<Set<String>> watchEligibleMemberIdsForServices(
    Set<String> serviceIds,
  ) {
    // Sem serviços atribuídos não há alunos — e perguntar ao servidor
    // por uma lista vazia devolveria um erro do `array-contains-any`.
    if (serviceIds.isEmpty) return Stream.value(const <String>{});

    return _subscriptions
        .where('status', isEqualTo: 'active')
        .where('activeServiceIds',
            arrayContainsAny: serviceIds.take(30).toList())
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.data()['memberId'] as String)
              .toSet(),
        );
  }

  @override
  Future<void> updateSubscriptionStatus({
    required String subscriptionId,
    required SubscriptionStatus status,
  }) async {
    // Cloud Function e não escrita direta: `firestore.rules` bloqueia
    // toda a escrita em `subscriptions` desde a Fase 3.
    await _functions.httpsCallable('updateSubscriptionStatus').call<void>({
      'subscriptionId': subscriptionId,
      'status': status.name,
    });
  }
}
