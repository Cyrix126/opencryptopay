import 'dart:convert';

import 'package:bech32/bech32.dart';
import 'package:http/http.dart';

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

  /// The QR links handed out by the standard look like:
  /// `https://<provider-host>/pl/?lightning=LNURL1...`
  ///
  /// The host can be any provider, so we
  /// detect by the `/pl/` path + a `lightning` query parameter, not by domain.
  static bool isOpenCryptoPayUri(String? data) {
    if (data == null) return false;
    final uri = Uri.tryParse(data.trim());
    if (uri == null) return false;
    if (!uri.isScheme('https')) {
      return false;
    }
    final lnurl = uri.queryParameters['lightning'];
    if (lnurl == null || lnurl.isEmpty) return false;
    // Path is "/pl/" (or "/pl"); normalize a trailing slash before comparing.
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return path == '/pl';
  }

  /// Extract the bech32 (LNURL) parameter from the scanned QR link.
  static String extractLnurl(String qrData) {
    final trimmed = qrData.trim();
    final uri = Uri.tryParse(trimmed);
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
    // LNURLs are well over the bech32 default max lex:h (90); allow plenty.
    final decoded = bech32.decode(lnurl, lnurl.length + 1);
    final bytes = _convertBits(decoded.data, 5, 8, false);
    return utf8.decode(bytes);
  }

  /// Build the simplified-flow request URL.
  /// The simplified flow does not send a request to fetch the supported coins by the provider,
  /// it tries directly with a given coin.
  static Uri buildSimplifiedFlowUrl({
    required String apiUrl,
    required String method,
    required String asset,
  }) {
    final base = Uri.parse(apiUrl);
    final params = Map<String, String>.from(base.queryParameters);
    params['method'] = method;
    params['asset'] = asset;
    return base.replace(queryParameters: params);
  }

  Future<OpenCryptoPayTransactionDetails> fetchTransactionDetails({
    required String apiUrl,
    required String method,
    required String asset,
  }) async {
    final url = buildSimplifiedFlowUrl(
      apiUrl: apiUrl,
      method: method,
      asset: asset,
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

    return OpenCryptoPayTransactionDetails.fromJson(json, apiUrl: apiUrl);
  }

  /// Fetch the list of payment method names the provider supports for this
  /// payment.
  Future<List<String>> fetchSupportedMethods({
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

    return parseSupportedMethods(json);
  }

  /// Extract the available method names from the payment-details JSON.
  static List<String> parseSupportedMethods(Map<String, dynamic> json) {
    final transfers = json['transferAmounts'];
    if (transfers is! List) return const [];
    final methods = <String>[];
    for (final entry in transfers) {
      if (entry is Map) {
        final available = entry['available'];
        final method = entry['method'];
        if (method is String && (available == null || available == true)) {
          methods.add(method);
        }
      }
    }
    return methods;
  }

  Future<bool> submitTransactionProof({
    required OpenCryptoPayTransactionDetails details,
    required String method,
    required String txHash,
    String? quoteId,
  }) async {
    final txEndpoint = details.txSubmissionEndpoint;
    if (txEndpoint == null) {
      throw OpenCryptoPayApiException(
        'No transaction submission endpoint was provided by the service.',
      );
    }

    final base = Uri.parse(txEndpoint);
    final params = Map<String, String>.from(base.queryParameters);
    final effectiveQuote = quoteId ?? details.quoteId;
    if (effectiveQuote != null) {
      params['quote'] = effectiveQuote;
    }
    params['method'] = method;
    params['tx'] = txHash;
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
