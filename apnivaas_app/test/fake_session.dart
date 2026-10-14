// A SESSION A TEST CAN INSTALL WITHOUT A NETWORK, AND WHY ONE IS NEEDED AT ALL.
//
// Half the point of the 2026-09-01 refusal work is that an empty answer means nothing until you
// know what credential asked the question. Every assertion about that therefore needs a client
// that is holding a credential — and until now the stubbed clients in this suite held none, so
// they were all, silently, the "not signed in" case. Tests written against them proved that a
// refusal is reported for an ANONYMOUS caller, which is true and is not what they claimed.
//
// `recoverSession` is the one way in that costs no round trip: for a session whose access token
// has not expired it decodes, stores and returns (gotrue_client.dart:1257-1286, 2.27.2). It
// never reaches the Auth server, so a MockClient answering PostgREST rows to everything is not
// disturbed by it.
//
// THE TOKEN HAS TO BE A REAL JWT, not a placeholder string. `Session.expiresAt` is derived by
// base64-decoding the payload segment and reading `exp` — it does NOT come from the `expires_at`
// field of the JSON — so a fake session built with an opaque token would report a null expiry
// and land in the "cannot tell, assume live" arm, quietly hiding the very case under test.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// An unsigned JWT carrying one claim that matters: `exp`, in seconds.
///
/// Nothing verifies the signature here — gotrue's `decodeJwtPayload` deliberately does not, and
/// PostgREST is a MockClient in these tests — so a constant third segment is honest about what
/// this is rather than pretending to be cryptography.
String fakeJwt({required DateTime expiresAt, String subject = 'user-1'}) {
  String segment(Map<String, Object?> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  final header = segment(const {'alg': 'HS256', 'typ': 'JWT'});
  final payload = segment({
    'sub': subject,
    'role': 'authenticated',
    'aal': 'aal2',
    'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
  });
  return '$header.$payload.not-a-real-signature';
}

/// Puts a live session on [client], so what it sends is a credential rather than the anon key.
///
/// [validFor] is generous by default: these tests assert about a session that IS alive, and a
/// short window would make them flaky on a slow machine for a reason that has nothing to do
/// with what they are checking.
Future<void> installLiveSession(
  SupabaseClient client, {
  Duration validFor = const Duration(hours: 1),
  String subject = 'user-1',
}) async {
  final expiresAt = DateTime.now().add(validFor);
  await client.auth.recoverSession(jsonEncode({
    'access_token': fakeJwt(expiresAt: expiresAt, subject: subject),
    'token_type': 'bearer',
    'refresh_token': 'refresh-1',
    'expires_in': validFor.inSeconds,
    'user': {
      'id': subject,
      'aud': 'authenticated',
      'role': 'authenticated',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-01-01T00:00:00.000Z',
    },
  }));
}
