import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/role.dart';
import 'design_system.dart';

/// Fase 11 — as ações de conta que o Gestor faz ao balcão, sem chamar
/// ninguém: repor a password de quem se esqueceu, e mudar os papéis de
/// um membro do staff.
///
/// Serve membros e staff pelo mesmo caminho, porque o problema é o
/// mesmo. Para um membro é o único caminho possível: alunos autenticam-se
/// com um email sintético a partir do nº de sócio, que não existe em
/// lado nenhum e ao qual não se pode enviar um link de recuperação.
class ResetPasswordTile extends ConsumerStatefulWidget {
  const ResetPasswordTile({
    super.key,
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  @override
  ConsumerState<ResetPasswordTile> createState() => _ResetPasswordTileState();
}

class _ResetPasswordTileState extends ConsumerState<ResetPasswordTile> {
  bool _busy = false;

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repor a password'),
        content: Text(
          'Vai ser gerada uma password temporária para '
          '${widget.displayName}. A password atual deixa de funcionar '
          'imediatamente e as sessões abertas noutros dispositivos são '
          'fechadas.\n\n'
          'No primeiro login, a app obriga a escolher uma nova.',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Repor'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final password = await ref
          .read(userProvisioningRepositoryProvider)
          .resetUserPassword(widget.userId);
      if (!mounted) return;
      setState(() => _busy = false);
      await _showPassword(password);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível repor a password: $e')),
      );
    }
  }

  /// A password só é mostrada UMA vez, e não fica guardada em lado
  /// nenhum legível — o Firebase Auth só guarda o hash. Daí o aviso e o
  /// botão de copiar: se este diálogo fechar sem a password ter sido
  /// entregue, o caminho é repor outra vez.
  Future<void> _showPassword(String password) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Password temporária'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Entrega esta password a ${widget.displayName}. Não volta a '
              'ser mostrada — se a perderes, repõe outra vez.',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 14),
            PanelCard(
              child: SelectableText(
                password,
                style: const TextStyle(
                  fontSize: 18,
                  fontFamily: 'monospace',
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(dialogContext);
              final navigator = Navigator.of(dialogContext);
              await Clipboard.setData(ClipboardData(text: password));
              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Password copiada.')),
              );
            },
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Já entreguei'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.key_outlined, size: 20),
        title: const Text('Repor a password'),
        subtitle: const Text(
          'Gera uma temporária para entregares em mão. A app obriga a '
          'trocá-la no primeiro login.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        onTap: _busy ? null : _reset,
      ),
    );
  }
}

/// Promover/despromover staff. Os papéis eram decididos na criação e
/// nunca mais mudavam — um instrutor que passasse a sócio-gerente
/// obrigava a mexer nas custom claims à mão.
class StaffRolesCard extends ConsumerStatefulWidget {
  const StaffRolesCard({
    super.key,
    required this.staffId,
    required this.currentRoles,
    required this.isSelf,
  });

  final String staffId;
  final Set<Role> currentRoles;

  /// O Gestor a olhar para a sua própria ficha. Não pode retirar-se o
  /// papel de Gestor — ficaria sem forma de o recuperar dentro da app.
  /// A Cloud Function recusa na mesma; isto é só para não oferecer um
  /// botão que vai falhar.
  final bool isSelf;

  @override
  ConsumerState<StaffRolesCard> createState() => _StaffRolesCardState();
}

class _StaffRolesCardState extends ConsumerState<StaffRolesCard> {
  bool _busy = false;

  Future<void> _setRoles(Set<Role> roles) async {
    setState(() => _busy = true);
    try {
      await ref.read(userProvisioningRepositoryProvider).updateStaffRoles(
            staffId: widget.staffId,
            roles: roles,
          );
      ref.invalidate(staffProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Papéis atualizados. A pessoa vê a mudança no próximo login.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível mudar os papéis: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(Role role, bool enabled) {
    final roles = {...widget.currentRoles};
    if (enabled) {
      roles.add(role);
    } else {
      roles.remove(role);
    }
    if (roles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Um membro do staff tem de ter pelo menos um papel. Para lhe '
            'tirar o acesso, desliga "Staff ativo".',
          ),
        ),
      );
      return;
    }
    _setRoles(roles);
  }

  @override
  Widget build(BuildContext context) {
    final isManager = widget.currentRoles.contains(Role.manager);
    final isInstructor = widget.currentRoles.contains(Role.instructor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Papéis'),
        const SizedBox(height: 2),
        const Text(
          'O Instrutor dá aulas, marca presenças e faz planos de treino. '
          'O Gestor faz tudo isso e ainda gere utilizadores, planos, '
          'horários e mensalidades.',
          style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 8),
        PanelCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isInstructor,
                onChanged: _busy ? null : (v) => _toggle(Role.instructor, v),
                title: const Text('Instrutor'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isManager,
                // Tirar o próprio papel de Gestor tranca-o fora.
                onChanged: _busy || (widget.isSelf && isManager)
                    ? null
                    : (v) => _toggle(Role.manager, v),
                title: const Text('Gestor'),
                subtitle: widget.isSelf && isManager
                    ? const Text(
                        'Não podes retirar o teu próprio papel de Gestor.',
                        style: TextStyle(fontSize: 11),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
