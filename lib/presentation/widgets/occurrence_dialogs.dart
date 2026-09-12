import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../domain/entities/session_occurrence.dart';
import 'design_system.dart';
import '../../core/utils/time_range.dart';
import 'time_range_field.dart';

/// Fase 8 (revisão geral) — estes dois diálogos existiam DUPLICADOS em
/// `series_detail_screen.dart` (Fase 5) e `occurrence_detail_screen.dart`
/// (Fase 8): quase byte-a-byte iguais, criados por eu ter acrescentado
/// as ações a `OccurrenceDetailScreen` copiando as que já existiam no
/// menu de `SeriesDetailScreen`, em vez de as extrair na altura. Duas
/// cópias da mesma regra ("nunca selecionar mais do que as vagas
/// disponíveis", "capacidade tem de ser > 0") divergem à primeira
/// alteração que só apanhe uma delas — que é exatamente o risco que o
/// `bookingLogic.ts` foi extraído para evitar do lado do servidor.
///
/// Resultado de [showEditOccurrenceDialog]: `null` se cancelado.
/// `endAt` passou a fazer parte do resultado: sem ele, quem chamava
/// isto tinha de reconstruir o fim a partir da duração antiga, e por
/// isso a duração era impossível de mudar.
typedef EditOccurrenceResult = ({
  DateTime startAt,
  DateTime endAt,
  int capacity,
});

/// UC18 — "editar só esta ocorrência" (hora/data/capacidade). Nunca
/// toca em `activeBookingCount` nem em `status`: cancelar passa sempre
/// pela Cloud Function (ver `SessionOccurrenceRepository`).
///
/// [title] distingue os dois pontos de entrada — "Editar aula"
/// (`OccurrenceDetailScreen`, uma sessão qualquer) vs "Editar esta
/// ocorrência" (`SeriesDetailScreen`, onde é importante deixar claro
/// que a alteração é só desta semana, nota de UX do UC17/UC19).
Future<EditOccurrenceResult?> showEditOccurrenceDialog({
  required BuildContext context,
  required SessionOccurrence occurrence,
  required String title,
  String? subtitle,
}) {
  return showDialog<EditOccurrenceResult>(
    context: context,
    builder: (_) => _EditOccurrenceDialog(
      occurrence: occurrence,
      title: title,
      subtitle: subtitle,
    ),
  );
}

/// UC08-A/UC17/UC19 — picker de membros elegíveis. [isExtra] só muda o
/// texto mostrado; quem decide o efeito real (isentar do limite
/// semanal) é sempre o backend (`assignMembersToOccurrence.ts`).
/// Devolve `null` se cancelado, ou a lista de `uid`s escolhidos.
Future<List<String>?> showAssignMemberDialog({
  required BuildContext context,
  required String serviceId,
  required SessionOccurrence occurrence,
  bool isExtra = false,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _AssignMemberDialog(
      serviceId: serviceId,
      occurrence: occurrence,
      isExtra: isExtra,
    ),
  );
}

class _EditOccurrenceDialog extends StatefulWidget {
  const _EditOccurrenceDialog({
    required this.occurrence,
    required this.title,
    this.subtitle,
  });

  final SessionOccurrence occurrence;
  final String title;
  final String? subtitle;

  @override
  State<_EditOccurrenceDialog> createState() => _EditOccurrenceDialogState();
}

class _EditOccurrenceDialogState extends State<_EditOccurrenceDialog> {
  late DateTime _date = widget.occurrence.startAt;
  late TimeOfDay _time = TimeOfDay.fromDateTime(widget.occurrence.startAt);

  /// Editar uma aula não deixava mexer na duração: ela era herdada em
  /// silêncio da aula original. Uma aula criada com 60 minutos ficava
  /// com 60 minutos para sempre — a única saída era apagá-la e criar
  /// outra, e as aulas geradas por série nem isso permitem.
  late TimeOfDay _endTime = TimeOfDay.fromDateTime(widget.occurrence.endAt);
  late final _capacityController =
      TextEditingController(text: widget.occurrence.capacity.toString());

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  bool get _valid {
    final capacity = int.tryParse(_capacityController.text.trim());
    return capacity != null && capacity > 0 && endsAfterStart(_time, _endTime);
  }

  void _submit() {
    if (!_valid) return;
    final capacity = int.parse(_capacityController.text.trim());
    final startAt =
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    final endAt = DateTime(
        _date.year, _date.month, _date.day, _endTime.hour, _endTime.minute);
    Navigator.of(context).pop(
      (startAt: startAt, endAt: endAt, capacity: capacity),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data'),
            subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 8),
          TimeRangeField(
            compact: true,
            start: _time,
            end: _endTime,
            onChanged: (start, end) => setState(() {
              _time = start;
              _endTime = end;
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _capacityController,
            decoration: const InputDecoration(labelText: 'Capacidade'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _AssignMemberDialog extends ConsumerStatefulWidget {
  const _AssignMemberDialog({
    required this.serviceId,
    required this.occurrence,
    required this.isExtra,
  });

  final String serviceId;
  final SessionOccurrence occurrence;
  final bool isExtra;

  @override
  ConsumerState<_AssignMemberDialog> createState() =>
      _AssignMemberDialogState();
}

class _AssignMemberDialogState extends ConsumerState<_AssignMemberDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final eligibleAsync = ref.watch(eligibleMembersProvider(widget.serviceId));
    final availableSlots = widget.occurrence.availableSlots;

    return AlertDialog(
      title: Text(widget.isExtra ? '+ Sessão extra' : 'Adicionar membro'),
      content: SizedBox(
        width: double.maxFinite,
        child: eligibleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorState(error: error, compact: true),
          data: (members) {
            if (members.isEmpty) {
              return const Text(
                'Nenhum membro tem ainda um plano ativo com acesso a este serviço.',
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$availableSlots vaga(s) disponível(eis).'),
                  if (widget.isExtra)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Sessão extra: não conta para o limite semanal do '
                        'plano destes membros (continua a ocupar vaga na '
                        'sala).',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  for (final member in members)
                    CheckboxListTile(
                      title: Text('${member.name} (${member.memberNumber})'),
                      value: _selected.contains(member.uid),
                      onChanged: (v) {
                        if (v == true && _selected.length >= availableSlots) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Não há mais vagas disponíveis.')),
                          );
                          return;
                        }
                        setState(() {
                          if (v == true) {
                            _selected.add(member.uid);
                          } else {
                            _selected.remove(member.uid);
                          }
                        });
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
