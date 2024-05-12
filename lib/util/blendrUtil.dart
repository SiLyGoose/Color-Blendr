import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class BlendrUtil {
  static TextStyle getDefaultTextStyle({
    Color color = Colors.black,
    String fontFamily = "Inter",
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w500,
    double? letterSpacing,
  }) {
    return TextStyle(
      color: color,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  static Widget get loadingAnimation {
    // prograssiveDots
    // halfTriangleDot
    // threeRotatingDots
    return Container(
      child: LoadingAnimationWidget.threeRotatingDots(
        color: const Color(0xffd7d7d7),
        size: 50,
      ),
    );
  }
}
