import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/service.dart';

void main() {
  group('Service', () {
    test('exclusiveGroup é null por omissão', () {
      const service = Service(id: 'svc_1', name: 'Hyrox', active: true);
      expect(service.exclusiveGroup, isNull);
    });

    group('Equatable', () {
      test('dois serviços com os mesmos campos são iguais', () {
        const a = Service(
          id: 'svc_1',
          name: 'Sem acompanhamento',
          active: true,
          exclusiveGroup: 'sala',
        );
        const b = Service(
          id: 'svc_1',
          name: 'Sem acompanhamento',
          active: true,
          exclusiveGroup: 'sala',
        );
        expect(a, equals(b));
      });

      test('exclusiveGroup diferente torna-os diferentes (UC26 fechado)', () {
        const a = Service(
          id: 'svc_1',
          name: 'Sem acompanhamento',
          active: true,
          exclusiveGroup: 'sala',
        );
        const b = Service(
          id: 'svc_1',
          name: 'Sem acompanhamento',
          active: true,
          exclusiveGroup: null,
        );
        expect(a, isNot(equals(b)));
      });
    });
  });
}
