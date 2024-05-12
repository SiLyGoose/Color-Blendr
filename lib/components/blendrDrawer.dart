import 'package:flutter/material.dart';

import '../util/blendrPalette.dart';

typedef OnTapCallback = void Function(int index);

class BlendrDrawer extends StatelessWidget {
  final OnTapCallback onTap;

  const BlendrDrawer({Key? key, required this.onTap}) : super(key: key);

  static const List<String> _generatorWidgetTitles = [
        "Palette",
        "Gradient",
        "Library",
      ],
      _accountWidgetTitles = ["Profile"];

  ListTile createWidgetTile(String title) {
    int index = _generatorWidgetTitles.indexOf(title);
    if (index == -1) {
      index =
          _accountWidgetTitles.indexOf(title) + _generatorWidgetTitles.length;
    }
    return ListTile(
      selectedTileColor: const Color(0xffd7d7d7),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: "Inter",
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () => {
        if (index != -1) {onTap(index)},
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(BlendrPalette.secondaryColor),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: ListView(
        children: [
          // Palette, Gradient, Library
          ..._generatorWidgetTitles.map((String widgetTitle) {
            return createWidgetTile(widgetTitle);
          }),
          // Drawer divider between pages and account
          const Divider(
            color: Color.fromRGBO(23, 23, 23, 0.2),
            indent: 10,
            endIndent: 10,
          ),
          // Profile
          ..._accountWidgetTitles.map((String widgetTitle) {
            return createWidgetTile(widgetTitle);
          })
        ],
      ),
    );
  }
}
