import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/plan.dart';
import '../../domain/entities/plan_service.dart';
import '../../domain/entities/usage_rule.dart';
import '../../repositories/plan_repository.dart';

Plan _planFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return Plan(
    id: doc.id,
    name: data['name'] as String,
    description: data['description'] as String? ?? '',
    currentPrice: (data['currentPrice'] as num).toDouble(),
    currency: data['currency'] as String? ?? 'EUR',
    active: data['active'] as bool? ?? true,
  );
}

UsageRule _usageRuleFromMap(Map<String, dynamic> data) {
  final type = data['type'] as String? ?? 'unlimited';
  if (type == 'unlimited') return const UsageRule.unlimited();
  return UsageRule.limited(
    limit: (data['limit'] as num).toInt(),
    period: UsagePeriod.fromValue(data['period'] as String),
  );
}

Map<String, dynamic> _usageRuleToMap(UsageRule rule) {
  if (rule.isUnlimited) return {'type': 'unlimited'};
  return {
    'type': 'limited',
    'limit': rule.limit,
    'period': rule.period!.name,
  };
}

PlanService _planServiceFromDoc(
  String planId,
  DocumentSnapshot<Map<String, dynamic>> doc,
) {
  final data = doc.data()!;
  return PlanService(
    planId: planId,
    serviceId: doc.id,
    enabled: data['enabled'] as bool? ?? true,
    usage: _usageRuleFromMap((data['usage'] as Map).cast<String, dynamic>()),
  );
}

class FirebasePlanRepository implements PlanRepository {
  FirebasePlanRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _plans =>
      _firestore.collection('tenants').doc(_tenantId).collection('plans');

  @override
  Stream<List<Plan>> watchPlans() {
    return _plans
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_planFromDoc).toList());
  }

  @override
  Future<List<PlanService>> getPlanServices(String planId) async {
    final snapshot = await _plans.doc(planId).collection('services').get();
    return snapshot.docs
        .map((doc) => _planServiceFromDoc(planId, doc))
        .toList();
  }

  @override
  Future<String> createPlan({
    required String name,
    required String description,
    required double currentPrice,
    required String currency,
  }) async {
    final ref = await _plans.add({
      'name': name,
      'description': description,
      'currentPrice': currentPrice,
      'currency': currency,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updatePlan(Plan plan) async {
    await _plans.doc(plan.id).update({
      'name': plan.name,
      'description': plan.description,
      'currentPrice': plan.currentPrice,
      'currency': plan.currency,
      'active': plan.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setPlanService({
    required String planId,
    required String serviceId,
    required bool enabled,
    required UsageRule usage,
  }) async {
    await _plans.doc(planId).collection('services').doc(serviceId).set({
      'serviceId': serviceId,
      'enabled': enabled,
      'usage': _usageRuleToMap(usage),
    });
  }
}
