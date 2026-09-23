// Preenche o catálogo do estúdio: biblioteca de exercícios, serviços,
// modalidades e planos. Opcionalmente, um plano de treino completo num
// aluno.
//
//   node seed-content.mjs --project=gym-sas --tenant=nxt_performance_studio --yes
//
// Escolher só uma parte:
//   --only=exercicios            (ou servicos, modalidades, planos)
//   --training-plan-for=900001   (nº de sócio; cria treinos A/B/C)
//
// ---------------------------------------------------------------------
// AO CONTRÁRIO do `create-test-users.mjs`, isto NÃO é dado descartável.
// É o catálogo do estúdio, feito para ficar e para ser editado pela app.
// Por isso:
//
//   · Não há modo `--delete`. Apagar um exercício que já está prescrito
//     no plano de alguém deixa a prescrição a apontar para o vazio; os
//     ecrãs de gestão são o sítio certo para mexer nisto.
//
//   · Os ids são fixos e legíveis (`ex_agachamento_barra`,
//     `plan_acompanhado_3x`). Correr duas vezes atualiza, não duplica.
//
//   · ⚠️ OS PREÇOS SÃO INVENTADOS. Estão todos juntos em PLANOS, mais
//     abaixo. Revê-os antes de mostrar isto a um cliente.
// ---------------------------------------------------------------------

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

// =====================================================================
// EXERCÍCIOS
//
// A descrição não é decorativa: é o que o aluno lê no telemóvel a meio
// da série, quando não se lembra da execução. Uma linha, o essencial,
// e o erro mais comum.
//
// `grupo` é a CATEGORIA do exercício. Deixou de haver uma lista fixa no
// código: o estúdio cria as suas em Gestão › Categorias de exercícios.
// Estes valores servem de ponto de partida, e o ecrã de categorias
// oferece importá-los quando ainda não existe nenhuma definida.
// =====================================================================

const EXERCICIOS = [
  // ---------------------------------------------------------- Pernas
  ['agachamento_barra', 'Agachamento com barra', 'Pernas',
    'Barra apoiada no trapézio, pés à largura dos ombros e ligeiramente virados para fora. Desce até a anca ficar ao nível do joelho, com o peito aberto e o peso a meio do pé. Não deixes os joelhos colapsarem para dentro na subida.'],
  ['agachamento_frontal', 'Agachamento frontal', 'Pernas',
    'Barra à frente, apoiada nos deltoides com os cotovelos bem altos. Tronco mais vertical do que no agachamento normal — assim que os cotovelos caem, a barra rola para a frente.'],
  ['agachamento_goblet', 'Agachamento goblet', 'Pernas',
    'Haltere ou kettlebell junto ao peito. É a melhor forma de aprender o padrão do agachamento: o peso à frente obriga o tronco a manter-se direito.'],
  ['prensa_pernas', 'Prensa de pernas', 'Pernas',
    'Pés a meio da plataforma, à largura da anca. Desce até 90° no joelho sem deixar a lombar descolar do encosto. Não travas a perna no fim.'],
  ['extensao_pernas', 'Extensão de pernas', 'Pernas',
    'Isolamento do quadricípite. Ajusta o encosto para o eixo do joelho ficar alinhado com o da máquina. Sobe controlado, pausa em cima.'],
  ['curl_femoral', 'Curl femoral deitado', 'Pernas',
    'Isquiotibiais. Anca colada ao banco durante todo o movimento — se a anca sobe, deixaste de treinar o que querias.'],
  ['peso_morto_romeno', 'Peso morto romeno', 'Pernas',
    'Joelhos quase estendidos, anca a ir para trás e a barra rente às pernas. Desce até sentires o alongamento atrás da coxa, não até ao chão. Costas sempre direitas.'],
  ['afundo_halteres', 'Afundo com halteres', 'Pernas',
    'Passo à frente, joelho de trás quase a tocar no chão, tronco vertical. Alterna as pernas. Se perdes o equilíbrio, encurta o passo.'],
  ['agachamento_bulgaro', 'Agachamento búlgaro', 'Pernas',
    'Pé de trás elevado num banco. Trabalha uma perna de cada vez e expõe desequilíbrios entre lados — é normal um lado ser mais fraco no início.'],
  ['hip_thrust', 'Hip thrust', 'Pernas',
    'Costas apoiadas num banco, barra sobre a anca. Sobe até o tronco ficar paralelo ao chão e aperta o glúteo em cima. Queixo para dentro, não estendas o pescoço.'],
  ['gemeos_pe', 'Elevação de gémeos em pé', 'Pernas',
    'Amplitude completa: desce o calcanhar abaixo do degrau e sobe até ao máximo. Movimento lento — os gémeos respondem mal a repetições atiradas.'],

  // ---------------------------------------------------------- Costas
  ['peso_morto', 'Peso morto convencional', 'Costas',
    'Barra sobre o meio do pé, mãos fora dos joelhos. Levanta empurrando o chão, mantendo a barra colada ao corpo. As costas nunca arredondam — se arredondam, o peso é demasiado.'],
  ['remada_curvada', 'Remada curvada com barra', 'Costas',
    'Tronco a cerca de 45°, barra a subir em direção ao umbigo. Puxa com os cotovelos, não com as mãos. Sem balanço do tronco.'],
  ['puxada_alta', 'Puxada alta na polia', 'Costas',
    'Pega larga, peito para cima, puxa a barra até à clavícula. Desce controlado até estender os braços. Puxar atrás da nuca não traz vantagem e castiga o ombro.'],
  ['remada_baixa', 'Remada baixa na polia', 'Costas',
    'Sentado, costas direitas, puxa até ao abdómen juntando as omoplatas. Evita usar a lombar para atirar o peso para trás.'],
  ['elevacoes_barra', 'Elevações na barra', 'Costas',
    'Pega pronada à largura dos ombros. Sobe até o queixo passar a barra, desce até estender. Se ainda não consegues, usa elástico ou a máquina assistida — não deixes de as fazer.'],
  ['remada_serrote', 'Remada unilateral com halter', 'Costas',
    'Joelho e mão apoiados no banco, costas paralelas ao chão. Puxa o halter à anca, sem rodar o tronco para ganhar amplitude.'],
  ['pullover_polia', 'Pullover na polia', 'Costas',
    'Braços quase estendidos, puxa a barra da altura da cara até às coxas num arco. Trabalha o grande dorsal sem envolver os bíceps.'],

  // ------------------------------------------------------------ Peito
  ['supino_reto', 'Supino reto com barra', 'Peito',
    'Omoplatas juntas e apoiadas, pés firmes no chão. Desce a barra ao meio do peito, cotovelos a cerca de 45° do tronco — não abertos a 90°.'],
  ['supino_inclinado', 'Supino inclinado com halteres', 'Peito',
    'Banco a 30-45°. Halteres descem até à linha do peito, sobem sem baterem um no outro. Mais inclinação do que isto passa o trabalho para o ombro.'],
  ['crucifixo_halteres', 'Aberturas com halteres', 'Peito',
    'Cotovelos ligeiramente fletidos e fixos durante todo o movimento. Abre até sentires o alongamento no peito, não mais. É um exercício de amplitude, não de carga.'],
  ['peck_deck', 'Peck deck', 'Peito',
    'Isolamento do peitoral com trajetória guiada. Ajusta o assento para as pegas ficarem à altura do peito. Aperta um segundo no fecho.'],
  ['flexoes', 'Flexões de braços', 'Peito',
    'Corpo em prancha da cabeça aos calcanhares. Desce até o peito quase tocar no chão. Se a anca cai, o core não está a segurar — faz de joelhos até ganhares força.'],
  ['cross_over', 'Cross-over na polia', 'Peito',
    'Polias em cima, um passo à frente. Junta as mãos à frente do corpo em arco. A tensão constante da polia é o que distingue este exercício das aberturas.'],

  // ----------------------------------------------------------- Ombros
  ['desenvolvimento_barra', 'Desenvolvimento militar com barra', 'Ombros',
    'De pé, barra à altura da clavícula. Empurra para cima passando a cabeça ligeiramente para trás e depois para a frente. Glúteo e abdominal contraídos — não arqueies a lombar.'],
  ['desenvolvimento_halteres', 'Desenvolvimento com halteres sentado', 'Ombros',
    'Costas apoiadas, halteres à altura das orelhas. Sobe sem bloquear os cotovelos com força no topo.'],
  ['elevacoes_laterais', 'Elevações laterais', 'Ombros',
    'Halteres leves, sobe até à altura do ombro com o cotovelo ligeiramente fletido. Se precisas de balanço, o peso é demasiado — este exercício vive de repetições limpas.'],
  ['elevacoes_frontais', 'Elevações frontais', 'Ombros',
    'Sobe o halter à frente até à altura dos olhos, sem balanço do tronco. Alterna os braços para controlares melhor.'],
  ['face_pull', 'Face pull', 'Ombros',
    'Corda na polia à altura da cara. Puxa em direção à testa, abrindo as mãos e rodando os ombros para fora. É o melhor seguro que existe contra ombros fechados de tanto supino.'],
  ['encolhimentos', 'Encolhimentos', 'Ombros',
    'Sobe os ombros a direito em direção às orelhas e segura. Rodar os ombros não acrescenta nada e irrita a articulação.'],

  // ----------------------------------------------------------- Braços
  ['curl_barra', 'Curl de bíceps com barra', 'Braços',
    'Cotovelos junto ao tronco e fixos. Sobe sem balançar a lombar. A barra W poupa os pulsos se sentires desconforto.'],
  ['curl_alternado', 'Curl alternado com halteres', 'Braços',
    'Roda o punho para fora à medida que sobes (supinação). Desce controlado — a parte negativa é onde o bíceps cresce.'],
  ['curl_martelo', 'Curl martelo', 'Braços',
    'Pega neutra, halteres a apontar para a frente. Trabalha o braquial e o antebraço; é o que dá espessura ao braço visto de lado.'],
  ['triceps_polia', 'Tríceps na polia alta', 'Braços',
    'Cotovelos colados ao tronco, só o antebraço se move. Estende até ao fim e abre a corda no final do percurso.'],
  ['triceps_testa', 'Tríceps testa', 'Braços',
    'Deitado, barra a descer até à testa com os cotovelos apontados ao teto. Movimento lento e controlado — não é um exercício para carga máxima.'],
  ['fundos_paralelas', 'Fundos em paralelas', 'Braços',
    'Tronco vertical para focar o tríceps (inclinado à frente passa o trabalho para o peito). Desce até 90° no cotovelo; mais do que isso castiga o ombro.'],
  ['curl_scott', 'Curl no banco Scott', 'Braços',
    'Braços apoiados na almofada, sem espaço para roubar com o tronco. Não estendas o cotovelo com violência no fim da descida.'],

  // ------------------------------------------------------------- Core
  ['prancha_frontal', 'Prancha frontal', 'Core',
    'Antebraços e pontas dos pés, corpo em linha reta. Aperta glúteo e abdominal. Melhor 30 segundos bem feitos do que dois minutos com a anca a cair.'],
  ['prancha_lateral', 'Prancha lateral', 'Core',
    'Apoio num antebraço, anca levantada e alinhada. Trabalha o oblíquo e o glúteo médio ao mesmo tempo.'],
  ['elevacao_pernas', 'Elevação de pernas suspenso', 'Core',
    'Pendurado na barra, sobe as pernas sem balanço. Se for difícil, começa com os joelhos fletidos.'],
  ['abdominal_polia', 'Abdominal na polia', 'Core',
    'De joelhos, corda atrás da cabeça. Enrola a coluna trazendo as costelas à bacia — não é uma flexão da anca.'],
  ['roda_abdominal', 'Roda abdominal', 'Core',
    'Rola para a frente mantendo a lombar neutra. Vai só até onde consegues manter a anca sem ceder, e aumenta a distância com as semanas.'],
  ['dead_bug', 'Dead bug', 'Core',
    'Deitado, estende braço e perna opostos mantendo a lombar colada ao chão. Exercício de controlo, não de esforço.'],
  ['pallof_press', 'Pallof press', 'Core',
    'De lado para a polia, empurra as mãos à frente resistindo à rotação. Treina o core a não rodar, que é metade do trabalho dele.'],

  // -------------------------------------------------------- Full body
  ['burpee', 'Burpee', 'Full body',
    'Agachamento, prancha, flexão, salto. Mantém o ritmo constante em vez de começar rápido e parar.'],
  ['thruster', 'Thruster', 'Full body',
    'Agachamento frontal seguido de desenvolvimento, num só movimento. A subida do agachamento dá o impulso para a barra passar a cabeça.'],
  ['kettlebell_swing', 'Kettlebell swing', 'Full body',
    'A força vem da anca, não dos braços. O kettlebell é atirado pela extensão da anca e os braços só o acompanham. Costas sempre direitas.'],
  ['clean_press', 'Clean and press', 'Full body',
    'Do chão ao ombro e do ombro acima da cabeça. Exercício técnico — aprende com carga leve antes de somar peso.'],
  ['turkish_getup', 'Turkish get-up', 'Full body',
    'Do chão até de pé com o peso sempre acima da cabeça. Lento e por etapas. Trabalha estabilidade do ombro como nenhum outro.'],
  ['farmers_walk', 'Farmer’s walk', 'Full body',
    'Anda com peso pesado em cada mão, ombros para trás e tronco direito. Simples e brutalmente eficaz para a pega e o core.'],
  ['battle_ropes', 'Battle ropes', 'Full body',
    'Semi-agachamento, ondas alternadas e contínuas. O objetivo é manter a amplitude quando o cansaço aparece.'],

  // ------------------------------------------------------------ Hyrox
  ['hyrox_skierg', 'SkiErg', 'Hyrox',
    'Puxa com o tronco, não só com os braços: a anca fecha ao mesmo tempo que as mãos descem. Ritmo constante é mais rápido do que arrancar forte.'],
  ['hyrox_sled_push', 'Sled Push (trenó — empurrar)', 'Hyrox',
    'Braços estendidos, corpo inclinado, passos curtos e contínuos. Parar custa mais do que abrandar.'],
  ['hyrox_sled_pull', 'Sled Pull (trenó — puxar)', 'Hyrox',
    'Anca baixa, puxa a corda mão sobre mão usando o peso do corpo para trás. Poupa os braços — as pernas fazem o trabalho.'],
  ['hyrox_burpee_jump', 'Burpee Broad Jump', 'Hyrox',
    'Burpee seguido de salto em comprimento. Mede o salto: saltos curtos e constantes batem saltos longos com paragens.'],
  ['hyrox_rowing', 'Remo (Concept2)', 'Hyrox',
    'Sequência: pernas, tronco, braços — e ao contrário na volta. A potência vem das pernas; os braços são o fim do movimento.'],
  ['hyrox_farmers_carry', 'Farmers Carry', 'Hyrox',
    'Kettlebells pesados, um em cada mão. Ombros para trás, passos rápidos. A pega é o que falha primeiro — treina-a à parte.'],
  ['hyrox_sandbag_lunges', 'Sandbag Lunges', 'Hyrox',
    'Saco ao ombro, afundos contínuos. Joelho de trás a tocar levemente no chão. É a estação onde a técnica se degrada mais depressa.'],
  ['hyrox_wall_balls', 'Wall Balls', 'Hyrox',
    'Agachamento completo e lançamento ao alvo. O ritmo respiratório é o que decide o resultado: expira no lançamento.'],
  ['hyrox_assault_bike', 'Assault Bike', 'Hyrox',
    'Braços e pernas em conjunto. Sobe a intensidade por etapas em vez de arrancar ao máximo.'],
  ['hyrox_corrida', 'Corrida (1 km)', 'Hyrox',
    'Os 8 segmentos de corrida são metade da prova. Treina a correr já cansado, não fresco — é o que vais encontrar.'],
];

// =====================================================================
// SERVIÇOS
//
// Um serviço é um nome. Teve um terceiro campo, `exclusivo`, que
// agrupava serviços "alternativos" uns dos outros para o servidor
// recusar planos incompatíveis — desapareceu com a passagem a um plano
// ativo por membro: sem dois planos ao mesmo tempo, não há combinações
// para proibir.
// =====================================================================

const SERVICOS = [
  ['svc_treino_livre', 'Treino livre', 'Acesso à sala, sem instrutor ao lado'],
  ['svc_treino_acompanhado', 'Treino acompanhado', 'Sessões com instrutor'],
  ['svc_aulas_grupo', 'Aulas de grupo', 'Pilates, Yoga, HIIT, ciclismo'],
  ['svc_personal_training', 'Personal Training', 'Sessões individuais'],
  ['svc_hyrox', 'Hyrox', 'Preparação específica para Hyrox'],
];

// =====================================================================
// MODALIDADES — o que se faz dentro de cada serviço.
// =====================================================================

const MODALIDADES = [
  ['mod_musculacao', 'Musculação', ['svc_treino_livre', 'svc_treino_acompanhado']],
  ['mod_funcional', 'Treino funcional', ['svc_aulas_grupo', 'svc_hyrox', 'svc_personal_training']],
  ['mod_pilates', 'Pilates', ['svc_aulas_grupo', 'svc_personal_training']],
  ['mod_yoga', 'Yoga', ['svc_aulas_grupo']],
  ['mod_hiit', 'HIIT', ['svc_aulas_grupo']],
  ['mod_cycling', 'Ciclismo indoor', ['svc_aulas_grupo']],
  ['mod_hyrox_race', 'Hyrox Race Prep', ['svc_hyrox']],
  ['mod_reabilitacao', 'Reabilitação e mobilidade', ['svc_personal_training']],
];

// =====================================================================
// PLANOS
//
// ⚠️ PREÇOS INVENTADOS — revê antes de usar a sério.
//
// Cada plano lista os serviços que inclui e a regra de utilização de
// cada um: `null` = ilimitado, ou [quantidade, período].
//
// **Um membro tem UM plano.** Por isso cada plano é um pacote completo,
// não uma peça para combinar: quem quer sala e aulas compra o plano que
// traz as duas, não dois planos. É assim que um ginásio vende de
// qualquer forma — três ou quatro pacotes, não combinações arbitrárias.
//
// A lista cobre de propósito os quatro casos que se quer ver a testar:
// um plano só de sala, um com limite semanal, um com dois limites
// diferentes, e um sem limite nenhum. O ecrã de atribuir ordena-os por
// nome, não por esta ordem.
// =====================================================================

const PLANOS = [
  ['plan_livre', 'Livre Trânsito', 39.9,
    'Só sala, em horário completo, sem instrutor ao lado.',
    [['svc_treino_livre', null]]],

  ['plan_aulas', 'Aulas de Grupo', 44.9,
    'Todas as aulas do horário — Pilates, Yoga, HIIT e ciclismo — mais acesso à sala.',
    [['svc_aulas_grupo', null], ['svc_treino_livre', null]]],

  ['plan_acompanhado_2x', 'Acompanhado 2x', 54.9,
    'Duas sessões por semana com instrutor e plano de treino individual, mais acesso livre à sala.',
    [['svc_treino_acompanhado', [2, 'week']], ['svc_treino_livre', null]]],

  ['plan_hyrox', 'Hyrox Team', 59.9,
    'Três sessões de preparação para Hyrox por semana, mais aulas de grupo e sala.',
    [['svc_hyrox', [3, 'week']], ['svc_aulas_grupo', null], ['svc_treino_livre', null]]],

  ['plan_premium', 'Premium', 89.9,
    'Tudo: treino acompanhado sem limite, todas as aulas, duas sessões de Hyrox por semana e sala.',
    [['svc_treino_acompanhado', null], ['svc_aulas_grupo', null],
      ['svc_hyrox', [2, 'week']], ['svc_treino_livre', null]]],
];

// =====================================================================
// PLANO DE TREINO (opcional, --training-plan-for=<nº de sócio>)
//
// Um split de 3 dias — a estrutura mais comum num estúdio: empurrar,
// puxar, pernas. As cargas são exemplos plausíveis para alguém com
// alguns meses de treino.
//
// Formato: [idExercicio, séries, reps, carga|null, descanso|null, nota]
// =====================================================================

const TREINOS = [
  {
    id: 'workout_a',
    nome: 'Treino A — Peito, Ombros e Tríceps',
    notas: 'Aquece 5 min na passadeira e faz uma série leve do primeiro exercício antes de começar. Descanso de 90 s entre séries pesadas.',
    exercicios: [
      ['supino_reto', 4, '8-10', 60, 120, 'Sobe 2,5 kg quando fizeres 10 repetições limpas nas quatro séries.'],
      ['supino_inclinado', 3, '10-12', 22, 90, ''],
      ['desenvolvimento_halteres', 3, '10-12', 16, 90, ''],
      ['elevacoes_laterais', 3, '12-15', 8, 60, 'Leve e limpo. Sem balanço.'],
      ['triceps_polia', 3, '12-15', 25, 60, ''],
      ['flexoes', 2, 'até à falha', null, 60, 'A fechar o treino, para esgotar.'],
    ],
  },
  {
    id: 'workout_b',
    nome: 'Treino B — Costas e Bíceps',
    notas: 'Se as elevações ainda forem difíceis, usa o elástico — mas mantém-nas no treino.',
    exercicios: [
      ['peso_morto', 4, '5-6', 90, 180, 'Técnica primeiro. Se as costas arredondarem, baixa a carga.'],
      ['elevacoes_barra', 4, '6-8', null, 120, 'Com elástico se precisares.'],
      ['remada_curvada', 3, '8-10', 50, 90, ''],
      ['remada_baixa', 3, '10-12', 45, 90, ''],
      ['curl_barra', 3, '10-12', 25, 60, ''],
      ['curl_martelo', 3, '12', 12, 60, ''],
      ['face_pull', 3, '15', 15, 45, 'Todos os treinos de costas. Compensa o supino.'],
    ],
  },
  {
    id: 'workout_c',
    nome: 'Treino C — Pernas e Core',
    notas: 'O treino mais duro da semana. Come qualquer coisa uma hora antes e bebe água durante.',
    exercicios: [
      ['agachamento_barra', 4, '8-10', 70, 150, 'Profundidade acima de carga. Filma-te de lado de vez em quando.'],
      ['peso_morto_romeno', 3, '10-12', 50, 120, ''],
      ['prensa_pernas', 3, '12', 120, 90, ''],
      ['curl_femoral', 3, '12-15', 30, 60, ''],
      ['afundo_halteres', 3, '10 por perna', 14, 90, ''],
      ['gemeos_pe', 4, '15-20', 40, 45, ''],
      ['prancha_frontal', 3, '45s', null, 45, 'Anca em linha. Para quando começar a cair.'],
    ],
  },
];

// =====================================================================

function arg(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const projectId = arg('project');
const tenantId = arg('tenant');
const only = arg('only');
const trainingPlanFor = arg('training-plan-for');
const confirmed = process.argv.includes('--yes');

const missing = Object.entries({ project: projectId, tenant: tenantId })
  .filter(([, value]) => !value)
  .map(([key]) => `--${key}`);

if (missing.length > 0) {
  console.error(`Faltam argumentos: ${missing.join(', ')}`);
  process.exit(1);
}

const SECOES = ['exercicios', 'servicos', 'modalidades', 'planos'];
const escolhidas = only ? only.split(',').map((s) => s.trim()) : SECOES;
const desconhecidas = escolhidas.filter((s) => !SECOES.includes(s));
if (desconhecidas.length > 0) {
  console.error(`--only desconhecido: ${desconhecidas.join(', ')}`);
  console.error(`Válidos: ${SECOES.join(', ')}`);
  process.exit(1);
}

const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const onde = usingEmulator ? '[EMULADOR]' : '[PROJETO REAL]';

if (!confirmed) {
  console.error(
    `Vai escrever o catálogo (${escolhidas.join(', ')}) em "${tenantId}" ` +
      `/ "${projectId}" ${onde}.\n` +
      (trainingPlanFor ? `E um plano de treino no sócio ${trainingPlanFor}.\n` : '') +
      'Confirma acrescentando --yes ao comando.',
  );
  process.exit(1);
}

initializeApp({ projectId });
const firestore = getFirestore();
const tenantRef = firestore.collection('tenants').doc(tenantId);

const tenantSnapshot = await tenantRef.get();
if (!tenantSnapshot.exists) {
  console.error(`O tenant "${tenantId}" não existe em "${projectId}".`);
  process.exit(1);
}

// Firestore aceita no máximo 500 operações por batch.
async function commitInChunks(rows, apply) {
  for (let i = 0; i < rows.length; i += 400) {
    const batch = firestore.batch();
    for (const row of rows.slice(i, i + 400)) apply(batch, row);
    await batch.commit();
  }
}

if (escolhidas.includes('exercicios')) {
  const collection = tenantRef.collection('exercises');
  await commitInChunks(EXERCICIOS, (batch, [id, name, grupo, description]) => {
    batch.set(
      collection.doc(`ex_${id}`),
      {
        name,
        description,
        category: grupo,
        // Não mexemos no vídeo: se alguém já tiver carregado um pela
        // app, correr o script outra vez não o pode apagar.
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  console.log(`✓ ${EXERCICIOS.length} exercícios`);
}

if (escolhidas.includes('servicos')) {
  await commitInChunks(SERVICOS, (batch, [id, name]) => {
    batch.set(
      tenantRef.collection('services').doc(id),
      { name, active: true, createdAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
  console.log(`✓ ${SERVICOS.length} serviços`);
}

if (escolhidas.includes('modalidades')) {
  await commitInChunks(MODALIDADES, (batch, [id, name, serviceIds]) => {
    batch.set(
      tenantRef.collection('modalities').doc(id),
      { name, active: true, serviceIds, createdAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
  console.log(`✓ ${MODALIDADES.length} modalidades`);
}

if (escolhidas.includes('planos')) {
  for (const [id, name, price, description, servicos] of PLANOS) {
    await tenantRef.collection('plans').doc(id).set(
      {
        name,
        description,
        currentPrice: price,
        currency: 'EUR',
        active: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const batch = firestore.batch();
    for (const [serviceId, regra] of servicos) {
      batch.set(
        tenantRef.collection('plans').doc(id).collection('services').doc(serviceId),
        {
          serviceId,
          enabled: true,
          usage:
            regra === null
              ? { type: 'unlimited' }
              : { type: 'limited', limit: regra[0], period: regra[1] },
        },
        { merge: true },
      );
    }
    await batch.commit();
    console.log(`✓ plano "${name}" — ${price.toFixed(2)} € (${servicos.length} serviço(s))`);
  }
}

// ------------------------------------------------- plano de treino

if (trainingPlanFor) {
  const found = await tenantRef
    .collection('members')
    .where('memberNumber', '==', trainingPlanFor)
    .limit(1)
    .get();

  if (found.empty) {
    console.error(`Não existe nenhum sócio nº ${trainingPlanFor} neste tenant.`);
    process.exit(1);
  }

  const memberId = found.docs[0].id;
  const memberName = found.docs[0].get('name');

  // O histórico de cargas regista QUEM prescreveu. Sem um instrutor
  // real, ficava um id inventado a aparecer na app — mais vale usar o
  // primeiro membro do staff que exista.
  const staff = await tenantRef.collection('staff').limit(1).get();
  const recordedBy = staff.empty ? 'seed-content' : staff.docs[0].id;

  const memberRef = tenantRef.collection('members').doc(memberId);

  for (const [posicao, treino] of TREINOS.entries()) {
    await memberRef.collection('workouts').doc(treino.id).set(
      {
        name: treino.nome,
        notes: treino.notas,
        position: posicao,
        active: true,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const batch = firestore.batch();
    treino.exercicios.forEach(([exercicioId, sets, reps, carga, descanso, nota], i) => {
      // Id determinístico: correr o script duas vezes atualiza a mesma
      // prescrição em vez de duplicar exercícios no plano do aluno.
      const entryId = `${treino.id}_${exercicioId}`;
      batch.set(
        memberRef.collection('planEntries').doc(entryId),
        {
          exerciseId: `ex_${exercicioId}`,
          sets,
          reps,
          currentLoad: carga,
          workoutId: treino.id,
          position: i,
          restSeconds: descanso,
          notes: nota,
        },
        { merge: true },
      );

      // UC16 — uma carga nunca existe sem a entrada de histórico
      // correspondente. Id determinístico pela mesma razão acima.
      if (carga !== null) {
        batch.set(
          memberRef.collection('loadHistory').doc(`seed_${entryId}`),
          {
            exerciseId: `ex_${exercicioId}`,
            load: carga,
            reps: Number.parseInt(reps, 10) || 0,
            recordedBy,
            recordedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    });
    await batch.commit();
    console.log(`✓ ${treino.nome} — ${treino.exercicios.length} exercícios`);
  }

  console.log(`\nPlano de treino atribuído a ${memberName} (nº ${trainingPlanFor}).`);
}

console.log('\nPronto. Tudo isto é editável pela app — Gestão › Serviços / Planos, e a biblioteca de exercícios.');
