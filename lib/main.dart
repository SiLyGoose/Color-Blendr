import 'package:color_blendr/components/blendrAppBar.dart';
import 'package:color_blendr/components/blendrDrawer.dart';
import 'package:color_blendr/components/blendrNavigationBar.dart';
import 'package:color_blendr/pages/base/accountBasePage.dart';
import 'package:color_blendr/pages/base/basePage.dart';
import 'package:color_blendr/pages/base/paletteBasePage.dart';
import 'package:color_blendr/pages/gradient.dart';
import 'package:color_blendr/pages/libary.dart';
import 'package:color_blendr/pages/palette.dart';
import 'package:color_blendr/pages/user/profile.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Color Blendr',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomeState();
}

class HomeState extends State<HomePage> {
  // page identifier (refer to _widgetOptions)
  int _selectedPageIndex = 0;

  // used to identify and access current state of drawer
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<PaletteBasePageState> _paletteKey =
      GlobalKey<PaletteBasePageState>();
  final GlobalKey<BasePageState> _libraryKey = GlobalKey<BasePageState>();
  final GlobalKey<AccountBasePageState> _profileKey =
      GlobalKey<AccountBasePageState>();

  // app body
  final Map<String, Widget> _widgetOptions = {};

  HomeState() {
    _initWidgetOptions();
  }

  void _initWidgetOptions() {
    _widgetOptions["Palette"] = PalettePage(key: _paletteKey);
    _widgetOptions["Gradient"] = GradientPage(key: _paletteKey);
    _widgetOptions["Library"] = LibraryPage(key: _libraryKey);
    _widgetOptions["Profile"] = ProfilePage(key: _profileKey);
  }

  void onPageSelect(int index) {
    setState(() {
      // changed page index and updates body accordingly
      _selectedPageIndex = index;
    });
    // closes drawer if opened
    _scaffoldKey.currentState?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    MapEntry<String, Widget> widgetOption =
        _widgetOptions.entries.elementAt(_selectedPageIndex);
    final String widgetTitle = widgetOption.key;
    final Widget widgetPage = widgetOption.value;

    Widget? bottomNavigationBar;
    if (widgetPage is PaletteBasePage) {
      bottomNavigationBar = BlendrNavigationBar(
        paletteKey: widgetPage.key as GlobalKey<PaletteBasePageState>,
        onPageSelect: onPageSelect,
      );
    }

    return SafeArea(
      child: Scaffold(
        key: _scaffoldKey,
        drawer: BlendrDrawer(onTap: onPageSelect),
        appBar: const BlendrAppBar(),
        body: Center(
          child: widgetPage,
        ),
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
