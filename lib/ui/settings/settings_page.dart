import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/config.dart';
import '../../data/color_source.dart';
import '../../data/models.dart';
import '../../state/ads_controller.dart';
import '../../state/auth_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import '../common.dart';
import '../pro/pro_sheet.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('Generator'),
          const _ColorCountTile(),
          const SizedBox(height: 8),
          const _SectionHeader('Account'),
          if (auth.isLoading && !auth.hasValue)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (user == null)
            const _SignedOutCard()
          else
            _SignedIn(user: user),
          // Google requires a way back to the ad consent form where it asked.
          if (ref.watch(adsControllerProvider).privacyOptionsRequired &&
              !(user?.isPro ?? false))
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Ad privacy choices'),
              onTap: () =>
                  ref.read(adsControllerProvider.notifier).showPrivacyOptions(),
            ),
          // Required credit for the color-name list (CC BY 2.5).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              'Color names from Name that Color by Chirag Mehta (CC BY 2.5)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ColorCountTile extends ConsumerWidget {
  const _ColorCountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(settingsProvider.select((s) => s.colorCount));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Colors per palette', style: theme.textTheme.bodyLarge),
          Text(
            'Applies to new palettes and gradients',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (
                  var n = ColorSource.minColors;
                  n <= ColorSource.maxColors;
                  n++
                )
                  ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {count},
              onSelectionChanged: (selection) {
                HapticFeedback.selectionClick();
                ref
                    .read(settingsProvider.notifier)
                    .setColorCount(selection.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Dec 4, 2026"
String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = date.toLocal();
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Opens Google Play's subscription page for this app.
Future<void> openManageSubscription(BuildContext context) async {
  final opened = await launchUrl(
    AppConfig.manageSubscriptionUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    showMessage(context, 'Couldn\u2019t open Google Play');
  }
}

class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usage = ref.watch(libraryUsageProvider);
    final subscription = user.subscription;
    // A one-time (lifetime) purchase comes back with no end date.
    final renewing = subscription?.expiresAt != null ? subscription : null;
    final ends = user.proExpiresAt;
    final String subtitle;
    if (user.isPro && renewing != null) {
      final date = _formatDate(renewing.expiresAt!);
      subtitle = renewing.willRenew ? 'Renews on $date' : 'Ends on $date';
    } else if (user.isPro && subscription != null) {
      subtitle = 'Lifetime';
    } else if (user.isPro) {
      subtitle = ends == null ? 'Active' : 'Active until ${_formatDate(ends)}';
    } else if (usage != null) {
      subtitle = 'Free plan \u00b7 ${usage.used} of ${usage.limit} saves used';
    } else {
      subtitle = 'Free plan';
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Row(
            children: [
              const Text('Color Blendr Pro'),
              if (user.isPro) ...[const SizedBox(width: 8), const ProBadge()],
            ],
          ),
          subtitle: Text(subtitle),
          trailing: user.isPro ? null : const Icon(Icons.chevron_right),
          onTap: user.isPro
              ? null
              : () => showProSheet(context, ProFeature.overview),
        ),
        if (renewing != null && renewing.billingIssue)
          ListTile(
            iconColor: theme.colorScheme.error,
            textColor: theme.colorScheme.error,
            leading: const Icon(Icons.credit_card_off_outlined),
            title: const Text('Payment problem'),
            subtitle: const Text(
              'Fix your payment method in Google Play to keep Pro',
            ),
            onTap: () => openManageSubscription(context),
          ),
        if (renewing != null)
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Manage subscription'),
            subtitle: const Text('Change or cancel in Google Play'),
            onTap: () => openManageSubscription(context),
          ),
      ],
    );
  }
}

class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                'Sign in to Color Blendr',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Your saved palettes sync to your account so they’re there on any device.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const GoogleSignInButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedIn extends ConsumerStatefulWidget {
  const _SignedIn({required this.user});
  final AppUser user;

  @override
  ConsumerState<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends ConsumerState<_SignedIn> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showMessage(context, doneMessage);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final count = ref.read(libraryProvider).value?.length;
    final palettes = switch (count) {
      null => 'all your saved palettes',
      1 => 'your 1 saved palette',
      _ => 'all $count of your saved palettes',
    };
    final renews = widget.user.subscription?.willRenew ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
          title: const Text('Delete your account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes your Color Blendr account and $palettes. This can’t be undone.',
              ),
              if (renews) ...[
                const SizedBox(height: 12),
                Text(
                  'Deleting your account doesn’t cancel your Google Play '
                  'subscription. Cancel it in Google Play to stop being charged.',
                  style: TextStyle(color: scheme.error),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => openManageSubscription(context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Manage subscription'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete account'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _run(
        ref.read(authProvider.notifier).deleteAccount,
        'Your account was deleted',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;
    final initial = user.displayName.characters.first.toUpperCase();

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundImage: user.avatarUrl == null
                ? null
                : NetworkImage(user.avatarUrl!),
            onForegroundImageError: user.avatarUrl == null ? null : (_, _) {},
            child: Text(
              initial,
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(user.displayName),
          subtitle: user.name == null ? null : Text(user.email),
        ),
        _PlanTile(user: user),
        if (_busy) const LinearProgressIndicator(),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () =>
              _run(ref.read(authProvider.notifier).signOut, 'Signed out'),
        ),
        ListTile(
          enabled: !_busy,
          iconColor: theme.colorScheme.error,
          textColor: theme.colorScheme.error,
          leading: const Icon(Icons.delete_forever_outlined),
          title: const Text('Delete account'),
          subtitle: const Text(
            'Permanently remove your account and saved palettes',
          ),
          onTap: _confirmDelete,
        ),
      ],
    );
  }
}
