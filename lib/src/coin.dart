class CryptoCoin {
  const CryptoCoin({
    required this.ticker,
    required this.prettyName,
    String? displayName,
  }) : _displayName = displayName;

  /// Coin or token ticker symbol (ex: "BTC", "ETH", "USDT").
  /// Becomes the OpenCryptoPay `asset` value.
  final String ticker;

  /// Human-readable blockchain name (ex: "Bitcoin", "Ethereum").
  /// Becomes the OpenCryptoPay `method` value (spaces stripped).
  final String prettyName;

  final String? _displayName;

  /// Short user-facing label for display (ex: "BTC", "USDT").
  ///
  /// Defaults to [ticker]; wallets with token contracts may set it to show
  /// the token symbol instead of the chain name.
  String get displayName => _displayName ?? ticker;
}
