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
                child: SwitchListTile(
                  title: Text(service.name),
                  subtitle: Text(service.active ? 'Ativo' : 'Inativo'),
                  value: service.active,
                  onChanged: (value) => _setActive(context, ref, service, value),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createService(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateServiceDialog(),
    );
    if (name == null) return;

    try {
      await ref.read(serviceRepositoryProvider).createService(name: name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar o serviço: $e')),
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

class _CreateServiceDialog extends StatefulWidget {
  const _CreateServiceDialog();

  @override
  State<_CreateServiceDialog> createState() => _CreateServiceDialogState();
}

class _CreateServiceDialogState extends State<_CreateServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo serviço'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Nome'),
          autofocus: true,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Criar')),
      ],
    );
  }
}
