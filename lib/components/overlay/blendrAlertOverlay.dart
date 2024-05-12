import 'package:color_blendr/controllers/accountController.dart';
import 'package:color_blendr/util/blendrPalette.dart';
import 'package:flutter/material.dart';

import '../../util/blendrTypeDef.dart';
import '../../util/blendrUtil.dart';
import '../blendrButtons.dart';

class BlendrAlertOverlay extends StatelessWidget {
  final PageSelectCallback navigateToLoginPage;
  final GoogleLoginCallback handleGoogleLogin;

  const BlendrAlertOverlay(
      {super.key,
      required this.navigateToLoginPage,
      required this.handleGoogleLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(BlendrPalette.primaryColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Hello!",
            style: TextStyle(
              color: Colors.black,
              fontFamily: "Inter",
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -.72,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Use your email or another service to continue with Color Blendr.",
              textAlign: TextAlign.center,
              style: BlendrUtil.getDefaultTextStyle(
                color: const Color(0xff7d7c83),
                fontFamily: "Inter",
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(
            height: 32,
          ),
          ElevatedButton(
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.all<Color>(
                Colors.white,
              ),
              shape: MaterialStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
            ),
            onPressed: () async {
              closeModalBottomSheet() {
                Navigator.of(context).pop();
              }

              await handleGoogleLogin(context, closeModalBottomSheet);
            },
            child: SizedBox(
              width: 300,
              height: 50,
              child: BlendrButtons.googleLoginButton,
            ),
          ),
          const SizedBox(
            height: 20,
          ),
        ],
      ),
    );
  }
}
