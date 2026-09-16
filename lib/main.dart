import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'controller.dart';
import 'native.dart';
import 'settings.dart';
import 'shell.dart';
import 'sounds.dart';
import 'theme.dart';
import 'ui/home.dart';
import 'ui/motion.dart';
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
    registerHotkey: Native.setHotkey,
  )..load();
  final shell = Shell(c);

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
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

class VigiliaApp extends StatefulWidget {
  const VigiliaApp({super.key, required this.c, required this.shell});

  final VigilController c;
  final Shell shell;

  @override
  State<VigiliaApp> createState() => _VigiliaAppState();
}

class _VigiliaAppState extends State<VigiliaApp> {
  final _ui = UiState();

  @override
  void initState() {
    super.initState();
    // стартовый каскад играет один раз; при смене цвета/языка экран появляется без него
    Future.delayed(const Duration(milliseconds: 1200), Cascade.finishIntro);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return WidgetsApp(
      title: 'Vigilia',
      color: accentPresets.first,
      debugShowCheckedModeBanner: false,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: widget.shell.visible,
        // окно скрыто — анимации на паузе, CPU не тратится
        builder: (context, visible, child) => TickerMode(enabled: visible, child: child!),
        child: VigiliaScreen(c: c, ui: _ui, onHide: widget.shell.hide),
      ),
    );
  }
}
