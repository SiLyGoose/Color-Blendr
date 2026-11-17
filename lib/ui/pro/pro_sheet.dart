import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/billing.dart';
import '../../data/blendr_api.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';
import '../common.dart';

/// What the user was trying to do when they hit a Pro feature. Headlines the
/// upgrade sheet.
enum ProFeature {
  overview(
    Icons.workspace_premium_outlined,
    'Color Blendr Pro',
    'More room and more tools for the palettes you make.',
  ),
  noAds(
    Icons.block,
    'Go ad-free',
    'Pro removes ads, and adds unlimited saves, folders, exports and more.',
  ),
  unlimitedSaves(
    Icons.all_inclusive,
    'Your library is full',
    'Free accounts keep up to {limit} palettes. Pro keeps as many as you like.',
  ),
  folders(
    Icons.folder_outlined,
    'Organize with folders',
    'Group palettes by project, client or mood.',
  ),
  tags(
    Icons.sell_outlined,
    'Tag your palettes',
    'Label palettes and filter your library by tag.',
  ),
  export(
    Icons.ios_share,
    'Export anywhere',
    'CSS, SCSS, Tailwind, JSON, Adobe swatches, GIMP palettes, images and wallpapers.',
  ),
  photo(
    Icons.add_photo_alternate_outlined,
    'Palettes from photos',
    'Pull a palette out of any photo, then fine-tune it with the eyedropper.',
  ),
  accessibility(
    Icons.accessibility_new,
    'Check accessibility',
    'See text contrast grades and how your palette looks with color blindness.',
  );

  const ProFeature(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

/// True if the account has Pro. Otherwise shows the upgrade sheet for
/// [feature] and returns false.
Future<bool> requirePro(
  BuildContext context,
  WidgetRef ref,
  ProFeature feature,
) async {
  if (ref.read(isProProvider)) return true;
  await showProSheet(context, feature);
  return false;
}

Future<void> showProSheet(BuildContext context, ProFeature feature) =>
    showModalBottomSheet<void>(
      context: context,
      // A close button instead of a drag handle: the sheet is tall and
      // scrolls, so dragging it down is fiddly.
      showDragHandle: false,
      isScrollControlled: true,
      // Keep the top of the sheet below the status bar (the app draws edge to edge).
      useSafeArea: true,
      builder: (context) => _ProSheet(feature: feature),
    );

/// Small "PRO" label for locked menu items and tiles.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'PRO',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ProSheet extends ConsumerStatefulWidget {
  const _ProSheet({required this.feature});
  final ProFeature feature;

  @override
  ConsumerState<_ProSheet> createState() => _ProSheetState();
}

enum _Busy { none, buying, activating }

class _ProSheetState extends ConsumerState<_ProSheet> {
  /// How long the API keeps a recent purchase check before asking RevenueCat
  /// again (SYNC_COOLDOWN_MS in api/src/app.ts), plus a little slack.
  static const _syncCooldown = Duration(seconds: 11);

  _Busy _busy = _Busy.none;

  /// Loaded once the user is signed in and this build can sell Pro.
  Future<List<ProOffer>>? _offers;

  Billing get _billing => ref.read(billingProvider);

  Future<List<ProOffer>> _loadOffers() async {
    try {
      final user = ref.read(authProvider).value;
      if (user != null) await _billing.identify(user.id);
      return await _billing.loadOffers();
    } on BillingException {
      return const [];
    }
  }

  void _say(String message) {
    if (mounted) showMessage(context, message);
  }

  /// Closes the sheet if the account now has Pro. Returns whether it does.
  bool _closeIfPro(String message) {
    if (!mounted || !ref.read(isProProvider)) return false;
    showMessage(context, message);
    Navigator.of(context).pop();
    return true;
  }

  Future<void> _buy(ProOffer offer) async {
    final user = ref.read(authProvider).value;
    if (user == null) return;
    setState(() => _busy = _Busy.buying);
    try {
      await _billing.identify(user.id);
      final bought = await _billing.buy(offer);
      if (!bought || !mounted) return; // Backed out of Play's dialog.
      setState(() => _busy = _Busy.activating);
      await _activate();
    } on BillingException catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  /// Pro comes from the API, which checks the purchase with RevenueCat. Asks
  /// right away, and once more after the API's cooldown if it isn't there yet.
  Future<void> _activate() async {
    final auth = ref.read(authProvider.notifier);
    try {
      await auth.syncBilling();
      if (_closeIfPro('Welcome to Pro!')) return;
      await Future<void>.delayed(_syncCooldown);
      if (!mounted) return;
      await auth.syncBilling();
      if (_closeIfPro('Welcome to Pro!')) return;
    } on ApiException {
      // Fall through: the webhook will catch up.
    }
    // They've paid: close the paywall rather than offer the purchase again.
    // The webhook, or the next return to the app, brings Pro in.
    if (!mounted) return;
    showMessage(
      context,
      'Purchase received. Pro will turn on in a minute or two.',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authProvider).value;
    final feature = widget.feature;
    final body = feature.body.replaceAll(
      '{limit}',
      '${user?.paletteLimit ?? 10}',
    );

    const perks = [
      (Icons.block, 'No ads'),
      (Icons.all_inclusive, 'Unlimited saved palettes'),
      (Icons.folder_outlined, 'Folders and tags'),
      (Icons.ios_share, 'Export to CSS, Tailwind, Adobe, GIMP, images'),
      (Icons.add_photo_alternate_outlined, 'Palettes from photos'),
      (Icons.accessibility_new, 'Contrast and color-blindness checks'),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 8, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      feature.icon,
                      size: 32,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    feature.title,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card.outlined(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                            child: Row(
                              children: [
                                Text(
                                  'Color Blendr Pro',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(width: 8),
                                const ProBadge(),
                              ],
                            ),
                          ),
                          for (final (icon, text) in perks)
                            ListTile(
                              dense: true,
                              leading: Icon(icon, color: scheme.primary),
                              title: Text(text),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (user == null) ...[
                    Text(
                      'Pro is tied to your account, so sign in first.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    const GoogleSignInButton(),
                  ] else ...[
                    _PurchaseArea(
                      billingAvailable: _billing.isAvailable,
                      offers: _offers ??= _billing.isAvailable
                          ? _loadOffers()
                          : Future.value(const <ProOffer>[]),
                      busy: _busy,
                      onBuy: _buy,
                      onRetry: () => setState(() {
                        _offers = _loadOffers();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The plans to choose from and the buy button with its terms.
///
/// No "Restore purchases": Pro belongs to the Color Blendr account, so it
/// follows sign-in, and RevenueCat picks up unfinished Play purchases when the
/// app opens (the profile refreshes on resume).
class _PurchaseArea extends StatefulWidget {
  const _PurchaseArea({
    required this.billingAvailable,
    required this.offers,
    required this.busy,
    required this.onBuy,
    required this.onRetry,
  });

  final bool billingAvailable;
  final Future<List<ProOffer>> offers;
  final _Busy busy;
  final ValueChanged<ProOffer> onBuy;
  final VoidCallback onRetry;

  @override
  State<_PurchaseArea> createState() => _PurchaseAreaState();
}

class _PurchaseAreaState extends State<_PurchaseArea> {
  static const _buttonSize = Size.fromHeight(52);

  /// The plan the user picked, by title; null until they pick one.
  String? _picked;

  /// Yearly if it's on offer (best value), otherwise the first plan.
  static ProOffer _defaultChoice(List<ProOffer> offers) =>
      offers.where((o) => o.period == 'year').firstOrNull ?? offers.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final busy = widget.busy;
    final idle = busy == _Busy.none;

    Widget spinnerButton(String label) => FilledButton.icon(
      onPressed: null,
      style: FilledButton.styleFrom(minimumSize: _buttonSize),
      icon: const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      label: Text(label),
    );

    if (!widget.billingAvailable) {
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(minimumSize: _buttonSize),
        child: const Text('Purchases aren\u2019t available in this build'),
      );
    }
    return FutureBuilder<List<ProOffer>>(
      future: widget.offers,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return spinnerButton('Loading prices\u2026');
        }
        final offers = snapshot.data ?? const <ProOffer>[];
        if (offers.isEmpty) {
          return Column(
            children: [
              Text(
                'Couldn\u2019t load Pro from Google Play.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: idle ? widget.onRetry : null,
                child: const Text('Try again'),
              ),
            ],
          );
        }
        final chosen =
            offers.where((o) => o.title == _picked).firstOrNull ??
            _defaultChoice(offers);
        final monthly = offers.where((o) => o.period == 'month').firstOrNull;

        return Column(
          children: [
            for (final o in offers)
              _PlanOption(
                offer: o,
                selected: identical(o, chosen),
                savings: monthly == null ? null : o.savingsOver(monthly),
                onTap: idle ? () => setState(() => _picked = o.title) : null,
              ),
            const SizedBox(height: 8),
            switch (busy) {
              _Busy.buying => spinnerButton('Opening Google Play\u2026'),
              _Busy.activating => spinnerButton(
                'Purchase received, activating\u2026',
              ),
              _ => FilledButton(
                onPressed: idle ? () => widget.onBuy(chosen) : null,
                style: FilledButton.styleFrom(minimumSize: _buttonSize),
                child: Text('Get Pro \u00b7 ${chosen.priceLabel}'),
              ),
            },
            const SizedBox(height: 8),
            // Google Play requires the price, period and renewal terms here.
            Text(chosen.terms, textAlign: TextAlign.center, style: muted),
          ],
        );
      },
    );
  }
}

/// One plan: title, price, and a "Save 40%" badge for a cheaper yearly plan.
class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.offer,
    required this.selected,
    required this.savings,
    required this.onTap,
  });

  final ProOffer offer;
  final bool selected;
  final int? savings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final price = offer.isLifetime
        ? '${offer.price} once'
        : '${offer.price} / ${offer.period}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      offer.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (savings != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Save $savings%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(price, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
