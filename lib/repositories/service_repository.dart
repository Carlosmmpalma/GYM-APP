import '../domain/entities/service.dart';

abstract class ServiceRepository {
  Future<List<Service>> getActiveServices();
}
