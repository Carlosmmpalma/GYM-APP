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
    this.exclusiveGroup,
  });

  final String id;
  final String name;
  final bool active;

  /// Fase 8 (auditoria funcional, UC26 fechado) — "Sem acompanhamento"
  /// e Standard/Plus/Premium não são produtos independentes, são
  /// NÍVEIS DO MESMO PRODUTO: um membro nunca pode ter subscriptions
  /// ativas a dois serviços com o mesmo `exclusiveGroup` ao mesmo
  /// tempo, mesmo quando são serviços DIFERENTES (ex.: "Treino sem
  /// acompanhamento" vs. "Aula de Grupo" — o conflito por
  /// `activeServiceIds` já existente em `createSubscription.ts`
  /// (Fase 3) só apanhava dois planos a dar acesso ao MESMO serviço,
  /// nunca este caso). `null` — a maioria dos serviços (Hyrox,
  /// Pilates) não pertence a nenhum grupo exclusivo, são livremente
  /// combináveis entre si, como o próprio UC26 descreve.
  final String? exclusiveGroup;

  @override
  List<Object?> get props => [id, name, active, exclusiveGroup];
}
