import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../domain/entities/member_summary.dart';

/// UC02 — "Perfil": o próprio membro vê o número de sócio (gerido pelo
/// Gestor, UC22) e edita só o telefone/email de contacto. Nome/nº de
/// sócio/estado continuam exclusivos do Gestor — mesma restrição já
/// aplicada em `firestore.rules` (não só nesta UI).
///
/// Mockup pedia também foto de perfil ("só foto/contactos editáveis") —
/// deliberadamente fora desta versão: exigiria integrar Firebase
/// Storage (upload de imagem, `storage.rules`, picker), infraestrutura
/// ainda não tocada em nenhuma fase; sinalizado, não escondido.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(memberProfileProvider(memberId));

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (member) {
          if (member == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não foi possível encontrar o teu perfil. Contacta o '
                  'Gestor do ginásio.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _ProfileForm(member: member);
        },
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.member});

  final MemberSummary member;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _phoneController =
      TextEditingController(text: widget.member.phone);
  late final _emailController =
      TextEditingController(text: widget.member.email);
  bool _saving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(memberRepositoryProvider).updateOwnContact(
            memberId: widget.member.uid,
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Nº de sócio ${member.memberNumber}${member.active ? '' : ' · inativo'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Nome e nº de sócio são geridos pelo Gestor do ginásio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(labelText: 'Telefone'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email de contacto'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
