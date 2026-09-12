import 'package:equatable/equatable.dart';

/// Como o estúdio arruma a sua biblioteca de exercícios.
///
/// Estava uma lista fixa no código — `Pernas`, `Costas`, `Peito`,
/// `Ombros`, `Braços`, `Core`, `Full body`, `Hyrox` — e um estúdio que
/// quisesse "Mobilidade" ou "Aquecimento" tinha de pedir a um
/// programador. É o mesmo erro que [Service], [Plan] e [Modality] já
/// evitavam desde o início: **nunca um enum fixo na app**, porque o
/// vocabulário é do estúdio, não do produto.
///
/// Chama-se categoria e não grupo muscular por causa do que já
/// acontecia na prática: "Hyrox" nunca foi um músculo. A palavra tinha
/// ficado pequena antes de alguém dar por isso.
///
/// ## Porque é que o exercício guarda o NOME e não o id
///
/// [Exercise.category] é o texto, não uma referência. Duas razões:
///
///  1. Os ecrãs do aluno mostram a categoria ao lado do exercício. Com
///     um id, cada um deles teria de ir buscar o documento da categoria
///     — leituras a mais num caminho que acabámos de otimizar
///     precisamente para as evitar.
///  2. Os exercícios que já existem guardam texto. Guardar o nome
///     significa que nada precisa de migração.
///
/// O preço é que **mudar o nome de uma categoria tem de propagar** aos
/// exercícios que a usam. Isso está feito em
/// `ExerciseCategoryRepository.rename`, e é a razão de esse método
/// existir em vez de um `update` genérico.
class ExerciseCategory extends Equatable {
  const ExerciseCategory({
    required this.id,
    required this.name,
    required this.active,
  });

  final String id;
  final String name;

  /// Desativar em vez de eliminar, para o caso de o estúdio deixar de
  /// oferecer uma categoria sem querer mexer nos exercícios que já a
  /// têm: some das escolhas, fica no que já existe.
  final bool active;

  @override
  List<Object?> get props => [id, name, active];
}
