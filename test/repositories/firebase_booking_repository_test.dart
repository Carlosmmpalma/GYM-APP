// Fase 2 — testava `FirebaseBookingRepository.createBooking`/
// `cancelBooking` como transações Firestore client-side, diretamente
// contra `FakeFirebaseFirestore`.
//
// Fase 4: essa lógica (elegibilidade, limite semanal, concorrência na
// última vaga, isExtra) migrou para Cloud Functions
// (`firebase/functions/src/createBooking.ts`/`cancelBooking.ts`, Admin
// SDK — ver nota de arquitetura em `firebase_booking_repository.dart`).
// `FirebaseBookingRepository` passou a ser um wrapper fino sobre
// `cloud_functions` (`httpsCallable(...).call(...)`); testá-lo aqui
// exigiria mockar `HttpsCallable`/`HttpsCallableResult` com mocktail
// sem forma de confirmar a forma exata dessa API sem correr Flutter a
// sério — o mesmo risco já documentado no README para
// `AssignSubscriptionScreen`/`ManagerScreen` (Fase 3).
//
// Os testes de comportamento do ECRÃ (reage bem a sucesso/erro) continuam
// cobertos em `test/presentation/book_training_screen_test.dart` e
// `test/presentation/my_bookings_screen_test.dart`, através de um fake
// de `BookingRepository` que simula, diretamente no
// `FakeFirebaseFirestore` do teste, o que a Cloud Function faria — não
// através deste ficheiro.
//
// A lógica de NEGÓCIO da Cloud Function em si (limite semanal,
// concorrência, devolução de usage na janela de antecedência) fica
// como lacuna real, sinalizada no README ("Fase 4 — Ainda em aberto"):
// precisaria de testes TypeScript contra o Firebase Functions Emulator
// (não montado neste projeto — só o Firestore Emulator tem testes de
// Rules hoje, em `firebase/tests`).
void main() {}
