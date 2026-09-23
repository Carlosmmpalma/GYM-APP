import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/service.dart';
import '../widgets/design_system.dart';
import '../../repositories/catalogue_admin_repository.dart';
import '../widgets/catalogue_delete.dart';

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
        error: (error, stack) => ErrorState(error: error),
        data: (services) {
          if (services.isEmpty) {
            return EmptyState(
              icon: Icons.local_activity_outlined,
              title: 'Ainda não há serviços',
              message: 'Um serviço é aquilo que o ginásio oferece: Aula de '
                  'Grupo, Pilates, PT, Treino Livre. É a peça base — os '
                  'planos dão acesso a serviços e cada aula do horário é '
                  'de um serviço.',
              actionLabel: 'Criar o primeiro serviço',
              onAction: () => _createService(context, ref),
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
                    ].join(' · '),
                  ),
                  onTap: () => _editService(context, ref, service),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: service.active,
                        onChanged: (value) =>
                            _setActive(context, ref, service, value),
                      ),
                      CatalogueRowMenu(
                        kind: CatalogueKind.service,
                        id: service.id,
                        name: service.name,
                      ),
                    ],
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
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _ServiceFormDialog(),
    );
    if (result == null) return;

    try {
      await ref.read(serviceRepositoryProvider).createService(
            name: result,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível criar o serviço. Tenta outra vez.'))),
      );
    }
  }

  Future<void> _editService(
    BuildContext context,
    WidgetRef ref,
    Service service,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ServiceFormDialog(service: service),
    );
    if (result == null) return;

    try {
      await ref.read(serviceRepositoryProvider).updateService(
            serviceId: service.id,
            name: result,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível editar o serviço. Tenta outra vez.'))),
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
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível atualizar o serviço. Tenta outra vez.'))),
      );
    }
  }
}

/// Serve tanto criar como editar — [service] `null` é criação.
///
/// Um serviço é um nome, e mais nada. Teve um segundo campo, "Grupo
/// exclusivo (opcional)": texto livre onde o Gestor escrevia a mesma
/// palavra em serviços que fossem alternativas uns dos outros, com uma
/// ajuda que falava em `UC26` e em `subscriptions`. Escrever
/// "Acompanhamento" num e "acompanhamento" noutro fazia-os não se
/// ligarem, em silêncio.
///
/// Ninguém o preencheria, e deixou de ser preciso: com **um plano
/// ativo por membro** não há combinações para proibir.
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
