import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/consent.dart';

/// Fase 11 (RGPD) — o que decide se o `AuthGate` pergunta outra vez.
void main() {
  group('MemberConsent', () {
    test('sem registo nenhum é vazio e não é atual', () {
      const consent = MemberConsent();
      expect(consent.isEmpty, isTrue);
      expect(consent.isCurrent, isFalse);
      // Não ter registo NÃO é o mesmo que ter recusado — é o caso das
      // contas criadas antes disto existir, que têm de ser perguntadas.
      expect(consent.healthDataGranted, isFalse);
    });

    test('a versão em vigor conta como atual', () {
      final consent = MemberConsent(
        privacyPolicyVersion: kPrivacyPolicyVersion,
        acceptedAt: DateTime(2026, 8, 19),
      );
      expect(consent.isCurrent, isTrue);
      expect(consent.isEmpty, isFalse);
    });

    test('uma versão anterior deixa de contar', () {
      // É este o mecanismo de subir `kPrivacyPolicyVersion`: quem
      // aceitou a versão antiga volta a ser perguntado.
      final consent = MemberConsent(
        privacyPolicyVersion: kPrivacyPolicyVersion - 1,
        acceptedAt: DateTime(2026, 1, 1),
      );
      expect(consent.isCurrent, isFalse);
      expect(consent.isEmpty, isFalse);
    });

    test('dados de saúde são independentes da aceitação da política', () {
      // Artigo 7.º, n.º 4: aceitar o aviso de privacidade e autorizar
      // dados de saúde são decisões separadas. Aceitar a política com o
      // interruptor desligado é um estado normal e completo.
      final consent = MemberConsent(
        privacyPolicyVersion: kPrivacyPolicyVersion,
        acceptedAt: DateTime(2026, 8, 19),
        healthDataGranted: false,
      );
      expect(consent.isCurrent, isTrue);
      expect(consent.healthDataGranted, isFalse);
    });
  });
}
