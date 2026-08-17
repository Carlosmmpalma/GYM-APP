import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _birthDateFormat = DateFormat('d MMM yyyy', 'pt_PT');

/// Pedido pelo Carlo depois de testar "Criar utilizador": telefone,
/// data de nascimento, morada, NIF e contacto de emergência aparecem
/// em três sítios (criar Aluno/Staff, editar Aluno, editar Staff) sem
/// nenhuma lógica a variar entre eles — só o `TextEditingController`
/// muda. Nome/email ficam FORA deste widget de propósito: têm
/// semântica diferente em cada ecrã (obrigatório vs opcional, contacto
/// vs login), não vale a pena forçá-los aqui dentro.
class PersonalDataFields extends StatelessWidget {
  const PersonalDataFields({
    super.key,
    required this.phoneController,
    required this.addressController,
    required this.nifController,
    required this.emergencyContactController,
    required this.birthDate,
    required this.onBirthDateChanged,
  });

  final TextEditingController phoneController;
  final TextEditingController addressController;
  final TextEditingController nifController;
  final TextEditingController emergencyContactController;
  final DateTime? birthDate;
  final ValueChanged<DateTime?> onBirthDateChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: phoneController,
          decoration: const InputDecoration(labelText: 'Telefone'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: const Text('Data de nascimento'),
            subtitle: Text(
              birthDate == null
                  ? 'Não definida'
                  : _birthDateFormat.format(birthDate!),
            ),
            trailing: const Icon(Icons.calendar_today_outlined, size: 18),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: birthDate ?? DateTime(2000),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (picked != null) onBirthDateChanged(picked);
            },
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: addressController,
          decoration: const InputDecoration(labelText: 'Morada'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: nifController,
          decoration: const InputDecoration(labelText: 'NIF'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: emergencyContactController,
          decoration: const InputDecoration(
            labelText: 'Contacto de emergência',
            hintText: 'Ex.: Mãe — 912345678',
          ),
        ),
      ],
    );
  }
}
