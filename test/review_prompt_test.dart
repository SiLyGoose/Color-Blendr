import 'package:color_blendr/app/review_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 19, 12);
  final installed = now.subtract(const Duration(days: 5));

  bool due({
    DateTime? firstSeen,
    int launches = 5,
    int saves = 5,
    DateTime? lastAsked,
    int asks = 0,
  }) => ReviewPrompt.isDue(
    now: now,
    firstSeen: firstSeen ?? installed,
    launches: launches,
    saves: saves,
    lastAsked: lastAsked,
    asks: asks,
  );

  test('a returning user with a few saves who was never asked is due', () {
    expect(due(), isTrue);
  });

  test('not before a few saves, sessions and days', () {
    expect(due(saves: ReviewPrompt.minSaves - 1), isFalse);
    expect(due(launches: ReviewPrompt.minLaunches - 1), isFalse);
    expect(due(firstSeen: now.subtract(const Duration(hours: 30))), isFalse);
  });

  test('waits the cooldown between asks', () {
    expect(
      due(asks: 1, lastAsked: now.subtract(const Duration(days: 20))),
      isFalse,
    );
    expect(
      due(
        asks: 1,
        lastAsked: now.subtract(
          ReviewPrompt.cooldown + const Duration(days: 1),
        ),
      ),
      isTrue,
    );
  });

  test('stops after the last ask', () {
    expect(
      due(
        asks: ReviewPrompt.maxAsks,
        lastAsked: now.subtract(const Duration(days: 400)),
      ),
      isFalse,
    );
  });
}
