import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/service.dart';

/// UC26 — Ecrã Gestor: criar e ativar/desativar Services.
///
/// Distinto de `PlanDetailScreen` (que só liga/desliga um Service já
/// existente a um Plan, com uma UsageRule): este ecrã é onde o Service
/// em si — o catálogo do ginásio (ex. "Aula de Grupo", "Pilates") —
/// nasce. Sem isto, `PlanDetailScreen` não tinha nada para listar além
/// do único Service semeado manualmente na Fase 2.
class ManageServicesScreen extends ConsumerWidget {
  const ManageServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Serviços')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createService(context, ref),
        tooltip: 'Novo serviço',
        child: const Icon(Icons.add),
      ),
      body: servicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (services) {
          if (services.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não existe nenhum serviço. Usa o botão "+" para '
                  'criar o primeiro.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final service = services[index];
              return Card(
                child: ListTile(
                  title: Text(service.name),
                  subtitle: Text(
                    [
                      service.active ? 'Ativo' : 'Inativo',
                      if (service.exclusiveGroup != null)
                        'Grupo exclusivo: ${service.exclusiveGroup}',
                    ].join(' · '),
                  ),
                  onTap: () => _editService(context, ref, service),
                  trailing: Switch(
                    value: service.active,
                    onChanged: (value) =>
                        _setActive(context, ref, service, value),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createService(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String name, String? exclusiveGroup})>(
      context: context,
      builder: (_) => const _ServiceFormDialog(),
    );
    if (result == null) return;

    try {
      await ref.read(serviceRepositoryProvider).createService(
            name: result.name,
            exclusiveGroup: result.exclusiveGroup,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar o serviço: $e')),
      );
    }
  }

  Future<void> _editService(
    BuildContext context,
    WidgetRef ref,
    Service service,
  ) async {
    final result = await showDialog<({String name, String? exclusiveGroup})>(
      context: context,
      builder: (_) => _ServiceFormDialog(service: service),
    );
    if (result == null) return;

    try {
      await ref.read(serviceRepositoryProvider).updateService(
            serviceId: service.id,
            name: result.name,
            exclusiveGroup: result.exclusiveGroup,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível editar o serviço: $e')),
      );
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    Service service,
    bool active,
  ) async {
    try {
      await ref.read(serviceRepositoryProvider).setServiceActive(
            serviceId: service.id,
            active: active,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o serviço: $e')),
      );
    }
  }
}

/// Serve tanto criar como editar — [service] `null` é criação. UC26
/// (fechado) — `exclusiveGroup` é um identificador LIVRE (não um
/// enum): o Gestor escreve a mesma palavra (ex.: "sala") em todos os
/// serviços que devem ser mutuamente exclusivos entre si ("Sem
/// acompanhamento" e o serviço que os planos Standard/Plus/Premium
/// concedem) — só a IGUALDADE da string é que importa para
/// `createSubscription.ts`, não o texto em si.
class _ServiceFormDialog extends StatefulWidget {
  const _ServiceFormDialog({this.service});

  final Service? service;

  @override
  State<_ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<_ServiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController =
      TextEditingController(text: widget.service?.name ?? '');
  late final _groupController =
      TextEditingController(text: widget.service?.exclusiveGroup ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final group = _groupController.text.trim();
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      exclusiveGroup: group.isEmpty ? null : group,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.service != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar serviço' : 'Novo serviço'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
              autofocus: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _groupController,
              decoration: const InputDecoration(
                labelText: 'Grupo exclusivo (opcional)',
                helperText: 'Serviços com o MESMO grupo tornam-se mutuamente '
                    'exclusivos (UC26) — um membro nunca pode ter '
                    'subscriptions ativas a dois deles ao mesmo tempo.',
                helperMaxLines: 3,
              ),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Guardar' : 'Criar'),
        ),
      ],
    );
  }
}
