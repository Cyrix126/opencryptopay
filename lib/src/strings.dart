import 'result.dart';

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

  static const String invalidAddressTitle = 'Invalid payment';
  static const String invalidAddressMessage =
      'The payment response did not contain a valid address.';

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
  static String quoteExpiredMessage({bool paymentNotSent = false}) =>
      'This payment quote has expired.'
      '${paymentNotSent ? ' The payment was NOT sent.' : ''}'
      ' Ask the seller to create a new payment and scan the QR code again.';

  static const String proofFailedTitle = 'Seller not notified';
  static const String proofFailed =
      'Payment sent, but the seller could not be notified. '
      'Show the transaction to the seller.';

  static const String deliveryFailedTitle = 'Payment not delivered';
  static const String deliveryFailed =
      'Could not deliver the payment to the seller. Nothing was sent.';

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
        OpenCryptoPayError(isDecodeError: true) => (
            title: decodeFailedTitle,
            message: decodeFailedMessage,
          ),
        OpenCryptoPayError() => (
            title: genericErrorTitle,
            message: genericErrorMessage,
          ),
      };

  /// Title and message for a failed proof submission.
  static ({String title, String message}) proofFailure({
    required bool requiresBroadcast,
  }) =>
      requiresBroadcast
          ? (title: proofFailedTitle, message: proofFailed)
          : (title: deliveryFailedTitle, message: deliveryFailed);
}
