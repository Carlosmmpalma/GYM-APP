import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/modality.dart';

Modality _modality({
  bool active = true,
  Set<String> serviceIds = const {},
}) {
  return Modality(
    id: 'modality_1',
    name: 'Pilates',
    active: active,
    serviceIds: serviceIds,
  );
}

void main() {
  group('Equatable', () {
    test('duas modalidades com os mesmos campos são iguais', () {
      expect(
        _modality(serviceIds: const {'service_1'}),
        equals(_modality(serviceIds: const {'service_1'})),
      );
    });

    test('serviceIds diferentes tornam-as diferentes', () {
      expect(
        _modality(serviceIds: const {'service_1'}),
        isNot(equals(_modality(serviceIds: const {'service_2'}))),
      );
    });

    test('active diferente torna-as diferentes', () {
      expect(
        _modality(active: true),
        isNot(equals(_modality(active: false))),
      );
    });
  });

  test('serviceIds vazio por omissão', () {
    const modality = Modality(id: 'm', name: 'Hyrox', active: true);
    expect(modality.serviceIds, isEmpty);
  });
}
