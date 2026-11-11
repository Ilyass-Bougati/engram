import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'auth/session.dart';
import 'auth/token_store.dart';
import 'preferences.dart';
import 'reminders/notifier.dart';
import 'reminders/reminders.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [
      ('IBM Plex Sans', 'OFL-IBMPlexSans.txt'),
      ('IBM Plex Mono', 'OFL-IBMPlexMono.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  final preferences = await Preferences.load();
  final session = SessionController(preferences: preferences, tokensFor: SecureTokenStore.new);
  final reminders = Reminders(
    preferences: preferences,
    scheduler: await _notifications(),
    device: await _deviceLocation(),
  );
  runApp(EngramApp(session: session, preferences: preferences, reminders: reminders));
  await session.start();
}

Future<LocalNotificationScheduler> _notifications() async {
  final scheduler = LocalNotificationScheduler();
  await scheduler.initialize();
  return scheduler;
}

/// The phone's timezone, which reminder times are in.
Future<tz.Location> _deviceLocation() async {
  tz_data.initializeTimeZones();
  try {
    final location = tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier);
    tz.setLocalLocation(location);
    return location;
  } on Object {
    return tz.UTC;
  }
}
