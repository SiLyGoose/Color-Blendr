import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/blendr_api.dart';
import '../data/color_source.dart';
import '../data/google_auth.dart';
import '../data/models.dart';
import '../state/auth_controller.dart';

/// A user-facing message for any error our layers throw.
String describeError(Object error) => switch (error) {
  ApiException(:final message) => message,
  GoogleAuthException(:final message) => message,
  ColorSourceException(:final message) => message,
  _ => 'Something went wrong. Try again.',
};

void showMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: Duration(milliseconds: action == null ? 2000 : 4000),
      ),
    );
}

Future<void> copyColors(BuildContext context, List<PaletteColor> colors) async {
  final text = colors.map((c) => c.label).join(' ');
  await Clipboard.setData(ClipboardData(text: text));
  await HapticFeedback.selectionClick();
  if (context.mounted) {
    showMessage(
      context,
      colors.length == 1 ? 'Copied $text' : 'Copied ${colors.length} hex codes',
    );
  }
}

/// "Continue with Google" with its own busy state. Shows errors as a snackbar
/// unless [onError] is given.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key, this.onSignedIn, this.onError});

  final VoidCallback? onSignedIn;
  final void Function(String message)? onError;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final signedIn = await ref.read(authProvider.notifier).signIn();
      if (signedIn) widget.onSignedIn?.call();
    } catch (e) {
      final message = describeError(e);
      if (widget.onError != null) {
        widget.onError!(message);
      } else if (mounted) {
        showMessage(context, message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _signIn,
      style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label: const Text('Continue with Google'),
    );
  }
}

/// Centered icon + title + body + optional action, for empty/signed-out/error states.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet asking the user to sign in. Resolves true once signed in.
Future<bool> showSignInSheet(
  BuildContext context, {
  required String reason,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => _SignInSheet(reason: reason),
  );
  return result ?? false;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.reason});
  final String reason;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_add_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Save your palettes', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              widget.reason,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            GoogleSignInButton(
              onSignedIn: () => Navigator.of(context).pop(true),
              onError: (message) => setState(() => _error = message),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
