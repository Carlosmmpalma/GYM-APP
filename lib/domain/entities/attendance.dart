import 'package:equatable/equatable.dart';

enum AttendanceStatus { attended, noShow }

/// Fase 6 (Domain Model v1 §29, UC10-A) — presença separada do
/// booking: uma marcação (`Booking`) diz "o membro reservou a vaga";
/// isto diz "o membro apareceu ou não". Documento em
/// `tenants/{t}/sessionOccurrences/{occId}/attendance/{memberId}` —
/// mesmo id-por-membro do `Booking`, para no máximo um registo por
/// membro por ocorrência.
class Attendance extends Equatable {
  const Attendance({
    required this.memberId,
    required this.status,
    required this.recordedBy,
    required this.recordedAt,
  });

  final String memberId;
  final AttendanceStatus status;

  /// uid de quem registou (Instrutor ou Manager).
  final String recordedBy;
  final DateTime recordedAt;

  @override
  List<Object?> get props => [memberId, status, recordedBy, recordedAt];
}
