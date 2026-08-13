import 'core/bootstrap/bootstrap.dart';
import 'core/config/environment.dart';

/// Corre com:
///   flutter run -t lib/main_staging.dart
Future<void> main() async {
  await bootstrap(Environment.staging);
}
