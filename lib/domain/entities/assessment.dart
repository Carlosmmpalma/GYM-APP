import 'package:equatable/equatable.dart';

/// Fase 8 (UC04/UC14, Firestore Data Model v1 §43) — avaliação física
/// de um membro. Histórica: uma avaliação nova NUNCA substitui a
/// anterior (Domain Model v1 §33 — "Member ├── Assessment — Janeiro
/// ├── Assessment — Abril └── Assessment — Agosto"), mas UC04/UC14
/// (fechado) confirma que o Instrutor pode EDITAR uma já criada —
/// `updatedBy`/`updatedAt` existem por isso (auditoria de quem
/// corrigiu o quê, sugestão aceite do próprio use case fechado).
///
/// Os 17 campos vêm do mockup ("Nova avaliação"/"Detalhe da
/// avaliação", `Functional/nxt-studio-screens.html`) — nenhum dos
/// documentos técnicos os enumera, só o path da coleção
/// (`Firestore Data Model v1` §43 usa `"data": {...}` como placeholder
/// genérico). [imc] não é um dos 17 — é `Auto` no mockup, sempre
/// calculado a partir de [peso]/[altura], nunca guardado como input.
class Assessment extends Equatable {
  const Assessment({
    required this.id,
    required this.memberId,
    required this.instructorId,
    required this.createdAt,
    this.updatedAt,
    this.updatedBy,
    required this.idade,
    required this.peso,
    required this.altura,
    required this.percentMassaGorda,
    required this.massaMuscular,
    required this.gorduraVisceral,
    required this.metabolismoBasal,
    required this.percentAgua,
    required this.idadeMetabolica,
    required this.pressaoArterial,
    required this.perimetroCintura,
    required this.perimetroAbdominal,
    required this.forcaMS,
    required this.forcaMI,
    required this.forcaCore,
    required this.flexibilidade,
    required this.resistencia,
  });

  final String id;
  final String memberId;

  /// Quem criou (staff.uid) — UC14 continua a exigir um Instrutor por
  /// trás de cada avaliação, mesmo que um Gestor também possa criar.
  final String instructorId;
  final DateTime createdAt;

  /// `null` numa avaliação nunca editada — UC04/UC14 (fechado): "fica
  /// em aberto (não bloqueante) se deve ficar registo de quem editou —
  /// sugestão: sim, por auditoria". Aceite, não opcional na prática:
  /// preenchido em toda edição, nunca na criação.
  final DateTime? updatedAt;
  final String? updatedBy;

  // --- Composição corporal ---
  final int idade;
  final double peso;
  final double altura;
  final double percentMassaGorda;
  final double massaMuscular;
  final double gorduraVisceral;
  final double metabolismoBasal;
  final double percentAgua;
  final int idadeMetabolica;

  // --- Saúde ---
  /// Texto livre (ex.: "112/72") — mesmo formato do mockup, não vale a
  /// pena modelar sistólica/diastólica como campos separados para uma
  /// avaliação manual.
  final String pressaoArterial;
  final double perimetroCintura;
  final double perimetroAbdominal;

  // --- Físicos --- (valores de um dropdown fechado, ex.: "Fraca" /
  // "Média" / "Boa" / "Muito boa" — texto livre aqui, a UI é que
  // restringe às opções do mockup)
  final String forcaMS;
  final String forcaMI;
  final String forcaCore;
  final String flexibilidade;
  final String resistencia;

  /// `Auto` no mockup — nunca um input, sempre calculado. `altura` em
  /// metros (mesmo formato do mockup, "1.75"), por isso sem *100.
  double get imc => altura > 0 ? peso / (altura * altura) : 0;

  bool get wasEdited => updatedAt != null;

  @override
  List<Object?> get props => [
        id,
        memberId,
        instructorId,
        createdAt,
        updatedAt,
        updatedBy,
        idade,
        peso,
        altura,
        percentMassaGorda,
        massaMuscular,
        gorduraVisceral,
        metabolismoBasal,
        percentAgua,
        idadeMetabolica,
        pressaoArterial,
        perimetroCintura,
        perimetroAbdominal,
        forcaMS,
        forcaMI,
        forcaCore,
        flexibilidade,
        resistencia,
      ];
}
