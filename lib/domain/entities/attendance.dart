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

/// Como está a chamada de uma aula, num relance.
///
/// ## Porque isto existe
///
/// A presença estava guardada por membro e lida por membro. Para saber
/// se uma aula já tinha sido marcada era preciso ABRIR a aula e ler a
/// cor de dois ícones por cada inscrito — vinte e quatro ícones numa
/// turma de doze. Um instrutor com quatro aulas num dia, que se
/// esqueceu de uma, tinha de abrir as quatro para descobrir qual.
///
/// O número que interessa não é "este membro veio?", é **"falta
/// alguém por marcar?"**. É essa a pergunta que se faz ao fim do dia, e
/// não havia nada na app que a respondesse.
class AttendanceSummary {
  const AttendanceSummary({
    required this.presentes,
    required this.faltas,
    required this.inscritos,
  });

  /// A partir da lista de registos e de quantos estão inscritos.
  ///
  /// `inscritos` vem do `activeBookingCount` da própria aula, que já
  /// está no documento — não custa uma leitura nova. É por isso que
  /// esta conta cabe num cartão de lista sem tornar o ecrã caro.
  factory AttendanceSummary.de(
    Iterable<Attendance> registos, {
    required int inscritos,
  }) {
    var presentes = 0;
    var faltas = 0;
    for (final r in registos) {
      switch (r.status) {
        case AttendanceStatus.attended:
          presentes++;
        case AttendanceStatus.noShow:
          faltas++;
      }
    }
    return AttendanceSummary(
      presentes: presentes,
      faltas: faltas,
      inscritos: inscritos,
    );
  }

  final int presentes;
  final int faltas;
  final int inscritos;

  int get marcados => presentes + faltas;

  /// Quantos continuam sem registo nenhum.
  ///
  /// Nunca negativo: um registo pode sobreviver a uma marcação
  /// cancelada (o membro desmarcou depois de já ter sido dado como
  /// presente), e nesse caso `marcados` passa `inscritos`. Mostrar
  /// "-1 por marcar" seria pior do que mostrar zero.
  int get porMarcar => (inscritos - marcados).clamp(0, inscritos);

  /// Ninguém por marcar, e havia alguém para marcar.
  ///
  /// Uma aula sem inscritos NÃO conta como feita: não há chamada
  /// nenhuma para fazer, e dar-lhe o visto verde dizia que houve uma
  /// turma que não houve.
  bool get completa => inscritos > 0 && porMarcar == 0;

  bool get vazia => inscritos == 0;
}
