// Runs the whole test/ suite on a real device or emulator:
//   flutter test integration_test -d <device-id>
import 'package:integration_test/integration_test.dart';

import '../test/accessibility_test.dart' as accessibility;
import '../test/ads_controller_test.dart' as ads_controller;
import '../test/blendr_api_pro_test.dart' as blendr_api_pro;
import '../test/blendr_api_test.dart' as blendr_api;
import '../test/color_namer_test.dart' as color_namer;
import '../test/color_source_test.dart' as color_source;
import '../test/generator_controller_test.dart' as generator_controller;
import '../test/palette_export_test.dart' as palette_export;
import '../test/palette_style_test.dart' as palette_style;
import '../test/photo_palette_test.dart' as photo_palette;
import '../test/pro_widget_test.dart' as pro_widget;
import '../test/widget_test.dart' as widget;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  accessibility.main();
  ads_controller.main();
  blendr_api.main();
  blendr_api_pro.main();
  color_namer.main();
  color_source.main();
  generator_controller.main();
  palette_export.main();
  palette_style.main();
  photo_palette.main();
  pro_widget.main();
  widget.main();
}
