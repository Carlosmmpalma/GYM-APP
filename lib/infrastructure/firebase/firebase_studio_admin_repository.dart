import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/studio_info.dart';
import '../../repositories/studio_admin_repository.dart';

class FirebaseStudioAdminRepository implements StudioAdminRepository {
  FirebaseStudioAdminRepository(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<void> updateStudioInfo(StudioInfo info) async {
    await _functions.httpsCallable('updateStudioInfo').call<void>({
      'address': info.address,
      'phone': info.phone,
      'email': info.email,
      'mapsUrl': info.mapsUrl,
      'privacyPolicyUrl': info.privacyPolicyUrl,
      'openingHours': [
        for (final linha in info.openingHours)
          {'days': linha.days, 'hours': linha.hours},
      ],
    });
  }
}
