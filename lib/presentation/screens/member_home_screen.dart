import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/payment_record.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/subscription.dart';
import '../widgets/design_system.dart';
import 'assessment_list_screen.dart';
import 'book_training_screen.dart';
import 'my_bookings_screen.dart';
import 'my_training_plan_screen.dart';

final _nextBookingFormat = DateFormat('EEE d MMM · HH:mm', 'pt_PT');

/// Fase 10 (mockup "Início") — o ecrã que faltava por completo. Até aqui
/// o Aluno entrava diretamente em "Marcar treino", e os atalhos para
/// perfil/plano/avaliações viviam espremidos como ícones na `AppBar`
/// (seis de uma vez, sem rótulo) — é a diferença mais visível entre a
/// app e o mockup, e a razão de a navegação parecer pobre.
///
/// Três blocos, pela ordem do mockup:
///   1. card de estado da conta (nº de sócio + nível contratado + pill
///      da mensalidade);
///   2. "Próxima marcação";
///   3. grelha 2×2 de atalhos.
///
/// Decisão registada: o mockup NÃO tem barra inferior em ecrã nenhum (a
/// classe `.bottom-nav` existe no CSS mas nunca é usada) — a navegação
/// seria só este dashboard. Mantivemos a barra e acrescentámos "Início"
/// como primeiro separador: dá o dashboard sem um refactor de navegação
/// arriscado, e "Marcar"/"Livre"/"Marcações" continuam a um toque em vez
/// de dois. Sinalizado como desvio deliberado ao mockup.
class MemberHomeScreen extends ConsumerWidget {
  const MemberHomeScreen({
    super.key,
    required this.memberId,
    this.onOpenTab,
  });

  final String memberId;

  /// "Marcar treino" e "Minhas marcações" são atalhos no mockup mas
  /// separadores no shell do Aluno — em vez de os duplicar como ecrãs
  /// empilhados (o utilizador ficaria com um "voltar" para um sítio de
  /// onde nunca saiu), o card troca de separador. `0` é este mesmo
  /// ecrã, por isso os índices úteis começam em 1.
  ///
  /// `null` quando este dashboard vive num shell SEM esses separadores
  /// — é o caso do Gestor que também é membro, cujos separadores são de
  /// gestão. Aí os mesmos atalhos empilham o ecrã, que é o
  /// comportamento correto nesse contexto.
  final ValueChanged<int>? onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberProfileProvider(memberId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        memberAsync.when(
          loading: () => const PanelCard(
            gradient: true,
            child: SizedBox(
              height: 52,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, stack) => ErrorState(error: error, compact: true),
          data: (member) {
            if (member == null) {
              return const PanelCard(
                child: Text(
                  'Não foi possível carregar a tua conta. Contacta o Gestor.',
                ),
              );
            }
            return _AccountCard(memberId: memberId, member: member);
          },
        ),
        const SizedBox(height: 16),
        const SectionLabel('Próxima marcação'),
        const SizedBox(height: 8),
        _NextBookingCard(memberId: memberId),
        const SizedBox(height: 16),
        _ShortcutGrid(memberId: memberId, onOpenTab: onOpenTab),
      ],
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.memberId, required this.member});

  final String memberId;
  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionsAsync = ref.watch(memberSubscriptionsProvider(memberId));
    final plansById = <String, Plan>{
      for (final p in ref.watch(plansProvider).valueOrNull ?? const <Plan>[])
        p.id: p,
    };

    // O mockup mostra o NÍVEL contratado ("Standard/Plus/Premium: Plus").
    // Um membro pode ter várias subscriptions ativas (Domain Model v1
    // §15) — mostramos os nomes dos planos ativos, que é o equivalente
    // real neste modelo de dados.
    final activePlanNames =
        (subscriptionsAsync.valueOrNull ?? const <Subscription>[])
            .where((s) => s.isActive)
            .map((s) => plansById[s.planId]?.name ?? s.planId)
            .toList();

    final paymentStatus = member.currentMonthStatus(DateTime.now());

    return PanelCard(
      gradient: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nº de sócio ${member.memberNumber}',
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  activePlanNames.isEmpty
                      ? 'Sem plano ativo'
                      : activePlanNames.join(' · '),
                  style: AppTheme.display(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PaymentPill(status: paymentStatus),
        ],
      ),
    );
  }
}

class _PaymentPill extends StatelessWidget {
  const _PaymentPill({required this.status});

  final PaymentStatus? status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      PaymentStatus.paid => const Pill('Em dia', tone: PillTone.ok),
      PaymentStatus.paidLate =>
        const Pill('Pago com atraso', tone: PillTone.warn),
      PaymentStatus.overdue => const Pill('Em atraso', tone: PillTone.danger),
      // Sem registo este mês nunca é alarme — ver `MemberSummary.isOverdueFor`.
      null => const Pill('Sem registo', tone: PillTone.neutral),
    };
  }
}

class _NextBookingCard extends ConsumerWidget {
  const _NextBookingCard({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.when(
      loading: () => const PanelCard(
        child: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stack) => ErrorState(error: error, compact: true),
      data: (bookings) {
        final active =
            bookings.where((b) => b.status == BookingStatus.booked).toList();
        if (active.isEmpty) {
          return const PanelCard(
            child: Text(
              'Não tens nenhuma marcação. Usa "Marcar" para reservar.',
              style: TextStyle(color: AppColors.mute),
            ),
          );
        }
        return _NextBookingResolver(bookings: active);
      },
    );
  }
}

/// `myBookingsProvider` devolve as marcações ativas mas SEM a data da
/// sessão (essa vive na ocorrência). Para saber qual é a "próxima" é
/// preciso resolver cada ocorrência — por isso este widget à parte, em
/// vez de o cálculo estar inline no card.
class _NextBookingResolver extends ConsumerWidget {
  const _NextBookingResolver({required this.bookings});

  final List<Booking> bookings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    SessionOccurrence? next;
    Booking? nextBooking;

    for (final booking in bookings) {
      final occurrence =
          ref.watch(occurrenceProvider(booking.occurrenceId)).valueOrNull;
      if (occurrence == null) continue;
      if (occurrence.startAt.isBefore(now)) continue;
      if (next == null || occurrence.startAt.isBefore(next.startAt)) {
        next = occurrence;
        nextBooking = booking;
      }
    }

    if (next == null || nextBooking == null) {
      return const PanelCard(
        child: Text(
          'Não tens nenhuma sessão futura marcada.',
          style: TextStyle(color: AppColors.mute),
        ),
      );
    }

    final servicesById = <String, Service>{
      for (final s
          in ref.watch(servicesProvider).valueOrNull ?? const <Service>[])
        s.id: s,
    };
    final serviceName = servicesById[next.serviceId]?.name ?? next.serviceId;

    return PanelCard(
      child: Row(
        children: [
          const IconBox(Icons.local_fire_department_outlined),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: const TextStyle(
                    color: AppColors.bone,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _nextBookingFormat.format(next.startAt),
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A grelha 2×2 do mockup. Substitui os ícones sem rótulo que estavam na
/// `AppBar` — o mesmo destino, agora nomeado e tocável.
class _ShortcutGrid extends ConsumerWidget {
  const _ShortcutGrid({required this.memberId, required this.onOpenTab});

  final String memberId;
  final ValueChanged<int>? onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Os quatro do mockup, pela mesma ordem.
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.9,
      children: [
        _ShortcutCard(
          icon: Icons.fitness_center,
          label: 'O meu plano',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MyTrainingPlanScreen(memberId: memberId),
            ),
          ),
        ),
        _ShortcutCard(
          icon: Icons.calendar_month_outlined,
          label: 'Marcar treino',
          onTap: () => onOpenTab == null
              ? Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Marcar treino')),
                      body: const BookTrainingScreen(),
                    ),
                  ),
                )
              : onOpenTab!(1),
        ),
        _ShortcutCard(
          icon: Icons.assignment_outlined,
          label: 'Avaliações',
          onTap: () async {
            final member =
                await ref.read(memberProfileProvider(memberId).future);
            if (member == null || !context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AssessmentListScreen(member: member),
              ),
            );
          },
        ),
        _ShortcutCard(
          icon: Icons.event_available_outlined,
          label: 'Minhas marcações',
          onTap: () => onOpenTab == null
              ? Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Minhas marcações')),
                      body: const MyBookingsScreen(),
                    ),
                  ),
                )
              : onOpenTab!(3),
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.red, size: 20),
          const SizedBox(height: 9),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.bone,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
