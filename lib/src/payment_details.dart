/// The transaction details returned by the request [fetchTransactionDetails]
///
/// Shape depends on the selected method:
///   - EVM / Bitcoin / Firo / Monero / Zano / Solana / Tron / Cardano:
///       { expiryDate, blockchain, uri, hint }
///   - Lightning:
///       { pr }
///   - BinancePay:
///       { expiryDate, uri, hint }
class OpenCryptoPayTransactionDetails {
  OpenCryptoPayTransactionDetails({
    required this.apiUrl,
    this.expiryDate,
    this.blockchain,
    this.displayName,
    this.uri,
    this.hint,
    this.lightningInvoice,
    this.quoteId,
    this.raw = const {},
  });

  final String apiUrl;

  final DateTime? expiryDate;

  /// PascalName of the coin
  final String? blockchain;

  /// The merchant's display name 
  final String? displayName;

  /// A coin URI (ex: `cardano:addr1...?amount=4.88`, `ethereum:0x..@1?value=..`).
  final String? uri;

  /// Human-readable hint. For non-lightning methods it names the endpoint to
  /// POST/GET the transaction proof to.
  final String? hint;

  /// BOLT11 invoice for the Lightning method (`pr` field).
  final String? lightningInvoice;

  /// The quote id, if present in the response.
  final String? quoteId;

  /// The full decoded JSON
  final Map<String, dynamic> raw;

  bool get isLightning => lightningInvoice != null;

  String? get address {
    if (uri == null) return null;
    final value = uri!;
    final colon = value.indexOf(':');
    if (colon == -1) return null;
    final afterScheme = value.substring(colon + 1);
    final q = afterScheme.indexOf('?');
    final addr = q == -1 ? afterScheme : afterScheme.substring(0, q);
    // Strip a possible chain-id suffix for EVM (ex: 0xabc@1).
    final at = addr.indexOf('@');
    return at == -1 ? addr : addr.substring(0, at);
  }

  String? get amount {
    if (uri == null) return null;
    final params = Uri.tryParse(uri ?? '')?.queryParameters;
    return params?['amount'] ??
        params?['tx_amount'] ??
        params?['value'];
  }

  /// The endpoint used to submit the transaction proof, parsed from [hint].
  ///
  /// The hint text contains a sentence like:
  ///   "...send the transaction hash back via the endpoint
  ///    https://api.example.com/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e
  String? get txSubmissionEndpoint {
    final h = hint;
    if (h == null) return null;
    final match = RegExp(
      r'https?://[^\s]*?/lnurlp/tx/[A-Za-z0-9_]+',
    ).firstMatch(h);
    return match?.group(0);
  }

  factory OpenCryptoPayTransactionDetails.fromJson(
    Map<String, dynamic> json, {
    required String apiUrl,
  }) {
    DateTime? expiry;
    final expiryRaw = json['expiryDate'];
    if (expiryRaw is String) {
      expiry = DateTime.tryParse(expiryRaw);
    }

    String? quoteId;
    final quote = json['quote'];
    if (quote is Map && quote['id'] is String) {
      quoteId = quote['id'] as String;
    } else if (json['quoteId'] is String) {
      quoteId = json['quoteId'] as String;
    }

    return OpenCryptoPayTransactionDetails(
      apiUrl: apiUrl,
      expiryDate: expiry,
      blockchain: json['blockchain'] as String?,
      displayName: json['displayName'] as String?,
      uri: json['uri'] as String?,
      hint: json['hint'] as String?,
      lightningInvoice: json['pr'] as String?,
      quoteId: quoteId,
      raw: Map<String, dynamic>.from(json),
    );
  }
}
