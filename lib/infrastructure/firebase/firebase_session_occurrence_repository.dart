import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/session_occurrence.dart';
import '../../repositories/session_occurrence_repository.dart';

SessionOccurrence _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return SessionOccurrence(
    id: doc.id,
    serviceId: data['serviceId'] as String,
    startAt: (data['startAt'] as Timestamp).toDate(),
    endAt: (data['endAt'] as Timestamp).toDate(),
    capacity: (data['capacity'] as num).toInt(),
    status: (data['status'] as String? ?? 'scheduled') == 'scheduled'
        ? SessionOccurrenceStatus.scheduled
        : SessionOccurrenceStatus.cancelled,
    activeBookingCount: (data['activeBookingCount'] as num? ?? 0).toInt(),
    seriesId: data['seriesId'] as String?,
    instructorId: data['instructorId'] as String?,
    modalityId: data['modalityId'] as String?,
  );
}

class FirebaseSessionOccurrenceRepository
    implements SessionOccurrenceRepository {
  FirebaseSessionOccurrenceRepository(
      this._firestore, this._functions, this._tenantId);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _occurrences => _firestore
      .collection('tenants')
      .doc(_tenantId)
      .collection('sessionOccurrences');

  /// Fase 8 (varredura de performance) — teto de segurança para as
  /// duas queries de "próximas ocorrências". Não tinham limite NENHUM:
  /// `startAt >= now` sem fronteira superior devolvia todas as
  /// ocorrências futuras que existissem, e o cron diário
  /// (`generateRecurringOccurrences.ts`) empurra o horizonte de 8
  /// semanas todos os dias — ou seja, o conjunto cresce com o número de
  /// séries do tenant e nunca encolhe. Pior: estas queries alimentam o
  /// ecrã principal do Aluno (`BookTrainingScreen`), por isso QUALQUER
  /// marcação feita por QUALQUER pessoa no tenant altera
  /// `activeBookingCount` e faz o snapshot inteiro voltar a chegar e a
  /// ser desserializado.
  ///
  /// Como o `orderBy('startAt')` é ascendente, o limite corta pelas
  /// ocorrências MAIS DISTANTES — as próximas, que são as únicas que um
  /// aluno realmente vai marcar, ficam sempre lá. 200 é folgado para um
  /// estúdio real (8 semanas × ~20 sessões/semana ≈ 160).
  static const _upcomingLimit = 200;

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrences(String serviceId) {
    final now = Timestamp.now();
    return _occurrences
        .where('serviceId', isEqualTo: serviceId)
        .where('startAt', isGreaterThanOrEqualTo: now)
        .orderBy('startAt')
        .limit(_upcomingLimit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrencesAllServices() {
    final now = Timestamp.now();
    return _occurrences
        .where('startAt', isGreaterThanOrEqualTo: now)
        .orderBy('startAt')
        .limit(_upcomingLimit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  /// O `whereIn` do Firestore aceita no máximo 30 valores. Acima
  /// disso não há query possível e volta-se ao horário completo — um
  /// estúdio com mais de 30 serviços não existe, mas o código não pode
  /// partir se existir.
  static const _maxWhereInValues = 30;

  @override
  Stream<List<SessionOccurrence>> watchUpcomingOccurrencesForServices(
    Set<String> serviceIds,
  ) {
    // Sem direito a nada: nem vale a pena perguntar ao servidor.
    if (serviceIds.isEmpty) {
      return Stream.value(const <SessionOccurrence>[]);
    }
    if (serviceIds.length > _maxWhereInValues) {
      return watchUpcomingOccurrencesAllServices();
    }

    final now = Timestamp.now();
    return _occurrences
        .where('serviceId', whereIn: serviceIds.toList())
        .where('startAt', isGreaterThanOrEqualTo: now)
        .orderBy('startAt')
        .limit(_upcomingLimit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<SessionOccurrence?> getOccurrence(String occurrenceId) async {
    final snapshot = await _occurrences.doc(occurrenceId).get();
    if (!snapshot.exists) return null;
    return _fromDoc(snapshot);
  }

  @override
  Stream<SessionOccurrence?> watchOccurrence(String occurrenceId) {
    return _occurrences
        .doc(occurrenceId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? _fromDoc(snapshot) : null);
  }

  @override
  Future<String> createOccurrence({
    required String serviceId,
    String? instructorId,
    String? modalityId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) async {
    final ref = await _occurrences.add({
      'serviceId': serviceId,
      'instructorId': instructorId,
      'modalityId': modalityId,
      'seriesId': null,
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'capacity': capacity,
      'status': 'scheduled',
      'activeBookingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updateOccurrence({
    required String occurrenceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
    String? instructorId,
    String? modalityId,
  }) async {
    await _occurrences.doc(occurrenceId).update({
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'capacity': capacity,
      'instructorId': instructorId,
      'modalityId': modalityId,
    });
  }

  @override
  Future<void> cancelOccurrence(String occurrenceId) async {
    // Fase 6 — deixou de ser uma escrita direta (`update({'status':
    // 'cancelled'})`, Fase 5): cancelar tem de cascatar para os
    // bookings ativos (libertar vaga + devolver usage, UC18/UC10), o
    // que exige Admin SDK — mesmo motivo de createBooking/cancelBooking
    // desde a Fase 4. `firestore.rules` já bloqueia mudar `status` por
    // escrita direta do cliente, mesmo para Manager.
    await _functions.httpsCallable('cancelOccurrenceForStudio').call<void>({
      'occurrenceId': occurrenceId,
    });
  }

  @override
  Stream<List<SessionOccurrence>> watchOccurrencesForSeries(String seriesId) {
    // Fase 10 — só de hoje para a frente. Uma série semanal gera 52
    // ocorrências por ano e este ecrã lista-as por ordem crescente: ao
    // fim de um ano, o Gestor abria a ficha da série e via primeiro
    // dezenas de aulas passadas, sobre as quais não há nada a fazer,
    // com as próximas (as únicas acionáveis) no fundo da lista. O
    // histórico de uma aula concreta continua no seu próprio detalhe.
    //
    // Início do dia, não `now`: uma aula que já começou hoje ainda é
    // relevante (marcar presenças).
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return _occurrences
        .where('seriesId', isEqualTo: seriesId)
        .where('startAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .orderBy('startAt')
        .limit(_upcomingLimit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Stream<List<SessionOccurrence>> watchOccurrencesStartingBetween(
    DateTime from,
    DateTime to,
  ) {
    return _occurrences
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('startAt', isLessThan: Timestamp.fromDate(to))
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<Map<String, bool>> assignMembers({
    required String occurrenceId,
    required List<String> memberIds,
    bool isExtra = false,
  }) async {
    final result = await _functions
        .httpsCallable('assignMembersToOccurrence')
        .call<Object?>({
      'occurrenceId': occurrenceId,
      'memberIds': memberIds,
      'isExtra': isExtra,
    });
    // Mesmo padrão defensivo de `firebase_usage_repository.dart#recalculateUsage`
    // — o interop do Flutter Web pode devolver `Map<Object?, Object?>`.
    final data = Map<String, dynamic>.from(result.data as Map);
    final entries = (data['results'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map));
    return {
      for (final entry in entries)
        entry['memberId'] as String: entry['ok'] as bool,
    };
  }

  @override
  Future<List<String>> removeMembers({
    required String occurrenceId,
    required List<String> memberIds,
    int? newCapacity,
  }) async {
    final result = await _functions
        .httpsCallable('removeMembersFromOccurrence')
        .call<Object?>({
      'occurrenceId': occurrenceId,
      'memberIds': memberIds,
      if (newCapacity != null) 'newCapacity': newCapacity,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return ((data['removed'] as List?) ?? const [])
        .map((e) => e as String)
        .toList();
  }

  @override
  Future<void> rescheduleBooking({
    required String fromOccurrenceId,
    required String toOccurrenceId,
    required String memberId,
  }) async {
    try {
      await _functions.httpsCallable('rescheduleBooking').call<void>({
        'fromOccurrenceId': fromOccurrenceId,
        'toOccurrenceId': toOccurrenceId,
        'memberId': memberId,
      });
    } on FirebaseFunctionsException catch (e) {
      final reason =
          e.details is Map ? (e.details as Map)['reason'] as String? : null;
      if (reason != null && reason.startsWith('from-cancelled')) {
        throw RescheduleFailedException(
            e.message ?? 'Não foi possível remarcar.');
      }
      rethrow;
    }
  }
}
