import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountController {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  // .doc(AccountController.user?.uid)
  static CollectionReference palettesRef =
      FirebaseFirestore.instance.collection("palettes");
  static User? user = _auth.currentUser;

  static Future<User?> handleGoogleLogin() async {
    final GoogleSignInAccount? account = await _googleSignIn.signIn();

    final GoogleSignInAuthentication accountAuthentication =
        await account!.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: accountAuthentication.accessToken,
      idToken: accountAuthentication.idToken,
    );

    final UserCredential userCredential =
        await _auth.signInWithCredential(credential);

    user = userCredential.user;

    print(user);

    return user;
  }

  static Future<void> handleGoogleLogout() async {
    await _auth.signOut();
    await _googleSignIn.signOut();

    user = null;
  }
}
