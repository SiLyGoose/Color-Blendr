import 'package:flutter/material.dart';

import '../base/accountBasePage.dart';
import '../base/basePage.dart';

class ProfilePage extends AccountBasePage {
  const ProfilePage({required GlobalKey<BasePageState> key}) : super(key: key);

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends AccountBasePageState {

}
