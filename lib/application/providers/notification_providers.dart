import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_user.dart';
import 'admin_providers.dart';
import 'firebase_providers.dart';
import 'plan_providers.dart';

/// Fase 6 (UC21) — regista o token de FCM deste dispositivo no
/// documento do utilizador autenticado (`members/{uid}.fcmTokens` ou
/// `staff/{uid}.fcmTokens`, consoante o role). `.family` por [AppUser]
/// (Equatable) para correr uma única vez por sessão de login — não
/// `autoDispose`, o registo deve sobreviver a navegação entre ecrãs.
///
/// Falha SEMPRE em silêncio (try/catch amplo): sem uma VAPID key (Web
/// push) ou certificado APNs (iOS) configurados na Firebase Console —
/// passo que não é feito por código, ver `app/README.md` — `getToken()`
/// lança ou devolve `null`. Isso não pode impedir o login nem aparecer
/// como erro ao utilizador; só significa que este dispositivo não vai
/// receber notificações push até essa configuração existir.
final fcmTokenRegistrationProvider =
    FutureProvider.family<void, AppUser>((ref, appUser) async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token == null) return;

    if (appUser.isMember) {
      await ref
          .read(memberRepositoryProvider)
          .registerFcmToken(memberId: appUser.uid, token: token);
    } else {
      await ref
          .read(staffRepositoryProvider)
          .registerFcmToken(staffId: appUser.uid, token: token);
    }
  } catch (_) {
    // Sinalizado na documentação da classe — não é um erro fatal.
  }
});

/// Cloud Function `sendNotification` — envia para um membro específico
/// OU para todos os inscritos ativos numa ocorrência (exatamente um dos
/// dois). Devolve quantos tokens receberam a notificação com sucesso.
final sendNotificationUseCaseProvider =
    Provider<SendNotificationUseCase>((ref) {
  return SendNotificationUseCase(ref.watch(functionsProvider));
});

class SendNotificationUseCase {
  SendNotificationUseCase(this._functions);

  final FirebaseFunctions _functions;

  Future<({int sent, int targets})> call({
    required String title,
    required String body,
    String? memberId,
    String? occurrenceId,
  }) async {
    final result =
        await _functions.httpsCallable('sendNotification').call<Object?>({
      'title': title,
      'body': body,
      if (memberId != null) 'memberId': memberId,
      if (occurrenceId != null) 'occurrenceId': occurrenceId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      sent: (data['sent'] as num? ?? 0).toInt(),
      targets: (data['targets'] as num? ?? 0).toInt(),
    );
  }
}
