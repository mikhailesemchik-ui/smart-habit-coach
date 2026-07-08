/// Application-level view of the current Supabase auth identity. Never
/// exposes the raw Supabase `User`/`Session` types to callers; those
/// types and their SDK-specific shape stay behind AuthRepository.
enum AuthIdentityKind {
  /// No session at all.
  unauthenticated,

  /// A session exists and the SDK reports `isAnonymous == true`.
  anonymous,

  /// The current session is email-backed. This is directly observable
  /// after anonymous-to-email linking, but after app restart the SDK only
  /// exposes an email-backed session, not whether it was originally linked
  /// on this device.
  linkedEmail,

  /// Returned only as operation context from an explicit returning-user
  /// sign-in call. This distinction is not reliably inferable from a
  /// persisted Supabase session alone after restart.
  authenticatedReturningUser,
}

class AuthIdentity {
  final String uid;
  final AuthIdentityKind kind;
  final String? email;

  /// Null when not applicable, or when the SDK did not report enough
  /// information to prove confirmation state.
  final bool? emailConfirmed;

  const AuthIdentity({
    required this.uid,
    required this.kind,
    this.email,
    this.emailConfirmed,
  });

  bool get isAnonymous => kind == AuthIdentityKind.anonymous;
  bool get isAuthenticated => uid.trim().isNotEmpty && !isAnonymous;

  static const unauthenticated = AuthIdentity(
    uid: '',
    kind: AuthIdentityKind.unauthenticated,
  );

  @override
  String toString() =>
      'AuthIdentity(uid: $uid, kind: $kind, email: $email, '
      'emailConfirmed: $emailConfirmed)';

  @override
  bool operator ==(Object other) =>
      other is AuthIdentity &&
      other.uid == uid &&
      other.kind == kind &&
      other.email == email &&
      other.emailConfirmed == emailConfirmed;

  @override
  int get hashCode => Object.hash(uid, kind, email, emailConfirmed);
}
