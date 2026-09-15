import 'package:decimal/decimal.dart';

import 'coin.dart';
import 'payment_details.dart';
import 'session.dart';

sealed class OpenCryptoPayResult {
  const OpenCryptoPayResult();
}

/// Any non-success outcome.
sealed class OpenCryptoPayFailure extends OpenCryptoPayResult {
  const OpenCryptoPayFailure();
}

/// The seller has no pending payment (HTTP 404).
class OpenCryptoPayNoPending extends OpenCryptoPayFailure {
  const OpenCryptoPayNoPending();
}

/// The provider rejected this wallet's coin (HTTP 400). [alternatives] holds
/// the user's other coins the provider does support if the user has given
/// the list of their owned coins
class OpenCryptoPayUnsupported extends OpenCryptoPayFailure {
  const OpenCryptoPayUnsupported([this.alternatives]);
  final List<CryptoCoin>? alternatives;
}

/// The payment requires a Lightning invoice
class OpenCryptoPayLightning extends OpenCryptoPayFailure {
  const OpenCryptoPayLightning();
}

/// The response did not contain a usable on-chain address.
class OpenCryptoPayInvalidAddress extends OpenCryptoPayFailure {
  const OpenCryptoPayInvalidAddress();
}

/// The link could not be decoded, or another error occurred.
class OpenCryptoPayError extends OpenCryptoPayFailure {
  const OpenCryptoPayError({required this.isDecodeError, this.error});
  final bool isDecodeError;
  final Object? error;
}

/// A pending payment was found and is payable with this wallet's coin.
class OpenCryptoPaySuccess extends OpenCryptoPayResult {
  OpenCryptoPaySuccess({
    required this.session,
    required this.address,
    required this.recipientLabel,
    required this.amount,
  });

  /// Holds the pending payment and submits the proof once paid.
  final OpenCryptoPaySession session;

  final String address;

  final String recipientLabel;

  /// The requested amount as found in the payment URI, if any. Raw
  /// (smallest-unit) for EVM `value`/`uint256` URIs, decimal coin units
  /// otherwise; prefer [amountInSmallestUnit], which normalizes the two.
  final Decimal? amount;

  OpenCryptoPayTransactionDetails get details => session.details;

  CryptoCoin get coin => session.coin;

  bool get isErc20Transfer => details.isErc20Transfer;

  String? get tokenContractAddress => details.tokenContractAddress;

  bool get isRawAmount => details.isRawAmount;

  OpenCryptoPayProofType get proofType => details.proofType;

  bool get requiresBroadcast => details.requiresBroadcast;

  /// The requested amount in the coin's/token's smallest unit
  /// ([fractionDigits] decimals), or null when the URI carries no amount.
  BigInt? amountInSmallestUnit(int fractionDigits) {
    if (isRawAmount) return BigInt.tryParse(details.amount ?? '');
    final a = amount;
    if (a == null) return null;
    return a.shift(fractionDigits).toBigInt();
  }
}
