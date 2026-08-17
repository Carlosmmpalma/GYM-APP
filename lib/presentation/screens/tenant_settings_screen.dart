import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';

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
  bool _initialized = false;
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
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
      ref.invalidate(minCancellationNoticeHoursProvider);
      ref.invalidate(minBookingNoticeMinutesProvider);
      if (!mounted) return;
      setState(() => _message = 'Guardado.');
    } catch (e) {
      setState(() => _message = 'Não foi possível guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoursAsync = ref.watch(minCancellationNoticeHoursProvider);
    final minutesAsync = ref.watch(minBookingNoticeMinutesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: hoursAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Text('Erro: $error'),
          data: (hours) {
            return minutesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Text('Erro: $error'),
              data: (minutes) {
                if (!_initialized) {
                  _hoursController.text = hours.toString();
                  _minutesController.text = minutes.toString();
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
