import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vale_engine/game/error_log.dart';
import 'package:vale_engine/theme/engine_palette.dart';

import 'ui/main_menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture every framework and platform error into the in-app log, so a
  // failure can be read on a device with no console attached. The default
  // presentation is kept as well, so debug builds still print to the console
  // and still show the red error screen.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorLog.instance.record('flutter', details.exception, details.stack);
    if (previousOnError != null) {
      previousOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorLog.instance.record('platform', error, stack);
    return true;
  };

  // Portrait is the design target: the board is square, the hand sits along
  // the foot and the game is played with one thumb. Landscape is kept for
  // desktop and the browser, where the window is always wide.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const GameApp());
}

class GameApp extends StatelessWidget {
  const GameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DomiVale',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Nunito',
        scaffoldBackgroundColor: EnginePalette.gameBackground,
        dialogTheme: DialogThemeData(
          backgroundColor: EnginePalette.dialogBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            fontFamily: 'Nunito',
            color: Color(0xFFF5ECD7),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const MainMenuScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
