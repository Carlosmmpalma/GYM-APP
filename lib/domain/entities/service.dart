import 'package:equatable/equatable.dart';

/// Um serviço disponibilizado pelo ginásio (Domain Model v1 §7).
///
/// Na Fase 2 existe uma única Service de teste ("Aula de Grupo"), criada
/// pelo seed script — ainda não há ecrã de gestão (isso é Fase 3).
class Service extends Equatable {
  const Service({
    required this.id,
    required this.name,
    required this.active,
  });

  final String id;
  final String name;
  final bool active;

  @override
  List<Object?> get props => [id, name, active];
}
