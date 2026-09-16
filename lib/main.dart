import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';
import 'settings.dart';
import 'shell.dart';
import 'sounds.dart';
import 'theme.dart';
import 'ui/home.dart';
import 'ui/pressable.dart';
import 'win32.dart';

const kWindowSize = Size(380, 700);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  systemReducedMotion = !systemAnimationsEnabled();
  trackKeyboardMode();

  final c = VigilController(
    power: PowerRequest(),
    sounds: Sounds(),
    store: SettingsStore.appData(),
    autostartService: Autostart(),
  )..load();
  final shell = Shell(c);

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: kWindowSize,
      minimumSize: kWindowSize,
      maximumSize: kWindowSize,
      center: true,
      title: 'Vigilia',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: C.base,
    ),
  );
  await windowManager.setResizable(false);
  await windowManager.setMaximizable(false);

  runApp(VigiliaApp(c: c, shell: shell));
  await shell.init(hidden: args.contains('--hidden'));
}

class VigiliaApp extends StatelessWidget {
  const VigiliaApp({super.key, required this.c, required this.shell});

  final VigilController c;
  final Shell shell;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Vigilia',
      color: C.accent,
      debugShowCheckedModeBanner: false,
      textStyle: mono(12),
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: shell.visible,
        // окно скрыто — анимации на паузе, CPU не тратится
        builder: (context, visible, child) => TickerMode(enabled: visible, child: child!),
        child: Home(c: c, onHide: shell.hide),
      ),
    );
  }
}
