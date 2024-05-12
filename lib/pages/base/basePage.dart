import 'package:flutter/material.dart';

abstract class BasePage extends StatefulWidget {
  final GlobalKey<BasePageState> key;

  const BasePage({required this.key}) : super(key: key);

  @override
  BasePageState createState();
}

abstract class BasePageState extends State<BasePage> {

}
