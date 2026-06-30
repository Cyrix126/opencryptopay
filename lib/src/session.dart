import 'coin.dart';
import 'exceptions.dart';
import 'payment_details.dart';
import 'service.dart';
import 'strings.dart';

/// Outcome of [OpenCryptoPaySession.submitProof].
sealed class OpenCryptoPayProofResult {
  const OpenCryptoPayProofResult();
}

/// The provider accepted the proof; the payment is complete.
class OpenCryptoPayProofAccepted extends OpenCryptoPayProofResult {
  const OpenCryptoPayProofAccepted();
}

/// The quote expired before the proof could be submitted. Only occurs on the
/// signed-transaction-hex flow, before anything reaches the provider — the
/// payment was NOT sent.
class OpenCryptoPayProofQuoteExpired extends OpenCryptoPayProofResult {
  const OpenCryptoPayProofQuoteExpired(this.error);
  final Object error;
}

/// Submission failed; the session stays active so the caller can retry.
class OpenCryptoPayProofFailed extends OpenCryptoPayProofResult {
  const OpenCryptoPayProofFailed({required this.message, required this.error});

  /// User-facing message, worded for whether the wallet already broadcast
  /// the transaction itself (see [OpenCryptoPayStrings.proofFailed] and
  /// [OpenCryptoPayStrings.deliveryFailed]).
  final String message;

  final Object error;
}

/// A pending payment accepted for the wallet's coin, awaiting proof of payment.
class OpenCryptoPaySession {
  OpenCryptoPaySession({
    required this.details,
    required this.coin,
    required OpenCryptoPayService service,
  }) : _service = service;

  final OpenCryptoPayTransactionDetails details;
  final CryptoCoin coin;
  final OpenCryptoPayService _service;

  bool _completed = false;

  /// Whether the proof was already submitted successfully.
  bool get isCompleted => _completed;

  OpenCryptoPayProofType get proofType => details.proofType;

  /// Whether the wallet must broadcast the transaction itself before
  /// submitting the proof.
  bool get requiresBroadcast => details.requiresBroadcast;

  bool get isQuoteExpired => details.isQuoteExpired;

  /// Whether this session still awaits proof of a payment to
  /// [recipientAddress].
  bool isActivePaymentFor(String? recipientAddress) =>
      !_completed &&
      details.address != null &&
      details.address == recipientAddress;

  /// Submit the proof of payment.
  /// [proofType]: the broadcast transaction's id
  /// ([OpenCryptoPayProofType.transactionHash]), or the signed raw transaction
  /// hex ([OpenCryptoPayProofType.signedTransactionHex]) which the provider
  /// broadcasts itself ([requiresBroadcast] is false).
  Future<OpenCryptoPayProofResult> submitProof(String txProof) async {
    if (_completed) return const OpenCryptoPayProofAccepted();
    try {
      await _service.submitTransactionProof(
        details: details,
        coin: coin,
        txProof: txProof,
      );
      _completed = true;
      return const OpenCryptoPayProofAccepted();
    } on OpenCryptoPayQuoteExpiredException catch (e) {
      return OpenCryptoPayProofQuoteExpired(e);
    } catch (e) {
      return OpenCryptoPayProofFailed(
        message: requiresBroadcast
            ? OpenCryptoPayStrings.proofFailed(e)
            : OpenCryptoPayStrings.deliveryFailed(e),
        error: e,
      );
    }
  }
}
