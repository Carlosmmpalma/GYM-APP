import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/admin_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/staff_private_profile.dart';
import '../../domain/entities/staff_summary.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/design_system.dart';
import '../widgets/personal_data_fields.dart';
import '../widgets/manager_account_actions.dart';

/// Detalhe de staff (Instrutor/Gestor): dados + toggle ativo/inativo.
/// Mesmo raciocínio de `MemberDetailScreen` (desativar, nunca eliminar
/// — mockup "Editar / desativar utilizador", UC23/UC24), sem a secção
/// de subscriptions (staff não tem Plans).
class StaffDetailScreen extends ConsumerWidget {
  const StaffDetailScreen({super.key, required this.staff});

  final StaffSummary staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve pelo `staffProvider` ao vivo, mesmo padrão de
    // `currentPlan`/`currentMember` — `staff` é a cópia imutável de
    // quando `ManageStaffScreen` construiu este ecrã.
    final currentStaff = ref.watch(staffProvider).valueOrNull?.firstWhere(
              (s) => s.uid == staff.uid,
              orElse: () => staff,
            ) ??
        staff;

    return Scaffold(
      appBar: AppBar(title: Text(currentStaff.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentStaff.email,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Papel: ${currentStaff.roles.map((r) => r.name).join(', ')}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Os dados pessoais vêm de uma leitura própria: deixaram de
          // estar no documento de staff, que todo o tenant consegue
          // ler (ver `StaffPrivateProfile`). Enquanto não chegam, o
          // formulário não abre — abrir com os campos vazios e gravar
          // por cima apagava a morada e o NIF de quem lá estava.
          Consumer(
            builder: (context, ref, _) {
              final privateAsync =
                  ref.watch(staffPrivateProfileProvider(currentStaff.uid));
              return privateAsync.when(
                loading: () => const PanelCard(
                  child: SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, stack) =>
                    ErrorState(error: error, compact: true),
                data: (profile) => _EditStaffProfileCard(
                  key: ValueKey(currentStaff.uid),
                  staff: currentStaff,
                  profile: profile,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Consumer(
            builder: (context, ref, _) {
              final me = ref.watch(currentAppUserProvider).valueOrNull;
              return StaffRolesCard(
                staffId: currentStaff.uid,
                currentRoles: currentStaff.roles,
                isSelf: me?.uid == currentStaff.uid,
              );
            },
          ),
          const SizedBox(height: 16),
          ResetPasswordTile(
            userId: currentStaff.uid,
            displayName: currentStaff.name,
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Staff ativo'),
              subtitle: Text(
                currentStaff.active
                    ? 'Pode continuar a fazer login e a dar aulas/PT.'
                    : 'Inativo — mantém o histórico (aulas dadas, etc.).'
                        '${currentStaff.roles.contains(Role.instructor) ? ' As séries/sessões futuras dele já foram canceladas (UC24).' : ''}',
              ),
              value: currentStaff.active,
              onChanged: (value) =>
                  _toggleActive(context, ref, currentStaff, value),
            ),
          ),
          if (currentStaff.roles.contains(Role.instructor)) ...[
            const SizedBox(height: 24),
            Text('Modalidades', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final modalitiesAsync = ref.watch(modalitiesProvider);
                return modalitiesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) =>
                      ErrorState(error: error, compact: true),
                  data: (modalities) {
                    final active = modalities.where((m) => m.active).toList();
                    if (active.isEmpty) {
                      return const Text(
                        'Ainda não existe nenhuma modalidade ativa.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      );
                    }
                    return Column(
                      children: active
                          .map(
                            (m) => CheckboxListTile(
                              title: Text(m.name),
                              value: currentStaff.modalityIds.contains(m.id),
                              onChanged: (checked) async {
                                final updated = {...currentStaff.modalityIds};
                                if (checked ?? false) {
                                  updated.add(m.id);
                                } else {
                                  updated.remove(m.id);
                                }
                                try {
                                  await ref
                                      .read(staffRepositoryProvider)
                                      .setModalityIds(
                                        staffId: currentStaff.uid,
                                        modalityIds: updated,
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
                          )
                          .toList(),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            const SectionLabel('Serviços que pode lecionar'),
            const SizedBox(height: 2),
            const Text(
              'Isto AUTORIZA: o instrutor só consegue criar aulas dos '
              'serviços marcados aqui, e o servidor recusa as outras. Sem '
              'nenhum marcado, não cria aulas nenhumas.',
              style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final servicesAsync = ref.watch(servicesProvider);
                return servicesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stack) =>
                      ErrorState(error: error, compact: true),
                  data: (services) {
                    final active = services.where((s) => s.active).toList();
                    if (active.isEmpty) {
                      return const Text(
                        'Ainda não existe nenhum serviço ativo.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      );
                    }
                    return Column(
                      children: active
                          .map(
                            (service) => CheckboxListTile(
                              title: Text(service.name),
                              value:
                                  currentStaff.serviceIds.contains(service.id),
                              onChanged: (checked) async {
                                final updated = {...currentStaff.serviceIds};
                                if (checked ?? false) {
                                  updated.add(service.id);
                                } else {
                                  updated.remove(service.id);
                                }
                                try {
                                  await ref
                                      .read(staffRepositoryProvider)
                                      .setStaffServices(
                                        staffId: currentStaff.uid,
                                        serviceIds: updated,
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
                          )
                          .toList(),
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    StaffSummary currentStaff,
    bool active,
  ) async {
    final isInstructor = currentStaff.roles.contains(Role.instructor);

    // UC24 — desativar um instrutor cancela em cadeia as suas séries/
    // sessões futuras; um Gestor puro não tem nada para cascatar.
    // Reativar nunca cascata (não faz sentido "des-cancelar" sessões
    // sozinho) — continua a escrita simples de sempre.
    if (!active && isInstructor) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Desativar instrutor?'),
          content: Text(
            'As séries ativas e as sessões futuras de ${currentStaff.name} vão '
            'ser canceladas automaticamente (UC24) — quem estiver inscrito '
            'recupera a utilização semanal, como um cancelamento pelo estúdio.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desativar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        final summary = await ref
            .read(staffRepositoryProvider)
            .deactivateInstructorWithCascade(currentStaff.uid);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Instrutor desativado — ${summary.seriesCancelled} série(s) e '
              '${summary.occurrencesCancelled} sessão/sessões futura(s) '
              'canceladas (${summary.bookingsCancelled} marcação(ões) '
              'afetada(s)).',
            ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(userFacingError(e,
                  fallback: 'Não foi possível desativar. Tenta outra vez.'))),
        );
      }
      return;
    }

    try {
      await ref.read(staffRepositoryProvider).setStaffActive(
            staffId: currentStaff.uid,
            active: active,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível atualizar o staff. Tenta outra vez.'))),
      );
    }
  }
}

/// Pedido pelo Carlo depois de testar "Criar utilizador": até aqui
/// este ecrã não tinha NENHUMA forma de editar nome/email/dados
/// pessoais de um staff depois de criado. Ao contrário do equivalente
/// em `member_detail_screen.dart`, mudar o email aqui passa pela Cloud
/// Function `updateStaffProfile` — é o email de LOGIN real, ver nota
/// de arquitetura em `updateStaffProfile.ts`.
class _EditStaffProfileCard extends ConsumerStatefulWidget {
  const _EditStaffProfileCard({
    super.key,
    required this.staff,
    required this.profile,
  });

  final StaffSummary staff;
  final StaffPrivateProfile profile;

  @override
  ConsumerState<_EditStaffProfileCard> createState() =>
      _EditStaffProfileCardState();
}

class _EditStaffProfileCardState extends ConsumerState<_EditStaffProfileCard> {
  late final _nameController = TextEditingController(text: widget.staff.name);
  late final _emailController = TextEditingController(text: widget.staff.email);
  late final _phoneController =
      TextEditingController(text: widget.profile.phone);
  late final _addressController =
      TextEditingController(text: widget.profile.address);
  late final _nifController = TextEditingController(text: widget.profile.nif);
  late final _emergencyContactController =
      TextEditingController(text: widget.profile.emergencyContact);
  late DateTime? _birthDate = widget.profile.birthDate;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nifController.dispose();
    _emergencyContactController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome e email válido são obrigatórios.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(staffRepositoryProvider).updateStaffProfile(
            staffId: widget.staff.uid,
            name: name,
            email: email,
            phone: _phoneController.text.trim(),
            birthDate: _birthDate,
            address: _addressController.text.trim(),
            nif: _nifController.text.trim(),
            emergencyContact: _emergencyContactController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados atualizados.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível guardar. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dados pessoais',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome completo'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration:
                  const InputDecoration(labelText: 'Email (usado para login)'),
              keyboardType: TextInputType.emailAddress,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Mudar o email muda também as credenciais de login deste staff.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 12),
            PersonalDataFields(
              phoneController: _phoneController,
              addressController: _addressController,
              nifController: _nifController,
              emergencyContactController: _emergencyContactController,
              birthDate: _birthDate,
              onBirthDateChanged: (date) => setState(() => _birthDate = date),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar dados'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
