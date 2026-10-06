import 'result.dart';
import 'session.dart';

/// User-facing strings for the OpenCryptoPay flow.
///
/// Kept as plain constants so wallets can either display them directly or use
/// them as keys for localization.
class OpenCryptoPayStrings {
  OpenCryptoPayStrings._();

  static const String loading = 'Loading OpenCryptoPay payment...';

  static const String noPendingTitle = 'No pending payment';
  static const String noPendingMessage =
      'The seller has not created a payment yet. Ask the seller to '
      'create the payment on their cash register, then scan the qr code again.';

  static const String lightningTitle = 'Unsupported payment';
  static const String lightningMessage =
      'This payment requires a Lightning invoice, which is not supported.';

  static const String multipleTransactionsTitle = 'Unsupported payment';
  static const String multipleTransactionsMessage =
      'The payment request accepts one transaction, and this payment needs '
      'several. Pay from another balance or wallet.';

  static const String signedTransactionTitle = 'Unsupported payment';
  static const String signedTransactionMessage =
      'This payment requires a signed transaction, which is not supported for '
      'this send. Pay from another balance or wallet.';

  static const String invalidAddressTitle = 'Invalid payment';
  static const String invalidAddressMessage =
      'The payment response did not contain a valid address.';

  static const String invalidAmountTitle = 'Invalid payment';
  static const String invalidAmountMessage =
      'The payment response did not contain a valid amount.';

  static const String unknownProofTypeTitle = 'Unsupported payment';
  static const String unknownProofTypeMessage =
      'This payment method is not supported. Pay with another coin.';

  static const String decodeFailedTitle = 'Decoding unsuccessful';
  static const String decodeFailedMessage =
      'This OpenCryptoPay code could not be decoded.';

  static const String unsupportedMethodTitle = 'Unsupported coin';
  static const String unsupportedMethod =
      'This cryptocurrency is not supported for this payment.';

  static const String genericErrorTitle = 'Something went wrong';
  static const String genericErrorMessage =
      'Could not load this OpenCryptoPay payment.';

  static const String quoteExpiredTitle = 'Payment quote expired';
  static String quoteExpiredMessage({bool isPaymentUnsent = false}) =>
      'This payment quote has expired.'
      '${isPaymentUnsent ? ' The payment was NOT sent.' : ''}'
      ' Ask the seller to create a new payment and scan the QR code again.';

  static const String proofFailedTitle = 'Seller confirmation missing';
  static const String proofFailed =
      'Payment sent, but the confirmation from the seller did not arrive. '
      'Show the transaction to the seller and do not pay again.';

  static const String deliveryFailedTitle = 'Payment not delivered';
  static const String deliveryFailed =
      'Could not deliver the payment to the seller. Nothing was sent.';

  static const String deliveryUnconfirmedTitle = 'Delivery not confirmed';
  static const String deliveryUnconfirmed =
      'The delivery to the seller could not be confirmed. '
      'Check your transaction history before paying again.';

  /// Title and message for a [failure].
  static ({String title, String message}) failure(
    OpenCryptoPayFailure failure,
  ) =>
      switch (failure) {
        OpenCryptoPayNoPending() => (
            title: noPendingTitle,
            message: noPendingMessage,
          ),
        OpenCryptoPayUnsupported() => (
            title: unsupportedMethodTitle,
            message: unsupportedMethod,
          ),
        OpenCryptoPayLightning() => (
            title: lightningTitle,
            message: lightningMessage,
          ),
        OpenCryptoPayInvalidAddress() => (
            title: invalidAddressTitle,
            message: invalidAddressMessage,
          ),
        OpenCryptoPayInvalidAmount() => (
            title: invalidAmountTitle,
            message: invalidAmountMessage,
          ),
        OpenCryptoPayUnknownProofType() => (
            title: unknownProofTypeTitle,
            message: unknownProofTypeMessage,
          ),
        OpenCryptoPayError(isDecodeError: true) => (
            title: decodeFailedTitle,
            message: decodeFailedMessage,
          ),
        OpenCryptoPayError() => (
            title: genericErrorTitle,
            message: genericErrorMessage,
          ),
      };

  /// Title and message for the session's failed proof submission.
  static ({String title, String message}) proofFailure(
    OpenCryptoPaySession session,
  ) {
    if (session.isBroadcastRequired) {
      return (title: proofFailedTitle, message: proofFailed);
    }
    return session.mayHoldPayment
        ? (title: deliveryUnconfirmedTitle, message: deliveryUnconfirmed)
        : (title: deliveryFailedTitle, message: deliveryFailed);
  }

  /// Title and message when an expired quote stops the session's payment.
  static ({String title, String message}) quoteExpiredAtSend(
    OpenCryptoPaySession session,
  ) =>
      session.mayHoldPayment
          ? (title: deliveryUnconfirmedTitle, message: deliveryUnconfirmed)
          : (
              title: quoteExpiredTitle,
              message: quoteExpiredMessage(isPaymentUnsent: true),
            );
}
