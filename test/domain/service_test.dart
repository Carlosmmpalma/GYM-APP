import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/service.dart';

void main() {
  group('Service', () {
    // Teve um `exclusiveGroup` — uma etiqueta de texto livre que
    // declarava quais serviços eram alternativas uns dos outros, para o
    // servidor recusar dois planos incompatíveis. Desapareceu com a
    // passagem a **um plano ativo por membro**: sem dois planos ao mesmo
    // tempo não há combinações para proibir, e a proteção que interessa
    // passou para o momento de marcar (ver `lib/overlap.ts`).
    //
    // Um serviço é um id, um nome e se está ativo.
    group('Equatable', () {
      test('dois serviços com os mesmos campos são iguais', () {
        const a = Service(id: 'svc_1', name: 'Hyrox', active: true);
        const b = Service(id: 'svc_1', name: 'Hyrox', active: true);
        expect(a, equals(b));
      });

      test('nome diferente torna-os diferentes', () {
        const a = Service(id: 'svc_1', name: 'Hyrox', active: true);
        const b = Service(id: 'svc_1', name: 'Pilates', active: true);
        expect(a, isNot(equals(b)));
      });

      test('estado diferente torna-os diferentes', () {
        const a = Service(id: 'svc_1', name: 'Hyrox', active: true);
        const b = Service(id: 'svc_1', name: 'Hyrox', active: false);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
