// Entry point por omissão (usado por `flutter run` sem -t, e por alguns
// plugins de IDE que assumem lib/main.dart). Redireciona para o ambiente
// de development — nunca uses este ficheiro para correr staging/production.
import 'main_development.dart' as development_entry_point;

Future<void> main() async {
  await development_entry_point.main();
}
