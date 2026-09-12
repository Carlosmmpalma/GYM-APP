import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/payment_record.dart';
import '../widgets/design_system.dart';
import '../widgets/privacy_section.dart';
import '../widgets/person_avatar.dart';

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
        error: (error, stack) => ErrorState(error: error),
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
    final member = widget.member;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PanelCard(
          gradient: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Column(
                    children: [
                      // Sem botão para mudar a foto, e é deliberado: a
                      // foto de perfil é do ESTÚDIO, não do aluno. É a
                      // cara que o instrutor vê na tira da turma para
                      // reconhecer quem tem à frente, e por isso quem a
                      // põe e quem a tira é quem gere o estúdio — na
                      // ficha do aluno. As Security Rules dizem o mesmo,
                      // não só esta ausência de botão.
                      PersonAvatar(
                        name: member.name,
                        photoUrl: member.photoUrl,
                        size: 44,
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name,
                            style: AppTheme.display(fontSize: 17)),
                        const SizedBox(height: 3),
                        Text(
                          'Nº de sócio ${member.memberNumber}'
                          '${member.active ? '' : ' · inativo'}',
                          style: const TextStyle(
                              color: AppColors.mute, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _PaymentStatusPill(member: member),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Os meus contactos'),
        const SizedBox(height: 2),
        // Dizer o que NÃO se pode mudar aqui, e por quem, evita a
        // procura por um campo de nome que nunca vai existir neste ecrã.
        const Text(
          'Só o telefone e o email são teus para editar. Nome, nº de sócio '
          'e estado da conta são geridos pelo estúdio.',
          style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 12),
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
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ),
        const PrivacySection(),
      ],
    );
  }
}

/// Fase 9 (UC27 fechado) — mockup do "Início" mostra "Mensalidade: Em
/// dia" no card de topo; este ecrã (`MyProfileScreen`) é o equivalente
/// real desta app (`HomeScreen`, Fase 2, é uma navegação por separadores
/// sem card de topo — não há um sítio direto para replicar esse layout
/// sem o reconstruir de raiz, fora de âmbito de uma fase sobre
/// pagamentos). Só o estado do MÊS ATUAL — o histórico completo é
/// exclusivo do Gestor (`PaymentHistoryScreen`, `firestore.rules`), o
/// próprio Aluno não tem, hoje, nenhum ecrã que navegue para lá.
class _PaymentStatusPill extends StatelessWidget {
  const _PaymentStatusPill({required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context) {
    // Fase 10 — era texto colorido com `Colors.green`/`Colors.orange`,
    // cores fora da paleta do mockup; passou ao `Pill`, que é como todos
    // os outros estados da app se mostram. As etiquetas encurtaram para
    // caber num pill: o detalhe ("contacta o estúdio") já está no ecrã
    // de conta inativa, que é onde a ação é preciso.
    final (String label, PillTone tone) =
        switch (member.currentMonthStatus(DateTime.now())) {
      PaymentStatus.paid => ('Em dia', PillTone.ok),
      PaymentStatus.paidLate => ('Paga com atraso', PillTone.warn),
      PaymentStatus.overdue => ('Em atraso', PillTone.danger),
      null => ('Sem registo', PillTone.neutral),
    };
    return Pill(label, tone: tone);
  }
}
