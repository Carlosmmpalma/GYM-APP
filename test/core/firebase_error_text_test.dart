import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/utils/firebase_error_text.dart';

/// Fase 11 — tradução dos erros do Firebase.
void main() {
  group('describeFirebaseError', () {
    test('sem rede diz que é a rede, não "algo correu mal"', () {
      final error =
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      expect(describeFirebaseError(error), contains('Sem ligação'));
    });

    test('rate limiting explica que é esperar, não que falhou', () {
      // É o que `lib/rateLimit.ts` devolve. Sem tradução, quem via isto
      // ficava a achar que a operação estava partida.
      final error = FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'too many',
      );
      expect(describeFirebaseError(error), contains('Espera um momento'));
    });

    test('permissões dizem o que fazer a seguir', () {
      final error = FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
      expect(describeFirebaseError(error), contains('fala com o estúdio'));
    });

    test('sessão expirada é acionável', () {
      final error =
          FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated');
      expect(describeFirebaseError(error), contains('Entra outra vez'));
    });

    test('um erro que não sabemos traduzir devolve null', () {
      // De propósito: inventar uma explicação para um erro que não
      // percebemos é pior do que cair na frase genérica.
      final error =
          FirebaseException(plugin: 'cloud_firestore', code: 'internal');
      expect(describeFirebaseError(error), isNull);
    });

    test('um erro que nem é do Firebase devolve null', () {
      expect(describeFirebaseError(StateError('boom')), isNull);
    });
  });
}
