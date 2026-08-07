/// Error taxonomy mirroring revnix-react, revnix-swift, and revnix-kotlin.
///
/// Every case is either RETRYABLE (transient — offline, timeout, 429, 5xx,
/// captive portal) or DELIBERATE (401/403/404/409 — the server refused on
/// purpose; a kill-switch must never be defeated by a cache or a retry).
///
/// These codes are the bridge contract: the native side serialises a failure
/// as `{code, message, status?, retryAfterMs?, isRetryable}` and this file
/// rehydrates it. If a typed error ever arrived as a bare `PlatformException`,
/// apps could no longer tell a kill switch from an outage — which is the whole
/// point of the taxonomy.
library;

class RevnixException implements Exception {
  const RevnixException(
    this.code,
    this.message, {
    this.status,
    this.retryAfterMs,
    required this.isRetryable,
  });

  /// One of the v1 taxonomy codes.
  final String code;
  final String message;

  /// HTTP status, when the failure came from a response.
  final int? status;

  /// Server-advised backoff in milliseconds (429 only).
  final int? retryAfterMs;

  /// True when retrying, or serving the offline cache, is the right move.
  final bool isRetryable;

  @override
  String toString() => 'RevnixException($code): $message';
}

/// Connectivity failure (offline, DNS, reset, body read failure). Retryable.
class RevnixNetworkException extends RevnixException {
  const RevnixNetworkException(String message)
      : super('network', message, isRetryable: true);
}

/// Request exceeded the configured timeout. Retryable.
class RevnixTimeoutException extends RevnixException {
  const RevnixTimeoutException(String message)
      : super('timeout', message, isRetryable: true);
}

/// HTTP 429. Retryable with backoff.
class RevnixRateLimitException extends RevnixException {
  const RevnixRateLimitException(String message, {int? retryAfterMs})
      : super('rate_limited', message,
            status: 429, retryAfterMs: retryAfterMs, isRetryable: true);
}

/// HTTP 5xx. Retryable.
class RevnixServerException extends RevnixException {
  const RevnixServerException(String message, {int? status})
      : super('server', message, status: status, isRetryable: true);
}

/// A 200 whose body was not the expected JSON (captive portal). Retryable.
class RevnixBadResponseException extends RevnixException {
  const RevnixBadResponseException(String message)
      : super('bad_response', message, isRetryable: true);
}

/// HTTP 401/403 — missing, revoked, or wrong-kind key. Deliberate.
class RevnixAuthException extends RevnixException {
  const RevnixAuthException(String message, {int? status})
      : super('auth', message, status: status, isRetryable: false);
}

/// HTTP 404 — unknown route or resource. Deliberate.
class RevnixNotFoundException extends RevnixException {
  const RevnixNotFoundException(String message)
      : super('not_found', message, status: 404, isRetryable: false);
}

/// HTTP 409 — blocked by the app's transfer policy. Deliberate.
class RevnixPurchaseBlockedException extends RevnixException {
  const RevnixPurchaseBlockedException(String message)
      : super('purchase_blocked', message, status: 409, isRetryable: false);
}

/// 400 validation, 413 payload cap, and other deliberate refusals.
class RevnixInvalidException extends RevnixException {
  const RevnixInvalidException(String message, {int? status})
      : super('invalid', message, status: status, isRetryable: false);
}

/// Rehydrate a native error into its typed Dart equivalent.
///
/// An unrecognised code is treated as NOT retryable: failing closed is the
/// safe default for a paid feature, and a code we do not understand is not
/// something to paper over with a cache.
RevnixException revnixExceptionFrom(
  String? code,
  String? message,
  Map<Object?, Object?>? details,
) {
  final text = message ?? 'unknown error';
  final status = details?['status'] as int?;
  final retryAfterMs = details?['retryAfterMs'] as int?;
  switch (code) {
    case 'network':
      return RevnixNetworkException(text);
    case 'timeout':
      return RevnixTimeoutException(text);
    case 'rate_limited':
      return RevnixRateLimitException(text, retryAfterMs: retryAfterMs);
    case 'server':
      return RevnixServerException(text, status: status);
    case 'bad_response':
      return RevnixBadResponseException(text);
    case 'auth':
      return RevnixAuthException(text, status: status);
    case 'not_found':
      return RevnixNotFoundException(text);
    case 'purchase_blocked':
      return RevnixPurchaseBlockedException(text);
    case 'invalid':
      return RevnixInvalidException(text, status: status);
    default:
      return RevnixException(code ?? 'unknown', text, isRetryable: false);
  }
}
