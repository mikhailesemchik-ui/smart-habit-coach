enum CloudErrorCode {
  unauthenticated,
  networkUnavailable,
  permissionDenied,
  rateLimited,
  malformedResponse,
  constraintViolation,
  unavailable,
  unknown,
}

class CloudFailure {
  final CloudErrorCode code;
  final String message;

  const CloudFailure(this.code, this.message);

  @override
  String toString() => 'CloudFailure($code)';
}

class CloudResult<T> {
  final T? _value;
  final CloudFailure? failure;

  const CloudResult._success(this._value) : failure = null;
  const CloudResult._failure(this.failure) : _value = null;

  factory CloudResult.success(T value) => CloudResult._success(value);
  factory CloudResult.failure(CloudFailure failure) =>
      CloudResult._failure(failure);

  bool get isSuccess => failure == null;

  T get value {
    if (failure != null) {
      throw StateError('CloudResult.value read on a failure result: $failure');
    }
    return _value as T;
  }
}

class CloudMappingException implements Exception {
  final String reason;

  const CloudMappingException(this.reason);

  @override
  String toString() => 'CloudMappingException($reason)';
}

CloudFailure cloudMalformed(String reason) => CloudFailure(
  CloudErrorCode.malformedResponse,
  'Cloud data was malformed: $reason',
);
