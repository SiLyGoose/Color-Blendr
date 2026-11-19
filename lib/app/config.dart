/// Build-time configuration. Override with `--dart-define=KEY=value`.
abstract final class AppConfig {
  /// The Neon Function serving the Color Blendr API (production branch).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://br-empty-smoke-bc031jex-api.compute.c-16.us-east-1.aws.neon.tech',
  );

  /// RevenueCat's public SDK key: `goog_…` for Google Play, or `test_…` for
  /// RevenueCat's Test Store (debug builds only). Safe to ship; it can only
  /// attach verified purchases. Empty disables buying Pro. Pass it with
  /// `--dart-define=REVENUECAT_GOOGLE_KEY=…`.
  static const revenueCatGoogleKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
  );

  /// AdMob interstitial unit shown between generates on free accounts, in
  /// release builds. Debug builds always show Google's test ads instead, so
  /// you never click your own live ads. Not secret. Override with
  /// `--dart-define=ADMOB_INTERSTITIAL_ID=…`; an empty value turns ads off.
  /// The AdMob *app* id goes in android/local.properties (`admob.appId`).
  static const adMobInterstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-9963034591853736/6738921200',
  );

  /// The Color Blendr website (landing page; the web app is at /app).
  static final websiteUrl = Uri.parse('https://color-blendr-ui.vercel.app');

  /// Google Play's page for managing this app's subscription.
  static final manageSubscriptionUrl = Uri.parse(
    'https://play.google.com/store/account/subscriptions?sku=pro&package=org.ColorBlendr.color_blendr',
  );

  /// OAuth *web* client ID in Google Cloud project 381822964866. Google
  /// issues the sign-in ID token for this audience, and the API checks it.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '381822964866-lt575n2vlmaduii4e0j5kn1ba6fq4a3b.apps.googleusercontent.com',
  );
}
