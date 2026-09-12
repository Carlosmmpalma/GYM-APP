import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/workout_session.dart';
import '../../repositories/workout_session_repository.dart';

/// Quantas sessões o histórico carrega. Cresce a cada ida ao ginásio,
/// para sempre; como vem ordenado da mais recente para a mais antiga, o
/// corte tira as antigas — que é o que a lista quer mostrar por último.
const _sessionHistoryLimit = 100;

SetLog _setFromMap(Map<String, dynamic> data) {
  return SetLog(
    exerciseId: data['exerciseId'] as String,
    setNumber: (data['setNumber'] as num? ?? 1).toInt(),
    reps: (data['reps'] as num? ?? 0).toInt(),
    load: (data['load'] as num?)?.toDouble(),
    completedAt:
        (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    loadHistoryId: data['loadHistoryId'] as String?,
  );
}

Map<String, dynamic> _setToMap(SetLog set) => {
      'exerciseId': set.exerciseId,
      'setNumber': set.setNumber,
      'reps': set.reps,
      'load': set.load,
      'completedAt': Timestamp.fromDate(set.completedAt),
      'loadHistoryId': set.loadHistoryId,
    };

WorkoutSession _fromDoc(
    String memberId, DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  final rawSets = (data['sets'] as List?) ?? const [];
  return WorkoutSession(
    id: doc.id,
    memberId: memberId,
    workoutId: data['workoutId'] as String?,
    workoutName: data['workoutName'] as String? ?? 'Treino',
    startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    finishedAt: (data['finishedAt'] as Timestamp?)?.toDate(),
    performedBy: data['performedBy'] as String? ?? '',
    notes: data['notes'] as String? ?? '',
    sets: rawSets
        .map((e) => _setFromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

class FirebaseWorkoutSessionRepository implements WorkoutSessionRepository {
  FirebaseWorkoutSessionRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> _memberDoc(String memberId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('members')
          .doc(memberId);

  CollectionReference<Map<String, dynamic>> _sessions(String memberId) =>
      _memberDoc(memberId).collection('workoutSessions');

  CollectionReference<Map<String, dynamic>> _loadHistory(String memberId) =>
      _memberDoc(memberId).collection('loadHistory');

  @override
  Stream<List<WorkoutSession>> watchSessions(String memberId) {
    return _sessions(memberId)
        .orderBy('startedAt', descending: true)
        .limit(_sessionHistoryLimit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => _fromDoc(memberId, doc)).toList());
  }

  @override
  Stream<WorkoutSession?> watchActiveSession(String memberId) {
    // `finishedAt == null` é o que marca uma sessão em curso. O `limit(1)`
    // não é otimização: só pode haver uma, e se por alguma razão houver
    // duas, a mais recente é a que interessa.
    return _sessions(memberId)
        .where('finishedAt', isNull: true)
        .orderBy('startedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isEmpty
            ? null
            : _fromDoc(memberId, snapshot.docs.first));
  }

  @override
  Future<String> startSession({
    required String memberId,
    required String? workoutId,
    required String workoutName,
    required String performedBy,
  }) async {
    final ref = _sessions(memberId).doc();
    await ref.set({
      'workoutId': workoutId,
      'workoutName': workoutName,
      'startedAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
      'performedBy': performedBy,
      'notes': '',
      'sets': <Map<String, dynamic>>[],
    });
    return ref.id;
  }

  @override
  Future<void> changeWorkout({
    required String memberId,
    required String sessionId,
    required String workoutId,
    required String workoutName,
  }) async {
    // `workoutName` é copiado, e não lido do treino em cada leitura: é
    // o nome que fica no histórico, e um treino renomeado meses depois
    // não deve reescrever o passado. Mesmo raciocínio de `startSession`.
    await _sessions(memberId).doc(sessionId).update({
      'workoutId': workoutId,
      'workoutName': workoutName,
    });
  }

  @override
  // ---------------------------------------------------------------
  // Porque as três operações abaixo (`updateSet`, `deleteSet`,
  // `undoLastSet`) correm dentro de uma TRANSAÇÃO.
  //
  // As séries vivem num array dentro do documento da sessão, e há duas
  // formas de lá mexer: `logSet` acrescenta com `arrayUnion`, e estas
  // três lêem o array inteiro, mudam-no em memória e reescrevem-no.
  //
  // Misturar as duas é uma corrida. Sem transação, uma série registada
  // entre a LEITURA e a ESCRITA de um "desfazer" desaparecia — a
  // reescrita punha lá uma versão do array anterior a ela existir.
  // Nada falhava, nada avisava: a série simplesmente não estava lá.
  //
  // Parecia improvável enquanto só o próprio aluno registava do seu
  // telemóvel. A aula de grupo mudou isso: o instrutor regista as séries
  // de toda a gente a partir do dispositivo dele, e o aluno pode estar a
  // registar no seu ao mesmo tempo. Dois escritores no mesmo array.
  //
  // A transação torna o ler-mudar-escrever atómico, e o Firestore repete
  // a operação se alguém lá mexeu entretanto.
  //
  // ⚠️ Não há teste a provar isto. As nossas ferramentas não conseguem:
  // os testes contra o Emulator Suite são em TypeScript e não chamam
  // este código Dart; e o `fake_cloud_firestore` dos testes de widget
  // não modela conflitos de transação. Fica escrito em vez de fingido.
  // ---------------------------------------------------------------

  Future<void> logSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required int reps,
    double? load,
    required String performedBy,
  }) async {
    final completedAt = DateTime.now();
    // O id do registo de carga é gerado ANTES de escrever, para poder
    // ficar guardado dentro da própria série: é essa ligação que
    // permite corrigir ou apagar a série mais tarde sem deixar um valor
    // errado para sempre na evolução da carga.
    final loadHistoryRef = load != null ? _loadHistory(memberId).doc() : null;
    final set = SetLog(
      exerciseId: exerciseId,
      setNumber: setNumber,
      reps: reps,
      load: load,
      completedAt: completedAt,
      loadHistoryId: loadHistoryRef?.id,
    );

    final batch = _firestore.batch();

    // As séries vivem num array no documento da sessão, e não numa
    // subcoleção: uma sessão lê-se e escreve-se como uma unidade, e a
    // alternativa custaria uma leitura por série cada vez que o ecrã
    // abre. Trinta séries de mapas pequenos não chegam perto do limite
    // de 1 MB de um documento.
    batch.update(_sessions(memberId).doc(sessionId), {
      'sets': FieldValue.arrayUnion([_setToMap(set)]),
    });

    // O histórico de cargas por exercício continua a existir e a ser
    // escrito aqui. É o que alimenta o gráfico de evolução (UC16), que
    // responde a "quanto levantava há três meses" — uma pergunta que as
    // sessões sozinhas não respondem sem varrer tudo, porque as séries
    // estão dentro de um array e não são consultáveis.
    if (loadHistoryRef != null) {
      batch.set(loadHistoryRef, {
        'exerciseId': exerciseId,
        'load': load,
        'reps': reps,
        'recordedBy': performedBy,
        'recordedAt': Timestamp.fromDate(completedAt),
        'sessionId': sessionId,
      });
    }

    await batch.commit();
  }

  @override
  Future<void> undoLastSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
  }) async {
    final ref = _sessions(memberId).doc(sessionId);

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) return;

      final rawSets = ((snapshot.data()?['sets'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // A última série DESTE exercício, não a última da sessão: numa
      // sessão alterna-se entre exercícios, e "desfazer" tem de tirar a
      // que se acabou de confirmar ali.
      final index =
          rawSets.lastIndexWhere((s) => s['exerciseId'] == exerciseId);
      if (index < 0) return;

      final removed = rawSets.removeAt(index);
      tx.update(ref, {'sets': rawSets});
      final loadHistoryId = removed['loadHistoryId'] as String?;
      if (loadHistoryId != null) {
        tx.delete(_loadHistory(memberId).doc(loadHistoryId));
      }
    });
  }

  @override
  Future<void> updateSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required int reps,
    double? load,
    required String performedBy,
  }) async {
    final ref = _sessions(memberId).doc(sessionId);

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) return;

      final rawSets = ((snapshot.data()?['sets'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final index = rawSets.indexWhere((s) =>
          s['exerciseId'] == exerciseId &&
          (s['setNumber'] as num?) == setNumber);
      if (index < 0) return;

      final original = _setFromMap(rawSets[index]);

      // O registo de carga antigo sai e entra um novo, em vez de ser
      // editado: o id é a ligação entre a série e a entrada do
      // histórico, e refazê-la é mais simples do que a manter.
      if (original.loadHistoryId != null) {
        tx.delete(_loadHistory(memberId).doc(original.loadHistoryId!));
      }
      DocumentReference<Map<String, dynamic>>? newLoadRef;
      if (load != null) {
        newLoadRef = _loadHistory(memberId).doc();
        tx.set(newLoadRef, {
          'exerciseId': exerciseId,
          'load': load,
          'reps': reps,
          'recordedBy': performedBy,
          'recordedAt': Timestamp.fromDate(original.completedAt),
          'sessionId': sessionId,
        });
      }

      rawSets[index] = _setToMap(
        SetLog(
          exerciseId: exerciseId,
          setNumber: setNumber,
          reps: reps,
          load: load,
          // A hora original mantém-se: corrigir um valor não muda quando
          // a série foi feita.
          completedAt: original.completedAt,
          loadHistoryId: newLoadRef?.id,
        ),
      );
      tx.update(ref, {'sets': rawSets});
    });
  }

  @override
  Future<void> deleteSession({
    required String memberId,
    required String sessionId,
  }) async {
    // As cargas registadas durante a sessão apontam para ela por
    // `sessionId` — e é essa marca que as Security Rules exigem para
    // permitir apagar histórico de carga. Uma carga escrita à mão pelo
    // instrutor não a tem, e continua protegida.
    final history = await _memberDoc(memberId)
        .collection('loadHistory')
        .where('sessionId', isEqualTo: sessionId)
        .get();

    final batch = _firestore.batch();
    for (final doc in history.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_sessions(memberId).doc(sessionId));
    await batch.commit();
  }

  @override
  Future<void> deleteSet({
    required String memberId,
    required String sessionId,
    required String exerciseId,
    required int setNumber,
  }) async {
    final ref = _sessions(memberId).doc(sessionId);

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) return;

      final rawSets = ((snapshot.data()?['sets'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final index = rawSets.indexWhere((s) =>
          s['exerciseId'] == exerciseId &&
          (s['setNumber'] as num?) == setNumber);
      if (index < 0) return;

      // As restantes NÃO são renumeradas — `setNumber` é guardado
      // precisamente para isso (ver `SetLog`). Renumerar mudaria o que
      // as outras séries dizem, e quem apaga a 2.ª de quatro quer perder
      // uma série, não reescrever o registo das outras três.
      final removed = rawSets.removeAt(index);
      tx.update(ref, {'sets': rawSets});
      final loadHistoryId = removed['loadHistoryId'] as String?;
      if (loadHistoryId != null) {
        tx.delete(_loadHistory(memberId).doc(loadHistoryId));
      }
    });
  }

  @override
  Future<void> finishSession({
    required String memberId,
    required String sessionId,
    String notes = '',
  }) async {
    await _sessions(memberId).doc(sessionId).update({
      'finishedAt': FieldValue.serverTimestamp(),
      if (notes.isNotEmpty) 'notes': notes,
    });
  }

  @override
  Future<void> discardSession({
    required String memberId,
    required String sessionId,
  }) async {
    await _sessions(memberId).doc(sessionId).delete();
  }
}
