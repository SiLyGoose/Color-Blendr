import 'package:color_blendr/pages/base/basePage.dart';
import 'package:color_blendr/util/blendrPaletteUtil.dart';
import 'package:flutter/material.dart';

import 'base/paletteBasePage.dart';

class GradientPage extends PaletteBasePage {
  const GradientPage({required GlobalKey<BasePageState> key}) : super(key: key);

  @override
  GradientPageState createState() => GradientPageState();
}

class GradientPageState extends PaletteBasePageState {
  @override
  Future<Map<String, PaletteEntry>> fetchData() async {
    return await BlendrPaletteUtil.generateGradient();
  }
}
