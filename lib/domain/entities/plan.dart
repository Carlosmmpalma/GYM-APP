import 'package:equatable/equatable.dart';

/// Domain Model v1 §10 — oferta comercial configurada pelo próprio
/// tenant. NUNCA um enum fixo na app: "Standard"/"Plus"/"Premium" são
/// só exemplos de nomes que um tenant pode escolher dar aos Plans que
/// cria — outro tenant pode ter "Gold"/"Unlimited"/"Pilates 2x" sem
/// nenhuma alteração ao código (Domain Model v1 §10).
class Plan extends Equatable {
  const Plan({
    required this.id,
    required this.name,
    required this.description,
    required this.currentPrice,
    required this.currency,
    required this.active,
  });

  final String id;
  final String name;
  final String description;
  final double currentPrice;
  final String currency;
  final bool active;

  @override
  List<Object?> get props => [id, name, description, currentPrice, currency, active];
}
