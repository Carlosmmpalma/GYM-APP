import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/service.dart';
import 'design_system.dart';

/// "O que ainda posso marcar esta semana?" — a pergunta que o aluno faz
/// antes de olhar para o horário.
///
/// ## Porque faltava
///
/// O limite semanal existia e era respeitado, mas só se via **dentro do
/// cartão de cada aula**, em letra pequena, e só nas aulas do serviço
/// correspondente. Para saber quantas sessões lhe sobravam, o aluno
/// tinha de rolar até encontrar uma aula daquele serviço e ler a linha
/// por baixo do preço.
///
/// Se o plano dele tivesse dois serviços com limites diferentes — o
/// caso normal num pacote — não havia sítio nenhum onde os dois
/// números aparecessem juntos.
///
/// ## O que mostra, e o que não mostra
///
/// Só os serviços **com limite**. Um serviço ilimitado não tem número
/// para dar, e uma linha a dizer "ilimitado" repetida por três serviços
/// empurra para baixo a única que interessa.
///
/// E só a semana CORRENTE. O limite é por semana ISO; um resumo que
/// tentasse cobrir as semanas seguintes teria de escolher qual mostrar,
/// e a resposta certa muda conforme a aula em que se está a pensar —
/// que é precisamente o que a linha dentro de cada cartão já resolve.
class WeeklyAllowance extends ConsumerWidget {
  const WeeklyAllowance({
    super.key,
    required this.memberId,
    required this.serviceIds,
    required this.servicesById,
  });

  final String memberId;

  /// Os serviços a que este aluno tem acesso.
  final Set<String> serviceIds;

  final Map<String, Service> servicesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (serviceIds.isEmpty) return const SizedBox.shrink();

    final semana = isoWeekKey(DateTime.now());
    final linhas = <Widget>[];

    // Ordenado pelo nome para a lista não saltar de posição entre
    // reconstruções — `serviceIds` é um `Set`.
    final ordenados = serviceIds.toList()
      ..sort((a, b) =>
          (servicesById[a]?.name ?? a).compareTo(servicesById[b]?.name ?? b));

    for (final serviceId in ordenados) {
      final regra = ref
          .watch(applicableUsageRuleProvider(
            (memberId: memberId, serviceId: serviceId),
          ))
          .valueOrNull;
      if (regra == null || regra.isUnlimited) continue;

      final limite = regra.limit!;
      final usadas = ref
              .watch(usageProvider((
                memberId: memberId,
                serviceId: serviceId,
                period: semana,
              )))
              .valueOrNull
              ?.used ??
          0;
      final restantes = (limite - usadas).clamp(0, limite);

      linhas.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  servicesById[serviceId]?.name ?? serviceId,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              // O número que interessa é o que SOBRA, não o que foi
              // gasto. "Resta 1" responde à pergunta; "1/2 usadas"
              // obriga a fazer a conta.
              Pill(
                restantes == 0
                    ? 'sem sessões'
                    : restantes == 1
                        ? 'resta 1'
                        : 'restam $restantes',
                tone: restantes == 0 ? PillTone.warn : PillTone.ok,
              ),
            ],
          ),
        ),
      );
    }

    if (linhas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: PanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta semana',
              style: TextStyle(
                color: AppColors.mute,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...linhas,
          ],
        ),
      ),
    );
  }
}
