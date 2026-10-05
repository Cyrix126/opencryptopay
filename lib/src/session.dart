import 'coin.dart';
import 'exceptions.dart';
import 'method_map.dart';
import 'payment_details.dart';
import 'service.dart';

/// Outcome of [OpenCryptoPaySession.submitProof].
sealed class OpenCryptoPayProofResult {
  const OpenCryptoPayProofResult();
}

/// The provider accepted the proof; the payment is complete.
class OpenCryptoPayProofAccepted extends OpenCryptoPayProofResult {
  const OpenCryptoPayProofAccepted();
}

/// The quote expired before the proof could be submitted. Only occurs on the
/// signed-transaction-hex flow, before this submission reaches the provider.
class OpenCryptoPayProofQuoteExpired extends OpenCryptoPayProofResult {
  const OpenCryptoPayProofQuoteExpired(this.error);
  final Object error;
}

/// Submission failed; the session stays active so the caller can retry.
class OpenCryptoPayProofFailed extends OpenCryptoPayProofResult {
  const OpenCryptoPayProofFailed(this.error);

  final Object error;

  /// Whether the provider refused the proof with a 4xx answer. After any
  /// other failure the provider may hold the payment.
  bool get isRejectedByProvider => switch (error) {
        OpenCryptoPayApiException(:final statusCode?) =>
          statusCode >= 400 && statusCode < 500,
        _ => false,
      };
}

/// A pending payment accepted for the wallet's coin, awaiting proof of payment.
class OpenCryptoPaySession {
  OpenCryptoPaySession({
    required this.details,
    required this.coin,
    required OpenCryptoPayService service,
    this.minFee = 0,
  }) : _service = service;

  final OpenCryptoPayTransactionDetails details;
  final CryptoCoin coin;

  /// [SupportedMethod.minFee] of the method matching [coin].
  final num minFee;
  final OpenCryptoPayService _service;

  OpenCryptoPayFeeUnit get minFeeUnit => switch (coin.chainType) {
        CryptoChainType.bitcoinDerived => OpenCryptoPayFeeUnit.satsPerVByte,
        CryptoChainType.evm => OpenCryptoPayFeeUnit.weiPerGas,
        CryptoChainType.other => OpenCryptoPayFeeUnit.unknown,
      };

  bool _isCompleted = false;
  bool _mayHoldPayment = false;

  /// Whether the proof was already submitted successfully.
  bool get isCompleted => _isCompleted;

  /// Whether a signed transaction whose submission failed may have reached
  /// the provider, so the payment may still go through.
  bool get mayHoldPayment => _mayHoldPayment;

  OpenCryptoPayProofType get proofType => details.proofType;

  /// Whether the wallet must broadcast the transaction itself before
  /// submitting the proof.
  bool get isBroadcastRequired => details.isBroadcastRequired;

  bool get isQuoteExpired => details.isQuoteExpired;

  /// Whether this session still awaits proof of a payment to
  /// [recipientAddress].
  bool isActivePaymentFor(String? recipientAddress) =>
      !_isCompleted &&
      details.address != null &&
      details.address == recipientAddress;

  /// Submit the proof of payment.
  /// [proofType]: the broadcast transaction's id
  /// ([OpenCryptoPayProofType.transactionHash]), or the signed raw transaction
  /// hex ([OpenCryptoPayProofType.signedTransactionHex]) which the provider
  /// broadcasts itself ([isBroadcastRequired] is false).
  Future<OpenCryptoPayProofResult> submitProof(String txProof) async {
    if (_isCompleted) return const OpenCryptoPayProofAccepted();
    try {
      await _service.submitTransactionProof(
        details: details,
        coin: coin,
        txProof: txProof,
      );
      _isCompleted = true;
      return const OpenCryptoPayProofAccepted();
    } on OpenCryptoPayQuoteExpiredException catch (e) {
      return OpenCryptoPayProofQuoteExpired(e);
    } catch (e) {
      final failed = OpenCryptoPayProofFailed(e);
      if (!isBroadcastRequired && !failed.isRejectedByProvider) {
        _mayHoldPayment = true;
      }
      return failed;
    }
  }
}
