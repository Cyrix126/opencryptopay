import 'package:clock/clock.dart';

import 'method_map.dart';

/// What the provider expects the wallet to submit back as proof of payment.
///
/// Detected from the [OpenCryptoPayTransactionDetails.hint] wording.
enum OpenCryptoPayProofType {
  transactionHash,
  signedTransactionHex,
}

/// Payment information returned by the first request to the OpenCryptoPay API.
class OpenCryptoPayPaymentInfo {
  OpenCryptoPayPaymentInfo({
    required this.apiUrl,
    required this.displayName,
    required this.quoteId,
    required this.callback,
    required this.supportedMethods,
    this.raw = const {},
    required this.quoteExpiration,
  });

  final String apiUrl;

  final String displayName;

  final String quoteId;

  final String callback;

  final DateTime quoteExpiration;

  final List<SupportedMethod> supportedMethods;

  final Map<String, dynamic> raw;

  factory OpenCryptoPayPaymentInfo.fromJson(
    Map<String, dynamic> json, {
    required String apiUrl,
  }) {
    final Map quote = json['quote'];
    final quoteId = quote['id'];

    final quoteExpiration = DateTime.tryParse(quote['expiration'])!;

    return OpenCryptoPayPaymentInfo(
      apiUrl: apiUrl,
      displayName: json['displayName'] as String,
      quoteId: quoteId,
      callback: json['callback'] as String,
      quoteExpiration: quoteExpiration,
      supportedMethods: parseSupportedMethodsFromJson(json),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// Transaction details returned by [fetchTransactionDetails].
///
/// [displayName], [quoteId], [callback], and [quoteExpiration] are carried
/// from the preceding [fetchPaymentInfo] request.
///
/// Shape depends on the selected method:
///   - EVM / Bitcoin / Firo / Monero / Zano / Solana / Tron / Cardano:
///       { expiryDate, blockchain, uri, hint }
///   - Lightning: { pr }
///   - BinancePay: { expiryDate, uri, hint }
class OpenCryptoPayTransactionDetails {
  OpenCryptoPayTransactionDetails({
    required this.apiUrl,
    required this.displayName,
    required this.quoteId,
    required this.callback,
    required this.quoteExpiration,
    this.expiryDate,
    this.blockchain,
    this.uri,
    this.hint,
    this.lightningInvoice,
    this.raw = const {},
  });

  final String apiUrl;

  final String displayName;

  final String quoteId;

  final String callback;

  final DateTime quoteExpiration;

  /// Whether the quote has expired.
  bool get isQuoteExpired {
    return quoteExpiration.isBefore(clock.now());
  }
  final DateTime? expiryDate;

  final String? blockchain;

  /// A coin URI (ex: `cardano:addr1...?amount=4.88`, `ethereum:0x..@1?value=..`).
  final String? uri;

  /// Human-readable hint, used to detect the [proofType].
  final String? hint;

  /// BOLT11 invoice for the Lightning method (`pr` field).
  final String? lightningInvoice;

  final Map<String, dynamic> raw;

  bool get isLightning => lightningInvoice != null;

  String? get address {
    if (uri == null) return null;
    final value = uri!;
    final colon = value.indexOf(':');
    if (colon == -1) return null;
    final afterScheme = value.substring(colon + 1);

    // ERC-20 / EVM token transfer form:
    //   ethereum:<tokenContract>@<chainId>/transfer?address=<recipient>&uint256=<raw>
    final transferMarker = afterScheme.indexOf('/transfer');
    if (transferMarker != -1) {
      final params = Uri.tryParse(value)?.queryParameters;
      final recipient = params?['address'];
      if (recipient != null && recipient.isNotEmpty) return recipient;
    }

    final q = afterScheme.indexOf('?');
    final addr = q == -1 ? afterScheme : afterScheme.substring(0, q);
    // Strip a possible chain-id suffix for EVM (ex: 0xabc@1).
    final at = addr.indexOf('@');
    return at == -1 ? addr : addr.substring(0, at);
  }

  /// The ERC-20 token contract address, when this payment is an EVM token
  String? get tokenContractAddress {
    if (uri == null) return null;
    final value = uri!;
    final colon = value.indexOf(':');
    if (colon == -1) return null;
    final afterScheme = value.substring(colon + 1);
    final transferMarker = afterScheme.indexOf('/transfer');
    if (transferMarker == -1) return null;
    final contractPart = afterScheme.substring(0, transferMarker);
    // Strip a possible chain-id suffix for EVM (ex: 0xabc@1).
    final at = contractPart.indexOf('@');
    final contract = at == -1 ? contractPart : contractPart.substring(0, at);
    return contract.isEmpty ? null : contract;
  }

  /// Whether this payment is an EVM ERC-20 token transfer (as opposed to a
  /// native coin transfer).
  bool get isErc20Transfer => tokenContractAddress != null;

  String? get amount {
    if (uri == null) return null;
    final params = Uri.tryParse(uri ?? '')?.queryParameters;
    return params?['amount'] ??
        params?['tx_amount'] ??
        params?['value'] ??
        params?['uint256'];
  }

  /// Whether the amount is a raw integer in the coin's/token's base units (EVM
  /// `value`/`uint256`) rather than a human-readable decimal (BTC `amount`,
  /// XMR `tx_amount`). Wallets must scale raw amounts by the coin's/token's
  /// decimals
  bool get isRawAmount {
    if (uri == null) return false;
    final params = Uri.tryParse(uri ?? '')?.queryParameters;
    return params != null &&
        (params.containsKey('value') || params.containsKey('uint256'));
  }


  OpenCryptoPayProofType get proofType {
    final h = hint;
    if (h == null) return OpenCryptoPayProofType.transactionHash;
    if (RegExp(r'\bas HEX\b', caseSensitive: false).hasMatch(h)) {
      return OpenCryptoPayProofType.signedTransactionHex;
    }
    return OpenCryptoPayProofType.transactionHash;
  }

  /// Whether the wallet must broadcast the signed transaction itself before
  /// submitting proof.
  bool get requiresBroadcast =>
      proofType == OpenCryptoPayProofType.transactionHash;

  factory OpenCryptoPayTransactionDetails.fromJson(
    Map<String, dynamic> json, {
    required String apiUrl,
    required String displayName,
    required String quoteId,
    required String callback,
    required DateTime quoteExpiration,
  }) {
    DateTime? expiry;
    final expiryRaw = json['expiryDate'];
    if (expiryRaw is String) {
      expiry = DateTime.tryParse(expiryRaw);
    }

    return OpenCryptoPayTransactionDetails(
      apiUrl: apiUrl,
      displayName: displayName,
      quoteId: quoteId,
      callback: callback,
      quoteExpiration: quoteExpiration,
      expiryDate: expiry,
      blockchain: json['blockchain'] as String?,
      uri: json['uri'] as String?,
      hint: json['hint'] as String?,
      lightningInvoice: json['pr'] as String?,
      raw: Map<String, dynamic>.from(json),
    );
  }
}
