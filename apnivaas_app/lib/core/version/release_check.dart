library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/failure.dart';
import '../../data/providers.dart' show supabaseClientProvider;
import 'app_release.dart';

/// READING THE PUBLISHED RELEASE, AND DECIDING WHETHER TO SAY ANYTHING ABOUT IT.
///
/// The read is one row of `public.app_releases` (see db/migrations/2026-09-02-app-releases.sql).
/// The decision is [decideUpdate], which lives in app_release.dart and touches no I/O.
///
/// ═══ WHY THE READ DOES NOT GO THROUGH lib/data/repositories ═══
///
/// Every other repository in this app answers a question about a TENANT: this hostel's rooms,
/// this resident's rent. They all extend `Repository`, and several of them call
/// `requireLiveSession()` first, because their nulls are read as facts about the caller. None
/// of that applies here. This row is public — `app_releases_select` is `using (true)` and
/// `anon` holds SELECT — and the answer is identical for every reader. Putting it in the
/// tenant data layer would invite the next person to add a hostel filter to it.
///
/// ═══ AND WHY IT DELIBERATELY WORKS WITH A DEAD SESSION ═══
///
/// When the access token has expired, supabase_flutter does not fail: it signs the request
/// with the anon key instead (core/auth/session_standing.dart). For every OTHER read in this
/// app that is a hazard, which is what SessionStanding exists to contain. Here it is the
/// feature. A phone whose session broke in a way a new build fixes is exactly the phone that
/// must still be able to learn a new build exists, so this read must not require a live
/// session — and because `anon` may SELECT this row, it does not.

/// The one row, or null when nothing has been published for this channel.
final class AppReleaseRepository {
  const AppReleaseRepository(this.db);

  final SupabaseClient db;

  /// The current Android release.
  ///
  /// `guard` gives it the same 12s [dataDeadline] every read in this app gets, and converts
  /// anything it throws into an [AppFailure]. Nothing here retries: an update check that
  /// cannot reach the server is not urgent, and the next cold start asks again.
  Future<AppRelease?> current() => guard(() async {
        final row = await db
            .from('app_releases')
            .select(AppRelease.columns)
            .eq('channel', 'android')
            .maybeSingle();
        // Null means the manifest row is missing — a database that has not had the migration
        // applied, not a statement about this reader. UpdateStatus.unknown, banner absent.
        return row == null ? null : AppRelease.fromJson(row);
      });
}

final appReleaseRepositoryProvider = Provider<AppReleaseRepository>(
  (ref) => AppReleaseRepository(ref.watch(supabaseClientProvider)),
);

/// Which build is running. A provider purely so a test can put another build in its place —
/// the real value is a compile-time constant read from the build (see [InstalledBuild]).
final installedBuildProvider = Provider<InstalledBuild>((ref) => InstalledBuild.current);

/// The published release, fetched ONCE per cold start.
///
/// NOT `autoDispose`, on purpose, and the purpose is the whole lifetime policy of this
/// provider. The banner mounts and unmounts as the user moves between role shells; an
/// autoDispose provider would re-run the query every time the last listener went away and came
/// back, which turns "check for updates on launch" into "check for updates on every
/// navigation". Held for the ProviderScope's life, this is one round trip per app launch.
///
/// A person who wants a fresher answer than that has one: the Check again button in the update
/// sheet calls `ref.invalidate` on this provider.
final latestReleaseProvider = FutureProvider<AppRelease?>((ref) async {
  return ref.watch(appReleaseRepositoryProvider).current();
});

/// What to draw, if anything.
///
/// LOADING AND FAILED BOTH COLLAPSE TO [UpdateStatus.unknown], and that is not the four-states
/// rule being fudged. A failed update check is not a failed SCREEN: nothing the user asked for
/// is missing, nothing is half-drawn, and there is no useful action to offer. Putting "could
/// not check for updates" across the top of the dashboard would be an error message about a
/// question nobody asked. The check simply runs again on the next launch.
final updateStatusProvider = Provider<UpdateStatus>((ref) {
  final release = ref.watch(latestReleaseProvider).value;
  return decideUpdate(ref.watch(installedBuildProvider), release);
});

/// The version code the user has waved away, for this run of the app.
///
/// ═══ IT IS DELIBERATELY NOT PERSISTED ═══
///
/// Dismissing hides the banner until the app is next started cold. Two reasons it is not
/// written to disk. First, honesty about cost: persisting it would need a preferences plugin
/// this project does not carry, and the value is one integer whose worst outcome is a banner
/// somebody has already learned to ignore. Second, and more important, a persisted dismissal
/// is a decision made once that keeps applying to builds it was never about — the person who
/// dismissed 1.0.1 in March has said nothing about 1.4.0 in June. Keyed by version code and
/// dropped at every launch, the nag is quiet within a session and honest across them.
///
/// A MANDATORY RELEASE IGNORES THIS ENTIRELY — see [UpdateBanner]. `mandatory` means the old
/// build gets something wrong, and a dismiss button on that is a dismiss button on the fix.
class UpdateDismissal extends Notifier<int?> {
  @override
  int? build() => null;

  void dismiss(int versionCode) => state = versionCode;

  /// True when this exact release is the one already waved away. Keyed by version code so
  /// publishing a NEWER build brings the banner back on its own, with nothing to reset.
  bool isDismissed(int versionCode) => state == versionCode;
}

final updateDismissalProvider =
    NotifierProvider<UpdateDismissal, int?>(UpdateDismissal.new);

/// Where a person goes to get the APK: the public install page on the web app, which explains
/// Android's "unknown sources" step that the raw download link cannot.
///
/// THE PAGE, NOT THE BINARY, is what the app hands out. The download URL in the manifest row
/// points straight at a 60-odd MB file; a person who taps that with no context gets a browser
/// warning, an "unsafe file" prompt and no idea what to do next — which is the failure the
/// install page exists to prevent. The page carries the same link plus the four sentences that
/// make it work.
///
/// Override per build:
///   flutter build apk --dart-define=INSTALL_PAGE_URL=https://…/install
const installPageUrl = String.fromEnvironment(
  'INSTALL_PAGE_URL',
  defaultValue: 'https://hostelpro-three.vercel.app/install',
);
