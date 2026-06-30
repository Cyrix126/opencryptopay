import 'package:decimal/decimal.dart';

import 'coin.dart';
import 'payment_details.dart';
import 'strings.dart';

sealed class OpenCryptoPayResult {
  const OpenCryptoPayResult();
}

/// The seller has no pending payment (HTTP 404).
class OpenCryptoPayNoPending extends OpenCryptoPayResult {
  const OpenCryptoPayNoPending();
}

/// The provider rejected this wallet's coin (HTTP 400). [alternatives] holds
/// the user's other coins the provider does support.
class OpenCryptoPayUnsupported extends OpenCryptoPayResult {
  const OpenCryptoPayUnsupported(this.alternatives);
  final List<CryptoCoin> alternatives;
}

/// The payment requires a Lightning invoice
class OpenCryptoPayLightning extends OpenCryptoPayResult {
  const OpenCryptoPayLightning();
}

/// The response did not contain a usable on-chain address.
class OpenCryptoPayInvalidAddress extends OpenCryptoPayResult {
  const OpenCryptoPayInvalidAddress();
}

/// The link could not be decoded, or another error occurred.
class OpenCryptoPayError extends OpenCryptoPayResult {
  const OpenCryptoPayError({required this.isDecodeError, this.error});
  final bool isDecodeError;
  final Object? error;

  String get title => isDecodeError
      ? OpenCryptoPayStrings.decodeFailedTitle
      : OpenCryptoPayStrings.genericErrorTitle;

  String get message => isDecodeError
      ? OpenCryptoPayStrings.decodeFailedMessage
      : (error?.toString() ?? OpenCryptoPayStrings.genericErrorMessage);
}

/// A pending payment was found and is payable with this wallet's coin.
class OpenCryptoPaySuccess extends OpenCryptoPayResult {
  const OpenCryptoPaySuccess({
    required this.details,
    required this.method,
    required this.address,
    required this.recipientLabel,
    required this.amount,
  });

  final OpenCryptoPayTransactionDetails details;

  /// Coin used (provider method name).
  final String method;

  /// Recipient crypto address.
  final String address;

  final String recipientLabel;

  /// The parsed payment amount
  final Decimal? amount;
}
