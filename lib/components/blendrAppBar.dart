import 'package:color_blendr/util/blendrUtil.dart';
import 'package:flutter/material.dart';

import '../util/blendrPalette.dart';

class BlendrAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BlendrAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(BlendrPalette.primaryColor),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.15),
            width: 0.5,
          ),
        ),
      ),
      child: AppBar(
        centerTitle: true,
        title: Text(
          "Blendr",
          style: BlendrUtil.getDefaultTextStyle(
            // color: Color.fromRGBO(33, 45, 99, 1.0),
            color: const Color(BlendrPalette.secondaryAccent),
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0.0,
      ),
    );
  }

  @override
  Size get preferredSize => AppBar().preferredSize;
}
