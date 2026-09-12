import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/training_workout.dart';
import '../../domain/entities/member_stats.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/workout_session.dart';
import '../widgets/design_system.dart';
import '../widgets/exercise_logger.dart';
import '../../domain/entities/training_plan_entry.dart';
import '../widgets/person_avatar.dart';

/// Treinar com a turma toda — o instrutor a dar uma aula de grupo.
///
/// O registo de treino que existia era para uma pessoa de cada vez:
/// abrir a ficha do aluno, iniciar, registar, terminar, voltar atrás,
/// e outra vez para o seguinte. Numa aula de dez isso é impossível de
/// fazer com o telemóvel na mão enquanto se dá a aula — e o resultado
/// prático era não se registar nada.
///
/// O modelo é o que os softwares de box/estúdio usam para a mesma
/// situação (Wodify, SugarWOD, PushPress, e o "group training" do
/// Trainerize): **parte-se da AULA, não do aluno**. Vê-se a turma
/// inteira numa linha, começa-se para todos de uma vez, salta-se entre
/// pessoas com um toque, e no fim fecha-se tudo junto.
///
/// Por baixo continuam a ser sessões individuais — uma por aluno, com o
/// nome da aula. Isso é deliberado: o histórico, as estatísticas e a
/// evolução da carga de cada um continuam a funcionar exatamente como
/// antes, sem nenhum conceito novo de "sessão partilhada" que depois
/// teria de ser tratado em todo o lado.
///
/// Cada aluno regista contra o **plano dele**. Numa aula de grupo o
/// circuito costuma ser igual para todos, mas neste estúdio o plano é
/// individual — e mostrar a prescrição de cada um é o que permite ao
/// instrutor dizer "hoje sobes para 60" com a informação à frente.
class GroupWorkoutScreen extends ConsumerStatefulWidget {
  const GroupWorkoutScreen({
    super.key,
    required this.occurrenceId,
    required this.title,
  });

  final String occurrenceId;

  /// O nome que fica no histórico de cada aluno ("Aula de Grupo ·
  /// qua, 19:00"). Copiado para a sessão, como em qualquer treino.
  final String title;

  @override
  ConsumerState<GroupWorkoutScreen> createState() => _GroupWorkoutScreenState();
}

class _GroupWorkoutScreenState extends ConsumerState<GroupWorkoutScreen> {
  String? _selectedMemberId;
  bool _busy = false;

  /// O swipe entre atletas.
  ///
  /// A tira de nomes continua a ser o caminho principal — numa turma de
  /// doze, chegar ao nono são oito swipes e um toque. O swipe é o
  /// conforto para as turmas pequenas, onde percorrer a linha é o gesto
  /// natural.
  ///
  /// O risco a vigiar não é o gesto colidir com o registo (é tudo em
  /// toques): é **registar uma série na pessoa errada** depois de um
  /// swipe que passou despercebido. Por isso a tira acompanha sempre a
  /// página, e o nome fica no topo do painel — o instrutor tem de poder
  /// ver de relance em quem está.
  final _pageController = PageController();
  final _stripController = ScrollController();

  /// Por aluno, ou por exercício.
  ///
  /// "Por aluno" é o que serve para PT e para uma sala onde cada um faz
  /// o seu plano: abre-se a Ana, regista-se tudo dela, passa-se ao
  /// seguinte.
  ///
  /// "Por exercício" é como um instrutor conduz mesmo uma aula de
  /// grupo. Ele não pensa "agora a Ana" — chama o exercício, e toda a
  /// gente o faz. Aí o ecrã certo tem o exercício no topo e a turma em
  /// coluna, para registar a carga de cada um sem trocar de pessoa.
  bool _byExercise = false;

  @override
  void dispose() {
    _pageController.dispose();
    _stripController.dispose();
    super.dispose();
  }

  /// Traz o cartão selecionado para dentro do ecrã.
  ///
  /// Sem isto, um swipe para o quinto atleta deixava a tira parada nos
  /// três primeiros: a página mudava e o nome destacado ficava fora de
  /// vista, que é exatamente a situação que faz alguém registar na
  /// pessoa errada.
  void _revealInStrip(int index) {
    if (!_stripController.hasClients) return;
    const cardWidth = 108.0 + 8.0;
    final target = (index * cardWidth) - 40;
    _stripController.animateTo(
      target.clamp(0, _stripController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _select(List<String> attendees, String memberId) {
    final index = attendees.indexOf(memberId);
    if (index < 0) return;
    setState(() => _selectedMemberId = memberId);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    _revealInStrip(index);
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync =
        ref.watch(occurrenceBookingsProvider(widget.occurrenceId));
    final membersById = <String, MemberSummary>{
      for (final m
          in ref.watch(membersProvider).valueOrNull ?? const <MemberSummary>[])
        m.uid: m,
    };

    // Com o tamanho de letra do sistema a 2.0×, o título mais o seletor
    // de modo mais "Terminar todos" passam 154 px da largura de um
    // iPhone SE. O `padding` dos botões do Material 3 escala com o
    // texto (`ButtonStyleButton.scaledPadding`), por isso a barra
    // cresce mesmo com os ícones a 18 px fixos.
    //
    // Acima de ~1.3× as ações descem para baixo do título, numa fila
    // que desliza na horizontal — que é a única forma de uma barra de
    // ações nunca estourar, seja qual for o tamanho de letra.
    final escala = MediaQuery.textScalerOf(context);
    final letraGrande = escala.scale(14) > 18;

    final seletorModo = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: SegmentedButton<bool>(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.person_outline, size: 18),
            tooltip: 'Por aluno',
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.fitness_center_outlined, size: 18),
            tooltip: 'Por exercício',
          ),
        ],
        selected: {_byExercise},
        showSelectedIcon: false,
        onSelectionChanged: (value) => setState(() {
          _byExercise = value.first;
          // Cada modo tem a sua paginação; reaproveitar o índice
          // levava para o exercício nº 3 quando se estava no
          // aluno nº 3.
          if (_pageController.hasClients) _pageController.jumpToPage(0);
        }),
      ),
    );

    final terminarTodos = TextButton(
      onPressed: _busy ? null : () => _finishAll(membersById),
      child: const Text('Terminar todos'),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Treino da turma'),
        actions: letraGrande ? null : [seletorModo, terminarTodos],
        bottom: letraGrande
            ? PreferredSize(
                preferredSize: Size.fromHeight(escala.scale(48)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      seletorModo,
                      const SizedBox(width: 8),
                      terminarTodos
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (bookings) {
          final attendees = bookings
              .where((b) => b.status == BookingStatus.booked)
              .map((b) => b.memberId)
              .toList();

          if (attendees.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Sem ninguém inscrito',
              message: 'Esta sessão ainda não tem inscritos. Assim que '
                  'houver, podes começar o treino de todos a partir daqui.',
            );
          }

          final selected = attendees.contains(_selectedMemberId)
              ? _selectedMemberId!
              : attendees.first;

          if (_byExercise) {
            return _ExerciseFirstView(
              attendees: attendees,
              membersById: membersById,
              sessionTitle: widget.title,
              pageController: _pageController,
              stripController: _stripController,
              startAllBar: _StartAllBar(
                attendees: attendees,
                busy: _busy,
                onStartAll: () => _askAndStart(attendees, membersById),
              ),
            );
          }

          return Column(
            children: [
              _AttendeeStrip(
                attendees: attendees,
                membersById: membersById,
                selected: selected,
                controller: _stripController,
                onSelected: (memberId) => _select(attendees, memberId),
              ),
              _StartAllBar(
                attendees: attendees,
                busy: _busy,
                onStartAll: () => _askAndStart(attendees, membersById),
              ),
              const Divider(height: 1),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: attendees.length,
                  onPageChanged: (index) {
                    setState(() => _selectedMemberId = attendees[index]);
                    _revealInStrip(index);
                  },
                  itemBuilder: (context, index) {
                    final memberId = attendees[index];
                    return _AthletePane(
                      key: ValueKey(memberId),
                      memberId: memberId,
                      member: membersById[memberId],
                      sessionTitle: widget.title,
                    );
                  },
                ),
              ),
              if (attendees.length > 1)
                _PageDots(
                    count: attendees.length,
                    current: attendees.indexOf(selected)),
            ],
          );
        },
      ),
    );
  }

  /// Pergunta que treino cada um vai fazer, e só depois arranca.
  ///
  /// Os treinos são lidos aqui e não com um listener por atleta: isto
  /// corre uma vez, ao carregar no botão, e não precisa de ficar a
  /// ouvir mudanças durante a aula inteira.
  Future<void> _askAndStart(
    List<String> attendees,
    Map<String, MemberSummary> membersById,
  ) async {
    final workoutsByMember = <String, List<TrainingWorkout>>{};
    try {
      for (final memberId in attendees) {
        workoutsByMember[memberId] =
            await ref.read(memberWorkoutsProvider(memberId).future);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível ler os planos da turma.')),
        ),
      );
      return;
    }
    if (!mounted) return;

    final choices = await showModalBottomSheet<Map<String, TrainingWorkout?>>(
      context: context,
      backgroundColor: AppColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _StartClassSheet(
        attendees: attendees,
        membersById: membersById,
        workoutsByMember: workoutsByMember,
      ),
    );
    if (choices == null || !mounted) return;

    await _startAll(attendees, choices, membersById);
  }

  /// Abre uma sessão para quem ainda não tem nenhuma a decorrer.
  ///
  /// Quem já está a treinar (chegou mais cedo, ou o próprio começou
  /// pelo telemóvel) é deixado em paz — abrir uma segunda sessão
  /// significaria não saber a qual pertence a próxima série.
  Future<void> _startAll(
    List<String> attendees,
    Map<String, TrainingWorkout?> choices,
    Map<String, MemberSummary> membersById,
  ) async {
    // `await ... .future` e não `.valueOrNull`: um StreamProvider só é
    // inicializado quando alguém olha para ele, e este ecrã não o
    // observa em lado nenhum. Lido dentro do handler com `valueOrNull`,
    // a primeira leitura apanhava-o ainda em carregamento e o botão
    // não fazia nada — o mesmo engano já documentado em
    // `book_training_screen.dart`.
    final performedBy = (await ref.read(currentAppUserProvider.future))?.uid;
    if (performedBy == null) return;

    setState(() => _busy = true);
    var started = 0;
    try {
      final repository = ref.read(workoutSessionRepositoryProvider);
      for (final memberId in attendees) {
        final active =
            await ref.read(activeWorkoutSessionProvider(memberId).future);
        if (active != null) continue;
        final workout = choices[memberId];
        // Sem treino escolhido (plano vazio) não se abre sessão: uma
        // sessão sem exercícios é uma linha no histórico que não diz
        // nada e que alguém tem de ir fechar à mão.
        if (workout == null) continue;
        await repository.startSession(
          memberId: memberId,
          // O que faltava. Sem isto o painel mostrava TODOS os
          // exercícios do aluno (de todos os treinos) e o histórico
          // ficava sem saber que treino foi feito.
          workoutId: workout.id,
          workoutName: workout.name,
          performedBy: performedBy,
        );
        started += 1;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(started == 0
              ? 'Já estavam todos a treinar.'
              : '$started treino(s) iniciado(s).'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível iniciar. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fecha as sessões da turma de uma vez.
  ///
  /// Uma sessão sem séries nenhumas é descartada em vez de guardada:
  /// no histórico de quem faltou a meio, um treino vazio é ruído.
  Future<void> _finishAll(Map<String, MemberSummary> membersById) async {
    final bookings =
        ref.read(occurrenceBookingsProvider(widget.occurrenceId)).valueOrNull ??
            const <Booking>[];
    final attendees = bookings
        .where((b) => b.status == BookingStatus.booked)
        .map((b) => b.memberId)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Terminar os treinos da turma?'),
        content: const Text(
          'Fecha os treinos a decorrer desta aula. Os que não tiverem '
          'nenhuma série registada são descartados.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    var finished = 0;
    var discarded = 0;
    try {
      final repository = ref.read(workoutSessionRepositoryProvider);
      for (final memberId in attendees) {
        final active =
            await ref.read(activeWorkoutSessionProvider(memberId).future);
        if (active == null) continue;
        if (active.sets.isEmpty) {
          await repository.discardSession(
            memberId: memberId,
            sessionId: active.id,
          );
          discarded += 1;
        } else {
          await repository.finishSession(
            memberId: memberId,
            sessionId: active.id,
          );
          finished += 1;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$finished treino(s) registado(s)'
            '${discarded > 0 ? ', $discarded sem séries descartado(s)' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível terminar. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A turma numa linha. É daqui que se salta de aluno para aluno — o
/// gesto que a versão individual não tinha e que torna isto usável
/// durante uma aula.
class _AttendeeStrip extends ConsumerWidget {
  const _AttendeeStrip({
    required this.attendees,
    required this.membersById,
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  final List<String> attendees;
  final Map<String, MemberSummary> membersById;
  final ScrollController controller;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      // A tira é horizontal, por isso PRECISA de uma altura fixa — mas
      // 84 pontos fixos eram 84 pontos para texto que o utilizador pode
      // aumentar. Com a letra do sistema a 1.3× faltavam 30 px, a 2.0×
      // faltavam 72, e o que ficava cortado era o nome do aluno.
      // Cresce MAIS depressa do que o texto de propósito: dos 84 pontos
      // só uma parte é texto — os espaçamentos da lista e do cartão são
      // fixos e não encolhem, por isso o texto fica com uma fatia cada
      // vez menor. Escalar 84 proporcionalmente ainda deixava faltar
      // 4,8 px a 1.3×. Assim, a 1.0× fica exatamente como estava.
      height: 84 + (MediaQuery.textScalerOf(context).scale(84) - 84) * 1.6,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        itemCount: attendees.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final memberId = attendees[index];
          final name = membersById[memberId]?.name ?? memberId;
          final session =
              ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull;
          final isSelected = memberId == selected;

          return InkWell(
            onTap: () => onSelected(memberId),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 108,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.red.withValues(alpha: 0.16)
                    : AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.red : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    session == null
                        ? 'por iniciar'
                        : '${session.sets.length} série(s)',
                    style: TextStyle(
                      fontSize: 10,
                      color: session == null ? AppColors.mute : AppColors.ok,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StartAllBar extends ConsumerWidget {
  const _StartAllBar({
    required this.attendees,
    required this.busy,
    required this.onStartAll,
  });

  final List<String> attendees;
  final bool busy;
  final VoidCallback onStartAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = attendees
        .where((memberId) =>
            ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull ==
            null)
        .length;

    if (pending == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 15, color: AppColors.ok),
            SizedBox(width: 6),
            Text(
              'Toda a turma com treino a decorrer.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: busy ? null : onStartAll,
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 18),
          label: Text(
            pending == attendees.length
                ? 'Iniciar treino para a turma ($pending)'
                : 'Iniciar para os restantes ($pending)',
          ),
        ),
      ),
    );
  }
}

/// O painel do aluno selecionado: a sessão dele e o plano dele.
class _AthletePane extends ConsumerWidget {
  const _AthletePane({
    super.key,
    required this.memberId,
    required this.member,
    required this.sessionTitle,
  });

  final String memberId;
  final MemberSummary? member;
  final String sessionTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(activeWorkoutSessionProvider(memberId));
    final planAsync = ref.watch(trainingPlanProvider(memberId));
    // Só os exercícios do plano deste aluno. Numa aula de grupo isto é
    // por aluno, mas cada pedido traz meia dúzia de documentos em vez
    // da biblioteca toda — e o cache do Firestore trata das repetições
    // entre alunos com o mesmo plano.
    final exercisesById = ref
            .watch(exercisesByIdsProvider(exerciseKeyFor(
              (planAsync.valueOrNull ?? const <TrainingPlanEntry>[])
                  .map((entry) => entry.exerciseId),
            )))
            .valueOrNull ??
        const <String, Exercise>{};

    final session = sessionAsync.valueOrNull;
    if (session == null) {
      return EmptyState(
        icon: Icons.play_circle_outline,
        title: '${member?.name ?? 'Este aluno'} ainda não começou',
        message: 'Usa "Iniciar treino para a turma" acima para abrir o '
            'treino de toda a gente de uma vez.',
      );
    }

    return planAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorState(error: error),
      data: (entries) {
        // O arranque de turma passou a perguntar que treino cada um
        // faz, por isso `workoutId` deixou de ser sempre `null` e este
        // filtro começou a servir para alguma coisa: mostra os
        // exercícios de HOJE, não o plano inteiro.
        final planned = entriesForSession(entries, session);

        if (planned.isEmpty) {
          return EmptyState(
            icon: Icons.assignment_outlined,
            title: 'Sem plano de treino',
            message: '${member?.name ?? 'Este aluno'} ainda não tem '
                'exercícios prescritos, por isso não há o que registar. '
                'Monta-lhe o plano na ficha dele.',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _AthleteHeader(member: member, session: session),
            Align(
              alignment: Alignment.centerLeft,
              child: _ChangeWorkoutButton(memberId: memberId, session: session),
            ),
            const SizedBox(height: 8),
            for (final entry in planned) ...[
              ExerciseLogger(
                key: ValueKey('${memberId}_${entry.id}'),
                memberId: memberId,
                sessionId: session.id,
                entry: entry,
                exercise: exercisesById[entry.exerciseId],
                done: session.setsFor(entry.exerciseId),
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _AthleteHeader extends StatelessWidget {
  const _AthleteHeader({required this.member, required this.session});

  final MemberSummary? member;
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Row(
        children: [
          PersonAvatar(
            name: member?.name ?? '?',
            photoUrl: member?.photoUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member?.name ?? session.memberId,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  // O nome do treino ao lado dos números: com um split
                  // A/B/C, saber QUAL está a ser feito é metade da
                  // informação, e antes não aparecia em lado nenhum.
                  '${session.workoutName} · ${session.sets.length} série(s) '
                  '· ${session.totalReps} reps',
                  style: const TextStyle(color: AppColors.mute, fontSize: 11),
                ),
              ],
            ),
          ),
          if (session.totalVolume > 0)
            Text(
              '${session.totalVolume.toStringAsFixed(0)} kg',
              style: AppTheme.display(fontSize: 16),
            ),
        ],
      ),
    );
  }
}

/// Os pontinhos por baixo do painel.
///
/// Sem eles, o swipe é uma funcionalidade escondida: quem não a
/// descobre continua a usar a tira, e quem a descobre por acidente não
/// percebe quantas pessoas há à frente.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current ? AppColors.red : AppColors.mute,
              ),
            ),
        ],
      ),
    );
  }
}

/// Só os exercícios do treino que esta sessão está a fazer.
///
/// Uma sessão guarda `workoutId` — qual dos treinos do split o aluno
/// está a fazer hoje. Sem filtrar por ele, o painel mostrava o plano
/// INTEIRO: quem tem A/B/C via vinte exercícios em vez dos sete de hoje,
/// e tinha de os procurar no meio dos outros com a aula a decorrer.
///
/// `workoutId` a `null` significa uma sessão aberta antes de isto
/// existir (ou começada pelo próprio aluno sem escolher). Aí mostra-se
/// tudo — esconder exercícios com base num campo em falta seria pior do
/// que mostrar a mais.
List<TrainingPlanEntry> entriesForSession(
  List<TrainingPlanEntry> plan,
  WorkoutSession session,
) {
  if (session.workoutId == null) return plan;
  return plan.where((e) => e.workoutId == session.workoutId).toList();
}

/// A aula vista pelo exercício, não pelo aluno.
///
/// "Toda a gente no agachamento" — um exercício no topo, a turma em
/// coluna, e a carga de cada um registada sem trocar de pessoa. O swipe
/// percorre os EXERCÍCIOS, que é a ordem por que a aula corre.
///
/// A lista de exercícios sai dos planos de quem está na sala
/// (`groupExerciseOrder`), e não de um "plano da aula" — esse conceito
/// não existe neste domínio, onde cada aluno tem o seu plano. A
/// vantagem é que isto funciona hoje e acompanha os planos; a limitação
/// é que só aparecem exercícios que alguém tem prescrito, e não um
/// circuito improvisado no momento. Assinalado, não escondido.
///
/// ⚠️ Custo: um listener de plano por atleta, aberto enquanto o ecrã
/// estiver aberto. Numa turma de doze são doze listeners e umas duas
/// centenas de leituras na abertura — o preço desta vista, e a razão de
/// não ser o modo por omissão.
class _ExerciseFirstView extends ConsumerStatefulWidget {
  const _ExerciseFirstView({
    required this.attendees,
    required this.membersById,
    required this.sessionTitle,
    required this.pageController,
    required this.stripController,
    required this.startAllBar,
  });

  final List<String> attendees;
  final Map<String, MemberSummary> membersById;
  final String sessionTitle;
  final PageController pageController;
  final ScrollController stripController;
  final Widget startAllBar;

  @override
  ConsumerState<_ExerciseFirstView> createState() => _ExerciseFirstViewState();
}

class _ExerciseFirstViewState extends ConsumerState<_ExerciseFirstView> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Filtrado pelo treino que cada um está mesmo a fazer. Sem isto, a
    // lista de exercícios da aula juntava os três treinos do split de
    // cada aluno — dezenas de páginas para percorrer a swipe.
    //
    // As sessões já são observadas por cada linha (`_AthleteExerciseRow`);
    // observá-las aqui não abre listeners novos, o Riverpod partilha a
    // mesma subscrição.
    final plansByMember = <String, List<TrainingPlanEntry>>{
      for (final memberId in widget.attendees)
        memberId: () {
          final plan = ref.watch(trainingPlanProvider(memberId)).valueOrNull ??
              const <TrainingPlanEntry>[];
          final session =
              ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull;
          return session == null ? plan : entriesForSession(plan, session);
        }(),
    };

    final order = groupExerciseOrder(plansByMember);
    if (order.isEmpty) {
      return Column(
        children: [
          widget.startAllBar,
          const Expanded(
            child: EmptyState(
              icon: Icons.fitness_center_outlined,
              title: 'Sem exercícios prescritos',
              message: 'Esta vista mostra os exercícios dos planos de quem '
                  'está na aula. Nenhum dos inscritos tem plano de treino '
                  'ainda — monta um em Gestão, no treino de cada aluno.',
            ),
          ),
        ],
      );
    }

    final exercisesById =
        ref.watch(exercisesByIdsProvider(exerciseKeyFor(order))).valueOrNull ??
            const <String, Exercise>{};

    final current = _index.clamp(0, order.length - 1);

    return Column(
      children: [
        _ExerciseStrip(
          order: order,
          exercisesById: exercisesById,
          selected: current,
          controller: widget.stripController,
          onSelected: (index) {
            setState(() => _index = index);
            widget.pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            );
          },
        ),
        widget.startAllBar,
        const Divider(height: 1),
        Expanded(
          child: PageView.builder(
            controller: widget.pageController,
            itemCount: order.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final exerciseId = order[index];
              return _ExercisePane(
                exerciseId: exerciseId,
                exercise: exercisesById[exerciseId],
                attendees: widget.attendees,
                membersById: widget.membersById,
                plansByMember: plansByMember,
              );
            },
          ),
        ),
        if (order.length > 1) _PageDots(count: order.length, current: current),
      ],
    );
  }
}

/// A mesma tira da turma, mas de exercícios.
///
/// Existe pela mesma razão: com dez exercícios no circuito, chegar ao
/// oitavo a swipe são sete gestos.
class _ExerciseStrip extends StatelessWidget {
  const _ExerciseStrip({
    required this.order,
    required this.exercisesById,
    required this.selected,
    required this.controller,
    required this.onSelected,
  });

  final List<String> order;
  final Map<String, Exercise> exercisesById;
  final int selected;
  final ScrollController controller;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        itemCount: order.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = index == selected;
          final name = exercisesById[order[index]]?.name ?? order[index];
          return InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 170),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.red.withValues(alpha: 0.16)
                    : AppColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.red : Colors.transparent,
                ),
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Um exercício, a turma toda por baixo.
class _ExercisePane extends ConsumerWidget {
  const _ExercisePane({
    required this.exerciseId,
    required this.exercise,
    required this.attendees,
    required this.membersById,
    required this.plansByMember,
  });

  final String exerciseId;
  final Exercise? exercise;
  final List<String> attendees;
  final Map<String, MemberSummary> membersById;
  final Map<String, List<TrainingPlanEntry>> plansByMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Só quem tem este exercício prescrito. Listar os outros com "não
    // tem" enchia a página de ruído numa turma onde os planos divergem
    // — a contagem no cabeçalho já diz que nem todos estão neste
    // movimento.
    final doing = <(String, TrainingPlanEntry)>[
      for (final memberId in attendees)
        for (final entry
            in plansByMember[memberId] ?? const <TrainingPlanEntry>[])
          if (entry.exerciseId == exerciseId) (memberId, entry),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          exercise?.name ?? exerciseId,
          style: AppTheme.display(fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          doing.length == attendees.length
              ? 'Toda a turma (${attendees.length})'
              : '${doing.length} de ${attendees.length} alunos',
          style: const TextStyle(color: AppColors.mute, fontSize: 12),
        ),
        if (exercise != null && exercise!.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            exercise!.description,
            style: const TextStyle(
              color: AppColors.mute,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final pair in doing) ...[
          _AthleteExerciseRow(
            key: ValueKey('${pair.$1}_$exerciseId'),
            memberId: pair.$1,
            member: membersById[pair.$1],
            entry: pair.$2,
            exercise: exercise,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// O registo de UM aluno para o exercício da página.
///
/// Reaproveita o `ExerciseLogger` do treino individual: por cima o
/// nome, por baixo exatamente o mesmo registo — mesma pré-carga da
/// última sessão, mesmo desfazer, mesma edição de série. Uma segunda
/// implementação seria a forma mais certa de as duas divergirem.
class _AthleteExerciseRow extends ConsumerWidget {
  const _AthleteExerciseRow({
    super.key,
    required this.memberId,
    required this.member,
    required this.entry,
    required this.exercise,
  });

  final String memberId;
  final MemberSummary? member;
  final TrainingPlanEntry entry;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(activeWorkoutSessionProvider(memberId)).valueOrNull;
    final name = member?.name ?? memberId;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: name,
                photoUrl: member?.photoUrl,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name, style: const TextStyle(fontSize: 14)),
              ),
              if (session == null)
                const Pill('por iniciar', tone: PillTone.neutral),
            ],
          ),
          if (session == null) ...[
            const SizedBox(height: 6),
            const Text(
              'Ainda não começou. Usa "Iniciar treino para a turma" acima.',
              style: TextStyle(color: AppColors.mute, fontSize: 11),
            ),
          ] else ...[
            const SizedBox(height: 8),
            ExerciseLogger(
              key: ValueKey('${memberId}_${entry.id}'),
              memberId: memberId,
              sessionId: session.id,
              entry: entry,
              exercise: exercise,
              done: session.setsFor(entry.exerciseId),
            ),
          ],
        ],
      ),
    );
  }
}

/// Que treino cada aluno vai fazer hoje.
///
/// O arranque em grupo abria sessões com `workoutId: null` e o nome da
/// AULA. Duas consequências, e nenhuma era óbvia a olhar para o ecrã:
///
///  1. O painel de cada aluno mostrava **todos** os exercícios do plano
///     dele, de todos os treinos. Quem tem um split A/B/C via vinte
///     exercícios em vez dos sete de hoje.
///  2. O histórico ficava sem saber que treino foi feito — a informação
///     que o arranque individual (`start_workout_button.dart`) sempre
///     guardou, e de que a rotação A/B/C depende.
///
/// A escolha é por ALUNO e não pela turma: numa aula de grupo cada um
/// pode estar num dia diferente do seu split.
class _StartClassSheet extends ConsumerStatefulWidget {
  const _StartClassSheet({
    required this.attendees,
    required this.membersById,
    required this.workoutsByMember,
  });

  final List<String> attendees;
  final Map<String, MemberSummary> membersById;
  final Map<String, List<TrainingWorkout>> workoutsByMember;

  @override
  ConsumerState<_StartClassSheet> createState() => _StartClassSheetState();
}

class _StartClassSheetState extends ConsumerState<_StartClassSheet> {
  /// `memberId` → treino escolhido. Ausente = não começa.
  late final Map<String, TrainingWorkout?> _choice = {
    for (final memberId in widget.attendees)
      memberId: _defaultFor(widget.workoutsByMember[memberId] ?? const []),
  };

  /// O primeiro treino ativo do plano.
  ///
  /// Não tenta adivinhar em que dia do split o aluno vai: isso exigiria
  /// ler o histórico de cada um (mais um listener por atleta) para
  /// acertar num palpite que o instrutor corrige num toque. Fica a
  /// escolha à vista, já preenchida.
  static TrainingWorkout? _defaultFor(List<TrainingWorkout> workouts) {
    for (final workout in workouts) {
      if (workout.active) return workout;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final comPlano = _choice.entries.where((e) => e.value != null).length;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const SectionLabel('Que treino vai cada um fazer?'),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final memberId in widget.attendees)
                  _ChoiceRow(
                    member: widget.membersById[memberId],
                    name: widget.membersById[memberId]?.name ?? memberId,
                    workouts: (widget.workoutsByMember[memberId] ?? const [])
                        .where((w) => w.active)
                        .toList(),
                    selected: _choice[memberId],
                    onChanged: (workout) =>
                        setState(() => _choice[memberId] = workout),
                  ),
              ],
            ),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                // Sem ninguém com treino escolhido não há nada para
                // abrir — e um botão que abre zero sessões e diz
                // "pronto" é pior do que um botão desativado.
                onPressed: comPlano == 0
                    ? null
                    : () => Navigator.of(context).pop(
                          Map<String, TrainingWorkout?>.from(_choice),
                        ),
                child: Text(comPlano == widget.attendees.length
                    ? 'Começar (${widget.attendees.length})'
                    : 'Começar ($comPlano de ${widget.attendees.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.member,
    required this.name,
    required this.workouts,
    required this.selected,
    required this.onChanged,
  });

  /// `null` quando o aluno não está na lista carregada — raro, mas o
  /// nome basta para o identificar.
  final MemberSummary? member;
  final String name;
  final List<TrainingWorkout> workouts;
  final TrainingWorkout? selected;
  final ValueChanged<TrainingWorkout?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (workouts.isEmpty) {
      // Sem plano montado não há treino para começar. Dizê-lo aqui
      // evita a pergunta "porque é que só arrancaram três dos quatro?".
      return ListTile(
        leading: PersonAvatar(
          name: name,
          photoUrl: member?.photoUrl,
        ),
        title: Text(name),
        subtitle: const Text(
          'Sem treinos no plano — não vai começar',
          style: TextStyle(color: AppColors.mute, fontSize: 11),
        ),
      );
    }

    return ListTile(
      leading: PersonAvatar(
        name: name,
        photoUrl: member?.photoUrl,
      ),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: DropdownButton<TrainingWorkout>(
        value: selected,
        isDense: true,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final workout in workouts)
            DropdownMenuItem(
              value: workout,
              child: Text(
                workout.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Trocar o treino de uma sessão já aberta.
///
/// Só aparece **enquanto não houver séries registadas**. Depois disso,
/// as séries já feitas pertencem a exercícios do treino antigo: trocar
/// por baixo delas deixava-as fora da lista (o painel filtra pelo
/// treino) mas a contar nos totais — um estado que não se explica a
/// ninguém.
///
/// Escondido em vez de desativado: é uma correção de engano dos
/// primeiros segundos, e um botão permanentemente cinzento no cabeçalho
/// de cada aluno seria ruído durante a aula toda.
class _ChangeWorkoutButton extends ConsumerStatefulWidget {
  const _ChangeWorkoutButton({required this.memberId, required this.session});

  final String memberId;
  final WorkoutSession session;

  @override
  ConsumerState<_ChangeWorkoutButton> createState() =>
      _ChangeWorkoutButtonState();
}

class _ChangeWorkoutButtonState extends ConsumerState<_ChangeWorkoutButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (widget.session.sets.isNotEmpty) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: _busy ? null : _change,
      icon: const Icon(Icons.swap_horiz, size: 16),
      label: const Text('Trocar treino', style: TextStyle(fontSize: 12)),
    );
  }

  Future<void> _change() async {
    final workouts = (await ref.read(
      memberWorkoutsProvider(widget.memberId).future,
    ))
        .where((w) => w.active)
        .toList();
    if (!mounted) return;

    if (workouts.length < 2) {
      // Com um treino só não há troca possível. Dizê-lo é melhor do que
      // abrir uma folha com uma linha.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este aluno só tem um treino no plano.'),
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<TrainingWorkout>(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const SectionLabel('Trocar para que treino?'),
            const SizedBox(height: 8),
            for (final workout in workouts)
              ListTile(
                leading: const IconBox(Icons.fitness_center_outlined),
                title: Text(workout.name),
                trailing: workout.id == widget.session.workoutId
                    ? const Pill('atual', tone: PillTone.neutral)
                    : null,
                onTap: workout.id == widget.session.workoutId
                    ? null
                    : () => Navigator.of(sheetContext).pop(workout),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(workoutSessionRepositoryProvider).changeWorkout(
            memberId: widget.memberId,
            sessionId: widget.session.id,
            workoutId: chosen.id,
            workoutName: chosen.name,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível trocar o treino.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
