import 'auth_error.dart';

/// A typed success/failure result for auth operations — never a bare
/// bool, never a thrown SDK exception reaching the caller.
class AuthResult<T> {
  final T? _value;
  final AuthFailure? failure;

  const AuthResult._success(this._value) : failure = null;
  const AuthResult._failure(this.failure) : _value = null;

  factory AuthResult.success(T value) => AuthResult._success(value);
  factory AuthResult.failure(AuthFailure failure) =>
      AuthResult._failure(failure);

  bool get isSuccess => failure == null;

  T get value {
    if (failure != null) {
      throw StateError('AuthResult.value read on a failure result: $failure');
    }
    return _value as T;
  }
}
