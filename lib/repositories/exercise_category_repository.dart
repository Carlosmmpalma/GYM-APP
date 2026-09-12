import '../domain/entities/exercise_category.dart';

/// Mesmo padrão de `ServiceRepository`/`ModalityRepository`: CRUD
/// simples, escrita direta do cliente.
///
/// Escrita permitida a Gestor **e Instrutor**, como a própria biblioteca
/// de exercícios (`firestore.rules`): quem cria exercícios é quem
/// precisa de os arrumar, e obrigar a pedir ao Gestor para criar uma
/// categoria seria recriar o mesmo bloqueio que isto veio resolver.
abstract class ExerciseCategoryRepository {
  Stream<List<ExerciseCategory>> watchCategories();

  /// Devolve o id do documento criado.
  Future<String> createCategory({required String name});

  Future<void> setCategoryActive({
    required String categoryId,
    required bool active,
  });

  /// Muda o nome, e **arrasta os exercícios com ele**.
  ///
  /// Não é um `update` genérico de propósito: `Exercise.category` guarda
  /// o texto, não uma referência (ver a nota em `exercise_category.dart`
  /// sobre porquê). Sem esta propagação, mudar "Braços" para "Bíceps e
  /// tríceps" deixava os exercícios existentes numa categoria fantasma
  /// que já não aparece em lado nenhum para escolher — visível na
  /// biblioteca, impossível de voltar a atribuir.
  ///
  /// Devolve quantos exercícios foram atualizados.
  Future<int> rename({required String categoryId, required String newName});

  /// As categorias distintas que os exercícios já usam.
  ///
  /// Serve o arranque: um estúdio que já tem a biblioteca montada tem
  /// categorias em uso sem nenhum documento a defini-las. Em vez de as
  /// perder, o ecrã de gestão oferece importá-las.
  Future<Set<String>> namesInUse();
}
