import 'package:decimal/decimal.dart';

import 'coin.dart';
import 'exceptions.dart';
import 'method_map.dart';
import 'payment_details.dart';
import 'result.dart';
import 'service.dart';
import 'session.dart';

export 'result.dart';

/// OpenCryptoPay payment flow.
///
/// Given scanned QR data and the wallet's coin, this:
/// 1. Decodes the LNURL embedded in the OpenCryptoPay link.
/// 2. Fetches the payment info (display name, quote id, supported methods).
/// 3. Checks whether the wallet's coin is supported; if not, computes payable
///    alternatives from the already-fetched supported-method list.
/// 4. Fetches the transaction details and classifies the outcome.
///
/// Stateless apart from the injected [OpenCryptoPayService]; a single shared
/// instance is fine.
class OpenCryptoPayController {
  OpenCryptoPayController({required OpenCryptoPayService service})
      : _service = service;

  final OpenCryptoPayService _service;

  /// Whether the qr code data is a scannable OpenCryptoPay link.
  static bool isOpenCryptoPayUri(String? data) =>
      OpenCryptoPayService.isOpenCryptoPayUri(data);

  /// Decode the scanned [qrData], fetch the payment info and transaction
  /// details for [coin], and classify the outcome. On an unsupported coin,
  /// [ownedCoins] is used to compute payable alternatives (excluding [coin]
  /// itself) from the supported-method list fetched in step 2.
  Future<OpenCryptoPayResult> run({
    required String qrData,
    required CryptoCoin coin,
    Iterable<CryptoCoin>? ownedCoins,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final method = openCryptoPayMethodFor(coin);

    final String apiUrl;
    try {
      final lnurl = OpenCryptoPayService.extractLnurl(qrData);
      apiUrl = OpenCryptoPayService.decodeLnurl(lnurl);
    } catch (e, s) {
      onError?.call(e, s);
      return OpenCryptoPayError(isDecodeError: true, error: e);
    }

    final OpenCryptoPayPaymentInfo paymentInfo;
    try {
      paymentInfo = await _service.fetchPaymentInfo(apiUrl: apiUrl);
    } on OpenCryptoPayNoPendingPaymentException {
      return const OpenCryptoPayNoPending();
    } catch (e, s) {
      onError?.call(e, s);
      return OpenCryptoPayError(isDecodeError: false, error: e);
    }

    if (!_isMethodSupported(paymentInfo.supportedMethods, method)) {
      if (ownedCoins != null) {
        return OpenCryptoPayUnsupported(
          _alternativesFor(
            supportedMethods: paymentInfo.supportedMethods,
            coin: coin,
            ownedCoins: ownedCoins,
          ),
        );
      } else {
        return const OpenCryptoPayUnsupported();
      }
    }

    final OpenCryptoPayTransactionDetails details;
    try {
      details = await _service.fetchTransactionDetails(
        apiUrl: apiUrl,
        coin: coin,
        displayName: paymentInfo.displayName,
        quoteId: paymentInfo.quoteId,
        callback: paymentInfo.callback,
        quoteExpiration: paymentInfo.quoteExpiration,
      );
    } on OpenCryptoPayNoPendingPaymentException {
      return const OpenCryptoPayNoPending();
    } on OpenCryptoPayUnsupportedMethodException {
      if (ownedCoins != null) {
        return OpenCryptoPayUnsupported(
          _alternativesFor(
            supportedMethods: paymentInfo.supportedMethods,
            coin: coin,
            ownedCoins: ownedCoins,
          ),
        );
      } else {
        return const OpenCryptoPayUnsupported();
      }
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

    final displayName = details.displayName;
    final recipientLabel = displayName.isNotEmpty ? displayName : address;

    Decimal? amount;
    final amountString = details.amount;
    if (amountString != null && amountString.isNotEmpty) {
      amount = Decimal.tryParse(amountString);
    }

    return OpenCryptoPaySuccess(
      session: OpenCryptoPaySession(
        details: details,
        coin: coin,
        service: _service,
      ),
      address: address,
      recipientLabel: recipientLabel,
      amount: amount,
    );
  }

  /// Check whether a specific method/asset pair is in the provider's supported
  /// list.
  static bool _isMethodSupported(
    List<SupportedMethod> supportedMethods,
    OpenCryptoPayMethod method,
  ) {
    final key = method.method;
    final asset = method.asset;
    for (final sm in supportedMethods) {
      if (sm.method == key) {
        if (sm.assets.isEmpty ||
            sm.assets.any((a) => a == asset)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Resolve payable alternatives, excluding the rejected (method, asset) pair
  /// but keeping other assets on the same method.
  static List<CryptoCoin> _alternativesFor({
    required List<SupportedMethod> supportedMethods,
    required CryptoCoin coin,
    required Iterable<CryptoCoin> ownedCoins,
  }) {
    final rejectedMethod = openCryptoPayMethodFor(coin).method;
    final rejectedAsset = openCryptoPayMethodFor(coin).asset;
    return ownedCoinsSupportingMethods(
      ownedCoins: ownedCoins.where((c) {
        final m = openCryptoPayMethodFor(c);
        if (m.method == rejectedMethod &&
            m.asset == rejectedAsset) {
          return false;
        }
        return true;
      }),
      supportedMethods: supportedMethods,
    );
  }

}