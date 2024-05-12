import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_blendr/components/overlay/blendrAlertOverlay.dart';
import 'package:color_blendr/controllers/accountController.dart';
import 'package:color_blendr/pages/base/accountBasePage.dart';
import 'package:color_blendr/pages/base/basePage.dart';
import 'package:color_blendr/util/hexColor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../util/blendrPaletteUtil.dart';
import '../../util/blendrTypeDef.dart';
import '../../util/blendrUtil.dart';

abstract class PaletteBasePage extends AccountBasePage {
  const PaletteBasePage({required GlobalKey<BasePageState> key})
      : super(key: key);
}

// mixin PaletteBasePageOptionalMethods<T extends PaletteBasePageState> {
//   void savePalette();
//   LinkedList<PaletteEntryMap> getSavedPaletteList();
// }

abstract class PaletteBasePageState extends AccountBasePageState {
  int _paletteEntryIndex = 0;
  late LinkedList<PaletteEntryMap> _libraryPaletteList = LinkedList();
  final LinkedList<PaletteEntryMap> _paletteHistoryList = LinkedList();
  Map<String, PaletteEntry> _paletteMap = {};

  bool isLoading = true;

  Future<Map<String, PaletteEntry>> fetchData();

  Map<String, PaletteEntry> getPaletteMap() {
    return _paletteMap;
  }

  Future<void> updateLibrary({bool forceRead = false}) async {
    LinkedList<PaletteEntryMap> updatedLibraryPaletteList =
        await BlendrPaletteUtil.readSavedPalettes(forceRead: forceRead);

    setState(() {
      _libraryPaletteList = updatedLibraryPaletteList;
    });
  }

  Future<void> updatePalette() async {
    setState(() {
      isLoading = true;
    });

    Map<String, PaletteEntry> updatedMap = await fetchData();
    _paletteHistoryList.add(PaletteEntryMap(data: updatedMap));
    _paletteEntryIndex = _paletteHistoryList.length - 1;

    setState(() {
      _paletteMap = updatedMap;
      isLoading = false;
    });
  }

  PaletteEntryMap _getPaletteAtIndex(int index) {
    return _paletteHistoryList.elementAt(index);
  }

  int get paletteHistoryCursor {
    return _paletteEntryIndex;
  }

  int get paletteHistorySize {
    return _paletteHistoryList.length;
  }

  bool get previousIsPressable {
    return _paletteEntryIndex > 0;
  }

  bool get nextIsPressable {
    return _paletteEntryIndex < paletteHistorySize - 1;
  }

  bool get paletteIsSaved {
    return paletteHistorySize == 0
        ? false
        : _libraryPaletteList.any((libraryPalette) {
            return mapEquals(libraryPalette.data,
                _getPaletteAtIndex(_paletteEntryIndex).data);
          });
  }

  int previousPalette() {
    if (_paletteEntryIndex > 0) {
      setState(() {
        _paletteMap = _getPaletteAtIndex(--_paletteEntryIndex).data;
      });
    }

    return _paletteEntryIndex;
  }

  int nextPalette() {
    if (_paletteEntryIndex < paletteHistorySize - 1) {
      setState(() {
        _paletteMap = _getPaletteAtIndex(++_paletteEntryIndex).data;
      });
    }

    return _paletteEntryIndex;
  }

  Future<void> savePalette(
      BuildContext context, PageSelectCallback onPageSelect) async {
    if (AccountController.user == null) {
      showModalBottomSheet(
        context: context,
        builder: (context) => BlendrAlertOverlay(
          navigateToLoginPage: onPageSelect,
          handleGoogleLogin: super.handleGoogleLogin,
        ),
      );
    } else {
      // var uuid = Uuid();
      // String uid = uuid.v4();
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection("palettes")
          .doc(AccountController.user?.uid)
          .get();

      // fetch saved palettes from db
      Map<String, dynamic> snapshotData =
          snapshot.data() as Map<String, dynamic>;

      List<dynamic> paletteList =
          snapshotData["savedPaletteList"] as List<dynamic>;

      DocumentReference<Map<String, dynamic>> documentRef = FirebaseFirestore
          .instance
          .collection("palettes")
          .doc(AccountController.user?.uid);

      if (!paletteIsSaved) {
        paletteList.add({
          "name": "My new palette",
          "dateAdded": DateTime.now().millisecondsSinceEpoch.toString(),
          "colorList": _paletteMap.entries.map((entry) => entry.key).toList(),
        });
      } else {
        paletteList.removeWhere((palette) {
          List<dynamic> colorList = palette["colorList"] as List<dynamic>;
          return listEquals(_paletteMap.keys.toList(), colorList);
        });
      }

      await documentRef.set({
        "savedPaletteList": paletteList,
      }).whenComplete(() async => await updateLibrary(forceRead: true));
    }
  }

  @override
  void initState() {
    super.initState();
    updateLibrary();
    updatePalette();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // lifo order
      children: [
        Column(
          children:
              _paletteMap.entries.map((MapEntry<String, PaletteEntry> entry) {
            final String colorHex = entry.key, colorName = entry.value.name;
            final Color colorTextValue =
                HexColor.fromHex(entry.value.textColor);

// expanded container takes up the remaining space
// between AppBar and BottomNavigationBar.
            return Expanded(
              child: Container(
                color: HexColor.fromHex(colorHex),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Text>[
                      Text(
                        colorHex.toUpperCase(),
                        style: BlendrUtil.getDefaultTextStyle(
                          color: colorTextValue.withOpacity(0.85),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        colorName,
                        style: BlendrUtil.getDefaultTextStyle(
                          color: colorTextValue.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: BlendrUtil.loadingAnimation,
              ),
            ),
          ),
      ],
    );
  }
}
