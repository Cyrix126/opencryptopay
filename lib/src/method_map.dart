import 'coin.dart';

/// Resolves a wallet coin to the OpenCryptoPay `method` + `asset` pair
///
/// Which coins are actually accepted is decided by the payment provider, not
/// by this library, so no allow-list is kept here. We derive the request values
/// for any coin and let the provider reject unsupported ones (HTTP 400), at
/// which point the caller fetches the provider's supported-method list.
class OpenCryptoPayMethod {
  const OpenCryptoPayMethod({required this.method, required this.asset});

  /// Provider blockchain/method name, ex: "Bitcoin", "Cardano", "Ethereum".
  final String method;

  /// Provider asset name, ex: "BTC", "ADA", "ETH".
  final String asset;
}

/// Derive the `method`/`asset` pair to request for [coin].
///
/// This always returns a value; the provider validates support server-side.
OpenCryptoPayMethod openCryptoPayMethodFor(CryptoCoin coin) {
  return OpenCryptoPayMethod(
    method: _deriveMethodName(coin),
    asset: coin.ticker.toUpperCase(),
  );
}

/// Provider method names are the PascalCase blockchain name.
String _deriveMethodName(CryptoCoin coin) {
  return coin.prettyName.replaceAll(' ', '');
}

/// Given a list of provider method names the provider supports for this request,
/// return the user's coins that can satisfy one of them.
///
/// [ownedCoins] is the set of coins the user already has a wallet for.
/// [supportedMethods] is the provider's supported method set.
/// Coins are deduplicated by their derived method name.
List<CryptoCoin> ownedCoinsSupportingMethods({
  required Iterable<CryptoCoin> ownedCoins,
  required Set<String> supportedMethods,
}) {
  final lowerSupported = supportedMethods.map((e) => e.toLowerCase()).toSet();
  final seen = <String>{};
  final result = <CryptoCoin>[];
  for (final coin in ownedCoins) {
    final method = openCryptoPayMethodFor(coin).method.toLowerCase();
    if (lowerSupported.contains(method) && seen.add(method)) {
      result.add(coin);
    }
  }
  return result;
}
