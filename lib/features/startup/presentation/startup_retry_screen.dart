import 'package:flutter/material.dart';

/// Shown when the app cannot establish its first-ever local identity
/// (no persisted session, and anonymous sign-in failed — typically no
/// network on a clean install). Never shows raw technical error text.
class StartupRetryScreen extends StatelessWidget {
  final bool isRetrying;
  final VoidCallback onRetry;
  final String title;
  final String message;

  const StartupRetryScreen({
    super.key,
    required this.isRetrying,
    required this.onRetry,
    this.title = 'Connect to the internet to set up Smart Habit Coach',
    this.message =
        'Smart Habit Coach needs an internet connection once to set up '
        'your private, on-device identity. After that, it works fully '
        'offline.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (isRetrying)
                  const CircularProgressIndicator()
                else
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
