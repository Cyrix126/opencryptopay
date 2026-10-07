import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:opencryptopay/opencryptopay.dart';

import 'sample_data/open_crypto_pay_payment_details_json.dart';

/// Minimal [CryptoCoin] for tests.
class TestCoin implements CryptoCoin {
  const TestCoin(this.ticker, this.prettyName,
      [this.chainType = CryptoChainType.other, this.chainId]);
  @override
  final String ticker;
  @override
  final String prettyName;
  @override
  final CryptoChainType chainType;
  @override
  final int? chainId;
}

const btc = TestCoin('BTC', 'Bitcoin', CryptoChainType.bitcoinDerived);
const eth = TestCoin('ETH', 'Ethereum', CryptoChainType.evm, 1);
const xmr = TestCoin('XMR', 'Monero');
const firo = TestCoin('FIRO', 'Firo', CryptoChainType.bitcoinDerived);
const ada = TestCoin('ADA', 'Cardano');
const sol = TestCoin('SOL', 'Solana');
const doge = TestCoin('DOGE', 'Dogecoin', CryptoChainType.bitcoinDerived);
const ltc = TestCoin('LTC', 'Litecoin', CryptoChainType.bitcoinDerived);
const usdt = TestCoin('USDT', 'Ethereum', CryptoChainType.evm, 1);
const zchf = TestCoin('ZCHF', 'Polygon', CryptoChainType.evm, 137);
const bnb = TestCoin('BNB', 'Binance Smart Chain', CryptoChainType.evm, 56);
const trx = TestCoin('TRX', 'Tron');
const spark = TestCoin('BTC', 'Spark');
const icp = TestCoin('ICP', 'Internet Computer');
const lightning = TestCoin('BTC', 'Lightning');
const binancePay = TestCoin('USDT', 'Binance Pay');

/// Build a `package:http` [MockClient] that returns [response] for every GET.
Client mockHttpReturning(Response response) =>
    MockClient((request) async => response);

/// Build a `package:http` [MockClient] that dispatches via [handler].
Client mockHttpWithHandler(Response Function(Uri url) handler) =>
    MockClient((request) async => handler(request.url));

Response res(String body, int code) => Response(body, code);

OpenCryptoPayController controllerFor(Client client) => OpenCryptoPayController(
      service: OpenCryptoPayService(client: client),
    );

const lnurl =
    'LNURL1DP68GURN8GHJ7CTSDYHXGENC9EEHW6TNWVHHVVF0D3H82UNVWQHHQMZLVFJK2ERYVG6RZCMYX33RVEPEV5YEJ9WT';
const qrLink = 'https://app.dfx.swiss/pl/?lightning=$lnurl';
const decodedApiUrl = 'https://api.dfx.swiss/v1/lnurlp/pl_beeddb41cd4b6d9e';

const btcDetails = {
  "expiryDate": "2026-07-11T11:20:24.888Z",
  "blockchain": "Bitcoin",
  "uri":
      "bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=0.00001947&label=DFX Payment",
  "hint":
      "Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain."
};
const callbackUrl = 'https://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e';
const quoteExpiration = '2026-06-24T08:37:49.704Z';

// Hints of the DFX demo payment link.
const dfxHexHint =
    'Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain.';
const dfxFiroHint =
    'Use this data to create a transaction and sign it. Either send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e, or broadcast the transaction yourself and send the transaction hash (txId) back via the same endpoint.';
const dfxHashHint =
    'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e';
const dfxSparkHint =
    'Pay the URI on Spark and send the transfer ID back as the tx parameter via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e';
const dfxInternetComputerHint =
    'Approve the address from the URI for the required amount plus transfer fee using icrc2_approve. Then send your Principal ID as the sender parameter via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e.';

final fixedClock = Clock.fixed(DateTime.utc(2026, 6, 24, 8));

final owned = <CryptoCoin>[btc, eth, xmr];

/// Mock handler for the two-request flow:
/// - First request (no method/asset params): returns the payment info JSON.
/// - Second request (with method/asset params): returns the tx details JSON.
Client mockTwoRequestFlow({
  required Map<String, dynamic> txDetailsJson,
  int txDetailsStatus = 200,
  Map<String, dynamic> paymentInfoJson = paymentDetailsJson,
}) {
  return mockHttpWithHandler((url) {
    final hasMethod = url.queryParameters.containsKey('method');
    if (!hasMethod) {
      return res(jsonEncode(paymentInfoJson), 200);
    }
    return res(jsonEncode(txDetailsJson), txDetailsStatus);
  });
}

bool isProof(Uri url) => url.pathSegments.contains('tx');
