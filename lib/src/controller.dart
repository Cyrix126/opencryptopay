import 'package:decimal/decimal.dart';

import 'coin.dart';
import 'exceptions.dart';
import 'method_map.dart';
import 'payment_details.dart';
import 'result.dart';
import 'service.dart';

export 'result.dart';

/// OpenCryptoPay payment flow.
///
/// Given scanned QR data and the wallet's coin, this:
/// 1. Decodes the LNURL embedded in the OpenCryptoPay link.
/// 2. Fetches the pending payment details for the coin's method/asset.
/// 3. Classifies the outcome as a [OpenCryptoPayResult], containing payment information for the user to perform.
///
/// Wallets construct the controller with an [OpenCryptoPayService] built with their own client.
/// The controller is stateless apart from that service, so a single shared instance is fine.
class OpenCryptoPayController {
  OpenCryptoPayController({required OpenCryptoPayService service})
      : _service = service;

  final OpenCryptoPayService _service;


  /// Whether the qr code data is a scannable OpenCryptoPay link.
  static bool isOpenCryptoPayUri(String? data) =>
      OpenCryptoPayService.isOpenCryptoPayUri(data);

  /// Decode the scanned [qrData], fetch the pending payment for [coin], and
  /// classify the outcome. On an unsupported coin, [ownedCoins] is used to
  /// compute payable alternatives (excluding [coin] itself).
  Future<OpenCryptoPayResult> run({
    required String qrData,
    required CryptoCoin coin,
    required Iterable<CryptoCoin> ownedCoins,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final method = openCryptoPayMethodFor(coin);

    // Decode QR data.
    final String apiUrl;
    try {
      final lnurl = OpenCryptoPayService.extractLnurl(qrData);
      apiUrl = OpenCryptoPayService.decodeLnurl(lnurl);
    } catch (e, s) {
      onError?.call(e, s);
      return OpenCryptoPayError(isDecodeError: true, error: e);
    }

    // Fetch details.
    final OpenCryptoPayTransactionDetails details;
    try {
      details = await _service.fetchTransactionDetails(
        apiUrl: apiUrl,
        method: method.method,
        asset: method.asset,
      );
    } on OpenCryptoPayNoPendingPaymentException {
      return const OpenCryptoPayNoPending();
    } on OpenCryptoPayUnsupportedMethodException {
      return OpenCryptoPayUnsupported(
        await _alternativesFor(
          apiUrl: apiUrl,
          coin: coin,
          ownedCoins: ownedCoins,
          onError: onError,
        ),
      );
    } catch (e, s) {
      onError?.call(e, s);
      return OpenCryptoPayError(isDecodeError: false, error: e);
    }

    if (details.isLightning) {
      return const OpenCryptoPayLightning();
    }

    final address = details.address;
    if (address == null || address.isEmpty) {
      return const OpenCryptoPayInvalidAddress();
    }

    final displayName = details.displayName?.trim();
    final recipientLabel =
        (displayName != null && displayName.isNotEmpty) ? displayName : address;

    Decimal? amount;
    final amountString = details.amount;
    if (amountString != null && amountString.isNotEmpty) {
      amount = Decimal.tryParse(amountString);
    }

    return OpenCryptoPaySuccess(
      details: details,
      method: method.method,
      address: address,
      recipientLabel: recipientLabel,
      amount: amount,
    );
  }

  /// Resolve the user's wallets whose coin the provider supports.
  Future<List<CryptoCoin>> _alternativesFor({
    required String apiUrl,
    required CryptoCoin coin,
    required Iterable<CryptoCoin> ownedCoins,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      final supported = await _service.fetchSupportedMethods(apiUrl: apiUrl);
      final rejectedMethod = openCryptoPayMethodFor(coin).method.toLowerCase();
      return ownedCoinsSupportingMethods(
        ownedCoins: ownedCoins.where(
          (c) => openCryptoPayMethodFor(c).method.toLowerCase() != rejectedMethod,
        ),
        supportedMethods: supported.toSet(),
      );
    } catch (e, s) {
      onError?.call(e, s);
      return const [];
    }
  }

  /// Submit a request containing the transaction hash as proof of payment.
  Future<Object?> submitProof({
    required OpenCryptoPayTransactionDetails details,
    required String method,
    required String txHash,
  }) async {
    try {
      await _service.submitTransactionProof(
        details: details,
        method: method,
        txHash: txHash,
      );
      return null;
    } catch (e) {
      return e;
    }
  }
}
