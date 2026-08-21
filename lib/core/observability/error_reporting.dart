import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Regista um erro que a app APANHOU e mostrou ao utilizador.
///
/// O Crashlytics estava ligado só a erros não apanhados — crashes. Mas
/// esta app quase não tem crashes: apanha tudo e mostra um `ErrorState`
/// ou um SnackBar. Resultado: se amanhã 30% das marcações começarem a
/// falhar por um índice em falta ou uma regra mal publicada, ninguém
/// fica a saber. Os utilizadores veem uma mensagem simpática, desistem,
/// e a consola diz que está tudo bem.
///
/// Erros apanhados são precisamente os que interessam num serviço em
/// produção: são os que acontecem a utilizadores reais e que ninguém
/// reporta.
///
/// `fatal: false` — não são crashes e não devem contaminar a taxa de
/// sessões sem falhas; aparecem no separador de não-fatais.
void reportHandledError(
  Object error,
  StackTrace? stack, {
  /// Onde aconteceu, em linguagem de quem vai investigar ("marcar
  /// sessão", "carregar mensalidades"). Vira o título do agrupamento
  /// no Crashlytics.
  String? context,
}) {
  if (kDebugMode) {
    // Em desenvolvimento o Crashlytics aponta para um projeto "demo-*"
    // que não existe; imprimir é mais útil e não engana ninguém.
    debugPrint('[erro tratado${context == null ? '' : ' · $context'}] $error');
    return;
  }

  // Nunca deixar a telemetria partir o ecrã que está a reportar um erro
  // — seria trocar uma mensagem por um crash.
  try {
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: context,
      fatal: false,
    );
  } catch (_) {
    // Sem nada a fazer: se o próprio reporte falha, não há onde o
    // reportar.
  }
}
