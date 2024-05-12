import 'package:color_blendr/util/blendrPalette.dart';
import 'package:color_blendr/util/blendrTypeDef.dart';
import 'package:flutter/material.dart';

import '../pages/base/paletteBasePage.dart';

class BlendrNavigationBar extends StatefulWidget {
  final GlobalKey<PaletteBasePageState> paletteKey;
  final PageSelectCallback onPageSelect;

  const BlendrNavigationBar(
      {Key? key, required this.paletteKey, required this.onPageSelect})
      : super(key: key);

  @override
  BlendrNavigationBarState createState() => BlendrNavigationBarState();
}

class BlendrNavigationBarState extends State<BlendrNavigationBar> {
  PaletteBasePageState? pageState;

  final Color inactiveColor = const Color(0xffd7d7d7);
  final Color activeColor = const Color(0xff000000);

  void updateState<T>(T Function()? callback) {
    callback?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    pageState = widget.paletteKey.currentState;

    return Container(
      decoration: BoxDecoration(
        color: const Color(BlendrPalette.primaryColor),
        border: Border(
          top: BorderSide(
            color: Colors.black.withOpacity(0.15),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16.0, top: 4.0, bottom: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              style: ButtonStyle(
                shape: MaterialStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
              ),
              onPressed: () async {
                await pageState?.updatePalette();
                setState(() {});
              },
              child: const Text(
                "Generate",
                style: TextStyle(
                  color: Color.fromRGBO(23, 23, 23, 1.0),
                  fontFamily: "Inter",
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                updateState(pageState?.previousPalette);
              },
              icon: Icon(
                Icons.keyboard_arrow_left,
                color: pageState?.previousIsPressable ?? false
                    ? activeColor
                    : inactiveColor,
              ),
            ),
            IconButton(
              onPressed: () {
                updateState(pageState?.nextPalette);
              },
              icon: Icon(
                Icons.keyboard_arrow_right,
                color: pageState?.nextIsPressable ?? false
                    ? activeColor
                    : inactiveColor,
              ),
            ),
            const Spacer(), // automatically generates space between children
            IconButton(
              onPressed: () async {
                await pageState?.savePalette(context, widget.onPageSelect);
                setState(() {});
              },
              icon: Icon(
                pageState != null && pageState!.paletteIsSaved
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: activeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
