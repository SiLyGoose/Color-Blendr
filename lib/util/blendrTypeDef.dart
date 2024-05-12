import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

typedef PageSelectCallback = void Function(int index);
typedef GoogleLoginCallback = Future<User?> Function(BuildContext context, [Function? callback]);