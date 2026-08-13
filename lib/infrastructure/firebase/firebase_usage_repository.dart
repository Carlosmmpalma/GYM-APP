import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/usage.dart';
import '../../repositories/usage_repository.dart';

class FirebaseUsageRepository implements UsageRepository {
  FirebaseUsageRepository(this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  @override
  Stream<Usage?> watchUsage({
    required String memberId,
    required String serviceId,
    required String period,
  }) {
    final docId = '${memberId}_${serviceId}_$period';
    return _firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('usage')
        .doc(docId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data()!;
      return Usage(
        memberId: data['memberId'] as String? ?? memberId,
        serviceId: data['serviceId'] as String? ?? serviceId,
        period: data['period'] as String? ?? period,
        used: (data['used'] as num? ?? 0).toInt(),
      );
    });
  }

  @override
  Future<List<UsageRecalculationEntry>> recalculateUsage({
    required String memberId,
    required String serviceId,
  }) async {
    final result = await _functions.httpsCallable('recalculateUsage').call<Object?>({
      'memberId': memberId,
      'serviceId': serviceId,
    });
    // Mesmo padrão defensivo já usado para `HttpsCallableResult.data`
    // noutros repositories (ver `firebase_booking_repository.dart`): o
    // interop do Flutter Web pode devolver `Map<Object?, Object?>` em
    // vez de `Map<String, dynamic>` diretamente.
    final data = Map<String, dynamic>.from(result.data as Map);
    final recalculated = (data['recalculated'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map<UsageRecalculationEntry>((m) => (
              period: m['period'] as String,
              used: (m['used'] as num).toInt(),
            ))
        .toList();
    return recalculated;
  }
}
