import 'package:flutter_test/flutter_test.dart';
import 'package:color_blendr/data/us_privacy.dart';

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// Encodes 2-bit fields after a 6-bit version, padded to whole characters,
/// the way a GPP section's core segment is written.
String _section(List<int> fields, {int version = 1}) {
  final bits = <int>[
    for (var s = 5; s >= 0; s--) (version >> s) & 1,
    for (final f in fields) ...[(f >> 1) & 1, f & 1],
  ];
  while (bits.length % 6 != 0) {
    bits.add(0);
  }
  final out = StringBuffer();
  for (var i = 0; i < bits.length; i += 6) {
    var v = 0;
    for (var j = 0; j < 6; j++) {
      v = (v << 1) | bits[i + j];
    }
    out.write(_alphabet[v]);
  }
  return out.toString();
}

/// usnat fields up to TargetedAdvertisingOptOut: six notices, then the three
/// opt-outs.
String _usnat({int sale = 2, int sharing = 2, int targeted = 2}) =>
    _section([1, 1, 1, 1, 1, 1, sale, sharing, targeted, 0, 0, 0]);

Map<String, String> _gpp(String sids, List<String> sections) => {
  'IABGPP_GppSID': sids,
  'IABGPP_HDR_GppString': ['DBABLA', ...sections].join('~'),
};

void main() {
  test('nothing saved: not opted out', () {
    expect(usPrivacyOptOut(const {}), isFalse);
  });

  test('IAB sample usnat string: did not opt out', () {
    expect(
      usPrivacyOptOut({
        'IABGPP_GppSID': '7',
        'IABGPP_HDR_GppString': 'DBABLA~BVQqAAAAAgA.QA',
      }),
      isFalse,
    );
  });

  test('usnat: any of sale, sharing or targeted ads opted out', () {
    expect(usPrivacyOptOut(_gpp('7', [_usnat()])), isFalse);
    expect(usPrivacyOptOut(_gpp('7', [_usnat(sale: 1)])), isTrue);
    expect(usPrivacyOptOut(_gpp('7', [_usnat(sharing: 1)])), isTrue);
    expect(usPrivacyOptOut(_gpp('7', [_usnat(targeted: 1)])), isTrue);
  });

  test('usnat: "not applicable" is not an opt-out', () {
    expect(
      usPrivacyOptOut(_gpp('7', [_usnat(sale: 0, sharing: 0, targeted: 0)])),
      isFalse,
    );
  });

  test('California section', () {
    // SaleOptOutNotice, SharingOptOutNotice, SensitiveDataLimitUseNotice,
    // SaleOptOut, SharingOptOut.
    expect(usPrivacyOptOut(_gpp('8', [_section([1, 1, 1, 2, 2])])), isFalse);
    expect(usPrivacyOptOut(_gpp('8', [_section([1, 1, 1, 2, 1])])), isTrue);
  });

  test('sections are matched to ids in order, with EU TCF alongside', () {
    final eu = 'CQabcdefgh.YAAAAAAAAAA';
    expect(usPrivacyOptOut(_gpp('2_7', [eu, _usnat()])), isFalse);
    expect(usPrivacyOptOut(_gpp('7_2', [eu, _usnat(sale: 1)])), isTrue);
  });

  test('EU only: not a US opt-out', () {
    expect(usPrivacyOptOut(_gpp('2', ['CQabcdefgh'])), isFalse);
  });

  test('unknown US state or broken string counts as opted out', () {
    expect(usPrivacyOptOut(_gpp('19', [_section([2, 2, 2, 2])])), isTrue);
    expect(usPrivacyOptOut(_gpp('7', ['B!!'])), isTrue);
    expect(usPrivacyOptOut(_gpp('7', ['B'])), isTrue);
    expect(usPrivacyOptOut(_gpp('7_8', [_usnat()])), isTrue);
  });

  test('legacy US Privacy string', () {
    expect(usPrivacyOptOut({'IABUSPrivacy_String': '1YNN'}), isFalse);
    expect(usPrivacyOptOut({'IABUSPrivacy_String': '1YYN'}), isTrue);
    expect(usPrivacyOptOut({'IABUSPrivacy_String': '1---'}), isFalse);
  });
}
