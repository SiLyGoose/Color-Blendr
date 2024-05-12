import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_blendr/controllers/accountController.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BlendrPaletteUtil {
  static final Map<String, LinkedList<PaletteEntryMap>> _userLibraryCache = {};
  static final Map<String, PaletteEntry> _hexNameCache = {};

  static String generateHex() {
    Random random = Random();

    int length = 6;
    String chars = '0123456789abcdef';
    String hex = '';
    while (length-- > 0) {
      hex += chars[(random.nextInt(16)) | 0];
    }

    return hex;
  }

  static Future<Map<String, PaletteEntry>> generateGradient() async {
    Map<String, PaletteEntry> paletteMap = {};

    String generatedHex = generateHex();
    dynamic responseData = await fetch(
        "https://www.thecolorapi.com/scheme?hex=$generatedHex&mode=monochrome&count=6");

    // https://www.thecolorapi.com/docs#schemes-generate-scheme-get
    if (responseData is Map<String, dynamic>) {
      List<dynamic> colorList = responseData["colors"];

      List<Future> futures = colorList.map((color) async {
        String hex = color["hex"]["value"].substring(1);
        paletteMap[hex] = PaletteEntry(
            name: color["name"]["value"],
            textColor: color["contrast"]["value"]);
      }).toList();

      await Future.wait(futures);
    }

    return paletteMap;
  }

  static Future<Map<String, PaletteEntry>> generatePalette() async {
    Map<String, PaletteEntry> paletteMap = {};

    String generatedHex = generateHex();
    dynamic responseData =
        await fetch("http://palett.es/API/v1/palette/from/$generatedHex");

    // https://palett.es/api
    if (responseData is List<dynamic>) {
      List<Future> futures = responseData.map((hex) async {
        hex = hex.toString().substring(1);
        paletteMap[hex] = await generateHexName(hex);
      }).toList();

      await Future.wait(futures);
    }

    return paletteMap;
  }

  static Future<PaletteEntry> generateHexName(String hex) async {
    if (_hexNameCache.containsKey(hex)) {
      return _hexNameCache[hex]!;
    }

    dynamic hexResponseData =
        await fetch("https://www.thecolorapi.com/id?hex=$hex");

    // https://www.thecolorapi.com/docs#schemes-generate-scheme-get
    PaletteEntry entry = PaletteEntry(
      name: hexResponseData["name"]["value"],
      textColor: hexResponseData["contrast"]["value"],
    );

    _hexNameCache[hex] = entry;
    return entry;
  }

  static dynamic fetch(String url) async {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
// throw Exception("Failed to load data");
      return List<dynamic>.empty();
    }
  }

  static Future<LinkedList<PaletteEntryMap>> readSavedPalettes(
      {bool forceRead = false}) async {
    LinkedList<PaletteEntryMap> libraryPaletteList = LinkedList();

    String? uid = AccountController.user?.uid;

    if (!forceRead && _userLibraryCache.containsKey(uid)) {
      return _userLibraryCache[uid]!;
    }

    DocumentSnapshot<Map<String, dynamic>> documentSnapshot =
        (await AccountController.palettesRef.doc(uid).get())
            as DocumentSnapshot<Map<String, dynamic>>;

    if (documentSnapshot.exists) {
      List<dynamic> savedPaletteList =
          (documentSnapshot.data()?["savedPaletteList"] ?? []) as List;

      print(savedPaletteList);

      for (var palette in savedPaletteList) {
        String name = palette["name"] as String;
        String dateAdded = palette["dateAdded"] as String;
        List<String> colorList = List<String>.from(palette["colorList"] ?? []);

        print(name);
        print(colorList);

        Map<String, PaletteEntry> paletteMap = {};

        List<Future> futures = colorList.map((color) async {
          PaletteEntry paletteEntry =
              await BlendrPaletteUtil.generateHexName(color);
          paletteMap[color] = paletteEntry;
        }).toList();

        await Future.wait(futures);

        libraryPaletteList.add(PaletteEntryMap(data: paletteMap, name: name));
      }

      _userLibraryCache[uid!] = libraryPaletteList;
    }

    return libraryPaletteList;
  }
}

final class PaletteEntry extends LinkedListEntry<PaletteEntry> {
  String name, textColor;

  PaletteEntry({required this.name, required this.textColor});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaletteEntry && other.name == name;
  }

  @override
  int get hashCode => Object.hash(name, textColor);
}

// factory PaletteEntryMap.sharedData(
//     {required Map<String, PaletteEntry> sharedData, required String name}) {
//   return PaletteEntryMap(data: sharedData, name: name);
// }
final class PaletteEntryMap extends LinkedListEntry<PaletteEntryMap> {
  String? name;
  Map<String, PaletteEntry> data;

  PaletteEntryMap({required this.data, this.name});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaletteEntryMap && mapEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(data, name);
}
