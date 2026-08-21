import 'package:equatable/equatable.dart';

/// Fase 11 — um TREINO dentro do plano de um membro.
///
/// A peça que faltava. Até aqui o plano de um aluno era uma lista
/// corrida de exercícios, sem forma de dizer "isto é o treino de costas
/// e aquilo é o de pernas" — e é assim que qualquer instrutor pensa e
/// prescreve, e como as apps da área o fazem (Trainerize, TrueCoach,
/// Hevy): um plano tem treinos, cada treino tem exercícios ordenados.
///
/// Um aluno que treina três vezes por semana tem tipicamente "Treino A —
/// Superiores", "Treino B — Inferiores", "Treino C — Full body". Sem
/// esta camada, os exercícios dos três apareciam todos misturados numa
/// lista só, e nem o instrutor nem o aluno sabiam o que fazer em que dia.
///
/// Vive em `tenants/{t}/members/{memberId}/workouts/{workoutId}`.
class TrainingWorkout extends Equatable {
  const TrainingWorkout({
    required this.id,
    required this.memberId,
    required this.name,
    this.notes = '',
    this.position = 0,
    this.active = true,
  });

  final String id;
  final String memberId;

  /// Como o instrutor lhe chama: "Treino A — Costas e Bíceps".
  final String name;

  /// Instruções gerais do treino: aquecimento, cadência, descanso entre
  /// séries quando é igual para tudo, o que fazer se doer.
  final String notes;

  /// Ordem dentro do plano. É o instrutor que a decide — "Treino A"
  /// antes de "Treino B" não é alfabético por acaso, é a sequência da
  /// semana.
  final int position;

  /// Desativar em vez de apagar: um treino antigo continua referenciado
  /// pelo histórico de cargas dos seus exercícios, e apagá-lo deixava
  /// esse histórico sem contexto.
  final bool active;

  TrainingWorkout copyWith(
      {String? name, String? notes, int? position, bool? active}) {
    return TrainingWorkout(
      id: id,
      memberId: memberId,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      position: position ?? this.position,
      active: active ?? this.active,
    );
  }

  @override
  List<Object?> get props => [id, memberId, name, notes, position, active];
}
