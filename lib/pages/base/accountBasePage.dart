import 'package:color_blendr/components/blendrButtons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../controllers/accountController.dart';
import '../../util/blendrUtil.dart';
import 'basePage.dart';

abstract class AccountBasePage extends BasePage {
  const AccountBasePage({required GlobalKey<BasePageState> key})
      : super(key: key);
}

abstract class AccountBasePageState extends BasePageState {
  bool isLoggedIn = false;

  Future<User?> handleGoogleLogin(BuildContext context,
      [Function? callback]) async {
    try {
      User? user = await AccountController.handleGoogleLogin();

      setState(() {}); // trigger page refresh
      callback?.call(); // call any post login functions

      return user;
    } on FirebaseAuthException catch (error) {
      print("Firebase error: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? "Something went wrong."),
        ),
      );
    } catch (error) {
      print("Google sign in error: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
        ),
      );
    }
    return null;
  }

  Widget buildUserNotLoggedIn(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
            await handleGoogleLogin(context);
            // setState(() {}); // trigger page refresh
          },
          child: SizedBox(
            width: 300,
            height: 50,
            child: BlendrButtons.googleLoginButton,
          ),
        ),
      ],
    );
  }

  Widget buildUserLoggedIn(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 50,
          foregroundImage: NetworkImage(AccountController.user?.photoURL ??
              "https://cdn.discordapp.com/embed/avatars/1.png"),
        ),
        const SizedBox(
          height: 10,
        ),
        Text(
          AccountController.user?.displayName ?? "Blendr User",
          style: BlendrUtil.getDefaultTextStyle(
            fontSize: 20,
          ),
        ),
        const SizedBox(
          height: 50,
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
            await AccountController.handleGoogleLogout();
            setState(() {}); // trigger page refresh
          },
          child: SizedBox(
            width: 150,
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(
                  Icons.logout,
                  color: Colors.black.withOpacity(0.6),
                ),
                Text(
                  "Logout",
                  style: BlendrUtil.getDefaultTextStyle(
                    color: Colors.red.withOpacity(0.85),
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    print(context);
    if (AccountController.user != null) {
      return buildUserLoggedIn(context);
    } else {
      return buildUserNotLoggedIn(context);
    }
  }
}
