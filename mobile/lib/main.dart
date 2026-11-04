import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'auth/session.dart';
import 'auth/token_store.dart';
import 'preferences.dart';

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
  runApp(EngramApp(session: session, preferences: preferences));
  await session.start();
}
