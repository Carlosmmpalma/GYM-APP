import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../domain/entities/assessment.dart';
import '../../domain/entities/member_summary.dart';

const _forcaOptions = ['Fraca', 'Média', 'Boa', 'Muito boa'];

/// Fase 8 (UC04/UC14) — "os 17 campos definidos no documento, sem
/// exceção" (mockup). [assessment] `null` → criar (`AssessmentFormScreen`
/// usada tanto para "Nova avaliação" como para "Editar avaliação",
/// UC04/UC14 fechado: "o Instrutor pode corrigir uma já registada" —
/// mesmo formulário, só muda o repository method chamado no fim).
/// IMC nunca é um campo — é sempre calculado, mostrado só como
/// pré-visualização de leitura.
class AssessmentFormScreen extends ConsumerStatefulWidget {
  const AssessmentFormScreen(
      {super.key, required this.member, this.assessment});

  final MemberSummary member;
  final Assessment? assessment;

  @override
  ConsumerState<AssessmentFormScreen> createState() =>
      _AssessmentFormScreenState();
}

class _AssessmentFormScreenState extends ConsumerState<AssessmentFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _idadeController =
      TextEditingController(text: widget.assessment?.idade.toString() ?? '');
  late final _pesoController =
      TextEditingController(text: widget.assessment?.peso.toString() ?? '');
  late final _alturaController =
      TextEditingController(text: widget.assessment?.altura.toString() ?? '');
  late final _percentMassaGordaController = TextEditingController(
      text: widget.assessment?.percentMassaGorda.toString() ?? '');
  late final _massaMuscularController = TextEditingController(
      text: widget.assessment?.massaMuscular.toString() ?? '');
  late final _gorduraVisceralController = TextEditingController(
      text: widget.assessment?.gorduraVisceral.toString() ?? '');
  late final _metabolismoBasalController = TextEditingController(
      text: widget.assessment?.metabolismoBasal.toString() ?? '');
  late final _percentAguaController = TextEditingController(
      text: widget.assessment?.percentAgua.toString() ?? '');
  late final _idadeMetabolicaController = TextEditingController(
      text: widget.assessment?.idadeMetabolica.toString() ?? '');
  late final _pressaoArterialController =
      TextEditingController(text: widget.assessment?.pressaoArterial ?? '');
  late final _perimetroCinturaController = TextEditingController(
      text: widget.assessment?.perimetroCintura.toString() ?? '');
  late final _perimetroAbdominalController = TextEditingController(
      text: widget.assessment?.perimetroAbdominal.toString() ?? '');

  late String _forcaMS = widget.assessment?.forcaMS ?? _forcaOptions.first;
  late String _forcaMI = widget.assessment?.forcaMI ?? _forcaOptions.first;
  late String _forcaCore = widget.assessment?.forcaCore ?? _forcaOptions.first;
  late String _flexibilidade =
      widget.assessment?.flexibilidade ?? _forcaOptions.first;
  late String _resistencia =
      widget.assessment?.resistencia ?? _forcaOptions.first;

  bool _saving = false;

  bool get _isEditing => widget.assessment != null;

  double get _previewImc {
    final peso =
        double.tryParse(_pesoController.text.replaceAll(',', '.')) ?? 0;
    final altura =
        double.tryParse(_alturaController.text.replaceAll(',', '.')) ?? 0;
    return altura > 0 ? peso / (altura * altura) : 0;
  }

  @override
  void dispose() {
    for (final controller in [
      _idadeController,
      _pesoController,
      _alturaController,
      _percentMassaGordaController,
      _massaMuscularController,
      _gorduraVisceralController,
      _metabolismoBasalController,
      _percentAguaController,
      _idadeMetabolicaController,
      _pressaoArterialController,
      _perimetroCinturaController,
      _perimetroAbdominalController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));
  int _int(TextEditingController c) => int.parse(c.text.trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final staffUid = ref.read(currentAppUserProvider).valueOrNull?.uid ?? '';
    try {
      if (_isEditing) {
        await ref.read(assessmentRepositoryProvider).updateAssessment(
              memberId: widget.member.uid,
              assessmentId: widget.assessment!.id,
              updatedBy: staffUid,
              idade: _int(_idadeController),
              peso: _num(_pesoController),
              altura: _num(_alturaController),
              percentMassaGorda: _num(_percentMassaGordaController),
              massaMuscular: _num(_massaMuscularController),
              gorduraVisceral: _num(_gorduraVisceralController),
              metabolismoBasal: _num(_metabolismoBasalController),
              percentAgua: _num(_percentAguaController),
              idadeMetabolica: _int(_idadeMetabolicaController),
              pressaoArterial: _pressaoArterialController.text.trim(),
              perimetroCintura: _num(_perimetroCinturaController),
              perimetroAbdominal: _num(_perimetroAbdominalController),
              forcaMS: _forcaMS,
              forcaMI: _forcaMI,
              forcaCore: _forcaCore,
              flexibilidade: _flexibilidade,
              resistencia: _resistencia,
            );
      } else {
        await ref.read(assessmentRepositoryProvider).createAssessment(
              memberId: widget.member.uid,
              instructorId: staffUid,
              idade: _int(_idadeController),
              peso: _num(_pesoController),
              altura: _num(_alturaController),
              percentMassaGorda: _num(_percentMassaGordaController),
              massaMuscular: _num(_massaMuscularController),
              gorduraVisceral: _num(_gorduraVisceralController),
              metabolismoBasal: _num(_metabolismoBasalController),
              percentAgua: _num(_percentAguaController),
              idadeMetabolica: _int(_idadeMetabolicaController),
              pressaoArterial: _pressaoArterialController.text.trim(),
              perimetroCintura: _num(_perimetroCinturaController),
              perimetroAbdominal: _num(_perimetroAbdominalController),
              forcaMS: _forcaMS,
              forcaMI: _forcaMI,
              forcaCore: _forcaCore,
              flexibilidade: _flexibilidade,
              resistencia: _resistencia,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numberField(TextEditingController controller, String label,
      {bool isInt = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
        onChanged: (_) => setState(() {}),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Obrigatório';
          final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
          return parsed == null ? 'Número inválido' : null;
        },
      ),
    );
  }

  Widget _dropdownField(
      String label, String value, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: _forcaOptions
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar avaliação' : 'Nova avaliação'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(widget.member.name,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              _numberField(_idadeController, 'Idade', isInt: true),
              Text('Composição corporal',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _numberField(_pesoController, 'Peso (kg)'),
              _numberField(_alturaController, 'Altura (m)'),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'IMC (Auto)'),
                  child: Text(_previewImc.toStringAsFixed(1)),
                ),
              ),
              _numberField(_percentMassaGordaController, '% Massa Gorda'),
              _numberField(_massaMuscularController, 'Massa Muscular (kg)'),
              _numberField(_gorduraVisceralController, 'Gordura Visceral'),
              _numberField(
                  _metabolismoBasalController, 'Metabolismo Basal (kcal)'),
              _numberField(_percentAguaController, '% Água'),
              _numberField(_idadeMetabolicaController, 'Idade Metabólica',
                  isInt: true),
              const SizedBox(height: 8),
              Text('Saúde', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _pressaoArterialController,
                  decoration: const InputDecoration(
                    labelText: 'Pressão Arterial',
                    hintText: 'ex.: 112/72',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
              ),
              _numberField(
                  _perimetroCinturaController, 'Perímetro Cintura (cm)'),
              _numberField(
                  _perimetroAbdominalController, 'Perímetro Abdominal (cm)'),
              const SizedBox(height: 8),
              Text('Físicos', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _dropdownField(
                  'Força MS', _forcaMS, (v) => setState(() => _forcaMS = v!)),
              _dropdownField(
                  'Força MI', _forcaMI, (v) => setState(() => _forcaMI = v!)),
              _dropdownField('Força Core', _forcaCore,
                  (v) => setState(() => _forcaCore = v!)),
              _dropdownField('Flexibilidade', _flexibilidade,
                  (v) => setState(() => _flexibilidade = v!)),
              _dropdownField('Resistência', _resistencia,
                  (v) => setState(() => _resistencia = v!)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar avaliação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
