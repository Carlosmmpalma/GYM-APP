import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../screens/occurrence_detail_screen.dart';
import 'attendance_status.dart';
import 'design_system.dart';

final _horaFormat = DateFormat('HH:mm', 'pt_PT');

/// As aulas de hoje, com o estado da chamada, e um toque para a fazer.
///
/// ## O problema que isto resolve
///
/// O início do Instrutor mostrava "Sessões hoje: 2" num cartão de
/// número. O painel do Gestor mostrava "Sessões (próx. 7 dias)". Os
/// dois diziam que havia trabalho; nenhum levava ao trabalho.
///
/// Marcar a chamada da aula de hoje eram três toques — "As minhas
/// aulas", escolher o dia, escolher a aula — e o estado de cada uma só
/// se via depois de a abrir. É a coisa mais frequente que um instrutor
/// faz nesta app, e estava mais longe do que "Biblioteca de
/// exercícios".
///
/// ## Porque a janela é a semana ISO e não "daqui para a frente"
///
/// As aulas que interessam para a chamada são precisamente as que **já
/// aconteceram**. O `upcomingWeekOccurrencesProvider` começa em
/// `DateTime.now()`, por isso a aula das 9h desaparecia da lista às
/// 9h01 — exatamente quando passava a precisar de chamada.
///
/// `occurrencesForWeekProvider` cobre a semana inteira e já está a ser
/// lido noutros ecrãs, por isso não é uma consulta nova por causa
/// disto.
class TodayClasses extends ConsumerWidget {
  const TodayClasses({super.key, this.instructorId, this.titulo = 'Hoje'});

  /// Quando presente, só as aulas deste instrutor. O Gestor vê todas —
  /// a pergunta dele é "alguma chamada por fazer no estúdio?", não "nas
  /// minhas aulas".
  final String? instructorId;

  final String titulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agora = DateTime.now();
    final aulas = (ref
                .watch(occurrencesForWeekProvider(isoWeekRange(agora).start))
                .valueOrNull ??
            const <SessionOccurrence>[])
        .where((o) =>
            o.status == SessionOccurrenceStatus.scheduled &&
            (instructorId == null || o.instructorId == instructorId) &&
            o.startAt.year == agora.year &&
            o.startAt.month == agora.month &&
            o.startAt.day == agora.day)
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    if (aulas.isEmpty) return const SizedBox.shrink();

    final servicesById = <String, Service>{
      for (final s
          in ref.watch(servicesProvider).valueOrNull ?? const <Service>[])
        s.id: s,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(titulo),
        const SizedBox(height: 8),
        for (final aula in aulas)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                '${_horaFormat.format(aula.startAt)} · '
                '${servicesById[aula.serviceId]?.name ?? aula.serviceId}',
              ),
              subtitle: Text(
                '${aula.activeBookingCount}/${aula.capacity} inscritos',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AttendanceBadge(occurrence: aula),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OccurrenceDetailScreen(occurrenceId: aula.id),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
