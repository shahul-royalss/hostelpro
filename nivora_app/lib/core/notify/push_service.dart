library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/providers.dart';

/// THE ANDROID CHANNEL EVERY NIVORA NOTIFICATION IS POSTED TO.
///
/// It MUST match the `channel_id` supabase/functions/push-send sends, or Android 8+ drops the
/// message silently — no banner, no error, nothing in logcat naming the cause. The two are the
/// same literal on purpose; if one moves, the other has to move in the same commit.
const nivoraChannelId = 'nivora_default';

/// FCM requires a background handler to be a top-level function, and it must be annotated so
/// tree-shaking cannot remove it from the release build.
///
/// IT DELIBERATELY DOES NOTHING. push-send sends a message carrying a `notification` block, so
/// Android itself draws the banner while the app is backgrounded or dead; a handler that also
/// drew one would post it twice. This exists so FCM has somewhere to deliver the data half, and
/// so the plugin does not warn about a missing handler.
@pragma('vm:entry-point')
Future<void> nivoraBackgroundMessage(RemoteMessage message) async {}

/// PUSH, END TO END ON THE DEVICE SIDE.
///
/// ── WHAT IT DOES, IN ORDER ───────────────────────────────────────────────────────────────
///
///   1. Starts Firebase. If there is no google-services.json in the build, this throws and the
///      whole service becomes a no-op — see [start].
///   2. Creates the Android channel and initialises local notifications.
///   3. ASKS, in the system dialog, for permission to post notifications.
///   4. Registers this device's FCM token against the signed-in user (public.push_devices).
///   5. Draws a banner for messages that arrive while the app is in the FOREGROUND, which
///      Android does not do by itself.
///   6. On sign-out, gives the token back so the next person to hold this handset does not
///      receive the last person's rent reminders.
///
/// ── NOTHING HERE NAVIGATES, AND THAT IS A DECISION ───────────────────────────────────────
///
/// Every notification row carries a `link` — '/manager/tasks', '/owner/payments',
/// '/student?receipt=…'. Those are the WEB app's paths. This router registers exactly six
/// auth-flow routes plus one home per role (see appScreens), so `go('/owner/payments')` would
/// fall through to the errorBuilder and put "That page has moved" in front of somebody who
/// tapped a rent reminder. That is worse than doing nothing.
///
/// So tapping a notification opens the app, and the app's own redirect puts the person on their
/// role's home — which is where the tab carrying that item lives anyway. Jumping to the exact
/// tab is a real improvement and needs a real in-app deep-link table; it is not this.
///
/// ── FAILURE IS ALWAYS SILENT ─────────────────────────────────────────────────────────────
///
/// A phone that cannot register is a phone that does not buzz. It is not a phone that cannot
/// run the PG, and nothing in the UI waits on any of this. Every step below is wrapped, and the
/// worst outcome of all of them failing is the app behaving exactly as it did before push
/// existed.
class PushService {
  PushService(this._ref);

  final Ref _ref;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _started = false;
  String? _token;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;

  /// Whether the build has a Firebase project behind it. False on every checkout without
  /// android/app/google-services.json, which includes CI and anybody who cloned this repo.
  bool _firebaseReady = false;

  static const _channel = AndroidNotificationChannel(
    nivoraChannelId,
    'Nivora',
    description: 'Rent reminders, notices, payments and tasks.',
    importance: Importance.high,
  );

  /// Called when a session appears. Safe to call repeatedly; only the first does anything.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Not on a phone, no push. This is also what keeps every widget test out of the whole path
    // — there is no platform channel under one, and Firebase would throw on the first call.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      // THE EXPECTED PATH UNTIL SOMEBODY CREATES THE FIREBASE PROJECT. initializeApp() throws
      // when there are no default options compiled in, which is exactly the state of a build
      // with no google-services.json. Everything below is skipped and the app is unchanged.
      debugPrint('[nivora] push disabled: no Firebase configuration ($e)');
      return;
    }

    try {
      await _prepareLocal();
      await _askPermission();
      await _registerToken();

      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        unawaited(_send(token));
      });

      // FOREGROUND ONLY. Android draws the banner itself when the app is backgrounded; while
      // somebody is looking at the app it delivers the message and draws nothing, so this is
      // the one case that needs a local notification.
      _foreground = FirebaseMessaging.onMessage.listen(_showForeground);

      FirebaseMessaging.onBackgroundMessage(nivoraBackgroundMessage);
    } catch (e) {
      debugPrint('[nivora] push setup failed: $e');
    }
  }

  /// Called on sign-out.
  Future<void> stop() async {
    await _tokenRefresh?.cancel();
    await _foreground?.cancel();
    _tokenRefresh = null;
    _foreground = null;

    final token = _token;
    _token = null;
    _started = false;
    if (token == null || !_firebaseReady) return;
    try {
      await _ref.read(pushRepositoryProvider).unregisterDevice(token);
    } catch (e) {
      // The row is also pruned server-side after 90 days without a check-in, and the next
      // person to sign in on this handset takes the token over outright — register_push_device
      // reassigns it. So a failed hand-back is untidy rather than harmful.
      debugPrint('[nivora] could not release the push token: $e');
    }
  }

  Future<void> _prepareLocal() async {
    await _local.initialize(
      // NAMED `settings:` — it is positional in v19 and earlier, and this project is on v22.
      settings: const InitializationSettings(
        // The launcher icon. A missing icon here is a notification that does not appear at all
        // on some Android skins.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTapped,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// THE SYSTEM DIALOG, ASKED FOR ONCE.
  ///
  /// On Android 13+ POST_NOTIFICATIONS is a runtime permission: without it the app can hold a
  /// valid token and the server can send a perfectly good message and nothing appears, with no
  /// error anywhere. permission_handler asks on Android; FirebaseMessaging.requestPermission is
  /// what asks on iOS, where the prompt is Apple's own.
  ///
  /// A REFUSAL IS NOT AN ERROR AND DOES NOT STOP REGISTRATION. Somebody who says no today may
  /// turn notifications on in Settings tomorrow, and a token registered now is what makes that
  /// work immediately rather than after the next sign-in.
  Future<void> _askPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Permission.notification.request();
      } else {
        await FirebaseMessaging.instance.requestPermission();
      }
    } catch (e) {
      debugPrint('[nivora] notification permission request failed: $e');
    }
  }

  Future<void> _registerToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    _token = token;
    await _send(token);
  }

  Future<void> _send(String token) async {
    try {
      await _ref.read(pushRepositoryProvider).registerDevice(
            token: token,
            platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          );
    } catch (e) {
      debugPrint('[nivora] could not register this device for push: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _local.show(
        // The message id hashed into 31 bits: two notifications about different things must not
        // replace each other, and Android's id is an int.
        id: message.messageId.hashCode & 0x7fffffff,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            nivoraChannelId,
            'Nivora',
            channelDescription: 'Rent reminders, notices, payments and tasks.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: message.data['link'] as String?,
      );
    } catch (e) {
      debugPrint('[nivora] could not draw a foreground notification: $e');
    }
  }

  /// Tapping one of OUR foreground banners. See the class note: it deliberately does not
  /// navigate, because the paths these carry belong to the web app's URL space.
  void _onTapped(NotificationResponse response) {}
}

/// One per app, created lazily the first time a session appears.
final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
