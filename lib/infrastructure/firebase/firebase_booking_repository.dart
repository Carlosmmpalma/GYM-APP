import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/booking.dart';
import '../../repositories/booking_repository.dart';

/// Resultado interno do callback de `runTransaction` em [createBooking]
/// — ver nota de arquitetura no método sobre porque não lançamos as
/// exceções de domínio diretamente lá dentro.
enum _BookingResult { booked, alreadyBooked, capacityExceeded, notBookable }

Booking _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  // occurrenceId é o segmento pai do path:
  // tenants/{t}/sessionOccurrences/{occurrenceId}/bookings/{bookingId}
  final occurrenceId = doc.reference.parent.parent!.id;
  return Booking(
    id: doc.id,
    occurrenceId: occurrenceId,
    memberId: data['memberId'] as String,
    status: (data['status'] as String) == 'booked'
        ? BookingStatus.booked
        : BookingStatus.cancelled,
    source: BookingSource.values.firstWhere(
      (s) => s.name == (data['source'] as String? ?? 'self'),
      orElse: () => BookingSource.self,
    ),
    isExtra: data['isExtra'] as bool? ?? false,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
  );
}

/// Nota de arquitetura (Fase 2): booking/cancelamento usam
/// `runTransaction` client-side, não uma Cloud Function.
///
/// Platform Foundation §17 recomenda explicitamente Firestore
/// Transactions para a concorrência da última vaga — é isso que está
/// implementado aqui. As Security Rules (`firestore.rules`) garantem,
/// documento a documento, que:
///   - `activeBookingCount` nunca é escrito para além de `capacity`,
///     nem alterado por outro campo que não seja +1/-1 por operação;
///   - só o próprio membro cria/cancela a sua marcação (docId == uid).
///
/// Limitação conhecida (documentada, não escondida): as Rules validam
/// cada escrita da transação isoladamente — não há forma nativa do
/// Firestore de exigir "o contador só sobe se o documento de booking
/// for criado a par". Um cliente malicioso podia, em teoria, enviar só
/// o incremento do contador sem criar o booking. Isto nunca permite
/// ultrapassar a capacidade (a Rule limita sempre `<= capacity`), e o
/// contador é um read model reconciliável a partir dos bookings reais
/// (Firestore Data Model v1 §28/32) — não é a fonte de verdade. Uma
/// versão futura pode substituir isto por uma Cloud Function
/// (Admin SDK, imune a Security Rules) se for preciso fechar esta
/// lacuna; para o MVP da Fase 2, o guia aceita explicitamente a
/// transação client-side.
class FirebaseBookingRepository implements BookingRepository {
  FirebaseBookingRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  DocumentReference<Map<String, dynamic>> _occurrenceDoc(String occurrenceId) =>
      _firestore
          .collection('tenants')
          .doc(_tenantId)
          .collection('sessionOccurrences')
          .doc(occurrenceId);

  @override
  Future<void> createBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    final occurrenceRef = _occurrenceDoc(occurrenceId);
    final bookingRef = occurrenceRef.collection('bookings').doc(memberId);

    // Nota (bug real, apanhado a testar em Chrome): o callback de
    // runTransaction() atravessa a fronteira do interop com JS no
    // Flutter Web (a Promise da SDK JS do Firestore, convertida de
    // volta para Future). Uma exceção Dart própria lançada AQUI DENTRO
    // (ex.: `throw const BookingCapacityExceededException()`) não
    // sobrevive a essa travessia com o tipo intacto — chega ao chamador
    // como um erro genérico de conversão ("Dart exception thrown from
    // converted Future..."), e nenhum `on XException catch` no ecrã
    // apanhava, caindo sempre na mensagem de erro genérica. Por isso o
    // callback só DEVOLVE um resultado; a exceção certa é lançada cá
    // fora, já em Dart puro, depois do `await`.
    final result = await _firestore.runTransaction<_BookingResult>((tx) async {
      // Todas as leituras da transação têm de vir antes de qualquer
      // escrita (regra do Firestore, não só boa prática).
      final occurrenceSnap = await tx.get(occurrenceRef);
      final bookingSnap = await tx.get(bookingRef);

      if (!occurrenceSnap.exists) {
        return _BookingResult.notBookable;
      }
      final data = occurrenceSnap.data()!;
      final status = data['status'] as String? ?? 'scheduled';
      final capacity = (data['capacity'] as num).toInt();
      final activeCount = (data['activeBookingCount'] as num? ?? 0).toInt();

      if (status != 'scheduled') {
        return _BookingResult.notBookable;
      }
      if (bookingSnap.exists && bookingSnap.data()?['status'] == 'booked') {
        return _BookingResult.alreadyBooked;
      }
      // Esta é a verificação que decide a corrida pela última vaga: o
      // Firestore garante que, se duas transações lerem o mesmo
      // activeCount e ambas tentarem escrever, só a primeira a
      // COMMITAR vence — a segunda falha e é automaticamente repetida
      // pelo SDK, lendo o valor já atualizado, e cai neste `if`.
      if (activeCount >= capacity) {
        return _BookingResult.capacityExceeded;
      }

      tx.set(bookingRef, {
        'memberId': memberId,
        'status': 'booked',
        'source': 'self',
        'isExtra': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(occurrenceRef, {'activeBookingCount': activeCount + 1});
      return _BookingResult.booked;
    });

    switch (result) {
      case _BookingResult.booked:
        return;
      case _BookingResult.alreadyBooked:
        throw const AlreadyBookedException();
      case _BookingResult.capacityExceeded:
        throw const BookingCapacityExceededException();
      case _BookingResult.notBookable:
        throw const SessionNotBookableException();
    }
  }

  @override
  Future<void> cancelBooking({
    required String occurrenceId,
    required String memberId,
  }) async {
    final occurrenceRef = _occurrenceDoc(occurrenceId);
    final bookingRef = occurrenceRef.collection('bookings').doc(memberId);

    // Ver nota em createBooking sobre porque o callback só devolve um
    // resultado, em vez de lançar a exceção lá dentro.
    final found = await _firestore.runTransaction<bool>((tx) async {
      final bookingSnap = await tx.get(bookingRef);
      final occurrenceSnap = await tx.get(occurrenceRef);

      if (!bookingSnap.exists || bookingSnap.data()?['status'] != 'booked') {
        return false;
      }
      final activeCount =
          (occurrenceSnap.data()?['activeBookingCount'] as num? ?? 0).toInt();

      tx.update(bookingRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      tx.update(occurrenceRef, {
        'activeBookingCount': activeCount > 0 ? activeCount - 1 : 0,
      });
      return true;
    });

    if (!found) {
      throw const BookingNotFoundException();
    }
  }

  @override
  Stream<List<Booking>> watchMyBookings(String memberId) {
    return _firestore
        .collectionGroup('bookings')
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }
}
