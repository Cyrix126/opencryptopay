import 'package:clock/clock.dart';

import 'method_map.dart';

/// What the provider expects the wallet to submit back as proof of payment.
///
/// Detected from the [OpenCryptoPayTransactionDetails.hint] wording.
enum OpenCryptoPayProofType {
  transactionHash,
  signedTransactionHex,
}

class OpenCryptoPayRecipient {
  const OpenCryptoPayRecipient({
    this.name,
    this.street,
    this.houseNumber,
    this.zip,
    this.city,
    this.country,
    this.phone,
    this.mail,
    this.website,
    this.registrationNumber,
  });

  final String? name;

  final String? street;

  final String? houseNumber;

  final String? zip;

  final String? city;

  final String? country;

  final String? phone;

  final String? mail;

  final String? website;

  /// Company register identifier, ex: "CHE-429.856.521".
  final String? registrationNumber;

  String? get postalAddress {
    final lines = [
      [street, houseNumber],
      [zip, city],
      [country],
    ]
        .map((parts) => parts.nonNulls.where((p) => p.isNotEmpty).join(' '))
        .where((line) => line.isNotEmpty);
    return lines.isEmpty ? null : lines.join('\n');
  }

  Uri? get phoneUri => switch (phone) {
        final phone? when phone.isNotEmpty => Uri(scheme: 'tel', path: phone),
        _ => null,
      };

  Uri? get mailUri => switch (mail) {
        final mail? when mail.isNotEmpty => Uri(scheme: 'mailto', path: mail),
        _ => null,
      };

  Uri? get websiteUri => switch (Uri.tryParse(website ?? '')) {
        final uri? when uri.hasScheme => uri,
        _ => null,
      };

  factory OpenCryptoPayRecipient.fromJson(Map<String, dynamic> json) {
    final postalAddress = json['address'];
    final address = postalAddress is Map ? postalAddress : const {};
    return OpenCryptoPayRecipient(
      name: _string(json['name']),
      street: _string(address['street']),
      houseNumber: _string(address['houseNumber']),
      zip: _string(address['zip']),
      city: _string(address['city']),
      country: _string(address['country']),
      phone: _string(json['phone']),
      mail: _string(json['mail']),
      website: _string(json['website']),
      registrationNumber: _string(json['registrationNumber']),
    );
  }
}

/// [value] when it is a string, so a malformed optional field reads as absent.
String? _string(Object? value) => value is String ? value : null;

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
    this.recipient,
  });

  final String apiUrl;

  final String displayName;

  final String quoteId;

  final String callback;

  final DateTime quoteExpiration;

  final List<SupportedMethod> supportedMethods;

  final OpenCryptoPayRecipient? recipient;

  final Map<String, dynamic> raw;

  factory OpenCryptoPayPaymentInfo.fromJson(
    Map<String, dynamic> json, {
    required String apiUrl,
  }) {
    final Map quote = json['quote'];
    final quoteId = quote['id'];

    final quoteExpiration = DateTime.tryParse(quote['expiration'])!;

    final recipient = json['recipient'];

    return OpenCryptoPayPaymentInfo(
      apiUrl: apiUrl,
      displayName: _string(json['displayName']) ?? '',
      quoteId: quoteId,
      callback: json['callback'] as String,
      quoteExpiration: quoteExpiration,
      supportedMethods: parseSupportedMethodsFromJson(json),
      recipient: recipient is Map
          ? OpenCryptoPayRecipient.fromJson(
              Map<String, dynamic>.from(recipient))
          : null,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// Transaction details returned by [fetchTransactionDetails].
///
/// [displayName], [quoteId], [callback], [quoteExpiration] and [recipient] are
/// carried from the preceding [fetchPaymentInfo] request.
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
    this.recipient,
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

  final OpenCryptoPayRecipient? recipient;

  /// Whether the quote has expired.
  bool get isQuoteExpired {
    return quoteExpiration.isBefore(clock.now());
  }

  String? get legalName => switch (recipient?.name) {
        final name? when name.isNotEmpty => name,
        _ => null,
      };

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
    final q = afterScheme.indexOf('?');
    final addr = q == -1 ? afterScheme : afterScheme.substring(0, q);

    // Token transfer forms:
    //   ethereum:<tokenContract>@<chainId>/transfer?address=<recipient>&uint256=<raw>
    //   icp:<ledger>/transfer?to=<recipient>&amount=<decimal>
    if (addr.endsWith('/transfer')) {
      final params = Uri.tryParse(value)?.queryParameters;
      final recipient = params?['address'] ?? params?['to'];
      return recipient == null || recipient.isEmpty ? null : recipient;
    }

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
    final q = afterScheme.indexOf('?');
    final path = q == -1 ? afterScheme : afterScheme.substring(0, q);
    if (!path.endsWith('/transfer')) return null;
    final contractPart = path.substring(0, path.length - '/transfer'.length);
    // Strip a possible chain-id suffix for EVM (ex: 0xabc@1).
    final at = contractPart.indexOf('@');
    final contract = at == -1 ? contractPart : contractPart.substring(0, at);
    return contract.isEmpty ? null : contract;
  }

  /// Whether this payment is an EVM ERC-20 token transfer.
  bool get isErc20Transfer => tokenContractAddress != null;

  String? get amount => _amountParam?.value;

  /// Whether the amount is a raw integer in the coin's/token's base units (EVM
  /// `value`/`uint256`). BTC `amount` and XMR `tx_amount` are decimals.
  /// Wallets must scale raw amounts by the coin's/token's decimals
  bool get isRawAmount => _amountParam?.isRaw ?? false;

  /// The first amount in the [uri] query, and whether it is raw.
  ({String value, bool isRaw})? get _amountParam {
    final params = Uri.tryParse(uri ?? '')?.queryParameters;
    if (params == null) return null;
    // In an ERC-20 transfer, `value` is the ether sent along with the call.
    for (final (key, isRaw) in const [
      ('amount', false),
      ('tx_amount', false),
      ('uint256', true),
      ('value', true),
    ]) {
      final value = params[key];
      if (value != null) return (value: value, isRaw: isRaw);
    }
    return null;
  }

  /// The signed transaction hex when the [hint] mentions hex, the transaction
  /// hash when it mentions a hash or the tx parameter, and null otherwise.
  OpenCryptoPayProofType? get proofType {
    final h = hint ?? '';
    if (RegExp(r'\bhex', caseSensitive: false).hasMatch(h)) {
      return OpenCryptoPayProofType.signedTransactionHex;
    }
    if (RegExp(r'\b(hash|tx parameter)\b', caseSensitive: false).hasMatch(h)) {
      return OpenCryptoPayProofType.transactionHash;
    }
    return null;
  }

  /// Whether the wallet must broadcast the signed transaction itself before
  /// submitting proof.
  bool get isBroadcastRequired =>
      proofType == OpenCryptoPayProofType.transactionHash;

  factory OpenCryptoPayTransactionDetails.fromJson(
    Map<String, dynamic> json, {
    required String apiUrl,
    required String displayName,
    required String quoteId,
    required String callback,
    required DateTime quoteExpiration,
    OpenCryptoPayRecipient? recipient,
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
      recipient: recipient,
      expiryDate: expiry,
      blockchain: json['blockchain'] as String?,
      uri: json['uri'] as String?,
      hint: json['hint'] as String?,
      lightningInvoice: json['pr'] as String?,
      raw: Map<String, dynamic>.from(json),
    );
  }
}
