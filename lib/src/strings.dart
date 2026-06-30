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

  static String proofFailed(Object error) =>
      'Payment sent, but notifying the seller failed: $error';

  static String deliveryFailed(Object error) =>
      'Could not deliver the payment to the seller: $error';
}
