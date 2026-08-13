import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/environment.dart';
import '../../infrastructure/firebase/firebase_ping_repository.dart';
import '../../repositories/ping_repository.dart';
import '../use_cases/ping_firestore_use_case.dart';

/// Injetado no bootstrap consoante o ambiente ativo (ver
/// lib/core/bootstrap/bootstrap.dart). Nenhum provider abaixo deste ponto
/// sabe se está a correr contra o emulador ou contra um Firebase Project
/// real — essa decisão fica isolada aqui.
final environmentConfigProvider = Provider<EnvironmentConfig>((ref) {
  throw UnimplementedError(
    'environmentConfigProvider tem de ser sobrescrito no bootstrap '
    '(ProviderScope(overrides: [...])) antes de correr a app.',
  );
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// Fase 3 — `createSubscription` corre como Cloud Function (Admin SDK),
/// não como transação client-side como em Fase 2: a validação "este
/// membro já tem outra subscription ativa que dá acesso a um destes
/// serviços" precisa de percorrer TODAS as subscriptions ativas do
/// membro, o que não dá para exprimir com a mesma robustez em Security
/// Rules (ver nota em firebase_subscription_repository.dart).
final functionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instance;
});

/// Repository Pattern (Platform Foundation §12): a camada acima só conhece
/// a interface [PingRepository]. Trocar a implementação (ex: para uma
/// infraestrutura dedicada, ou para um fake em testes) não deve exigir
/// alterações fora deste ficheiro.
final pingRepositoryProvider = Provider<PingRepository>((ref) {
  return FirebasePingRepository(ref.watch(firestoreProvider));
});

final pingFirestoreUseCaseProvider = Provider<PingFirestoreUseCase>((ref) {
  return PingFirestoreUseCase(ref.watch(pingRepositoryProvider));
});
