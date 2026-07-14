import 'package:flutter/material.dart';

import '../../sync/presentation/sync_controller.dart';
import '../data/auth_repository.dart';
import '../data/returning_user_sign_in_service.dart';
import '../data/sign_out_service.dart';
import '../domain/auth_identity.dart';
import 'account_controller.dart';
import 'account_keys.dart';

class AccountScreen extends StatefulWidget {
  final AuthRepository? authRepository;
  final ReturningUserSignInService? returningUserSignInService;
  final SignOutService? signOutService;
  final Future<void> Function()? onIdentityChanged;
  final AccountController? controller;
  final SyncController? syncController;

  const AccountScreen({
    super.key,
    this.authRepository,
    this.returningUserSignInService,
    this.signOutService,
    this.onIdentityChanged,
    this.controller,
    this.syncController,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountController _controller;
  late final bool _ownsController;
  late final SyncController _syncController;
  late final bool _ownsSyncController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        AccountController(
          authRepository: widget.authRepository,
          returningUserSignInService: widget.returningUserSignInService,
          signOutService: widget.signOutService,
          onIdentityChanged: widget.onIdentityChanged,
        );
    _controller.addListener(_onControllerChanged);
    _controller.load();

    _ownsSyncController = widget.syncController == null;
    _syncController = widget.syncController ?? SyncController();
    _syncController.addListener(_onControllerChanged);
    _syncController.loadStatus();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _syncController.removeListener(_onControllerChanged);
    if (_ownsSyncController) _syncController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final pending = _controller.state.pendingSignIn;
    if (pending != null && !_s2DialogOpen) {
      _showS2Confirmation();
    }
  }

  bool _s2DialogOpen = false;

  Future<void> _showS2Confirmation() async {
    _s2DialogOpen = true;
    final preserve = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preserve local data?'),
        content: const Text(
          'This anonymous local data will stay stored on this device under its current identity. It will not be merged into the returning account. After sign-in, the app will show data associated with the returning account.',
        ),
        actions: [
          TextButton(
            key: cancelAccountSwitchButtonKey,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: preserveAndSignInButtonKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Preserve data, then sign in'),
          ),
        ],
      ),
    );
    _s2DialogOpen = false;
    if (!mounted) return;
    if (preserve == true) {
      await _controller.confirmPreserveAndSignIn();
    } else {
      _controller.cancelPendingSignIn();
    }
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your current account data remains stored under this account identity. The app will return to a new anonymous identity. No data is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.operation == AccountOperation.loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            _StatusCard(identity: state.identity),
            if (state.failure != null) ...[
              const SizedBox(height: 12),
              _MessageBanner(
                icon: Icons.error_outline,
                text: authFailureMessage(state.failure!),
              ),
            ],
            if (state.successMessage != null) ...[
              const SizedBox(height: 12),
              _MessageBanner(
                icon: Icons.check_circle_outline,
                text: state.successMessage!,
              ),
            ],
            const SizedBox(height: 16),
            if (state.identity.kind == AuthIdentityKind.unauthenticated)
              _UnauthenticatedSection(onRetry: _controller.load)
            else if (state.identity.isAnonymous)
              _AnonymousSection(controller: _controller)
            else
              _LinkedSection(
                identity: state.identity,
                isBusy: state.isBusy,
                onSignOut: _confirmSignOut,
              ),
          ],
          if (!state.identity.isAnonymous &&
              state.identity.kind != AuthIdentityKind.unauthenticated) ...[
            const SizedBox(height: 24),
            const Divider(),
            _SyncSection(controller: _syncController),
          ],
        ],
      ),
    );
  }
}

class _SyncSection extends StatelessWidget {
  final SyncController controller;

  const _SyncSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sync', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          state.lastSuccessfulSyncAt != null
              ? 'Last synced: ${state.lastSuccessfulSyncAt}'
              : 'Never synced on this device.',
          key: lastSyncedTextKey,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (state.lastFailure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MessageBanner(
              icon: Icons.error_outline,
              text: syncFailureMessage(state.lastFailure!),
            ),
          )
        else if (state.lastSummary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MessageBanner(
              icon: Icons.check_circle_outline,
              text: syncSummaryMessage(state.lastSummary!),
            ),
          ),
        FilledButton.icon(
          key: syncNowButtonKey,
          onPressed: state.isSyncing ? null : controller.syncNow,
          icon: state.isSyncing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(state.isSyncing ? 'Syncing…' : 'Sync now'),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AuthIdentity identity;

  const _StatusCard({required this.identity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (identity.kind) {
      AuthIdentityKind.unauthenticated => 'Session not ready',
      AuthIdentityKind.anonymous => 'Anonymous account',
      AuthIdentityKind.linkedEmail ||
      AuthIdentityKind.authenticatedReturningUser =>
        identity.email ?? 'Email account',
    };
    final subtitle = switch (identity.kind) {
      AuthIdentityKind.unauthenticated =>
        'Retry account setup before changing account settings.',
      AuthIdentityKind.anonymous =>
        'Your habit data is private to this device identity.',
      AuthIdentityKind.linkedEmail ||
      AuthIdentityKind.authenticatedReturningUser => _confirmationLabel(
        identity,
      ),
    };

    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(title),
        subtitle: Text(subtitle),
        titleTextStyle: theme.textTheme.titleMedium,
      ),
    );
  }

  static String _confirmationLabel(AuthIdentity identity) {
    if (identity.emailConfirmed == true) return 'Email confirmed.';
    if (identity.emailConfirmed == false) {
      return 'Check your email to confirm the address.';
    }
    return 'Email confirmation status is unknown.';
  }
}

class _MessageBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MessageBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _UnauthenticatedSection extends StatelessWidget {
  final VoidCallback onRetry;

  const _UnauthenticatedSection({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: accountRetryButtonKey,
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Retry'),
    );
  }
}

class _AnonymousSection extends StatelessWidget {
  final AccountController controller;

  const _AnonymousSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isBusy = controller.state.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Link this anonymous identity to an email account, or sign in to an existing account. Returning sign-in never merges anonymous data into the returning account.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: accountLinkActionKey,
          onPressed: isBusy ? null : () => _openLinkForm(context),
          icon: const Icon(Icons.link),
          label: const Text('Link account'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: accountSignInActionKey,
          onPressed: isBusy ? null : () => _openSignInForm(context),
          icon: const Icon(Icons.login),
          label: const Text('Sign in to existing account'),
        ),
        if (isBusy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Future<void> _openLinkForm(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LinkAccountSheet(controller: controller),
    );
  }

  Future<void> _openSignInForm(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SignInSheet(controller: controller),
    );
  }
}

class _LinkedSection extends StatelessWidget {
  final AuthIdentity identity;
  final bool isBusy;
  final VoidCallback onSignOut;

  const _LinkedSection({
    required this.identity,
    required this.isBusy,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Local data remains associated with this account identity on this device.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: signOutActionKey,
          onPressed: isBusy ? null : onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        if (isBusy) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

class _LinkAccountSheet extends StatefulWidget {
  final AccountController controller;

  const _LinkAccountSheet({required this.controller});

  @override
  State<_LinkAccountSheet> createState() => _LinkAccountSheetState();
}

class _LinkAccountSheetState extends State<_LinkAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    await widget.controller.linkAccount(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (widget.controller.state.failure == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.state.isBusy || _isSubmitting;
    return _AccountFormShell(
      title: 'Link account',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: linkEmailFieldKey,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) => validateAccountEmail(value ?? ''),
            ),
            TextFormField(
              key: linkPasswordFieldKey,
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) => validateAccountPassword(value ?? ''),
            ),
            TextFormField(
              key: linkConfirmPasswordFieldKey,
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) {
                if (value != _password.text) return 'Passwords must match.';
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: linkSubmitButtonKey,
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Link account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInSheet extends StatefulWidget {
  final AccountController controller;

  const _SignInSheet({required this.controller});

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    await widget.controller.signIn(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    final state = widget.controller.state;
    if (state.failure == null && !state.confirmationRequired) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.state.isBusy || _isSubmitting;
    return _AccountFormShell(
      title: 'Sign in',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: signInEmailFieldKey,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) => validateAccountEmail(value ?? ''),
            ),
            TextFormField(
              key: signInPasswordFieldKey,
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (value) =>
                  validateAccountPassword(value ?? '', requireMinimum: false),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: signInSubmitButtonKey,
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountFormShell extends StatelessWidget {
  final String title;
  final Widget child;

  const _AccountFormShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
