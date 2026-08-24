import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/member_summary.dart';
import 'package:gym_saas/infrastructure/firebase/firebase_member_repository.dart';

/// A lista de alunos estava ordenada por nome. O número de sócio é a
/// identidade que o estúdio usa ao balcão — é por ele que se procura
/// alguém — e a ordem alfabética escondia-a.
///
/// Também tornava visível um problema que ninguém quer numa lista:
/// nomes que acabam em número ordenam "Aluno 10" antes de "Aluno 2", o
/// que parece simplesmente partido.
void main() {
  MemberSummary member(String number, String name) => MemberSummary(
        uid: 'uid_$number',
        memberNumber: number,
        name: name,
        active: true,
      );

  List<String> ordered(List<MemberSummary> members) =>
      (members.toList()..sort(compareMembersByNumber))
          .map((m) => m.memberNumber)
          .toList();

  test('ordena por número de sócio, não por nome', () {
    final result = ordered([
      member('000003', 'Ana'),
      member('000001', 'Zulmira'),
      member('000002', 'Bruno'),
    ]);
    expect(result, ['000001', '000002', '000003']);
  });

  test('compara como número, não como texto', () {
    // O caso que a comparação de strings falhava: sem os zeros à
    // esquerda, "1000" vinha antes de "999". Os números criados pela
    // app vêm preenchidos, mas nada obriga a que todos venham — basta
    // um registo importado ou escrito à mão para desalinhar a lista.
    final result = ordered([
      member('1000', 'A'),
      member('999', 'B'),
      member('99', 'C'),
    ]);
    expect(result, ['99', '999', '1000']);
  });

  test('os de teste (9xxxxx) ficam depois dos sócios reais', () {
    final result = ordered([
      member('900001', 'Aluno Teste 1'),
      member('000002', 'Bruno'),
      member('900010', 'Aluno Teste 10'),
      member('900002', 'Aluno Teste 2'),
    ]);
    expect(result, ['000002', '900001', '900002', '900010']);
  });

  test('sem número vai para o fim, por nome, em vez de se misturar', () {
    final result = (<MemberSummary>[
      member('', 'Zulmira'),
      member('000005', 'Ana'),
      member('', 'Bruno'),
    ].toList()
          ..sort(compareMembersByNumber))
        .map((m) => m.name)
        .toList();
    expect(result, ['Ana', 'Bruno', 'Zulmira']);
  });

  test('acentos não mandam ninguém para o fim do alfabeto', () {
    // Desempate por nome, quando o número não decide.
    final result = (<MemberSummary>[
      member('', 'Bruno'),
      member('', 'Álvaro'),
    ].toList()
          ..sort(compareMembersByNumber))
        .map((m) => m.name)
        .toList();
    expect(result, ['Álvaro', 'Bruno']);
  });
}
