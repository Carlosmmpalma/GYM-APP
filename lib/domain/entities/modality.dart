import 'package:equatable/equatable.dart';

/// Fase 6 (Domain Model v1 §8-9) — modalidade dentro de um serviço
/// (ex.: "Pilates" dentro de "Aulas de Grupo" e dentro de "PT").
/// Independente do serviço em si — nunca um enum fixo na app (mesmo
/// princípio de `Service`/`Plan`).
///
/// Relação Service↔Modality (Firestore Data Model v1 §12): "para o
/// MVP, se a relação for pequena e raramente consultada, manter uma
/// lista de IDs no documento da modalidade é aceitável" — por isso
/// `serviceIds` vive aqui, não numa collection de relação à parte.
class Modality extends Equatable {
  const Modality({
    required this.id,
    required this.name,
    required this.active,
    this.serviceIds = const {},
  });

  final String id;
  final String name;
  final bool active;
  final Set<String> serviceIds;

  @override
  List<Object?> get props => [id, name, active, serviceIds];
}
