import 'package:equatable/equatable.dart';

/// Tenant — o limite fundamental de isolamento de dados (Domain Model v1
/// §3, Platform Foundation §6-7).
///
/// Config mínima da Fase 1. Branding/planos/regras completos ficam para
/// quando os respetivos ecrãs existirem (Fase 3+).
class Tenant extends Equatable {
  const Tenant({
    required this.id,
    required this.name,
    required this.timezone,
    required this.status,
  });

  final String id;
  final String name;
  final String timezone;
  final TenantStatus status;

  @override
  List<Object?> get props => [id, name, timezone, status];
}

enum TenantStatus { active, suspended }
