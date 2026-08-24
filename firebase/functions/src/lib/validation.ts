import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

/**
 * Validação de input com uma mensagem que uma pessoa consegue ler.
 *
 * O que estava antes, e era um problema a sério: metade das funções
 * fazia `schema.parse(...)`, que lança um `ZodError` cru. Uma exceção
 * que não é `HttpsError` chega ao cliente como **`internal` /
 * `INTERNAL`** — o utilizador carrega em "Criar conta" sem preencher um
 * campo e recebe "erro interno", que não diz o que fazer nem sugere que
 * a culpa não é da app. A outra metade fazia `safeParse` e devolvia
 * `parsed.error.message`, que é o JSON do erro do zod: um bloco de
 * `[{"code":"too_small","path":["name"],...}]` despejado no ecrã.
 *
 * Aqui a mensagem passa a ser em português e a dizer QUE campo falta,
 * porque é a única coisa acionável. Os `details` levam os nomes dos
 * campos para a app poder, se quiser, marcá-los no formulário.
 *
 * A validação do lado do cliente continua a ser a primeira linha (é ela
 * que evita a ida ao servidor); isto é a rede que apanha o resto —
 * pedidos fora da app, versões antigas, e os casos que o formulário não
 * cobre.
 */

/** Nomes de campo como aparecem nos formulários. */
const FIELD_LABELS: Record<string, string> = {
  name: 'nome',
  email: 'email',
  phone: 'telefone',
  birthDate: 'data de nascimento',
  address: 'morada',
  nif: 'NIF',
  emergencyContact: 'contacto de emergência',
  roles: 'papéis (Instrutor/Gestor)',
  memberId: 'aluno',
  staffId: 'membro do staff',
  userId: 'utilizador',
  planId: 'plano',
  serviceId: 'serviço',
  occurrenceId: 'sessão',
  subscriptionId: 'subscrição',
  weekId: 'semana',
  slotId: 'horário',
  exerciseId: 'exercício',
  capacity: 'lotação',
  startAt: 'início',
  endAt: 'fim',
  title: 'título',
  body: 'mensagem',
  status: 'estado',
  confirmMemberNumber: 'número de sócio de confirmação',
};

function labelFor(path: (string | number)[]): string {
  const field = path.find((part) => typeof part === 'string') as
    | string
    | undefined;
  if (!field) return 'os dados enviados';
  return FIELD_LABELS[field] ?? field;
}

/** Uma frase por tipo de problema, em vez do JSON do zod. */
function describe(issue: z.ZodIssue): string {
  const label = labelFor(issue.path);

  // Campo em falta ou vazio — de longe o caso mais comum, e o único
  // que o utilizador resolve sozinho.
  if (
    issue.code === 'invalid_type' &&
    (issue.received === 'undefined' || issue.received === 'null')
  ) {
    return `Falta preencher: ${label}.`;
  }
  if (issue.code === 'too_small') {
    return issue.type === 'array'
      ? `Escolhe pelo menos um: ${label}.`
      : `Falta preencher: ${label}.`;
  }
  if (issue.code === 'invalid_string' && issue.validation === 'email') {
    return 'O email não tem um formato válido.';
  }
  if (issue.code === 'too_big') {
    return `Valor demasiado grande em: ${label}.`;
  }
  return `Valor inválido em: ${label}.`;
}

export function parseInput<Schema extends z.ZodTypeAny>(
  schema: Schema,
  data: unknown,
): z.infer<Schema> {
  const parsed = schema.safeParse(data ?? {});
  if (parsed.success) return parsed.data;

  // Uma frase por problema, sem repetir a mesma duas vezes (dois
  // campos em falta dão duas frases; o mesmo campo com dois problemas
  // dá uma).
  const messages = [...new Set(parsed.error.issues.map(describe))];
  const fields = [
    ...new Set(
      parsed.error.issues
        .map((issue) => issue.path.find((p) => typeof p === 'string'))
        .filter((field): field is string => typeof field === 'string'),
    ),
  ];

  throw new HttpsError('invalid-argument', messages.join(' '), {
    reason: 'invalid-input',
    fields,
  });
}

/**
 * Traduz as falhas do Firebase Auth que acontecem a criar ou a repor
 * contas.
 *
 * Sem isto, criar um instrutor com um email que já existe devolvia
 * `internal` — o utilizador via "erro interno" quando o que se passava
 * era uma coisa que ele percebe e resolve num segundo.
 */
export function rethrowAuthError(error: unknown): never {
  const code = (error as { code?: string })?.code ?? '';

  switch (code) {
    case 'auth/email-already-exists':
      throw new HttpsError(
        'already-exists',
        'Já existe uma conta com este email. Usa outro, ou procura a '
          + 'pessoa na lista de utilizadores.',
        { reason: 'email-already-exists', fields: ['email'] },
      );
    case 'auth/invalid-email':
      throw new HttpsError(
        'invalid-argument',
        'O email não tem um formato válido.',
        { reason: 'invalid-email', fields: ['email'] },
      );
    case 'auth/invalid-password':
    case 'auth/weak-password':
      throw new HttpsError(
        'invalid-argument',
        'A palavra-passe gerada não foi aceite. Tenta outra vez.',
        { reason: 'invalid-password' },
      );
    case 'auth/user-not-found':
      throw new HttpsError(
        'not-found',
        'Esta conta já não existe no sistema de autenticação.',
        { reason: 'user-not-found' },
      );
    case 'auth/too-many-requests':
      throw new HttpsError(
        'resource-exhausted',
        'Demasiadas tentativas seguidas. Espera um momento e tenta outra '
          + 'vez.',
        { reason: 'too-many-requests' },
      );
    default:
      throw error;
  }
}
