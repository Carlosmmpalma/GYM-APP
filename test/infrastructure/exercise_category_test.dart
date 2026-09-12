import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_exercise_category_repository.dart';

/// As categorias da biblioteca deixaram de ser uma lista fixa no
/// código. A parte frágil não é criá-las — é o que acontece ao mudar o
/// nome de uma que já está em uso.
const _tenantId = 'tenant_test';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirebaseExerciseCategoryRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirebaseExerciseCategoryRepository(firestore, _tenantId);
  });

  Future<void> seedExercise(String id, String category) {
    return firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('exercises')
        .doc(id)
        .set({'name': id, 'description': '', 'category': category});
  }

  Future<String?> categoryOf(String id) async {
    final doc = await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('exercises')
        .doc(id)
        .get();
    return doc.data()?['category'] as String?;
  }

  test('criar devolve uma categoria ativa', () async {
    final id = await repository.createCategory(name: '  Mobilidade  ');

    final categories = await repository.watchCategories().first;
    expect(categories.single.id, id);
    // Espaços à volta viriam parar aos exercícios e criavam uma
    // categoria "Mobilidade " distinta de "Mobilidade".
    expect(categories.single.name, 'Mobilidade');
    expect(categories.single.active, isTrue);
  });

  test('renomear arrasta os exercícios que a usam', () async {
    // Este é o teste que justifica o método existir. Os exercícios
    // guardam o TEXTO da categoria, não uma referência (para não
    // custarem uma leitura extra nos ecrãs do aluno). Sem a
    // propagação, mudar o nome deixava-os numa categoria fantasma:
    // visível na biblioteca, impossível de voltar a escolher.
    final id = await repository.createCategory(name: 'Braços');
    await seedExercise('ex_curl', 'Braços');
    await seedExercise('ex_triceps', 'Braços');
    await seedExercise('ex_agachamento', 'Pernas');

    final updated =
        await repository.rename(categoryId: id, newName: 'Bíceps e tríceps');

    expect(updated, 2);
    expect(await categoryOf('ex_curl'), 'Bíceps e tríceps');
    expect(await categoryOf('ex_triceps'), 'Bíceps e tríceps');
    // E não toca em quem não era dela.
    expect(await categoryOf('ex_agachamento'), 'Pernas');

    final categories = await repository.watchCategories().first;
    expect(categories.single.name, 'Bíceps e tríceps');
  });

  test('renomear para o mesmo nome não escreve nada', () async {
    final id = await repository.createCategory(name: 'Core');
    await seedExercise('ex_prancha', 'Core');

    expect(await repository.rename(categoryId: id, newName: 'Core'), 0);
    expect(await repository.rename(categoryId: id, newName: '  Core  '), 0);
  });

  test('desativar não mexe nos exercícios', () async {
    // Desativar é para deixar de OFERECER a categoria, não para a tirar
    // de quem já a tem.
    final id = await repository.createCategory(name: 'Hyrox');
    await seedExercise('ex_ski', 'Hyrox');

    await repository.setCategoryActive(categoryId: id, active: false);

    expect(await categoryOf('ex_ski'), 'Hyrox');
    expect((await repository.watchCategories().first).single.active, isFalse);
  });

  group('namesInUse', () {
    test('devolve as categorias que os exercícios já usam', () async {
      // O arranque de um estúdio que já tinha a biblioteca montada
      // quando a lista ainda vivia no código: há categorias em uso sem
      // nenhum documento a defini-las.
      await seedExercise('ex_a', 'Pernas');
      await seedExercise('ex_b', 'Pernas');
      await seedExercise('ex_c', 'Costas');

      expect(await repository.namesInUse(), {'Pernas', 'Costas'});
    });

    test('ignora exercícios sem categoria', () async {
      await seedExercise('ex_a', 'Pernas');
      await seedExercise('ex_sem', '');
      await seedExercise('ex_espacos', '   ');

      expect(await repository.namesInUse(), {'Pernas'});
    });
  });
}
