import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/search_text.dart';
import '../../domain/entities/consent.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/payment_record.dart';
import '../../repositories/member_repository.dart';

MemberSummary _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data()!;
  return MemberSummary(
    uid: doc.id,
    memberNumber: data['memberNumber'] as String? ?? '',
    name: data['name'] as String? ?? '(sem nome)',
    active: (data['status'] as String? ?? 'active') == 'active',
    phone: data['phone'] as String? ?? '',
    email: data['email'] as String? ?? '',
    birthDate: (data['birthDate'] as Timestamp?)?.toDate(),
    address: data['address'] as String? ?? '',
    nif: data['nif'] as String? ?? '',
    emergencyContact: data['emergencyContact'] as String? ?? '',
    // Fase 9 — denormalizado por `FirebasePaymentRepository.setPaymentStatus`.
    // `null` até o Gestor marcar a primeira mensalidade deste membro.
    currentPaymentStatus: (data['currentPaymentStatus'] as String?) == null
        ? null
        : PaymentStatus.fromValue(data['currentPaymentStatus'] as String),
    currentPaymentPeriod: data['currentPaymentPeriod'] as String?,
    consent: _consentFromMap(data['consent'] as Map<String, dynamic>?),
  );
}

/// Fase 11 (RGPD) — o mapa `consent` só existe em contas que já
/// passaram pelo ecrã de consentimento. Ausente devolve
/// [MemberConsent] vazio, que é diferente de ter recusado: o
/// `ConsentGate` volta a perguntar.
MemberConsent _consentFromMap(Map<String, dynamic>? data) {
  if (data == null) return const MemberConsent();
  return MemberConsent(
    privacyPolicyVersion: (data['privacyPolicyVersion'] as num?)?.toInt(),
    acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
    healthDataGranted: data['healthDataGranted'] as bool? ?? false,
    healthDataUpdatedAt: (data['healthDataUpdatedAt'] as Timestamp?)?.toDate(),
  );
}

/// Compara membros pelo número de sócio, tratando-o como número quando
/// o é.
///
/// Comparar as strings diretamente só funciona enquanto todos os
/// números tiverem o mesmo comprimento — "1000" vinha antes de "999"
/// assim que o estúdio passasse dos três dígitos. Os números reais são
/// preenchidos com zeros ("000001"), mas nada obriga a isso, e um
/// número escrito à mão sem os zeros bastava para desalinhar a lista
/// toda.
///
/// Sem número (registo por arrumar) vai para o fim, ordenado por nome,
/// em vez de se misturar com quem tem.
int compareMembersByNumber(MemberSummary a, MemberSummary b) {
  final byName = searchNormalize(a.name).compareTo(searchNormalize(b.name));

  final numberA = int.tryParse(a.memberNumber.trim());
  final numberB = int.tryParse(b.memberNumber.trim());

  if (numberA != null && numberB != null) {
    final byNumber = numberA.compareTo(numberB);
    return byNumber != 0 ? byNumber : byName;
  }
  if (numberA != null) return -1;
  if (numberB != null) return 1;

  final byText = a.memberNumber.trim().compareTo(b.memberNumber.trim());
  return byText != 0 ? byText : byName;
}

class FirebaseMemberRepository implements MemberRepository {
  FirebaseMemberRepository(this._firestore, this._tenantId);

  final FirebaseFirestore _firestore;
  final String _tenantId;

  CollectionReference<Map<String, dynamic>> get _members =>
      _firestore.collection('tenants').doc(_tenantId).collection('members');

  /// Ordenado por NÚMERO DE SÓCIO, aqui e não na query.
  ///
  /// Ordenar no cliente (e não com um `orderBy`) porque um `orderBy`
  /// EXCLUI documentos sem o campo: um registo antigo sem `name` ou sem
  /// `memberNumber` desaparecia da gestão em vez de aparecer por
  /// arrumar.
  ///
  /// Era por nome. O número de sócio é a identidade que o estúdio usa
  /// no dia a dia — é por ele que se procura alguém ao balcão — e a
  /// ordenação alfabética escondia isso. Também tornava óbvio um
  /// problema que ninguém quer ver numa lista: com nomes que acabam em
  /// número ("Aluno 10" antes de "Aluno 2"), a ordem alfabética parece
  /// simplesmente partida.
  @override
  Stream<List<MemberSummary>> watchMembers() {
    return _members.snapshots().map(
          (snapshot) => snapshot.docs.map(_fromDoc).toList()
            ..sort(compareMembersByNumber),
        );
  }

  @override
  Stream<MemberSummary?> watchMember(String memberId) {
    return _members.doc(memberId).snapshots().map(
          (snapshot) => snapshot.exists ? _fromDoc(snapshot) : null,
        );
  }

  @override
  Future<void> setMemberActive({
    required String memberId,
    required bool active,
  }) async {
    await _members.doc(memberId).update({
      'status': active ? 'active' : 'inactive',
    });
  }

  @override
  Future<void> updateOwnContact({
    required String memberId,
    required String phone,
    required String email,
  }) async {
    await _members.doc(memberId).update({
      'phone': phone,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> registerFcmToken({
    required String memberId,
    required String token,
  }) async {
    await _members.doc(memberId).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  @override
  Future<void> updateMemberProfile({
    required String memberId,
    required String name,
    required String phone,
    required String email,
    DateTime? birthDate,
    required String address,
    required String nif,
    required String emergencyContact,
  }) async {
    await _members.doc(memberId).update({
      'name': name,
      'phone': phone,
      'email': email,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate) : null,
      'address': address,
      'nif': nif,
      'emergencyContact': emergencyContact,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
