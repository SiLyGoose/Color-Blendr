# Release-build (R8) rules. Flutter's Gradle plugin picks this file up on its own.

# google_mobile_ads -> play-services-ads-api pulls in WorkManager 2.7.0 (Room 2.2.5).
# Its consumer rules keep these classes without their no-arg constructors, and R8
# full mode (AGP 8+) then strips the constructors. Room and WorkManager create them
# by reflection, so the app crashed at startup with "Failed to create an instance
# of androidx.work.impl.WorkDatabase" (Play pre-launch report, 2.0.0+9).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.work.InputMerger { <init>(); }

# OkHttp (brought in by the Liftoff Monetize ad SDK) supports optional TLS
# libraries the app doesn't include. It only uses them when they're present,
# so R8 can ignore the missing classes. Without these, the release build fails.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
