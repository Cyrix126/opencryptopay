import 'dart:convert';

import 'package:blockchain_utils/bech32/bech32_base.dart';
import 'package:http/http.dart';

import 'coin.dart';
import 'exceptions.dart';
import 'method_map.dart';
import 'payment_details.dart';

/// OpenCryptoPay flow service.
///
/// Stateless apart from the injected [Client]; safe to share via a single
/// instance. Wallets construct it with their `package:http` [Client] (which
/// may be configured for Tor / SOCKS routing at the client level).
class OpenCryptoPayService {
  OpenCryptoPayService({required Client client}) : _client = client;

  final Client _client;

  /// QR links look like `https://<provider-host>/pl/?lightning=LNURL1...`.
  /// Detected on any host by the `/pl/` path and the `lightning` query
  /// parameter.
  static bool isOpenCryptoPayUri(String? data) {
    if (data == null) return false;
    final uri = Uri.tryParse(data);
    if (uri == null) return false;
    if (!uri.isScheme('https')) {
      return false;
    }
    final String? lnurl;
    try {
      lnurl = uri.queryParameters['lightning'];
    } on FormatException {
      // A percent escape in the query does not decode to UTF-8.
      return false;
    }
    if (lnurl == null || lnurl.isEmpty) return false;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return path == '/pl';
  }

  /// Extract the bech32 (LNURL) parameter from the scanned QR link.
  static String extractLnurl(String qrData) {
    final uri = Uri.tryParse(qrData);
    final lnurl = uri?.queryParameters['lightning'];
    if (lnurl == null || lnurl.isEmpty) {
      throw OpenCryptoPayInvalidUriException(
        'Scanned code is not a valid OpenCryptoPay link.',
      );
    }
    return lnurl;
  }

  /// Decode an LNURL (LUD-01) into its https (or onion http) API URL.
  static String decodeLnurl(String lnurl) {
    final url = Uri.parse(utf8.decode(Bech32Decoder.decode('lnurl', lnurl)));
    if (!(url.isScheme('https') || url.isScheme('http'))) {
      throw OpenCryptoPayInvalidUriException(
        'The LNURL does not encode a web URL.',
      );
    }
    if (url.host.isEmpty) {
      throw OpenCryptoPayInvalidUriException('The LNURL has no host.');
    }
    return _upgradeToHttps(url).toString();
  }

  // LUD-01 allows plain http for onion services.
  static Uri _upgradeToHttps(Uri url) =>
      url.isScheme('http') && !url.host.endsWith('.onion')
          ? url.replace(scheme: 'https')
          : url;

  /// Build the transaction-details request URL by appending the `quote`,
  /// `method` and `asset` query parameters to the [callback] URL.
  static Uri buildTransactionDetailsUrl({
    required String callback,
    required CryptoCoin coin,
    required String quoteId,
  }) {
    final base = _upgradeToHttps(Uri.parse(callback));
    final method = openCryptoPayMethodFor(coin);
    final params = Map<String, String>.from(base.queryParameters);
    params['quote'] = quoteId;
    params['method'] = method.method;
    params['asset'] = method.asset;
    return base.replace(queryParameters: params);
  }

  /// First request: fetch payment info from the OpenCryptoPay API.
  Future<OpenCryptoPayPaymentInfo> fetchPaymentInfo({
    required String apiUrl,
  }) async {
    final response = await _get(Uri.parse(apiUrl));
    return OpenCryptoPayPaymentInfo.fromJson(_json(response), apiUrl: apiUrl);
  }

  /// Second request: fetch transaction details for [coin] from the
  /// [callback]. Values from [fetchPaymentInfo] are carried through into the
  /// returned details.
  Future<OpenCryptoPayTransactionDetails> fetchTransactionDetails({
    required String apiUrl,
    required CryptoCoin coin,
    required String displayName,
    required String quoteId,
    required String callback,
    required DateTime quoteExpiration,
    OpenCryptoPayRecipient? recipient,
  }) async {
    final response = await _get(buildTransactionDetailsUrl(
      callback: callback,
      coin: coin,
      quoteId: quoteId,
    ));
    if (response.statusCode == 400) {
      throw OpenCryptoPayUnsupportedMethodException(
        _tryExtractMessage(response),
      );
    }

    return OpenCryptoPayTransactionDetails.fromJson(
      _json(response),
      apiUrl: apiUrl,
      displayName: displayName,
      quoteId: quoteId,
      callback: callback,
      quoteExpiration: quoteExpiration,
      recipient: recipient,
    );
  }

  /// Build the https transaction-proof URL from the [callback] URL by
  /// replacing its `cb` path segment with `tx`, as specified by the standard
  /// ("The API URL to send the transaction proof back to the payment provider
  /// can be constructed by using the callback URL and replacing `/cb` with
  /// `/tx`").
  static Uri buildTransactionProofUrl(String callback) {
    final base = Uri.parse(callback);
    final segments = List<String>.of(base.pathSegments);
    final index = segments.lastIndexOf('cb');
    if (base.host.isEmpty || index == -1) {
      throw OpenCryptoPayApiException(
        'Callback URL has no host or no /cb segment to derive the proof '
        'endpoint from.',
      );
    }
    segments[index] = 'tx';
    return _upgradeToHttps(base.replace(pathSegments: segments));
  }

  /// Submit [txProof] under [quoteId], or the quote of [details] when null.
  Future<void> submitTransactionProof({
    required OpenCryptoPayTransactionDetails details,
    required CryptoCoin coin,
    required String txProof,
    String? quoteId,
  }) async {
    if (!details.isBroadcastRequired && details.isQuoteExpired) {
      throw OpenCryptoPayQuoteExpiredException(
        'The payment quote has expired; cannot submit signed transaction HEX.',
      );
    }

    final base = buildTransactionProofUrl(details.callback);
    final params = Map<String, String>.from(base.queryParameters);
    params['quote'] = quoteId ?? details.quoteId;
    params['method'] = openCryptoPayMethodFor(coin).method;
    if (details.isBroadcastRequired) {
      params['tx'] = txProof;
    } else {
      params['hex'] = txProof;
    }

    final response = await _get(base.replace(queryParameters: params));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCryptoPayApiException(
        'Transaction proof submission failed (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  Future<Response> _get(Uri url) async {
    try {
      return await _client.get(url);
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Failed to reach OpenCryptoPay service: $e',
      );
    }
  }

  /// The JSON object of a successful [response].
  static Map<String, dynamic> _json(Response response) {
    if (response.statusCode == 404) {
      throw OpenCryptoPayNoPendingPaymentException(
        _tryExtractMessage(response),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCryptoPayApiException(
        'OpenCryptoPay service returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Could not parse OpenCryptoPay response.',
      );
    }
  }

  static String? _tryExtractMessage(Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // ignore – fall back to default message
    }
    return null;
  }
}
