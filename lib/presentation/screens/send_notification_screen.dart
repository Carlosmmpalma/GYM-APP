import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/notification_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../widgets/design_system.dart';

/// Fase 6 (UC21) — enviar uma notificação push. Dois modos, conforme
/// [occurrenceId]:
///   * definido → alvo fixo "todos os inscritos ativos desta sessão"
///     (aberto a partir de `OccurrenceDetailScreen`), sem picker.
///   * `null` → picker de UM membro específico (aberto a partir de
///     `ManagerScreen`) — não existe hoje nenhuma noção de "todos os
///     membros" como alvo de notificação em massa fora do contexto de
///     uma sessão concreta (ver nota em `sendNotification.ts`).
class SendNotificationScreen extends ConsumerStatefulWidget {
  const SendNotificationScreen({super.key, this.occurrenceId});

  final String? occurrenceId;

  @override
  ConsumerState<SendNotificationScreen> createState() =>
      _SendNotificationScreenState();
}

class _SendNotificationScreenState
    extends ConsumerState<SendNotificationScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String? _selectedMemberId;
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _canSend {
    if (_sending) return false;
    if (_titleController.text.trim().isEmpty) return false;
    if (_bodyController.text.trim().isEmpty) return false;
    if (widget.occurrenceId == null && _selectedMemberId == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (widget.occurrenceId != null)
              const Text('Alvo: todos os inscritos ativos desta sessão.')
            else
              membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    ErrorState(error: error, compact: true),
                data: (members) => DropdownButtonFormField<String>(
                  initialValue: _selectedMemberId,
                  decoration: const InputDecoration(labelText: 'Membro'),
                  items: members
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m.uid,
                          child: Text(m.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedMemberId = value),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Mensagem'),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canSend ? _send : null,
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final result = await ref.read(sendNotificationUseCaseProvider).call(
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            memberId: widget.occurrenceId == null ? _selectedMemberId : null,
            occurrenceId: widget.occurrenceId,
          );
      if (!mounted) return;
      final message = result.targets == 0
          ? 'Ninguém elegível para notificar (sem inscritos, ou sem tokens registados).'
          : 'Enviada a ${result.sent}/${result.targets} dispositivo(s).';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      if (result.targets > 0) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
