import 'package:cloud_functions/cloud_functions.dart';

import '../../repositories/privacy_repository.dart';

/// Mesmo motivo de `firebase_user_provisioning_repository.dart`: em
/// Flutter Web o `.data` chega como `Map<Object?, Object?>` por causa do
/// interop com JS, e um cast direto rebentava.
Map<String, dynamic> _asMap(Object? data) =>
    Map<String, dynamic>.from(data as Map);

class FirebasePrivacyRepository implements PrivacyRepository {
  FirebasePrivacyRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> recordConsent({
    required int privacyPolicyVersion,
    required bool healthDataGranted,
  }) async {
    await _functions.httpsCallable('recordConsent').call<Object?>({
      'privacyPolicyVersion': privacyPolicyVersion,
      'healthDataGranted': healthDataGranted,
    });
  }

  @override
  Future<Map<String, dynamic>> exportMemberData({String? memberId}) async {
    final result =
        await _functions.httpsCallable('exportMemberData').call<Object?>({
      if (memberId != null) 'memberId': memberId,
    });
    return _asMap(result.data);
  }

  @override
  Future<MemberDeletionReport> deleteMemberData({
    required String memberId,
    required String confirmMemberNumber,
  }) async {
    final result =
        await _functions.httpsCallable('deleteMemberData').call<Object?>({
      'memberId': memberId,
      'confirmMemberNumber': confirmMemberNumber,
    });
    final data = _asMap(result.data);
    final deleted = _asMap(data['deleted']);
    return MemberDeletionReport(
      deletedByCollection: {
        for (final entry in deleted.entries)
          entry.key: (entry.value as num).toInt(),
      },
      anonymizedPaymentRecords:
          (data['anonymizedPaymentRecords'] as num?)?.toInt() ?? 0,
    );
  }
}
