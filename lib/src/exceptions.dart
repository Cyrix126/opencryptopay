
/// OpenCryptoPay API responds with HTTP 404, the
/// seller has not created a pending payment for the scanned cash register yet.
class OpenCryptoPayNoPendingPaymentException implements Exception {
  OpenCryptoPayNoPendingPaymentException([this.message]);
  final String? message;

  @override
  String toString() =>
      message ?? 'The seller has not created a pending payment yet.';
}

/// Thrown when the selected method/asset is not supported by the provider
/// (HTTP 400).
class OpenCryptoPayUnsupportedMethodException implements Exception {
  OpenCryptoPayUnsupportedMethodException([this.message]);
  final String? message;

  @override
  String toString() =>
      message ?? 'This cryptocurrency is not supported for this payment.';
}

/// The scanned data is recognized as an OpenCryptoPay link but is
/// invalid.
class OpenCryptoPayInvalidUriException implements Exception {
  OpenCryptoPayInvalidUriException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown for unexpected HTTP failures or malformed responses.
class OpenCryptoPayApiException implements Exception {
  OpenCryptoPayApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

