import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../widgets/design_system.dart';

/// Fase 4 — Ecrã Gestor: "antecedência mínima para cancelar" (horas).
/// Único campo por agora — não havia nenhum sítio para configurar isto
/// (decisão: um valor por tenant, não por Plan/Service, ver README).
/// Cancelar dentro da janela devolve a utilização semanal consumida;
/// fora da janela, cancela na mesma (a vaga liberta-se) mas a
/// utilização não é devolvida.
class TenantSettingsScreen extends ConsumerStatefulWidget {
  const TenantSettingsScreen({super.key});

  @override
  ConsumerState<TenantSettingsScreen> createState() =>
      _TenantSettingsScreenState();
}

class _TenantSettingsScreenState extends ConsumerState<TenantSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  final _reminderHoursController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _reminderHoursController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final tenantId = ref.read(tenantAppConfigProvider).tenantId;
      await ref.read(tenantRepositoryProvider).setMinCancellationNoticeHours(
            tenantId: tenantId,
            hours: int.parse(_hoursController.text.trim()),
          );
      await ref.read(tenantRepositoryProvider).setMinBookingNoticeMinutes(
            tenantId: tenantId,
            minutes: int.parse(_minutesController.text.trim()),
          );
      await ref.read(tenantRepositoryProvider).setSessionReminderHours(
            tenantId: tenantId,
            hours: int.parse(_reminderHoursController.text.trim()),
          );
      ref.invalidate(minCancellationNoticeHoursProvider);
      ref.invalidate(minBookingNoticeMinutesProvider);
      ref.invalidate(sessionReminderHoursProvider);
      if (!mounted) return;
      setState(() => _message = 'Guardado.');
    } catch (e) {
      setState(() => _message = userFacingError(e,
          fallback: 'Não foi possível guardar. Tenta outra vez.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Guarda logo à escolha, sem esperar pelo botão "Guardar": é uma
  /// escolha única e discreta, e obrigar a submeter o formulário todo
  /// por causa dela seria pedir dois passos onde basta um.
  Future<void> _setFreeTrainingService(String? serviceId) async {
    try {
      await ref.read(tenantRepositoryProvider).setFreeTrainingServiceId(
            tenantId: ref.read(tenantAppConfigProvider).tenantId,
            serviceId: serviceId,
          );
      ref.invalidate(freeTrainingServiceIdProvider);
      if (!mounted) return;
      setState(() => _message = 'Serviço de treino livre atualizado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = userFacingError(e,
          fallback: 'Não foi possível guardar. Tenta outra vez.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoursAsync = ref.watch(minCancellationNoticeHoursProvider);
    final minutesAsync = ref.watch(minBookingNoticeMinutesProvider);
    final freeTrainingAsync = ref.watch(freeTrainingServiceIdProvider);
    final reminderHoursAsync = ref.watch(sessionReminderHoursProvider);
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: hoursAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorState(error: error, compact: true),
          data: (hours) {
            return minutesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorState(error: error, compact: true),
              data: (minutes) {
                // O lembrete não bloqueia o ecrã enquanto carrega (é
                // o último campo, e tem default) — só se espera por
                // ele para preencher a caixa.
                final reminderHours = reminderHoursAsync.valueOrNull;
                if (!_initialized && reminderHours != null) {
                  _hoursController.text = hours.toString();
                  _minutesController.text = minutes.toString();
                  _reminderHoursController.text = reminderHours.toString();
                  _initialized = true;
                }
                return Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      const Text(
                        'Antecedência mínima para cancelar uma marcação, em '
                        'horas. Cancelar DENTRO desta janela devolve a '
                        'utilização semanal consumida; cancelar FORA da janela '
                        'cancela na mesma (a vaga liberta-se) mas a utilização '
                        'fica consumida — funciona como penalização por '
                        'cancelar tarde. "0" significa sem restrição: qualquer '
                        'cancelamento devolve sempre a utilização.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hoursController,
                        decoration: const InputDecoration(
                          labelText:
                              'Antecedência mínima para cancelar (horas)',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final parsed = int.tryParse((v ?? '').trim());
                          if (parsed == null) {
                            return 'Introduz um número inteiro';
                          }
                          return parsed < 0 ? 'Não pode ser negativo' : null;
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Antecedência mínima para MARCAR uma sessão, em '
                        'minutos (não pode marcar-se, por exemplo, 5 minutos '
                        'antes da aula começar). Só se aplica à marcação '
                        'feita pelo próprio aluno — atribuição manual por '
                        'Instrutor/Gestor não tem esta restrição. "0" '
                        'significa sem restrição.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _minutesController,
                        decoration: const InputDecoration(
                          labelText:
                              'Antecedência mínima para marcar (minutos)',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final parsed = int.tryParse((v ?? '').trim());
                          if (parsed == null) {
                            return 'Introduz um número inteiro';
                          }
                          return parsed < 0 ? 'Não pode ser negativo' : null;
                        },
                      ),
                      const SizedBox(height: 24),
                      // Fase 11 — lembrete antes da aula. A falta sem
                      // aviso é o custo real de um estúdio com
                      // capacidade limitada: o lugar ficou ocupado e
                      // ninguém o pôde usar.
                      const Text(
                        'Com quantas horas de antecedência o aluno recebe o '
                        'lembrete da aula marcada. Serve tanto para quem vem '
                        'confirmar como para quem já não pode vir cancelar a '
                        'tempo — libertando o lugar para quem está em lista '
                        'de espera. "0" desliga os lembretes.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _reminderHoursController,
                        decoration: const InputDecoration(
                          labelText: 'Lembrete da aula (horas antes)',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final parsed = int.tryParse((v ?? '').trim());
                          if (parsed == null) {
                            return 'Introduz um número inteiro';
                          }
                          if (parsed < 0) return 'Não pode ser negativo';
                          // Mais do que uma semana deixa de ser
                          // lembrete e passa a ser ruído.
                          return parsed > 168 ? 'No máximo 168 (7 dias)' : null;
                        },
                      ),
                      const SizedBox(height: 24),
                      // Fase 11 — o treino livre precisa de um serviço,
                      // como qualquer marcação: é o que o liga ao plano
                      // do aluno e ao limite semanal. Mas é SEMPRE o
                      // mesmo, e a app pedia-o duas vezes — ao criar a
                      // grelha da semana e outra vez em cada bloco.
                      // Escolhe-se aqui, uma vez.
                      const Text(
                        'Qual dos teus serviços é o treino livre. É o '
                        'serviço que fica associado a cada bloco da grelha '
                        'semanal, e é o que decide que planos dão acesso ao '
                        'treino livre. Escolhe-se uma vez: depois disto, '
                        'criar a grelha e os blocos deixa de perguntar.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      servicesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) =>
                            ErrorState(error: error, compact: true),
                        data: (services) {
                          final active =
                              services.where((s) => s.active).toList();
                          if (active.isEmpty) {
                            return const AppBanner(
                              text: 'Cria primeiro um serviço (Gestão › '
                                  'Serviços) — por exemplo "Treino Livre".',
                              tone: PillTone.neutral,
                              icon: Icons.info_outline,
                            );
                          }
                          final current = freeTrainingAsync.valueOrNull;
                          return DropdownButtonFormField<String?>(
                            initialValue: active.any((s) => s.id == current)
                                ? current
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Serviço de treino livre',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Nenhum — treino livre desligado'),
                              ),
                              ...active.map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                _setFreeTrainingService(value),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_message != null) ...[
                        Text(_message!),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Guardar'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
