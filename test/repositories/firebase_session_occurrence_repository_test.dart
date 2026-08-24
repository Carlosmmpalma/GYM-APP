import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_session_occurrence_repository.dart';
import 'package:mocktail/mocktail.dart';

const _tenantId = 'tenant_test';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Otimização de custo (Fase 11) — o ecrã de marcar treino lia o
/// horário INTEIRO do ginásio e filtrava em memória pelos serviços do
/// plano do aluno. Num estúdio com quatro serviços, um aluno que só
/// tem aulas de grupo descarregava três quartos de sessões para as
/// deitar fora; um aluno sem plano nenhum descarregava tudo para lhe
/// dizerem que não tinha acesso a nada.
///
/// Firestore cobra por documento LIDO, não por documento mostrado — é
/// por isso que isto é um teste e não um detalhe de implementação.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirebaseSessionOccurrenceRepository repository;

  Future<void> addOccurrence(String id, String serviceId, int daysAhead) async {
    final start = DateTime.now().add(Duration(days: daysAhead));
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('sessionOccurrences')
        .doc(id)
        .set({
      'serviceId': serviceId,
      'startAt': Timestamp.fromDate(start),
      'endAt': Timestamp.fromDate(start.add(const Duration(hours: 1))),
      'capacity': 10,
      'status': 'scheduled',
      'activeBookingCount': 0,
    });
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = FirebaseSessionOccurrenceRepository(
      firestore,
      _MockFirebaseFunctions(),
      _tenantId,
    );
    await addOccurrence('occ_aulas', 'service_aulas', 1);
    await addOccurrence('occ_pilates', 'service_pilates', 2);
    await addOccurrence('occ_pt', 'service_pt', 3);
  });

  test('sem serviços, devolve vazio sem ir ao servidor', () async {
    // O ginásio TEM horário — o que se prova aqui é que ele não é
    // lido. Se houvesse query, viriam as três sessões.
    final result =
        await repository.watchUpcomingOccurrencesForServices({}).first;
    expect(result, isEmpty);
  });

  test('devolve só as sessões dos serviços pedidos', () async {
    final result = await repository
        .watchUpcomingOccurrencesForServices({'service_aulas'}).first;

    expect(result.map((o) => o.id), ['occ_aulas']);
  });

  test('vários serviços vêm ordenados por data', () async {
    final result = await repository.watchUpcomingOccurrencesForServices(
      {'service_pt', 'service_aulas'},
    ).first;

    expect(result.map((o) => o.id), ['occ_aulas', 'occ_pt']);
  });

  test('sessões já passadas não entram', () async {
    await addOccurrence('occ_ontem', 'service_aulas', -1);

    final result = await repository
        .watchUpcomingOccurrencesForServices({'service_aulas'}).first;

    expect(result.map((o) => o.id), ['occ_aulas']);
  });
}
