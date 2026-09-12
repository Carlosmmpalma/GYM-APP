import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/public_schedule.dart';
import '../../domain/entities/studio_info.dart';
import '../../repositories/public_schedule_repository.dart';

class FirebasePublicScheduleRepository implements PublicScheduleRepository {
  FirebasePublicScheduleRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _public(String tenantId) =>
      _firestore.collection('tenants').doc(tenantId).collection('public');

  @override
  Future<PublicSchedule> getSchedule(String tenantId) async {
    final snapshot = await _public(tenantId).doc('schedule').get();

    final data = snapshot.data();
    if (data == null) return const PublicSchedule(entries: []);

    final raw = (data['entries'] as List?) ?? const [];
    return PublicSchedule(
      entries: raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(
            (e) => PublicScheduleEntry(
              name: e['name'] as String? ?? '',
              dayOfWeek: (e['dayOfWeek'] as num?)?.toInt() ?? 1,
              startTime: e['startTime'] as String? ?? '',
              durationMinutes: (e['durationMinutes'] as num?)?.toInt() ?? 0,
              capacity: (e['capacity'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  Future<StudioInfo> getStudioInfo(String tenantId) async {
    final snapshot = await _public(tenantId).doc('info').get();
    final data = snapshot.data();
    // Ainda não existe: o Gestor nunca preencheu. Não é um erro — a
    // vitrina esconde o que não sabe.
    if (data == null) return const StudioInfo();

    final horas = (data['openingHours'] as List?) ?? const [];
    return StudioInfo(
      address: data['address'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      email: data['email'] as String? ?? '',
      mapsUrl: data['mapsUrl'] as String? ?? '',
      privacyPolicyUrl: data['privacyPolicyUrl'] as String? ?? '',
      openingHours: horas
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => OpeningHours(
                days: e['days'] as String? ?? '',
                hours: e['hours'] as String? ?? '',
              ))
          .toList(),
    );
  }
}
