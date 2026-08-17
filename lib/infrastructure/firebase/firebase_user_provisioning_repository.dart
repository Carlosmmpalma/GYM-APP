import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/new_account_credentials.dart';
import '../../domain/entities/role.dart';
import '../../repositories/user_provisioning_repository.dart';

/// `Map<String, dynamic>.from(...)` em vez de um cast direto: o
/// `.data` de um `HttpsCallableResult` pode chegar como um
/// `Map<Object?, Object?>` (comum em Flutter Web, por causa do
/// interop com JS) — um `as Map<String, dynamic>` direto rebentaria
/// nesse caso. `.from()` copia as entradas para o tipo certo,
/// independentemente do tipo exato do Map original.
Map<String, dynamic> _asMap(Object? data) =>
    Map<String, dynamic>.from(data as Map);

class FirebaseUserProvisioningRepository implements UserProvisioningRepository {
  FirebaseUserProvisioningRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<NewAccountCredentials> createMember({
    required String name,
    String phone = '',
    String email = '',
    DateTime? birthDate,
    String address = '',
    String nif = '',
    String emergencyContact = '',
  }) async {
    final result =
        await _functions.httpsCallable('createMember').call<Object?>({
      'name': name,
      'phone': phone,
      'email': email,
      if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
      'address': address,
      'nif': nif,
      'emergencyContact': emergencyContact,
    });
    final data = _asMap(result.data);
    return NewAccountCredentials(
      uid: data['uid'] as String,
      loginIdentifier: data['memberNumber'] as String,
      temporaryPassword: data['temporaryPassword'] as String,
    );
  }

  @override
  Future<NewAccountCredentials> createStaff({
    required String name,
    required String email,
    required Set<Role> roles,
    Set<String> modalityIds = const {},
    String phone = '',
    DateTime? birthDate,
    String address = '',
    String nif = '',
    String emergencyContact = '',
  }) async {
    final result = await _functions.httpsCallable('createStaff').call<Object?>({
      'name': name,
      'email': email,
      'roles': roles.map((r) => r.name).toList(),
      'modalityIds': modalityIds.toList(),
      'phone': phone,
      if (birthDate != null) 'birthDate': birthDate.toIso8601String(),
      'address': address,
      'nif': nif,
      'emergencyContact': emergencyContact,
    });
    final data = _asMap(result.data);
    return NewAccountCredentials(
      uid: data['uid'] as String,
      loginIdentifier: data['email'] as String,
      temporaryPassword: data['temporaryPassword'] as String,
    );
  }
}
