import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/search_text.dart';
import '../../domain/entities/member_summary.dart';
import 'design_system.dart';
import 'person_avatar.dart';

/// Fase 11 — escolher um membro numa lista pesquisável, em vez de um
/// `DropdownButtonFormField`.
///
/// Um dropdown funciona com dez nomes. Com trezentos — que é o tamanho
/// de um ginásio a sério — é uma lista infinita por onde se rola à
/// procura, sem forma de escrever o que se sabe. Aqui abre-se uma folha
/// com pesquisa por nome ou número, que é como o Gestor tem a
/// informação na cabeça ("a Rita" ou "a 142").
class MemberPickerField extends StatelessWidget {
  const MemberPickerField({
    super.key,
    required this.members,
    required this.selected,
    required this.onSelected,
    this.label = 'Membro',
  });

  final List<MemberSummary> members;
  final MemberSummary? selected;
  final ValueChanged<MemberSummary> onSelected;
  final String label;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<MemberSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _MemberPickerSheet(members: members),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        // Sem `isEmpty`, o label fica sobreposto ao texto quando ainda
        // não há ninguém escolhido.
        border: const OutlineInputBorder(),
      ),
      isEmpty: false,
      child: InkWell(
        onTap: () => _open(context),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected == null
                    ? 'Escolher membro'
                    : '${selected!.name} · Nº ${selected!.memberNumber}',
                style: TextStyle(
                  color: selected == null ? AppColors.mute : AppColors.bone,
                ),
              ),
            ),
            const Icon(Icons.search, size: 20, color: AppColors.mute),
          ],
        ),
      ),
    );
  }
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.members});

  final List<MemberSummary> members;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    // Inativos ficam de fora: atribuir um plano a quem saiu do ginásio é
    // quase sempre engano, e quem quiser mesmo fazê-lo reativa-o
    // primeiro na ficha dele.
    final visible = widget.members
        .where((m) => m.active)
        .where((m) => searchMatchesAny([m.name, m.memberNumber], _query))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      // Empurra a folha acima do teclado — sem isto a pesquisa fica
      // tapada assim que se começa a escrever.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const SectionLabel('Escolher membro'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchField(
                hintText: 'Procurar por nome ou nº de sócio',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (visible.isEmpty)
              Expanded(
                child: EmptyState(
                  icon: Icons.search_off,
                  title: 'Nada encontrado',
                  message: _query.isEmpty
                      ? 'Não há membros ativos.'
                      : 'Nenhum membro ativo corresponde a "$_query".',
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final member = visible[index];
                    return ListTile(
                      leading: PersonAvatar(
                        name: member.name,
                        photoUrl: member.photoUrl,
                      ),
                      title: Text(member.name),
                      subtitle: Text('Nº ${member.memberNumber}'),
                      onTap: () => Navigator.of(context).pop(member),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
