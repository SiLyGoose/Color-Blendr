import 'package:material_ui/material_ui.dart';

import '../ui/home_shell.dart';
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
      home: const HomeShell(),
    );
  }
}
