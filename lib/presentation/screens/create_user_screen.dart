import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../domain/entities/new_account_credentials.dart';
import '../../domain/entities/role.dart';
import '../widgets/personal_data_fields.dart';

enum _UserType { aluno, staff }

/// UC22 — Ecrã Gestor: criar um Aluno ou Staff. Gap encontrado a
/// comparar a app com `Functional/nxt-studio-screens.html`: a história
/// da Fase 1 já pedia isto ("Ecrã de login (UC01) + criação de conta
/// pelo Gestor (UC22, nº de sócio automático)"), mas só o login tinha
/// sido feito — `createMember`/`createStaff` existiam desde a Fase 1
/// sem nenhuma UI a chamá-las.
///
/// Fase 6: o mockup ("Modalidade associada": Hyrox/PT/Pilates como
/// checkboxes) tinha ficado sem seguimento porque `createStaff.ts` não
/// tinha nenhum campo de modalidade — `Modality` não existia em
/// nenhuma parte da app. Agora existe (UC12/22 fechado); o picker
/// aparece só quando "Instrutor" está selecionado.
class CreateUserScreen extends ConsumerStatefulWidget {
  const CreateUserScreen({super.key});

  @override
  ConsumerState<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends ConsumerState<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  // Aluno: email de CONTACTO (login usa o nº de sócio sintético).
  // Staff: email de LOGIN real (decisão fechada, ver createStaff.ts).
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _nifController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  DateTime? _birthDate;

  _UserType _type = _UserType.aluno;
  final Set<Role> _staffRoles = {Role.instructor};
  final Set<String> _modalityIds = {};
  bool _submitting = false;
  String? _errorMessage;

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == _UserType.staff && _staffRoles.isEmpty) {
      setState(() =>
          _errorMessage = 'Escolhe pelo menos um papel (Instrutor/Gestor).');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    // `_submitting` só cobre a chamada de rede (o spinner do botão),
    // nunca o tempo em que o diálogo de credenciais fica aberto — um
    // `CircularProgressIndicator` indeterminado ainda a animar por
    // baixo do diálogo faz o `pumpAndSettle()` de um teste nunca
    // estabilizar (mesma armadilha já documentada em
    // `member_detail_screen.dart#_recalculate`).
    NewAccountCredentials credentials;
    try {
      final repository = ref.read(userProvisioningRepositoryProvider);
      credentials = _type == _UserType.aluno
          ? await repository.createMember(
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim(),
              email: _emailController.text.trim(),
              birthDate: _birthDate,
              address: _addressController.text.trim(),
              nif: _nifController.text.trim(),
              emergencyContact: _emergencyContactController.text.trim(),
            )
          : await repository.createStaff(
              name: _nameController.text.trim(),
              email: _emailController.text.trim(),
              roles: _staffRoles,
              modalityIds: _staffRoles.contains(Role.instructor)
                  ? _modalityIds
                  : const {},
              phone: _phoneController.text.trim(),
              birthDate: _birthDate,
              address: _addressController.text.trim(),
              nif: _nifController.text.trim(),
              emergencyContact: _emergencyContactController.text.trim(),
            );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Não foi possível criar a conta: $e';
          _submitting = false;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    await _showCredentialsDialog(credentials);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Mockup ("Criar utilizador — Aluno"): "Credenciais comunicadas ao
  /// utilizador fora da app (ex: presencialmente)" — por isso isto é
  /// um diálogo bloqueante que o Gestor tem de fechar explicitamente,
  /// não um SnackBar que desaparece sozinho: é a ÚNICA vez que a
  /// password temporária é mostrada.
  Future<void> _showCredentialsDialog(NewAccountCredentials credentials) {
    final isStaff = _type == _UserType.staff;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Conta criada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isStaff ? 'Email de login' : 'Nº de sócio'),
            SelectableText(
              credentials.loginIdentifier,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text('Password temporária'),
            SelectableText(
              credentials.temporaryPassword,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            const Text(
              'Comunica estas credenciais fora da app (ex: presencialmente). '
              'Não voltam a ser mostradas depois de fechares este ecrã — o '
              'utilizador é obrigado a defini-las de novo no primeiro login.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar utilizador')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<_UserType>(
                segments: const [
                  ButtonSegment(value: _UserType.aluno, label: Text('Aluno')),
                  ButtonSegment(value: _UserType.staff, label: Text('Staff')),
                ],
                selected: {_type},
                onSelectionChanged: (selection) =>
                    setState(() => _type = selection.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome completo'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),
              PersonalDataFields(
                phoneController: _phoneController,
                addressController: _addressController,
                nifController: _nifController,
                emergencyContactController: _emergencyContactController,
                birthDate: _birthDate,
                onBirthDateChanged: (date) => setState(() => _birthDate = date),
              ),
              if (_type == _UserType.aluno) ...[
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'O nº de sócio é gerado automaticamente — não é preciso '
                      'escrever nada aqui (UC22).',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration:
                      const InputDecoration(labelText: 'Email de contacto'),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
              if (_type == _UserType.staff) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                      labelText: 'Email (usado para login)'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Obrigatório';
                    return v.contains('@') ? null : 'Email inválido';
                  },
                ),
                const SizedBox(height: 16),
                const Text('Papel'),
                CheckboxListTile(
                  title: const Text('Instrutor'),
                  value: _staffRoles.contains(Role.instructor),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _staffRoles.add(Role.instructor);
                    } else {
                      _staffRoles.remove(Role.instructor);
                    }
                  }),
                ),
                CheckboxListTile(
                  title: const Text('Gestor'),
                  value: _staffRoles.contains(Role.manager),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _staffRoles.add(Role.manager);
                    } else {
                      _staffRoles.remove(Role.manager);
                    }
                  }),
                ),
                if (_staffRoles.contains(Role.instructor)) ...[
                  const SizedBox(height: 16),
                  const Text('Modalidades'),
                  Consumer(
                    builder: (context, ref, _) {
                      final modalitiesAsync = ref.watch(modalitiesProvider);
                      return modalitiesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Text('Erro: $error'),
                        data: (modalities) {
                          final active =
                              modalities.where((m) => m.active).toList();
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
                                    value: _modalityIds.contains(m.id),
                                    onChanged: (checked) => setState(() {
                                      if (checked ?? false) {
                                        _modalityIds.add(m.id);
                                      } else {
                                        _modalityIds.remove(m.id);
                                      }
                                    }),
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
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '🔑 Password inicial é temporária — o utilizador é '
                    'obrigado a defini-la de novo no primeiro login.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Criar e gerar credenciais'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
