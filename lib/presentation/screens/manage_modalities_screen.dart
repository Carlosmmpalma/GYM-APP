import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/service.dart';
import '../widgets/design_system.dart';
import '../../repositories/catalogue_admin_repository.dart';
import '../widgets/catalogue_delete.dart';

/// Fase 6 (Domain Model v1 §8-9) — Ecrã Gestor: criar/ativar/desativar
/// modalidades e escolher a que serviços cada uma se aplica. Mesmo
/// padrão de `ManageServicesScreen` (lista + FAB) para a criação;
/// `ModalityDetailScreen` (abaixo) para a relação com serviços, mesmo
/// espírito de `PlanDetailScreen`.
class ManageModalitiesScreen extends ConsumerWidget {
  const ManageModalitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modalitiesAsync = ref.watch(modalitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Modalidades')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createModality(context, ref),
        tooltip: 'Nova modalidade',
        child: const Icon(Icons.add),
      ),
      body: modalitiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (modalities) {
          if (modalities.isEmpty) {
            return EmptyState(
              icon: Icons.category_outlined,
              title: 'Ainda não há modalidades',
              message: 'Uma modalidade agrupa serviços por tipo de treino '
                  '(Pilates, Hyrox, Musculação) e serve para dizer o que '
                  'cada instrutor dá e para filtrar o horário.',
              actionLabel: 'Criar a primeira modalidade',
              onAction: () => _createModality(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: modalities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final modality = modalities[index];
              return Card(
                child: ListTile(
                  title: Text(modality.name),
                  subtitle: Text(
                    '${modality.serviceIds.length} serviço(s)'
                    '${modality.active ? '' : ' · inativa'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => confirmAndDeleteCatalogueEntry(
                          context,
                          ref,
                          kind: CatalogueKind.modality,
                          id: modality.id,
                          name: modality.name,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ModalityDetailScreen(modality: modality),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createModality(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateModalityDialog(),
    );
    if (name == null) return;

    try {
      await ref.read(modalityRepositoryProvider).createModality(name: name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível criar a modalidade. Tenta outra vez.'))),
      );
    }
  }
}

class _CreateModalityDialog extends StatefulWidget {
  const _CreateModalityDialog();

  @override
  State<_CreateModalityDialog> createState() => _CreateModalityDialogState();
}

class _CreateModalityDialogState extends State<_CreateModalityDialog> {
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
      title: const Text('Nova modalidade'),
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

class ModalityDetailScreen extends ConsumerWidget {
  const ModalityDetailScreen({super.key, required this.modality});

  final Modality modality;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentModality =
        ref.watch(modalitiesProvider).valueOrNull?.firstWhere(
                  (m) => m.id == modality.id,
                  orElse: () => modality,
                ) ??
            modality;
    final servicesAsync = ref.watch(servicesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(currentModality.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Modalidade ativa'),
              value: currentModality.active,
              onChanged: (value) async {
                try {
                  await ref.read(modalityRepositoryProvider).setModalityActive(
                        modalityId: currentModality.id,
                        active: value,
                      );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(userFacingError(e,
                            fallback:
                                'Não foi possível atualizar. Tenta outra vez.'))),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('Serviços', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          servicesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ErrorState(error: error, compact: true),
            data: (services) {
              final active = services.where((s) => s.active).toList();
              if (active.isEmpty) {
                return const Text(
                  'Ainda não existe nenhum serviço ativo no tenant.',
                );
              }
              return Column(
                children: active
                    .map(
                      (service) => _ServiceTile(
                        modalityId: currentModality.id,
                        service: service,
                        enabled:
                            currentModality.serviceIds.contains(service.id),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({
    required this.modalityId,
    required this.service,
    required this.enabled,
  });

  final String modalityId;
  final Service service;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(service.name),
        value: enabled,
        onChanged: (value) async {
          try {
            await ref.read(modalityRepositoryProvider).setServiceEnabled(
                  modalityId: modalityId,
                  serviceId: service.id,
                  enabled: value,
                );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(userFacingError(e,
                      fallback:
                          'Não foi possível atualizar. Tenta outra vez.'))),
            );
          }
        },
      ),
    );
  }
}
