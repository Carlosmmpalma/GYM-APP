import 'core/bootstrap/bootstrap.dart';
import 'core/config/environment.dart';

/// Corre com:
///   flutter run -t lib/main_production.dart
Future<void> main() async {
  await bootstrap(Environment.production);
}
