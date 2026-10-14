// A CONSENT STORE A TEST CAN INSTALL WITHOUT A NETWORK.
//
// ConsentGate wraps every role home in the router's table (core/router/router.dart), so from
// the moment it exists, ANY test that drives the real router into a signed-in destination is
// also exercising a consent check. Without a stand-in that check reaches for a live Supabase
// client and the shell under test never draws — which is exactly what happened to the five
// "lands in their own shell" tests in role_routing_test.dart the moment the gate landed.
//
// The default is ACCEPTED, because that is the precondition those tests were always implicitly
// asserting under: a user who is already through the door. A test that wants the gate itself
// asks for it explicitly with `FakeConsentStore.notAccepted()`.
//
// IT HOLDS A SET OF VERSIONS, NOT A BOOLEAN. That is what makes "when the documents change,
// consent is asked again" a testable claim rather than a comment: a store that has accepted
// '2020-01-01' and nothing else is a real user of a real earlier build, and the gate must put
// the documents back in front of them.
library;

import 'package:mobile/features/legal/legal_documents.dart';
import 'package:mobile/features/legal/legal_repository.dart';

class FakeConsentStore implements LegalConsentStore {
  FakeConsentStore({Set<String>? acceptedVersions, this.readError, this.writeError})
      : _accepted = {...?acceptedVersions};

  /// Somebody who has already agreed to the version this build ships.
  factory FakeConsentStore.accepted() =>
      FakeConsentStore(acceptedVersions: {kLegalVersion});

  /// Somebody who has never agreed to anything — the first-run case.
  factory FakeConsentStore.notAccepted() => FakeConsentStore();

  /// Somebody who agreed to an EARLIER version and has not seen this one.
  factory FakeConsentStore.acceptedOnly(String version) =>
      FakeConsentStore(acceptedVersions: {version});

  /// The check itself fails. [error] is what [acceptedAt] throws.
  factory FakeConsentStore.failing(Object error) => FakeConsentStore(readError: error);

  final Set<String> _accepted;
  final Object? readError;
  final Object? writeError;

  int reads = 0;
  int writes = 0;
  final List<String> versionsRead = [];
  String? lastVersionWritten;
  String? lastSurface;

  static final _stamp = DateTime.utc(2026, 9, 2, 10);

  @override
  Future<DateTime?> acceptedAt({
    required String userId,
    String version = kLegalVersion,
  }) async {
    reads++;
    versionsRead.add(version);
    if (readError != null) throw readError!;
    return _accepted.contains(version) ? _stamp : null;
  }

  @override
  Future<DateTime> accept({
    required String version,
    required String surface,
    String? appVersion,
  }) async {
    writes++;
    lastVersionWritten = version;
    lastSurface = surface;
    if (writeError != null) throw writeError!;
    // Mirrors the server: the acceptance becomes readable the moment it is written, so a
    // provider invalidated after a successful accept finds it.
    _accepted.add(version);
    return _stamp;
  }
}
