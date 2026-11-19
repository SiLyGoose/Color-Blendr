import 'package:material_ui/material_ui.dart';

import '../ui/home_shell.dart';
import '../ui/update_screen.dart';
import 'app_update.dart';
import 'theme.dart';

class BlendrApp extends StatelessWidget {
  const BlendrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Color Blendr',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) =>
          UpdateGate(lockScreen: const UpdateScreen(), child: child!),
      home: const HomeShell(),
    );
  }
}
