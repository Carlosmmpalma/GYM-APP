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
}
