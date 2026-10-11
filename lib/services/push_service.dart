import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';

/// Runs when a push arrives while the app is closed or in the background.
/// The phone itself shows the notification (the server sends a title and text),
/// so nothing has to be drawn here. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Push notifications (also when the app is closed).
///
///  * `init()`        once, at start-up, in main()
///  * `register()`    after a person is logged in: saves this phone against them
///  * `unregister()`  just BEFORE logging out, so the next person who uses the
///                    same phone never gets the previous person's alerts
///
/// Every alert in the app is a row in `notifications`; the database sends each
/// new row to the `send-push` function, which sends it to the person's phones.
/// Everything here is safe to call even if push is not set up yet: it just does
/// nothing.
class PushService {
  PushService._();

  static bool _ready = false;
  static String? _token;
  static StreamSubscription<String>? _refreshSub;

  // Android notification channels. The server names one of these for every
  // message; geofence and emergency alerts are the loudest.
  static const _channels = <(String, String, String, Importance)>[
    ('geofence_alerts', 'Bus alerts', 'Your bus comes near or leaves your stop', Importance.max),
    ('emergency_alerts', 'Emergency alerts', 'SOS and breakdown alerts', Importance.max),
    ('general_alerts', 'Updates', 'Trip, request and complaint updates', Importance.high),
    ('announcements', 'Announcements', 'Announcements from your institution', Importance.high),
  ];

  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        final android = FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        for (final c in _channels) {
          await android?.createNotificationChannel(AndroidNotificationChannel(
            c.$1,
            c.$2,
            description: c.$3,
            importance: c.$4,
            playSound: true,
            enableVibration: true,
          ));
        }
      }
      _ready = true;
    } catch (e) {
      debugPrint('Push is not set up yet, skipped: $e');
    }
  }

  static Future<void> register() async {
    if (!_ready) return;
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    try {
      final perm = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? dotenv.env['FCM_VAPID_KEY'] : null,
      );
      if (token == null || token.isEmpty) return;
      _token = token;
      await sb.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });

      // Firebase sometimes gives the phone a new token: keep it up to date
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        _token = t;
        try {
          await Supabase.instance.client.rpc('register_device_token', params: {
            'p_token': t,
            'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          });
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  /// Call BEFORE signing out (it needs the login to remove this phone).
  static Future<void> unregister() async {
    if (!_ready) return;
    final t = _token;
    try {
      if (t != null) {
        await Supabase.instance.client
            .rpc('unregister_device_token', params: {'p_token': t});
      }
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken(); // next login gets a fresh one
    } catch (_) {}
    _token = null;
  }
}