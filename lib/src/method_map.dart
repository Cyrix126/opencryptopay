import 'coin.dart';

/// A provider-supported payment method and the assets it accepts.
class SupportedMethod {
  const SupportedMethod({required this.method, this.assets = const []});

  /// Provider blockchain/method name, ex: "Bitcoin", "Ethereum".
  final String method;

  /// Asset tickers accepted under this method, ex: ["BTC"], ["ETH", "USDT"].
  /// Empty when the provider didn't publish an asset list (treat as "any asset").
  final List<String> assets;
}
/// Resolves a wallet coin to the OpenCryptoPay `method` + `asset` pair.
/// The provider validates support server-side.
class OpenCryptoPayMethod {
  const OpenCryptoPayMethod({required this.method, required this.asset});

  /// Provider blockchain/method name, ex: "Bitcoin", "Cardano", "Ethereum".
  final String method;

  /// Provider asset name, ex: "BTC", "ADA", "ETH".
  final String asset;
}

/// Derive the `method`/`asset` pair to request for [coin].
OpenCryptoPayMethod openCryptoPayMethodFor(CryptoCoin coin) {
  return OpenCryptoPayMethod(
    method: _deriveMethodName(coin),
    asset: coin.ticker,
  );
}

/// Provider method names are the PascalCase blockchain name.
String _deriveMethodName(CryptoCoin coin) {
  return coin.prettyName.replaceAll(' ', '');
}

/// Return the user's owned coins that can satisfy one of the provider's
/// supported methods. A coin matches when its method is supported and its
/// asset is in the method's asset list (or the list is empty = any asset).
/// Coins are deduplicated by method+asset.
List<CryptoCoin> ownedCoinsSupportingMethods({
  required Iterable<CryptoCoin> ownedCoins,
  required Iterable<SupportedMethod> supportedMethods,
}) {
  final byMethod = <String, SupportedMethod>{};
  for (final sm in supportedMethods) {
    byMethod[sm.method] = sm;
  }
  final seen = <String>{};
  final result = <CryptoCoin>[];
  for (final coin in ownedCoins) {
    final m = openCryptoPayMethodFor(coin);
    final key = m.method;
    final sm = byMethod[key];
    if (sm == null) continue;
    final assetOk =
        sm.assets.isEmpty || sm.assets.any((a) => a == m.asset);
    final dedupKey = '$key:${m.asset}';
    if (assetOk && seen.add(dedupKey)) {
      result.add(coin);
    }
  }
  return result;
}

/// Extract the available methods (with their accepted assets) from the
/// payment-info JSON.
///
/// Unavailable methods (those with `available: false`) are excluded.
List<SupportedMethod> parseSupportedMethodsFromJson(Map<String, dynamic> json) {
  final transfers = json['transferAmounts'];
  if (transfers is! List) return const [];
  final methods = <SupportedMethod>[];
  for (final entry in transfers) {
    if (entry is Map) {
      final available = entry['available'];
      final method = entry['method'];
      if (method is String && (available == null || available == true)) {
        final assets = <String>[];
        final assetList = entry['assets'];
        if (assetList is List) {
          for (final asset in assetList) {
            if (asset is Map) {
              final name = asset['asset'];
              if (name is String && name.isNotEmpty) {
                assets.add(name);
              }
            }
          }
        }
        methods.add(SupportedMethod(method: method, assets: assets));
      }
    }
  }
  return methods;
}
