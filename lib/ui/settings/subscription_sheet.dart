// "Your subscription" for Pro bought on the website: plan, next payment (or
// when Pro ends) and invoice history, like the web app's subscription dialog.
// "Change subscription" cancels or resumes it at the end of the period paid
// for. Switching plans and changing the card stay on the website, since they
// charge outside Google Play (Play's payments policy). Each settled invoice
// links to Stripe's hosted page (receipt and PDF); unpaid ones don't, since
// that page has a Pay button.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';
import '../common.dart';

/// While Stripe's search hasn't listed a new subscription yet: up to about a
/// minute of checks (the sheet only opens for Pro bought on the web).
const _searchChecks = 12;
const _searchRetry = Duration(seconds: 5);

Future<void> showSubscriptionSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            _SubscriptionSheet(controller: controller),
      ),
    );

class _SubscriptionSheet extends ConsumerStatefulWidget {
  const _SubscriptionSheet({required this.controller});
  final ScrollController controller;

  @override
  ConsumerState<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<_SubscriptionSheet> {
  /// Null once [_loaded]: Stripe doesn't list one yet.
  WebSubscription? _sub;
  bool _loaded = false;
  String? _error;
  int _checks = 0;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sub = await ref.read(blendrApiProvider).webSubscription();
      if (!mounted) return;
      setState(() {
        _sub = sub;
        _loaded = true;
        _error = null;
      });
      if (sub == null && _checks < _searchChecks) {
        _retry = Timer(_searchRetry, () {
          _checks++;
          _load();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _error = describeError(e);
      });
    }
  }

  void _tryAgain() {
    _retry?.cancel();
    setState(() {
      _loaded = false;
      _error = null;
      _checks = 0;
    });
    _load();
  }

  bool get _waiting => _loaded && _sub == null && _checks < _searchChecks;

  bool _saving = false;

  /// "Change subscription": cancel, or keep a cancelled one.
  Future<void> _change() async {
    final sub = _sub;
    if (sub == null) return;
    final cancel = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _ChangeOptions(sub: sub),
    );
    if (cancel == null || !mounted) return;
    if (cancel && !await _confirmCancel(sub)) return;

    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(authProvider.notifier)
          .setWebRenewal(cancel: cancel, test: sub.test);
      if (!mounted) return;
      if (updated != null) setState(() => _sub = updated);
      showMessage(
        context,
        cancel ? 'Subscription cancelled' : 'Your subscription will renew',
      );
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmCancel(WebSubscription sub) async {
    final end = sub.currentPeriodEnd;
    final until = end != null
        ? ' until ${longDate(end)}'
        : ' until the end of this period';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Cancel your subscription?'),
          content: Text(
            'You won’t be charged again, and you keep Pro$until. You can change your mind before then.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Pro'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancel subscription'),
            ),
          ],
        );
      },
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final List<Widget> body;
    if (_error != null) {
      body = [
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 12),
        _TryAgain(onPressed: _tryAgain),
      ];
    } else if (!_loaded) {
      body = [const _Loading('Loading your subscription…')];
    } else if (_waiting) {
      body = [
        const _Loading('Getting your subscription details from Stripe…'),
        const SizedBox(height: 8),
        Text(
          'Your Pro is already on. If you just bought it, the details can take up to a minute to show up here.',
          style: muted,
        ),
      ];
    } else if (_sub == null) {
      body = [
        Text(
          'Your Pro is on, but Stripe hasn’t sent the subscription details yet. Try again in a minute.',
          style: muted,
        ),
        const SizedBox(height: 12),
        _TryAgain(onPressed: _tryAgain),
      ];
    } else {
      body = [
        _PlanCard(
          sub: _sub!,
          saving: _saving,
          onChange: _sub!.isRunning ? _change : null,
        ),
        const SizedBox(height: 16),
        _InvoiceCard(invoices: _sub!.invoices),
      ];
    }

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Your subscription', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        ...body,
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

class _TryAgain extends StatelessWidget {
  const _TryAgain({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton(onPressed: onPressed, child: const Text('Try again')),
  );
}

/// The choices behind "Change subscription". Pops true to cancel, false to
/// keep (resume) a cancelled one.
class _ChangeOptions extends StatelessWidget {
  const _ChangeOptions({required this.sub});
  final WebSubscription sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final end = sub.cancelAt ?? sub.currentPeriodEnd;
    final price = formatMoney(sub.amount, sub.currency);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Change subscription', style: theme.textTheme.titleLarge),
        ),
        if (sub.isEnding)
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('Keep my subscription'),
            subtitle: Text(
              end == null
                  ? 'It renews automatically, and you keep Pro.'
                  : 'It renews on ${longDate(end)}${price.isEmpty ? '' : ' for $price'}, and you keep Pro.',
            ),
            onTap: () => Navigator.of(context).pop(false),
          )
        else
          ListTile(
            iconColor: scheme.error,
            textColor: scheme.error,
            leading: const Icon(Icons.cancel_outlined),
            title: const Text('Cancel subscription'),
            subtitle: Text(
              end == null
                  ? 'You won’t be charged again.'
                  : 'You keep Pro until ${longDate(end)}, and won’t be charged again.',
            ),
            onTap: () => Navigator.of(context).pop(true),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text(
            'To switch between monthly and yearly, or to change your card, use the Color Blendr website, under Account.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.sub, this.saving = false, this.onChange});
  final WebSubscription sub;
  final bool saving;

  /// Null hides "Change subscription" (it has ended).
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final price = formatMoney(sub.amount, sub.currency);
    final plan = switch (sub.interval) {
      'year' => 'Yearly',
      'month' => 'Monthly',
      _ => 'Pro',
    };
    final end = sub.cancelAt ?? sub.currentPeriodEnd;

    final String status;
    if (!sub.isRunning) {
      status = sub.endedAt != null
          ? 'Ended on ${longDate(sub.endedAt!)}.'
          : 'This subscription has ended.';
    } else if (sub.isEnding && end != null) {
      status =
          'Cancelled. You keep Pro until ${longDate(end)}, and won’t be charged again.';
    } else if (sub.currentPeriodEnd != null) {
      status =
          'Next payment: ${price.isEmpty ? '' : '$price '}on ${longDate(sub.currentPeriodEnd!)}.';
    } else {
      status = 'Renews automatically.';
    }

    final (stateLabel, stateColor) = !sub.isRunning
        ? ('Ended', scheme.onSurfaceVariant)
        : sub.isEnding
        ? ('Cancelled', scheme.tertiary)
        : ('Active', scheme.primary);

    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Color Blendr Pro · $plan',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (price.isNotEmpty && sub.interval != null)
                        Text(
                          '$price per ${sub.interval}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  stateLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: stateColor,
                  ),
                ),
              ],
            ),
            if (sub.test) ...[
              const SizedBox(height: 4),
              Text(
                'Test purchase (Stripe test mode)',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(status),
            if (sub.status == 'past_due') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your last payment didn’t go through. Update your card on the Color Blendr website to keep Pro.',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            if (onChange != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: saving ? null : onChange,
                child: Text(saving ? 'Saving…' : 'Change subscription'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoices});
  final List<WebInvoice> invoices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Invoice history', style: theme.textTheme.titleMedium),
          ),
          if (invoices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'No invoices yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (final i in invoices) _InvoiceRow(invoice: i),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});
  final WebInvoice invoice;

  /// Paid, refunded or void invoices only: an unpaid invoice's Stripe page
  /// asks for payment, which the app must not offer outside Google Play.
  Uri? get _link {
    final url = invoice.url;
    final settled =
        invoice.refunded ||
        invoice.status == 'paid' ||
        invoice.status == 'void';
    if (url == null || !settled) return null;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' ? uri : null;
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showMessage(context, 'Couldn’t open the invoice');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = invoice.refunded
        ? 'Refunded'
        : switch (invoice.status) {
            'paid' => 'Paid',
            'open' => 'Due',
            'void' => 'Void',
            'uncollectible' => 'Unpaid',
            final s => s,
          };
    final labelColor = switch (label) {
      'Paid' => scheme.primary,
      'Due' || 'Unpaid' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
    final link = _link;

    return ListTile(
      title: Text(shortDate(invoice.date)),
      subtitle: Text(formatMoney(invoice.amount, invoice.currency)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: labelColor)),
          if (link != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.open_in_new, size: 18, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
      onTap: link == null ? null : () => _open(context, link),
    );
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "November 19, 2026"
String longDate(DateTime date) {
  final d = date.toLocal();
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// "Nov 19, 2026"
String shortDate(DateTime date) {
  final d = date.toLocal();
  return '${_months[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';
}

/// Stripe's currencies without minor units (amounts are already whole).
const _zeroDecimal = {
  'bif', 'clp', 'djf', 'gnf', 'jpy', 'kmf', 'krw', 'mga', //
  'pyg', 'rwf', 'ugx', 'vnd', 'vuv', 'xaf', 'xof', 'xpf',
};

const _symbols = {
  'usd': r'$',
  'cad': r'CA$',
  'aud': r'A$',
  'eur': '€',
  'gbp': '£',
  'jpy': '¥',
  'inr': '₹',
};

/// A Stripe amount in minor units as "$4.99", or "" when unknown.
String formatMoney(int? amount, String? currency) {
  if (amount == null || currency == null || currency.isEmpty) return '';
  final code = currency.toLowerCase();
  final whole = _zeroDecimal.contains(code);
  final value = whole ? amount.toString() : (amount / 100).toStringAsFixed(2);
  final symbol = _symbols[code];
  return symbol != null ? '$symbol$value' : '$value ${code.toUpperCase()}';
}
