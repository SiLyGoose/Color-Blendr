import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'palette_style.dart';

/// Normalizes "#AABBCC" / "aabbcc" to "aabbcc". Throws [FormatException] otherwise.
String normalizeHex(String input) {
  final hex = input.trim().replaceFirst('#', '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) {
    throw FormatException('Not a 6-digit hex color', input);
  }
  return hex;
}

Color colorFromHex(String hex) => Color(0xFF000000 | int.parse(hex, radix: 16));

/// One swatch: its color, a human name, and the text color that reads on it.
@immutable
class PaletteColor {
  const PaletteColor({
    required this.hex,
    required this.name,
    required this.textHex,
  });

  /// 6 lowercase hex digits, no '#'.
  final String hex;
  final String name;

  /// 6 lowercase hex digits, no '#'.
  final String textHex;

  Color get color => colorFromHex(hex);
  Color get textColor => colorFromHex(textHex);

  /// "#2B301F"
  String get label => '#${hex.toUpperCase()}';

  factory PaletteColor.fromJson(Map<String, dynamic> json) => PaletteColor(
    hex: normalizeHex(json['hex'] as String),
    name: json['name'] as String,
    textHex: normalizeHex(json['textColor'] as String),
  );

  Map<String, dynamic> toJson() => {
    'hex': hex,
    'name': name,
    'textColor': textHex,
  };

  @override
  bool operator ==(Object other) =>
      other is PaletteColor &&
      other.hex == hex &&
      other.name == name &&
      other.textHex == textHex;

  @override
  int get hashCode => Object.hash(hex, name, textHex);

  @override
  String toString() => 'PaletteColor($label $name)';
}

/// Which generator produced a palette.
enum PaletteKind {
  palette('Palette'),
  gradient('Gradient');

  const PaletteKind(this.label);
  final String label;

  static PaletteKind parse(String? value) => PaletteKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => PaletteKind.palette,
  );
}

/// A palette produced by the generator (not necessarily saved).
@immutable
class GeneratedPalette {
  const GeneratedPalette({
    required this.kind,
    required this.colors,
    this.style,
  });

  final PaletteKind kind;
  final List<PaletteColor> colors;

  /// The style it was generated with, for learning what the user likes. Null
  /// for palettes opened from the library. Not part of equality.
  final PaletteStyle? style;

  /// Two palettes are "the same" for saving purposes when their colors match in order.
  bool sameColorsAs(List<PaletteColor> other) => listEquals(
    colors.map((c) => c.hex).toList(),
    other.map((c) => c.hex).toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is GeneratedPalette &&
      other.kind == kind &&
      listEquals(other.colors, colors);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(colors));
}

/// A palette stored in the user's library.
@immutable
class SavedPalette {
  const SavedPalette({
    required this.id,
    required this.name,
    required this.kind,
    required this.colors,
    required this.createdAt,
    this.folderId,
    this.tags = const [],
  });

  final String id;
  final String name;
  final PaletteKind kind;
  final List<PaletteColor> colors;
  final DateTime createdAt;

  /// The [Folder] it's filed in (Pro), or null.
  final String? folderId;

  /// Labels (Pro), in the order they were added.
  final List<String> tags;

  factory SavedPalette.fromJson(Map<String, dynamic> json) => SavedPalette(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: PaletteKind.parse(json['kind'] as String?),
    colors: (json['colors'] as List)
        .map((c) => PaletteColor.fromJson(c as Map<String, dynamic>))
        .toList(growable: false),
    createdAt: DateTime.parse(json['createdAt'] as String),
    folderId: json['folderId'] as String?,
    tags: List.unmodifiable(
      (json['tags'] as List?)?.cast<String>() ?? const <String>[],
    ),
  );

  SavedPalette copyWith({
    String? name,
    String? Function()? folderId,
    List<String>? tags,
  }) => SavedPalette(
    id: id,
    name: name ?? this.name,
    kind: kind,
    colors: colors,
    createdAt: createdAt,
    folderId: folderId != null ? folderId() : this.folderId,
    tags: tags ?? this.tags,
  );
}

/// A library folder (Pro).
@immutable
class Folder {
  const Folder({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final DateTime createdAt;

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}

/// The Google Play subscription behind Pro, as the API last saw it.
@immutable
class StoreSubscription {
  const StoreSubscription({
    this.productId,
    this.expiresAt,
    this.willRenew = false,
    this.billingIssue = false,
    this.store,
  });

  final String? productId;

  /// When the current period ends (renews, or ends if [willRenew] is false).
  final DateTime? expiresAt;

  /// False once the user cancels; Pro still runs to [expiresAt].
  final bool willRenew;

  /// The store couldn't charge the user (they keep Pro during the grace period).
  final bool billingIssue;

  /// RevenueCat's store: "play_store", "rc_billing" (bought on the website),
  /// "promotional"… Null from older API versions, which only sold on Play.
  final String? store;

  /// Bought on Google Play, so it's managed there. Web purchases are managed
  /// on the website; the app only names it (Play's payments policy).
  bool get isGooglePlay => store == null || store == 'play_store';

  factory StoreSubscription.fromJson(Map<String, dynamic> json) =>
      StoreSubscription(
        productId: json['productId'] as String?,
        expiresAt: switch (json['expiresAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        willRenew: json['willRenew'] == true,
        billingIssue: json['billingIssue'] == true,
        store: json['store'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'expiresAt': expiresAt?.toIso8601String(),
    'willRenew': willRenew,
    'billingIssue': billingIssue,
    'store': store,
  };
}

/// The signed-in account, as returned by the API.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.name,
    this.avatarUrl,
    this.isPro = false,
    this.proExpiresAt,
    this.paletteLimit = defaultPaletteLimit,
    this.subscription,
  });

  /// Used until the server says otherwise (e.g. a profile saved by an older
  /// version of the app). Matches the API's FREE_PALETTE_LIMIT.
  static const defaultPaletteLimit = 10;

  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;

  /// Whether the account has Color Blendr Pro right now. The server decides.
  final bool isPro;

  /// When Pro ends; null if it doesn't (or the account is free).
  final DateTime? proExpiresAt;

  /// How many palettes the account may keep; null means unlimited.
  final int? paletteLimit;

  /// The Play subscription giving Pro, or null (free, or Pro granted by hand).
  final StoreSubscription? subscription;

  String get displayName =>
      (name?.trim().isNotEmpty ?? false) ? name!.trim() : email;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'];
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      isPro: json['plan'] == 'pro',
      proExpiresAt: switch (json['proExpiresAt']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
      paletteLimit: limits is Map && limits.containsKey('palettes')
          ? limits['palettes'] as int?
          : defaultPaletteLimit,
      subscription: switch (json['subscription']) {
        final Map<String, dynamic> m => StoreSubscription.fromJson(m),
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'avatarUrl': avatarUrl,
    'plan': isPro ? 'pro' : 'free',
    'proExpiresAt': proExpiresAt?.toIso8601String(),
    'limits': {'palettes': paletteLimit},
    'subscription': subscription?.toJson(),
  };
}

/// What the app keeps after signing in.
@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  final String token;
  final DateTime expiresAt;
  final AppUser user;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };
}
