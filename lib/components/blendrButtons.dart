import 'package:flutter/material.dart';

import '../util/blendrUtil.dart';

class BlendrButtons {
  static Widget get googleLoginButton {
      // Row(
      //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      //   children: [
      //     Image.network(
      //       "http://pngimg.com/uploads/google/google_PNG19635.png",
      //       fit: BoxFit.cover,
      //     ),
      //     Text(
      //       "Sign in with Google",
      //       style: BlendrUtil.getDefaultTextStyle(
      //         color: Colors.black.withOpacity(0.85),
      //         fontSize: 16,
      //       ),
      //     ),
      //   ],
      // ),
    return Stack(
      children: [
        Image.network(
          "http://pngimg.com/uploads/google/google_PNG19635.png",
          fit: BoxFit.cover,
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.center,
            child: Text(
              "Sign in with Google",
              textAlign: TextAlign.center,
              style: BlendrUtil.getDefaultTextStyle(
                color: Colors.black.withOpacity(0.85),
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}