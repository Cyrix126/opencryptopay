/// Kind of blockchain a coin lives on.
enum CryptoChainType {
  /// Bitcoin and the chains derived from it, which pay a fee per virtual
  /// byte.
  bitcoinDerived,

  /// Ethereum virtual machine; transactions pay a price per unit of gas.
  evm,

  /// Any other chain.
  other,
}

class CryptoCoin {
  const CryptoCoin({
    required this.ticker,
    required this.prettyName,
    String? displayName,
    this.chainType = CryptoChainType.other,
  }) : _displayName = displayName;

  /// Coin or token ticker symbol (ex: "BTC", "ETH", "USDT").
  /// Becomes the OpenCryptoPay `asset` value.
  final String ticker;

  /// Human-readable blockchain name (ex: "Bitcoin", "Ethereum").
  /// Becomes the OpenCryptoPay `method` value (spaces stripped).
  final String prettyName;

  /// Sets the unit of a provider's minimum fee.
  final CryptoChainType chainType;

  final String? _displayName;

  /// Short user-facing label for display (ex: "BTC", "USDT").
  ///
  /// Defaults to [ticker]; wallets with token contracts may set it to show
  /// the token symbol instead of the chain name.
  String get displayName => _displayName ?? ticker;
}
