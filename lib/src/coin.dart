/// Coin abstraction a wallet must implement to use OpenCryptoPay.
abstract class CryptoCoin {
  /// Coin ticker symbol (ex: "BTC", "ETH", "XMR").
  String get ticker;

  /// Human-readable blockchain name (ex: "Bitcoin", "Ethereum").
  ///
  /// This becomes the OpenCryptoPay `method` value (with spaces stripped), so
  /// it must match the PascalCase blockchain name the provider expects.
  String get prettyName;
}
