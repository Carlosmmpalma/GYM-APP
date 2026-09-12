import 'package:flutter/material.dart';

/// Contas sobre intervalos de horas, num sítio só.
///
/// Estavam espalhadas: o formulário de aulas pedia a duração **em
/// minutos escritos à mão**, o treino livre pedia início e fim, e a
/// verificação de "o fim é depois do início" existia só num deles — o
/// outro deixou entrar blocos das 08:10 às 08:00 em produção.

/// Minutos desde a meia-noite. É a forma de comparar duas horas sem
/// arrastar uma data atrás.
int minutesOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

/// Um intervalo tem de acabar depois de começar.
///
/// Não permite atravessar a meia-noite, de propósito: uma aula das
/// 23:00 às 00:30 não é um caso real num ginásio, e aceitá-la obrigava
/// a distinguir "acaba amanhã" de "escrevi ao contrário" — que é o
/// engano que isto existe para apanhar.
bool endsAfterStart(TimeOfDay start, TimeOfDay end) =>
    minutesOfDay(end) > minutesOfDay(start);

int durationInMinutes(TimeOfDay start, TimeOfDay end) =>
    minutesOfDay(end) - minutesOfDay(start);

/// Soma minutos a uma hora, sem passar do fim do dia.
///
/// O corte às 23:59 é o mesmo raciocínio de [endsAfterStart]: em vez de
/// dar a volta e devolver uma hora de madrugada, encosta ao limite.
TimeOfDay addMinutes(TimeOfDay start, int minutes) {
  final total = (minutesOfDay(start) + minutes).clamp(0, 23 * 60 + 59);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

/// "45 min", "1 h", "1 h 30" — como as pessoas dizem, não "90 minutos".
String formatDuration(int minutes) {
  if (minutes <= 0) return '—';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest';
}
