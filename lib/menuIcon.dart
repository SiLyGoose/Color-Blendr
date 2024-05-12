import 'package:flutter/material.dart';

class MenuIcon extends StatefulWidget {
  const MenuIcon({super.key, required this.animationController});
  // const MenuIcon({Key? key, required this.animationController}) : super(key: key);

  final AnimationController animationController;

  @override
  State<MenuIcon> createState() => _MenuIconState();
}

class _MenuIconState extends State<MenuIcon>
    with SingleTickerProviderStateMixin {
  late Animation<double> animation;

  @override
  void initState() {
    super.initState();
    animation =
        Tween<double>(begin: 0.0, end: 1.0).animate(widget.animationController);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      icon: AnimatedIcons.menu_close,
      progress: animation,
    );
  }
}
