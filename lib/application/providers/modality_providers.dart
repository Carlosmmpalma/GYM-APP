import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/modality.dart';
import '../../infrastructure/firebase/firebase_modality_repository.dart';
import '../../repositories/modality_repository.dart';
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';

/// Fase 6 (Domain Model v1 §8-9).
final modalityRepositoryProvider = Provider<ModalityRepository>((ref) {
  return FirebaseModalityRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final modalitiesProvider = StreamProvider<List<Modality>>((ref) {
  return ref.watch(modalityRepositoryProvider).watchModalities();
});
