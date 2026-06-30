import 'dart:convert';

import 'package:bech32/bech32.dart';
import 'package:http/http.dart';

import 'coin.dart';
import 'exceptions.dart';
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
  /// Detected by `/pl/` path + `lightning` query parameter, not by domain.
  static bool isOpenCryptoPayUri(String? data) {
    if (data == null) return false;
    final uri = Uri.tryParse(data);
    if (uri == null) return false;
    if (!uri.isScheme('https')) {
      return false;
    }
    final lnurl = uri.queryParameters['lightning'];
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

  /// Decode an LNURL (LUD-01) into its underlying https API URL.
  static String decodeLnurl(String lnurl) {
    final decoded = bech32.decode(lnurl, lnurl.length + 1);
    final bytes = _convertBits(decoded.data, 5, 8, false);
    return utf8.decode(bytes);
  }

  /// Build the transaction-details request URL by appending the `method` and
  /// `asset` query parameters (derived from [coin]) to the base API URL.
  static Uri buildTransactionDetailsUrl({
    required String apiUrl,
    required CryptoCoin coin,
    required String quoteId
  }) {
    final base = Uri.parse(apiUrl);
    final params = Map<String, String>.from(base.queryParameters);
    params['quote'] = quoteId;
    params['method'] = coin.prettyName.replaceAll(' ', '');
    params['asset'] = coin.ticker;
    return base.replace(queryParameters: params);
  }

  /// First request: fetch payment info from the OpenCryptoPay API.
  /// No method/asset query parameters are appended.
  Future<OpenCryptoPayPaymentInfo> fetchPaymentInfo({
    required String apiUrl,
  }) async {
    final url = Uri.parse(apiUrl);

    final Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Failed to reach OpenCryptoPay service: $e',
      );
    }

    if (response.statusCode == 404) {
      throw OpenCryptoPayNoPendingPaymentException(
        _tryExtractMessage(response.body),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCryptoPayApiException(
        'OpenCryptoPay service returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Could not parse OpenCryptoPay response.',
      );
    }

    return OpenCryptoPayPaymentInfo.fromJson(json, apiUrl: apiUrl);
  }

  /// Second request: fetch transaction details for [coin]. Values from
  /// [fetchPaymentInfo] are carried through into the returned details.
  Future<OpenCryptoPayTransactionDetails> fetchTransactionDetails({
    required String apiUrl,
    required CryptoCoin coin,
    required String displayName,
    required String quoteId,
    required String callback,
    required DateTime quoteExpiration,
  }) async {
    final url = buildTransactionDetailsUrl(
      apiUrl: apiUrl,
      coin: coin,
      quoteId: quoteId
    );

    final Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Failed to reach OpenCryptoPay service: $e',
      );
    }

    if (response.statusCode == 404) {
      throw OpenCryptoPayNoPendingPaymentException(
        _tryExtractMessage(response.body),
      );
    }

    if (response.statusCode == 400) {
      throw OpenCryptoPayUnsupportedMethodException(
        _tryExtractMessage(response.body),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCryptoPayApiException(
        'OpenCryptoPay service returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Could not parse OpenCryptoPay response.',
      );
    }

    return OpenCryptoPayTransactionDetails.fromJson(
      json,
      apiUrl: apiUrl,
      displayName: displayName,
      quoteId: quoteId,
      callback: callback,
      quoteExpiration: quoteExpiration,
    );
  }

  /// Build the transaction-proof URL from the [callback] URL by replacing
  /// its `cb` path segment with `tx`, as specified by the standard ("The API
  /// URL to send the transaction proof back to the payment provider can be
  /// constructed by using the callback URL and replacing `/cb` with `/tx`").
  static Uri buildTransactionProofUrl(String callback) {
    final base = Uri.parse(callback);
    final segments = List<String>.of(base.pathSegments);
    final index = segments.lastIndexOf('cb');
    if (index == -1) {
      throw OpenCryptoPayApiException(
        'Callback URL has no /cb segment to derive the proof endpoint from.',
      );
    }
    segments[index] = 'tx';
    return base.replace(pathSegments: segments);
  }

  Future<bool> submitTransactionProof({
    required OpenCryptoPayTransactionDetails details,
    required CryptoCoin coin,
    required String txProof,
    String? quoteId,
  }) async {
    if (!details.requiresBroadcast && details.isQuoteExpired) {
      throw OpenCryptoPayQuoteExpiredException(
        'The payment quote has expired; cannot submit signed transaction HEX.',
      );
    }

    final base = buildTransactionProofUrl(details.callback);
    final params = Map<String, String>.from(base.queryParameters);
    final effectiveQuote = quoteId ?? details.quoteId;
    params['quote'] = effectiveQuote;
    params['method'] = coin.prettyName.replaceAll(' ', '');
    if (details.requiresBroadcast) {
      params['tx'] = txProof;
    } else {
      params['hex'] = txProof;
    }
    final url = base.replace(queryParameters: params);

    final Response response;
    try {
      response = await _client.get(url);
    } catch (e) {
      throw OpenCryptoPayApiException(
        'Failed to submit transaction proof: $e',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }

    throw OpenCryptoPayApiException(
      'Transaction proof submission failed (HTTP ${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  static String? _tryExtractMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // ignore – fall back to default message
    }
    return null;
  }
}

/// Standard bech32 5<->8 bit regrouping (BIP-173 `convertBits`).
List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxv = (1 << to) - 1;

  for (final value in data) {
    if (value < 0 || (value >> from) != 0) {
      throw OpenCryptoPayInvalidUriException(
        'Invalid value while decoding LNURL data.',
      );
    }
    acc = (acc << from) | value;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((acc >> bits) & maxv);
    }
  }

  if (pad) {
    if (bits > 0) {
      result.add((acc << (to - bits)) & maxv);
    }
  } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
    throw OpenCryptoPayInvalidUriException(
      'Invalid padding while decoding LNURL data.',
    );
  }

  return result;
}
