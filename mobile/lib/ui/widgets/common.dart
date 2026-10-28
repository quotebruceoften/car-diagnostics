import 'package:flutter/material.dart';

import '../../core/errors.dart';

String errorText(Object error) => error is CarDiagException ? error.message : '$error';

/// An error message with an optional make-specific hint and retry button.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.hint, this.onRetry});

  final Object error;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(errorText(error), style: TextStyle(color: scheme.onErrorContainer)),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint!, style: TextStyle(color: scheme.onErrorContainer)),
            ],
            if (onRetry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRetry, child: const Text('Try again')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Runs [load], showing a spinner, the error, or [builder]'s result.
class AsyncLoader<T> extends StatefulWidget {
  const AsyncLoader({super.key, required this.load, required this.builder, this.hint});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final String? Function(Object error)? hint;

  @override
  State<AsyncLoader<T>> createState() => _AsyncLoaderState<T>();
}

class _AsyncLoaderState<T> extends State<AsyncLoader<T>> {
  late Future<T> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Center(
          child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
        );
      }
      if (snap.hasError) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [ErrorPanel(error: snap.error!, hint: widget.hint?.call(snap.error!), onRetry: _reload)],
        );
      }
      return widget.builder(context, snap.data as T, _reload);
    },
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required Widget content,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A small coloured pill, e.g. a fault count.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );
}
