import 'package:equatable/equatable.dart';

/// Entidade de domínio mínima, usada apenas para validar a fatia vertical
/// "hello world" da Fase 0 (guia-desenvolvimento.md): confirma que a app
/// consegue escrever e depois ler um documento no Firestore (emulado ou
/// real, dependendo do ambiente).
///
/// Isto não é uma entidade de negócio — o domínio real começa na Fase 1/2
/// com Tenant, GymMember, Booking, etc. (ver Technical/Domain Model v1).
class PingResult extends Equatable {
  const PingResult({
    required this.id,
    required this.message,
    required this.recordedAt,
  });

  final String id;
  final String message;
  final DateTime recordedAt;

  @override
  List<Object?> get props => [id, message, recordedAt];
}
