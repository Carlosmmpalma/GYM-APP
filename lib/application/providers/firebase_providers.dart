import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/environment.dart';

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
  // `instanceFor`, não `instance`: as funções estão implantadas em
  // `europe-west1` (ver `firebase/functions/src/index.ts`) e
  // `FirebaseFunctions.instance` aponta para `us-central1`. Com a
  // região errada, TODAS as chamadas falham com `not-found` — e a
  // mensagem não deixa perceber que o problema é geográfico.
  return FirebaseFunctions.instanceFor(region: kFunctionsRegion);
});

/// Fase 8 — primeiro provider a precisar de Storage a sério (vídeo de
/// exercícios, UC15).
final firebaseStorageProvider = Provider<FirebaseStorage>((ref) {
  return FirebaseStorage.instance;
});
