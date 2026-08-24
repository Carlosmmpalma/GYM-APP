import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/retention_overview.dart';
import '../../repositories/retention_repository.dart';

class FirebaseRetentionRepository implements RetentionRepository {
  FirebaseRetentionRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<RetentionOverview> getOverview({
    int windowDays = 30,
    int riskWeeks = 3,
  }) async {
    final result =
        await _functions.httpsCallable('getRetentionOverview').call<Object?>({
      'windowDays': windowDays,
      'riskWeeks': riskWeeks,
    });

    // Mesmo cuidado de `firebase_booking_repository.dart`: no Flutter
    // Web o interop devolve `Map<Object?, Object?>`, por isso nada de
    // `as Map<String, dynamic>` direto.
    final data = Map<String, dynamic>.from(result.data as Map);
    final occupancy = Map<String, dynamic>.from(data['occupancy'] as Map);
    final attendance = Map<String, dynamic>.from(data['attendance'] as Map);

    return RetentionOverview(
      windowDays: (data['windowDays'] as num).toInt(),
      riskWeeks: (data['riskWeeks'] as num).toInt(),
      scanDays: (data['scanDays'] as num).toInt(),
      membersWithActivePlan: (data['membersWithActivePlan'] as num).toInt(),
      sessions: (occupancy['sessions'] as num).toInt(),
      occupancyPercent: (occupancy['ratePercent'] as num?)?.toInt(),
      attendanceRecorded: (attendance['recorded'] as num).toInt(),
      noShows: (attendance['noShows'] as num).toInt(),
      noShowPercent: (attendance['noShowRatePercent'] as num?)?.toInt(),
      atRisk: (data['atRisk'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .map(
            (entry) => MemberAtRisk(
              memberId: entry['memberId'] as String,
              name: entry['name'] as String? ?? '',
              memberNumber: entry['memberNumber'] as String? ?? '',
              lastAttendanceAt: entry['lastAttendanceAt'] == null
                  ? null
                  : DateTime.parse(entry['lastAttendanceAt'] as String),
            ),
          )
          .toList(),
    );
  }
}
