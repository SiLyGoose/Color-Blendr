import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The US privacy opt-out ("do not sell or share") that Google's consent form
/// saved, read back so it can be passed to each mediation network.
///
/// The AdMob adapters forward GDPR consent from the consent form by
/// themselves, but Google's docs say the US-state opt-out has to be given to
/// each network (here, Unity Ads) through its own call. The consent form saves
/// it in the IAB Global Privacy Platform (GPP) format, which this decodes.

const _channel = MethodChannel('org.ColorBlendr.color_blendr/privacy');

/// Every IAB value the consent form saved (key → value as text). Empty off
/// Android, or if the platform call fails.
Future<Map<String, String>> readIabStrings() async {
  if (defaultTargetPlatform != TargetPlatform.android) return const {};
  try {
    final raw = await _channel.invokeMapMethod<String, String>('iabStrings');
    return raw ?? const {};
  } catch (e) {
    debugPrint('IAB strings unavailable: $e');
    return const {};
  }
}

/// Whether the user opted out of the sale or sharing of their personal
/// information, or of targeted ads, under a US state privacy law.
///
/// False when nothing says so (outside the US, or no choice saved). A US
/// section this doesn't know how to read counts as opted out: wrongly
/// limiting ads costs a little revenue, wrongly selling data breaks the law.
bool usPrivacyOptOut(Map<String, String> iab) {
  // Legacy US Privacy string, such as "1YYN": the third letter is the opt-out.
  final usp = iab['IABUSPrivacy_String'];
  if (usp != null && usp.length >= 3 && usp[2].toUpperCase() == 'Y') {
    return true;
  }

  final gpp = iab['IABGPP_HDR_GppString'];
  final sids = iab['IABGPP_GppSID'];
  if (gpp == null || gpp.isEmpty || sids == null || sids.isEmpty) return false;

  final ids =
      sids
          .split('_')
          .map(int.tryParse)
          .whereType<int>()
          .where((id) => id > 0)
          .toList()
        ..sort();
  // The first part is the header; then one part per section, in id order.
  final parts = gpp.split('~');
  if (parts.length != ids.length + 1) {
    // Can't line the sections up with their ids. Only matters if a US
    // section is among them.
    return ids.any(_isUsSection);
  }
  for (var i = 0; i < ids.length; i++) {
    final optedOut = _sectionOptOut(ids[i], parts[i + 1]);
    if (optedOut ?? _isUsSection(ids[i])) return true;
  }
  return false;
}

/// US Privacy (6), the national section (7) and the state sections (8 on).
bool _isUsSection(int id) => id >= 6;

/// For each US section, where its opt-out fields sit in the core segment: a
/// bit offset per 2-bit field (0 = not applicable, 1 = opted out, 2 = didn't).
/// Layouts from the IAB GPP specification.
const _optOutFields = <int, List<int>>{
  // usnat: SaleOptOut, SharingOptOut, TargetedAdvertisingOptOut.
  7: [18, 20, 22],
  // usca: SaleOptOut, SharingOptOut.
  8: [12, 14],
  // usva: SaleOptOut, TargetedAdvertisingOptOut.
  9: [12, 14],
  // usco: SaleOptOut, TargetedAdvertisingOptOut.
  10: [12, 14],
  // usut: SaleOptOut, TargetedAdvertisingOptOut.
  11: [14, 16],
  // usct: SaleOptOut, TargetedAdvertisingOptOut.
  12: [12, 14],
};

/// True or false for a section this can read, null for one it can't (an
/// unknown US state, or a malformed string). Non-US sections are false.
bool? _sectionOptOut(int id, String section) {
  if (id == 6) {
    // uspv1 is the plain US Privacy text, not base64.
    if (section.length < 3) return null;
    return section[2].toUpperCase() == 'Y';
  }
  if (!_isUsSection(id)) return false;
  final fields = _optOutFields[id];
  if (fields == null) return null;
  final bits = _bits(section.split('.').first);
  if (bits == null) return null;
  for (final offset in fields) {
    if (offset + 2 > bits.length) return null;
    final value = (bits[offset] << 1) | bits[offset + 1];
    if (value == 1) return true;
  }
  return false;
}

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// GPP's URL-safe base64, as a list of bits (6 per character).
List<int>? _bits(String encoded) {
  final bits = <int>[];
  for (final char in encoded.split('')) {
    final value = _alphabet.indexOf(char);
    if (value < 0) return null;
    for (var shift = 5; shift >= 0; shift--) {
      bits.add((value >> shift) & 1);
    }
  }
  return bits;
}
