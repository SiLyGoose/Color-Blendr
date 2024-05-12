import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_blendr/controllers/accountController.dart';
import 'package:color_blendr/util/blendrPaletteUtil.dart';
import 'package:color_blendr/util/blendrUtil.dart';
import 'package:color_blendr/util/hexColor.dart';
import 'package:flutter/material.dart';

import 'base/accountBasePage.dart';
import 'base/basePage.dart';

class LibraryPage extends AccountBasePage {
  const LibraryPage({required GlobalKey<BasePageState> key}) : super(key: key);

  @override
  LibraryPageState createState() => LibraryPageState();
}

class LibraryPageState extends AccountBasePageState {
  final LinkedList<PaletteEntryMap> _libraryPaletteList = LinkedList();

  Future<void> readPalettes() async {
    try {
      _libraryPaletteList.clear();

      LinkedList<PaletteEntryMap> savedPaletteList =
          await BlendrPaletteUtil.readSavedPalettes();

      _libraryPaletteList.addAll(savedPaletteList
          .map((entry) => PaletteEntryMap(data: entry.data, name: entry.name)));
    } catch (e) {
      print("ERROR READING PALETTE: $e");
    }
  }

  @override
  Widget buildUserLoggedIn(BuildContext context) {
    // viewport width
    final double vw = MediaQuery.of(context).size.width * 0.9;
    final double vh = MediaQuery.of(context).size.height * 0.1;
    print(vh);

    return FutureBuilder(
      future: readPalettes(),
      builder: (context, snapshot) {
        return snapshot.connectionState == ConnectionState.waiting
            ? BlendrUtil.loadingAnimation
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: _libraryPaletteList.map((savedPalette) {
                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 20),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(20),
                            ),
                            child: SizedBox(
                              width: vw,
                              height: 100,
                              child: Row(
                                children: savedPalette.data.entries.map(
                                  (MapEntry<String, PaletteEntry> entry) {
                                    final String colorHex = entry.key,
                                        colorName = entry.value.name;
                                    final Color colorTextValue =
                                        HexColor.fromHex(entry.value.textColor);

                                    return Expanded(
                                      child: Container(
                                        color: HexColor.fromHex(colorHex),
                                      ),
                                    );
                                  },
                                ).toList(),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: vw,
                          height: 50,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    savedPalette.name ?? "My new palette",
                                    style: BlendrUtil.getDefaultTextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.favorite_outline,
                                  color: Colors.grey.withOpacity(0.85),
                                  size: 20,
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Icon(
                                  Icons.more_horiz,
                                  color: Colors.grey.withOpacity(0.85),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              );
      },
    );
  }
}
