import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/utils/search_text.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/staff_private_profile.dart';
import '../../domain/entities/staff_summary.dart';
import '../../repositories/staff_repository.dart';

StaffSummary _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? const {};
  final rolesRaw = (data['roles'] as List?) ?? const [];
  final modalityIdsRaw = (data['modalityIds'] as List?) ?? const [];
  final serviceIdsRaw = (data['serviceIds'] as List?) ?? const [];
  return StaffSummary(
    uid: doc.id,
    name: data['name'] as String? ?? '(sem nome)',
    email: data['email'] as String? ?? '',
    photoPath: data['photoPath'] as String?,
    photoUrl: data['photoUrl'] as String?,
    photoUpdatedAt: (data['photoUpdatedAt'] as num?)?.toInt(),
    roles: rolesRaw.map((r) => Role.fromClaim(r as String)).toSet(),
    active: (data['status'] as String? ?? 'active') == 'active',
    modalityIds: modalityIdsRaw.map((e) => e as String).toSet(),
    serviceIds: serviceIdsRaw.map((e) => e as String).toSet(),
  );
}

StaffPrivateProfile _privateFromDoc(
  DocumentSnapshot<Map<String, dynamic>> doc,
) {
  final data = doc.data();
  if (!doc.exists || data == null) return StaffPrivateProfile.empty;
  return StaffPrivateProfile(
    phone: data['phone'] as String? ?? '',
    birthDate: (data['birthDate'] as Timestamp?)?.toDate(),
    address: data['address'] as String? ?? '',
    nif: data['nif'] as String? ?? '',
    emergencyContact: data['emergencyContact'] as String? ?? '',
  );
}

class FirebaseStaffRepository implements StaffRepository {
  FirebaseStaffRepository(this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _staff =>
      _firestore.collection('tenants').doc(_tenantId).collection('staff');

  @override
  Stream<StaffPrivateProfile> watchPrivateProfile(String staffId) {
    return _staff
        .doc(staffId)
        .collection('private')
        .doc('profile')
        .snapshots()
        .map(_privateFromDoc)
        // Um Instrutor a abrir a ficha de outro recebe uma recusa das
        // Rules — e isso não é um erro a mostrar, é a resposta certa.
        .handleError((Object _) {}, test: (_) => true)
        .cast<StaffPrivateProfile>();
  }

  /// Ordenado por nome — ver a nota equivalente em
  /// `firebase_member_repository.dart`.
  @override
  Stream<List<StaffSummary>> watchStaff() {
    return _staff.snapshots().map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList()
            ..sort((a, b) =>
                searchNormalize(a.name).compareTo(searchNormalize(b.name))),
        );
  }

  @override
  Future<void> setStaffActive({
    required String staffId,
    required bool active,
  }) async {
    await _staff.doc(staffId).update({
      'status': active ? 'active' : 'inactive',
    });
  }

  @override
  Future<void> setModalityIds({
    required String staffId,
    required Set<String> modalityIds,
  }) async {
    await _staff.doc(staffId).update({'modalityIds': modalityIds.toList()});
  }

  @override
  Future<void> setStaffServices({
    required String staffId,
    required Set<String> serviceIds,
  }) async {
    await _staff.doc(staffId).update({'serviceIds': serviceIds.toList()});
  }

  @override
  Future<
      ({
        int seriesCancelled,
        int occurrencesCancelled,
        int bookingsCancelled
      })> deactivateInstructorWithCascade(String staffId) async {
    final result =
        await _functions.httpsCallable('deactivateInstructor').call<Object?>({
      'staffId': staffId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      seriesCancelled: (data['seriesCancelled'] as num? ?? 0).toInt(),
      occurrencesCancelled: (data['occurrencesCancelled'] as num? ?? 0).toInt(),
      bookingsCancelled: (data['bookingsCancelled'] as num? ?? 0).toInt(),
    );
  }

  @override
  Future<void> registerFcmToken({
    required String staffId,
    required String token,
  }) async {
    await _staff.doc(staffId).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  @override
  Future<void> updateStaffProfile({
    required String staffId,
    required String name,
    required String email,
    required String phone,
    DateTime? birthDate,
    required String address,
    required String nif,
    required String emergencyContact,
  }) async {
    await _functions.httpsCallable('updateStaffProfile').call<void>({
      'staffId': staffId,
      'name': name,
      'email': email,
      'phone': phone,
      if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
      'address': address,
      'nif': nif,
      'emergencyContact': emergencyContact,
    });
  }
}
