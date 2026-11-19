import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update.dart';

/// Asks happy users for a Google Play rating, now and then.
///
/// It uses Google Play's own review card (stars and an optional comment,
/// without leaving the app). Google's rules for that card:
/// - no question of our own before it ("Enjoying Color Blendr?"), and no
///   changes or overlays on the card;
/// - ask only after the user has seen enough of the app;
/// - Play limits how often the card can appear, so a "Rate" button must open
///   the store page instead ([openStorePage]).
///
/// So the card comes up only right after the user saves a palette they like,
/// once they have saved [minSaves], and only for returning users:
/// [minLaunches] launches, [minDaysInstalled] days since the first launch, at
/// most once per session, [cooldown] between asks and [maxAsks] in total.
abstract final class ReviewPrompt {
  static const minSaves = 3;
  static const minLaunches = 3;
  static const minDaysInstalled = 2;
  static const cooldown = Duration(days: 60);
  static const maxAsks = 3;

  /// Wait after the save so the "Saved to library" message is seen first.
  static const delay = Duration(milliseconds: 1200);

  /// Build with `--dart-define=FORCE_REVIEW_PROMPT=true` to skip the checks.
  /// Play only shows the card to builds installed from Play (internal testing
  /// or internal app sharing), and not again once this account has reviewed.
  static const _force = bool.fromEnvironment('FORCE_REVIEW_PROMPT');

  static const _kFirstSeen = 'review.firstSeen';
  static const _kLaunches = 'review.launches';
  static const _kSaves = 'review.saves';
  static const _kLastAsked = 'review.lastAsked';
  static const _kAsks = 'review.asks';

  static bool _askedThisSession = false;

  /// Counts a launch. Call once at startup.
  static Future<void> recordLaunch() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!p.containsKey(_kFirstSeen)) {
        await p.setInt(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
      }
      await p.setInt(_kLaunches, (p.getInt(_kLaunches) ?? 0) + 1);
    } catch (e) {
      debugPrint('Review launch not counted: $e');
    }
  }

  /// Call after a palette is saved: counts it, then shows Play's review card
  /// if the user is due for one. Never throws.
  static Future<void> paletteSaved() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final p = await SharedPreferences.getInstance();
      final saves = (p.getInt(_kSaves) ?? 0) + 1;
      await p.setInt(_kSaves, saves);
      if (_askedThisSession) return;
      final now = DateTime.now();
      if (!_force &&
          !isDue(
            now: now,
            firstSeen: _date(p.getInt(_kFirstSeen)),
            launches: p.getInt(_kLaunches) ?? 0,
            saves: saves,
            lastAsked: _date(p.getInt(_kLastAsked)),
            asks: p.getInt(_kAsks) ?? 0,
          )) {
        return;
      }
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      _askedThisSession = true;
      await Future<void>.delayed(delay);
      // Counted before showing: Play never says whether the card appeared
      // or whether the user rated.
      await p.setInt(_kLastAsked, now.millisecondsSinceEpoch);
      await p.setInt(_kAsks, (p.getInt(_kAsks) ?? 0) + 1);
      await review.requestReview();
    } catch (e) {
      debugPrint('Review prompt skipped: $e');
    }
  }

  /// Whether a user with this history should be asked now.
  @visibleForTesting
  static bool isDue({
    required DateTime now,
    required DateTime? firstSeen,
    required int launches,
    required int saves,
    required DateTime? lastAsked,
    required int asks,
  }) {
    if (firstSeen == null) return false;
    if (saves < minSaves || launches < minLaunches) return false;
    if (now.difference(firstSeen) < const Duration(days: minDaysInstalled)) {
      return false;
    }
    if (asks >= maxAsks) return false;
    if (lastAsked != null && now.difference(lastAsked) < cooldown) {
      return false;
    }
    return true;
  }

  /// For a "Rate Color Blendr" button: opens the Play page, where the user
  /// can always rate (the review card may not appear when asked for).
  static Future<bool> openStorePage() => AppUpdate.openStore();

  static DateTime? _date(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}
