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
    this.chainType = CryptoChainType.other,
    this.chainId,
  });

  /// Coin or token ticker symbol (ex: "BTC", "ETH", "USDT").
  /// Becomes the OpenCryptoPay `asset` value.
  final String ticker;

  /// Human-readable blockchain name (ex: "Bitcoin", "Ethereum").
  /// Becomes the OpenCryptoPay `method` value (spaces stripped).
  final String prettyName;

  /// Sets the unit of a provider's minimum fee.
  final CryptoChainType chainType;

  /// EIP-155 chain ID of an EVM coin's network (ex: 1 for Ethereum). A
  /// payment URI that names another chain is refused.
  final int? chainId;
}
