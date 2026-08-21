import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/staff_summary.dart';
import '../widgets/design_system.dart';
import 'create_user_screen.dart';
import 'member_detail_screen.dart';
import 'staff_detail_screen.dart';

/// Fase 10 (UC22/UC23/UC24) — "Utilizadores": uma lista só, como no
/// mockup `Functional/nxt-studio-screens.html`.
///
/// A app tinha isto partido em dois ecrãs (`ManageMembersScreen` e
/// `ManageStaffScreen`) por uma razão de implementação e não de
/// utilização: eram dois streams (`membersProvider`/`staffProvider`) e
/// era mais simples ter um ecrã por stream. O resultado foi que "criar
/// um utilizador" ficou escondido atrás de dois FABs em sítios
/// diferentes e não se percebia onde se criava uma conta — foi o
/// primeiro problema apontado ao testar a app a sério.
///
/// Os dois ecrãs antigos continuam a existir e navegáveis, mas a Gestão
/// passa por aqui: os separadores fazem o mesmo trabalho que a
/// separação em dois ecrãs fazia, sem obrigar a saber de antemão em qual
/// dos dois está a pessoa que se procura.
class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

enum _UsersFilter { todos, alunos, staff }

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  _UsersFilter _filter = _UsersFilter.todos;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final staffAsync = ref.watch(staffProvider);
    final modalityNames = <String, String>{
      for (final m
          in ref.watch(modalitiesProvider).valueOrNull ?? const <Modality>[])
        m.id: m.name,
    };

    // Um erro em qualquer um dos dois streams é um erro do ecrã — mostrar
    // meia lista sem dizer que a outra metade falhou seria pior do que
    // não mostrar nada.
    final error = membersAsync.error ?? staffAsync.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Utilizadores')),
        body: ErrorState(error: error),
      );
    }
    final members = membersAsync.valueOrNull;
    final staff = staffAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Utilizadores')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateUserScreen()),
        ),
        tooltip: 'Criar utilizador',
        child: const Icon(Icons.add),
      ),
      body: members == null || staff == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(members, staff, modalityNames),
    );
  }

  Widget _buildBody(
    List<MemberSummary> members,
    List<StaffSummary> staff,
    Map<String, String> modalityNames,
  ) {
    final now = DateTime.now();
    final query = _query.trim().toLowerCase();

    final rows = <_UserRow>[
      if (_filter != _UsersFilter.staff)
        for (final m in members)
          _UserRow(
            name: m.name,
            subtitle: 'Aluno · Nº ${m.memberNumber}',
            tone: _memberTone(m, now),
            status: _memberStatus(m, now),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MemberDetailScreen(member: m)),
            ),
          ),
      if (_filter != _UsersFilter.alunos)
        for (final s in staff)
          _UserRow(
            name: s.name,
            subtitle: _staffSubtitle(s, modalityNames),
            tone: s.active ? PillTone.ok : PillTone.neutral,
            status: s.active ? 'Ativo' : 'Inativo',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StaffDetailScreen(staff: s)),
            ),
          ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final visible =
        query.isEmpty ? rows : rows.where((r) => r.matches(query)).toList();

    return Column(
      children: [
        const SizedBox(height: 12),
        PillTabs(
          labels: const ['Todos', 'Alunos', 'Staff'],
          selectedIndex: _UsersFilter.values.indexOf(_filter),
          onSelected: (i) => setState(() => _filter = _UsersFilter.values[i]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Procurar por nome ou nº de sócio',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _emptyState(nothingAtAll: rows.isEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => visible[index].build(),
                ),
        ),
      ],
    );
  }

  Widget _emptyState({required bool nothingAtAll}) {
    if (!nothingAtAll) {
      return const EmptyState(
        icon: Icons.search_off_outlined,
        title: 'Ninguém encontrado',
        message: 'Nenhum utilizador corresponde à procura. Experimenta '
            'outro nome, ou o nº de sócio.',
      );
    }
    return EmptyState(
      icon: Icons.people_outline,
      title: 'Ainda não há utilizadores',
      message: 'Aqui ficam todas as contas do ginásio: alunos, instrutores '
          'e gestores. Criar uma conta dá acesso à app com uma password '
          'temporária que a pessoa troca no primeiro login.',
      actionLabel: 'Criar o primeiro utilizador',
      onAction: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CreateUserScreen()),
      ),
    );
  }

  /// O mockup mostra "Instrutor · modalidade: Hyrox, PT" — os nomes, não
  /// os ids. Enquanto as modalidades não estiverem carregadas, mostra só
  /// o papel em vez de ids crus.
  String _staffSubtitle(StaffSummary s, Map<String, String> modalityNames) {
    final roles = s.roles.map(_roleLabel).join(' · ');
    final names = s.modalityIds
        .map((id) => modalityNames[id])
        .whereType<String>()
        .toList()
      ..sort();
    if (names.isEmpty) return roles;
    return '$roles · modalidade: ${names.join(', ')}';
  }

  String _roleLabel(Role role) => switch (role) {
        Role.manager => 'Gestor',
        Role.instructor => 'Instrutor',
        Role.member => 'Aluno',
      };

  /// Mensalidade em atraso ganha ao "Ativo" (é o que o Gestor precisa de
  /// ver primeiro) e "Inativo" ganha às duas — uma conta desligada não
  /// deve mensalidades.
  String _memberStatus(MemberSummary m, DateTime now) {
    if (!m.active) return 'Inativo';
    return m.isOverdueFor(now) ? 'Em atraso' : 'Ativo';
  }

  PillTone _memberTone(MemberSummary m, DateTime now) {
    if (!m.active) return PillTone.neutral;
    return m.isOverdueFor(now) ? PillTone.warn : PillTone.ok;
  }
}

/// Uma linha da lista, já resolvida (nome/legenda/estado/destino) para
/// que alunos e staff possam ser ordenados numa lista só — é isso que
/// distingue este ecrã dos dois que substitui na Gestão.
class _UserRow {
  const _UserRow({
    required this.name,
    required this.subtitle,
    required this.tone,
    required this.status,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final PillTone tone;
  final String status;
  final VoidCallback onTap;

  bool matches(String query) =>
      name.toLowerCase().contains(query) ||
      subtitle.toLowerCase().contains(query);

  Widget build() => Card(
        child: ListTile(
          leading: Avatar(name),
          title: Text(name),
          subtitle: Text(subtitle),
          trailing: Pill(status, tone: tone),
          onTap: onTap,
        ),
      );
}
