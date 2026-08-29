import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_exercise_repository.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_session_occurrence_repository.dart';
import 'package:mocktail/mocktail.dart';

/// As duas queries que existem para LER MENOS.
///
/// Os ecrãs do aluno carregavam a biblioteca de exercícios inteira para
/// resolver meia dúzia de nomes, e o ecrã "Marcar" trazia até 200
/// ocorrências — as 8 semanas todas — para mostrar as poucas que alguém
/// vai marcar. Nenhuma das duas correções é visível na interface, por
/// isso é aqui que ficam presas.
const _tenantId = 'tenant_test';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

void main() {
  group('getExercisesByIds', () {
    late FakeFirebaseFirestore firestore;
    late FirebaseExerciseRepository repository;

    Future<void> seed(int count) async {
      for (var i = 0; i < count; i++) {
        await firestore
            .collection('tenants')
            .doc(_tenantId)
            .collection('exercises')
            .doc('ex_$i')
            .set({
          'name': 'Exercício $i',
          'description': '',
          'muscleGroup': 'Core',
        });
      }
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirebaseExerciseRepository(firestore, _tenantId);
    });

    test('devolve só os pedidos, não a biblioteca', () async {
      await seed(20);

      final result = await repository.getExercisesByIds({'ex_3', 'ex_7'});

      expect(result.map((e) => e.id).toSet(), {'ex_3', 'ex_7'});
    });

    test('sem ids, não pergunta nada ao servidor', () async {
      await seed(5);

      // O caso real: o ecrã desenha-se antes de o plano chegar. Sem
      // esta guarda, cada abertura fazia uma query a pedir nada.
      expect(await repository.getExercisesByIds({}), isEmpty);
    });

    test('mais de 30 ids são partidos em blocos', () async {
      // O `whereIn` do Firestore aceita 30 valores. Sem a partição, um
      // plano grande rebentava com um erro do servidor em vez de
      // carregar.
      await seed(75);
      final ids = {for (var i = 0; i < 75; i++) 'ex_$i'};

      final result = await repository.getExercisesByIds(ids);

      expect(result.length, 75);
      expect(result.map((e) => e.id).toSet(), ids);
    });

    test('ids que já não existem não fazem rebentar nada', () async {
      // Um exercício eliminado da biblioteca continua referenciado por
      // prescrições antigas — a query devolve o que existe e cala-se
      // sobre o resto.
      await seed(3);

      final result =
          await repository.getExercisesByIds({'ex_1', 'ex_inexistente'});

      expect(result.map((e) => e.id).toSet(), {'ex_1'});
    });
  });

  group('watchUpcomingOccurrencesForServices', () {
    late FakeFirebaseFirestore firestore;
    late FirebaseSessionOccurrenceRepository repository;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      // Nenhum caminho aqui chama uma Cloud Function — estas queries
      // são Firestore puro.
      repository = FirebaseSessionOccurrenceRepository(
          firestore, _MockFirebaseFunctions(), _tenantId);

      final now = DateTime.now();
      // Uma aula por semana, durante 8 semanas — o horizonte que as
      // séries geram.
      for (var week = 0; week < 8; week++) {
        final startAt = now.add(Duration(days: week * 7 + 1));
        await firestore
            .collection('tenants')
            .doc(_tenantId)
            .collection('sessionOccurrences')
            .doc('occ_semana_$week')
            .set({
          'serviceId': 'svc_1',
          'startAt': Timestamp.fromDate(startAt),
          'endAt': Timestamp.fromDate(startAt.add(const Duration(hours: 1))),
          'capacity': 6,
          'status': 'scheduled',
          'activeBookingCount': 0,
        });
      }
    });

    test('sem horizonte, traz o calendário todo', () async {
      final result =
          await repository.watchUpcomingOccurrencesForServices({'svc_1'}).first;

      expect(result.length, 8);
    });

    test('com horizonte de 2 semanas, traz só o que cabe nele', () async {
      // É esta a diferença que o ecrã "Marcar" passou a fazer: ler as
      // duas semanas que o aluno vai mesmo usar, e não as oito.
      final result = await repository
          .watchUpcomingOccurrencesForServices({'svc_1'}, weeksAhead: 2).first;

      expect(result.length, 2);
      expect(
        result.map((o) => o.id).toSet(),
        {'occ_semana_0', 'occ_semana_1'},
      );
    });

    test('sem serviços elegíveis, não pergunta nada ao servidor', () async {
      final result =
          await repository.watchUpcomingOccurrencesForServices({}).first;

      expect(result, isEmpty);
    });
  });
}
