import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/utils/firebase_error_text.dart';

FirebaseFunctionsException _functionsError(String code, String message) {
  return FirebaseFunctionsException(code: code, message: message);
}

/// Reportado a testar: criar uma conta sem preencher tudo mostrava
/// `[firebase_functions/internal] internal`. O servidor passou a
/// devolver mensagens escritas para pessoas; isto garante que a app as
/// mostra — e que continua a proteger-se do que NÃO é para mostrar.
void main() {
  group('O que vem do servidor', () {
    test('uma mensagem escrita para pessoas é usada tal como está', () {
      final error = _functionsError(
        'invalid-argument',
        'Falta preencher: nome.',
      );

      expect(
        userFacingError(error, fallback: 'Não foi possível criar a conta.'),
        'Falta preencher: nome.',
      );
    });

    test('"já existe" também', () {
      final error = _functionsError(
        'already-exists',
        'Já existe uma conta com este email. Usa outro, ou procura a pessoa '
            'na lista de utilizadores.',
      );

      expect(
        userFacingError(error, fallback: 'Não foi possível criar a conta.'),
        contains('Já existe uma conta com este email'),
      );
    });

    test('um bloco de JSON NÃO é mostrado', () {
      // Era isto que a app despejava no ecrã quando a validação não
      // era traduzida: o erro da biblioteca, em JSON.
      final error = _functionsError(
        'invalid-argument',
        '[\n  {\n    "code": "too_small",\n    "path": ["name"]\n  }\n]',
      );

      expect(
        userFacingError(error, fallback: 'Não foi possível criar a conta.'),
        'Faltam dados ou algum campo está mal preenchido. Confirma o '
        'formulário e tenta outra vez.',
      );
    });

    test('"INTERNAL" cai no fallback de quem chamou', () {
      final error = _functionsError('internal', 'INTERNAL');

      expect(
        userFacingError(error, fallback: 'Não foi possível criar a conta.'),
        'Não foi possível criar a conta.',
      );
    });

    test('sem rede, a frase é sobre a rede — não sobre a ação', () {
      final error = _functionsError('unavailable', 'UNAVAILABLE');

      expect(
        userFacingError(error, fallback: 'Não foi possível guardar.'),
        contains('Sem ligação'),
      );
    });
  });

  group('Erros da própria app', () {
    test('uma exceção de domínio fala por si', () {
      // As exceções de domínio desta app existem precisamente para
      // dizer o que aconteceu em português.
      expect(
        userFacingError(
          const _NotEligible(),
          fallback: 'Não foi possível marcar.',
        ),
        'O teu plano não inclui este serviço.',
      );
    });

    test('uma exceção de programador não vai para o ecrã', () {
      expect(
        userFacingError(
          Exception('Null check operator used on a null value'),
          fallback: 'Não foi possível marcar.',
        ),
        'Não foi possível marcar.',
      );
    });

    test('um TypeError também não', () {
      expect(
        userFacingError(
          TypeError(),
          fallback: 'Não foi possível guardar.',
        ),
        'Não foi possível guardar.',
      );
    });
  });
}

class _NotEligible implements Exception {
  const _NotEligible();
  @override
  String toString() => 'O teu plano não inclui este serviço.';
}
