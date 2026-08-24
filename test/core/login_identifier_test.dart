import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/config/login_identifier.dart';

void main() {
  test('gera o mesmo email para o mesmo (tenantId, número), sempre', () {
    final a = buildSyntheticEmail(tenantId: 'nxt', memberNumber: '000123');
    final b = buildSyntheticEmail(tenantId: 'nxt', memberNumber: '000123');
    expect(a, b);
  });

  test('normaliza maiúsculas/espaços', () {
    final a = buildSyntheticEmail(tenantId: 'NXT ', memberNumber: ' 000123');
    expect(a, 'member-000123@nxt.gymsaas.internal');
  });

  test('tenants diferentes geram emails diferentes para o mesmo número', () {
    final a = buildSyntheticEmail(tenantId: 'nxt', memberNumber: '000001');
    final b =
        buildSyntheticEmail(tenantId: 'outro_ginasio', memberNumber: '000001');
    expect(a, isNot(b));
  });

  // ------------------------------------------------------------------
  // Regressão. O `tenantId` real é `nxt_performance_studio`, e o
  // underscore ia parar ao lado direito do `@`. O emulador de Auth
  // aceitava; o Firebase Auth real recusou com `auth/invalid-email` —
  // ou seja, em produção nenhum aluno era criado nem conseguia entrar.
  //
  // Os testes acima não apanhavam porque usavam o tenant `nxt`, que
  // por acaso já era um rótulo de domínio válido. Estes usam o id a
  // sério.
  // ------------------------------------------------------------------

  test('o domínio nunca leva caracteres inválidos (tenant real)', () {
    final email = buildSyntheticEmail(
      tenantId: 'nxt_performance_studio',
      memberNumber: '000001',
    );
    expect(email, 'member-000001@nxt-performance-studio.gymsaas.internal');
  });

  test('qualquer tenantId produz um email que o Firebase Auth aceita', () {
    // Só letras, dígitos e hífenes de cada lado dos pontos, sem hífen
    // no início nem no fim de nenhum rótulo — as regras que o Auth
    // aplica ao domínio.
    final valido = RegExp(
      r'^member-[a-z0-9]+@[a-z0-9]([a-z0-9-]*[a-z0-9])?'
      r'\.gymsaas\.internal$',
    );

    for (final tenantId in [
      'nxt_performance_studio',
      'Ginásio__do_Bairro',
      '  espacos  ',
      '_a_',
      'já-válido',
      '',
    ]) {
      final email = buildSyntheticEmail(
        tenantId: tenantId,
        memberNumber: '000001',
      );
      expect(
        valido.hasMatch(email),
        isTrue,
        reason: 'tenantId "$tenantId" gerou um email inválido: $email',
      );
    }
  });
}
