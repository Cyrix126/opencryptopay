import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'sample_data/open_crypto_pay_payment_details_json.dart';

/// Minimal [CryptoCoin] for tests.
class _Coin implements CryptoCoin {
  const _Coin(this.ticker, this.prettyName);
  @override
  final String ticker;
  @override
  final String prettyName;
  @override
  String get displayName => ticker;
}

const _btc = _Coin('BTC', 'Bitcoin');
const _eth = _Coin('ETH', 'Ethereum');
const _xmr = _Coin('XMR', 'Monero');
const _firo = _Coin('FIRO', 'Firo');
const _ada = _Coin('ADA', 'Cardano');
const _sol = _Coin('SOL', 'Solana');
const _doge = _Coin('DOGE', 'Dogecoin');
const _ltc = _Coin('LTC', 'Litecoin');
const _usdt = _Coin('USDT', 'Ethereum');

/// Build a `package:http` [MockClient] that returns [response] for every GET.
Client _mockHttpReturning(Response response) =>
    MockClient((request) async => response);

/// Build a `package:http` [MockClient] that dispatches via [handler].
Client _mockHttpWithHandler(Response Function(Uri url) handler) =>
    MockClient((request) async => handler(request.url));

Response _res(String body, int code) => Response(body, code);

OpenCryptoPayController _controller(Client client) => OpenCryptoPayController(
      service: OpenCryptoPayService(client: client),
    );

const _lnurl =
    'LNURL1DP68GURN8GHJ7CTSDYHXGENC9EEHW6TNWVHHVVF0D3H82UNVWQHHQMZLVFJK2ERYVG6RZCMYX33RVEPEV5YEJ9WT';
const _qrLink = 'https://app.dfx.swiss/pl/?lightning=$_lnurl';
const _decodedApiUrl = 'https://api.dfx.swiss/v1/lnurlp/pl_beeddb41cd4b6d9e';

const _btcDetails = {
  "expiryDate": "2026-07-11T11:20:24.888Z",
  "blockchain": "Bitcoin",
  "uri":
      "bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=0.00001947&label=DFX Payment",
  "hint":
      "Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain."
};
const _callbackUrl = 'https://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e';
const _quoteExpiration = '2026-06-24T08:37:49.704Z';
void main() {
  final fixedTime = DateTime(2026, 6, 24, 8);
  final fixedClock = Clock.fixed(fixedTime);

  group('OpenCryptoPay URI handling', () {
    test('recognizes Open CryptoPay QR links from any provider host', () {
      expect(OpenCryptoPayService.isOpenCryptoPayUri(_qrLink), isTrue);
      // A different provider host must also be detected.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://pay.example.com/pl/?lightning=$_lnurl',
        ),
        isTrue,
      );
      // Path "/pl" without a trailing slash is still valid.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://pay.example.com/pl?lightning=$_lnurl',
        ),
        isTrue,
      );
      // Wrong path must be rejected even with a lightning param.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://app.dfx.swiss/other/?lightning=$_lnurl',
        ),
        isFalse,
      );
      // Missing lightning param must be rejected.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri('https://app.dfx.swiss/pl/'),
        isFalse,
      );
      // Crypto addresses are not recognized.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri('bitcoin:bc1qexampleaddress'),
        isFalse,
      );
      expect(OpenCryptoPayService.isOpenCryptoPayUri(null), isFalse);
    });

    test('extracts the lightning (LNURL) query parameter', () {
      expect(OpenCryptoPayService.extractLnurl(_qrLink), _lnurl);
    });

    test('decodes an LNURL (LUD-01) to its API URL', () {
      expect(OpenCryptoPayService.decodeLnurl(_lnurl), _decodedApiUrl);
    });
  });

  group('OpenCryptoPay transaction details URL building', () {
    test('appends quote, method and asset query parameters', () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        apiUrl: _decodedApiUrl,
        coin: _xmr,
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.path, '/v1/lnurlp/pl_beeddb41cd4b6d9e');
      expect(url.queryParameters['quote'], 'plq_62b1865ed28358be');
      expect(url.queryParameters['method'], 'Monero');
      expect(url.queryParameters['asset'], 'XMR');
    });

    test('strips spaces from the method derived from the coin pretty name',
        () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        apiUrl: _decodedApiUrl,
        coin: const _Coin('BNB', 'Binance Smart Chain'),
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.queryParameters['method'], 'BinanceSmartChain');
      expect(url.queryParameters['asset'], 'BNB');
    });
  });

  group('OpenCryptoPay transaction proof URL building', () {
    test('replaces the /cb path segment of the callback with /tx', () {
      final url = OpenCryptoPayService.buildTransactionProofUrl(_callbackUrl);
      expect(
        url.toString(),
        'https://api.dfx.swiss/v1/lnurlp/tx/pl_beeddb41cd4b6d9e',
      );
    });

    test('only rewrites the path, not a "cb" elsewhere in the URL', () {
      final url = OpenCryptoPayService.buildTransactionProofUrl(
        'https://cb.example.com/v1/lnurlp/cb/pl_x?shop=cb',
      );
      expect(url.host, 'cb.example.com');
      expect(url.path, '/v1/lnurlp/tx/pl_x');
      expect(url.queryParameters['shop'], 'cb');
    });

    test('throws when the callback has no /cb segment to replace', () {
      expect(
        () => OpenCryptoPayService.buildTransactionProofUrl(_decodedApiUrl),
        throwsA(isA<OpenCryptoPayApiException>()),
      );
    });
  });

  group('Parsing payment info correctly', () {
    test('parses payment info with display name, quote id and methods', () {
      withClock(fixedClock, () {
      final info = OpenCryptoPayPaymentInfo.fromJson(
        paymentDetailsJson,
        apiUrl: _decodedApiUrl,
      );

      expect(info.displayName, 'Test Shop');
      expect(info.quoteId, 'plq_62b1865ed28358be');
      expect(info.callback, _callbackUrl);
      expect(info.supportedMethods, isNotEmpty);
      expect(info.quoteExpiration, DateTime.parse(_quoteExpiration));

      final eth = info.supportedMethods.firstWhere((e) => e.method == 'Ethereum');
      expect(eth.assets, containsAll(<String>['ETH', 'USDT', 'USDC', 'WBTC']));
      });
    });
  });

  group('Parsing transaction details correctly', () {
    test('parses a Bitcoin details response', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        _btcDetails,
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Bitcoin');
      expect(details.displayName, 'Test Shop');
      expect(details.quoteId, 'plq_62b1865ed28358be');
      expect(details.callback, _callbackUrl);
      expect(
        details.address,
        'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
      );
      expect(details.amount, '0.00001947');
      expect(details.isRawAmount, isFalse);
      expect(details.isErc20Transfer, isFalse);
      expect(details.tokenContractAddress, isNull);
    });

    test('parses a Monero details response', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-06-25T08:59:05.950Z',
          'blockchain': 'Monero',
          'uri':
              'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
          'hint':
              'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e'
        },
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Monero');
      expect(
        details.address,
        '88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u',
      );
      expect(details.amount, '0.00394642');
      expect(details.callback, _callbackUrl);
    });

    test('parses an Ethereum details response', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-06-25T09:19:23.631Z',
          'blockchain': 'Ethereum',
          'uri':
              'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1?value=753470000000000',
          'hint':
              'Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain.',
        },
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Ethereum');
      expect(
        details.address,
        '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
      );
      expect(details.amount, '753470000000000');
      expect(details.isRawAmount, isTrue);
      expect(details.isErc20Transfer, isFalse);
      expect(details.tokenContractAddress, isNull);
      expect(details.callback, _callbackUrl);
    });

    test('parses an ERC-20 Token details responses', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-07-08T15:43:24.795Z',
          'blockchain': 'Ethereum',
          'uri':
              'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC&uint256=1246858',
          'hint':
              'Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain.',
        },
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Ethereum');
      expect(
        details.address,
        '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
      );
      expect(details.isErc20Transfer, isTrue);
      expect(
        details.tokenContractAddress,
        '0xdac17f958d2ee523a2206206994597c13d831ec7',
      );
      expect(details.amount, '1246858');
      expect(details.isRawAmount, isTrue);
      expect(details.callback, _callbackUrl);
    });
  });

  group('Proof type detection from hint', () {
    test('HEX hint -> signedTransactionHex, requiresBroadcast false', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        _btcDetails,
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );
      expect(details.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
      expect(details.requiresBroadcast, isFalse);
    });

    test('hash hint -> transactionHash, requiresBroadcast true', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-06-25T08:59:05.950Z',
          'blockchain': 'Monero',
          'uri':
              'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
          'hint':
              'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
        },
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );
      expect(details.proofType, OpenCryptoPayProofType.transactionHash);
      expect(details.requiresBroadcast, isTrue);
    });

    test('case-insensitive "as hex" detection', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'blockchain': 'Ethereum',
          'uri': 'ethereum:0xabc@1?value=1',
          'hint':
              'Send the signed transaction back as hex via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_x',
        },
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );
      expect(details.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
    });

    test('ERC-20 HEX hint classifies as signedTransactionHex', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-07-08T15:43:24.795Z',
          'blockchain': 'Ethereum',
          'uri':
              'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC&uint256=1246858',
          'hint':
              'Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain.',
        },
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );
      expect(details.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
      expect(details.requiresBroadcast, isFalse);
    });
  });

  group('OpenCryptoPay method mapping', () {
    test('derives method (pretty name) and asset (ticker) from a coin', () {
      final btc = openCryptoPayMethodFor(_btc);
      expect(btc.method, 'Bitcoin');
      expect(btc.asset, 'BTC');

      final eth = openCryptoPayMethodFor(_eth);
      expect(eth.method, 'Ethereum');
      expect(eth.asset, 'ETH');

      final xmr = openCryptoPayMethodFor(_xmr);
      expect(xmr.method, 'Monero');
      expect(xmr.asset, 'XMR');
    });

    test('suggests owned wallets whose coin the provider supports', () {
      final owned = <CryptoCoin>[_ltc, _btc];
      final supported = ownedCoinsSupportingMethods(
        ownedCoins: owned,
        supportedMethods: const [
          SupportedMethod(method: 'Bitcoin', assets: ['BTC']),
          SupportedMethod(method: 'Ethereum', assets: ['ETH']),
        ],
      );
      expect(supported.map((e) => e.prettyName), ['Bitcoin']);
    });
  });

  group('detect the provider supported coins', () {
    test('detects every available method and excludes unavailable ones', () {
      final methods = parseSupportedMethodsFromJson(paymentDetailsJson);

      final methodNames = methods.map((e) => e.method).toList();
      expect(
        methodNames,
        containsAll(<String>[
          'Lightning',
          'Polygon',
          'Arbitrum',
          'Optimism',
          'Base',
          'Ethereum',
          'BinanceSmartChain',
          'Bitcoin',
          'Firo',
          'Monero',
          'Zano',
          'Solana',
          'Tron',
          'Cardano',
          'InternetComputer',
          'BinancePay',
        ]),
      );

      // 16 available, 3 unavailable (TaprootAsset, Spark, Arkade).
      expect(methodNames.length, 16);
      expect(methodNames, isNot(contains('TaprootAsset')));
      expect(methodNames, isNot(contains('Spark')));
      expect(methodNames, isNot(contains('Arkade')));

      // Ethereum method should list its assets including USDT and ETH.
      final eth = methods.firstWhere((e) => e.method == 'Ethereum');
      expect(eth.assets, containsAll(<String>['ETH', 'USDT', 'USDC', 'WBTC']));
    });

    test('maps supported methods to the user\'s payable wallets', () {
      final supportedMethods = parseSupportedMethodsFromJson(paymentDetailsJson);

      // The user owns wallets for these coins: only some are supported by the provider.
      final owned = <CryptoCoin>[
        _btc, // supported
        _eth, // supported
        _xmr, // supported
        _firo, // supported
        _ada, // supported
        _sol, // supported
        _doge, // NOT in provider list
        _ltc, // NOT in provider list
      ];

      final payable = ownedCoinsSupportingMethods(
        ownedCoins: owned,
        supportedMethods: supportedMethods,
      );

      final payableNames = payable.map((e) => e.prettyName).toSet();
      expect(
        payableNames,
        {'Bitcoin', 'Ethereum', 'Monero', 'Firo', 'Cardano', 'Solana'},
      );
      expect(payableNames, isNot(contains('Dogecoin')));
      expect(payableNames, isNot(contains('Litecoin')));
    });

    test('matches token coins by asset, not just method', () {
      final supportedMethods = parseSupportedMethodsFromJson(paymentDetailsJson);

      // User owns an ETH wallet and a USDT token wallet (same method, different asset).
      final owned = <CryptoCoin>[
        _eth, // ETH asset on Ethereum method — supported
        _usdt, // USDT asset on Ethereum method — supported
        _doge, // not supported
      ];

      final payable = ownedCoinsSupportingMethods(
        ownedCoins: owned,
        supportedMethods: supportedMethods,
      );

      final payableTickers = payable.map((e) => e.ticker.toUpperCase()).toSet();
      expect(payableTickers, containsAll(<String>['ETH', 'USDT']));
      expect(payableTickers, isNot(contains('DOGE')));
    });
  });

  group('OpenCryptoPayController', () {
    final owned = <CryptoCoin>[_btc, _eth, _xmr];

    /// Mock handler for the two-request flow:
    /// - First request (no method/asset params): returns the payment info JSON.
    /// - Second request (with method/asset params): returns the tx details JSON.
    Client _mockTwoRequestFlow({
      required Map<String, dynamic> txDetailsJson,
      int txDetailsStatus = 200,
    }) {
      return _mockHttpWithHandler((url) {
        final hasMethod = url.queryParameters.containsKey('method');
        if (!hasMethod) {
          return _res(jsonEncode(paymentDetailsJson), 200);
        }
        return _res(jsonEncode(txDetailsJson), txDetailsStatus);
      });
    }

    test('success: classifies a payable Bitcoin payment and labels it',
        () async {
      final controller = _controller(_mockTwoRequestFlow(
        txDetailsJson: _btcDetails,
      ));

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPaySuccess>());
      final success = result as OpenCryptoPaySuccess;
      expect(success.address, 'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6');
      expect(success.amount.toString(), '0.00001947');
      expect(success.coin.prettyName, 'Bitcoin');
      expect(success.recipientLabel, 'Test Shop');
      expect(success.details.displayName, 'Test Shop');
      expect(success.details.quoteId, 'plq_62b1865ed28358be');
      // Bitcoin hint asks for HEX → wallet must NOT broadcast.
      expect(success.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
      expect(success.requiresBroadcast, isFalse);
    });

    test('check that the transaction detail url is constructed with the same quoteId'
      'found in the payment detail response', () async {
      final fetched = <Uri>[];
      final controller = _controller(
        _mockHttpWithHandler((url) {
          fetched.add(url);
          if (!url.queryParameters.containsKey('method')) {
            return _res(jsonEncode(paymentDetailsJson), 200);
          }
          return _res(jsonEncode(_btcDetails), 200);
        }),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );
      expect(result, isA<OpenCryptoPaySuccess>());
      expect(fetched, hasLength(2));
      expect(fetched[0].toString(), _decodedApiUrl);

      final detailsUrl = fetched[1];
      expect(detailsUrl.host, Uri.parse(_decodedApiUrl).host);
      expect(detailsUrl.path, Uri.parse(_decodedApiUrl).path);
      expect(
        detailsUrl.queryParameters['quote'],
        paymentDetailsJson['quote']['id'],
      );
      expect(detailsUrl.queryParameters['method'], _btc.prettyName);
      expect(detailsUrl.queryParameters['asset'], _btc.ticker);
    });

    test('success: Monero hash flow requires broadcast', () async {
      final controller = _controller(_mockTwoRequestFlow(
        txDetailsJson: {
          'expiryDate': '2026-06-25T08:59:05.950Z',
          'blockchain': 'Monero',
          'uri':
              'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
          'hint':
              'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
        },
      ));

      final result = await controller.run(
        qrData: _qrLink,
        coin: _xmr,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPaySuccess>());
      final success = result as OpenCryptoPaySuccess;
      expect(success.proofType, OpenCryptoPayProofType.transactionHash);
      expect(success.requiresBroadcast, isTrue);
    });

    test('404 on first request maps to no pending payment', () async {
      final controller = _controller(
        _mockHttpReturning(_res('{"message":"none"}', 404)),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayNoPending>());
    });

    test('lightning response maps to lightning result', () async {
      final controller = _controller(_mockTwoRequestFlow(
        txDetailsJson: {'pr': 'lnbc1...'},
      ));

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayLightning>());
    });

    test('missing address maps to an invalid address result', () async {
      final controller = _controller(_mockTwoRequestFlow(
        txDetailsJson: {'blockchain': 'Bitcoin', 'hint': 'x'},
      ));

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayInvalidAddress>());
    });

    test('unsupported coin maps to unsupported result with alternatives',
        () async {
      var calls = 0;
      final controller = _controller(
        _mockHttpWithHandler((url) {
          calls++;
          final hasMethod = url.queryParameters.containsKey('method');
          if (hasMethod) {
            return _res('{"message":"unsupported"}', 400);
          }
          return _res(jsonEncode(paymentDetailsJson), 200);
        }),
      );

      // Use a coin the provider does not list so the rejected coin is excluded
      // and only owned, supported alternatives come back.
      final result = await controller.run(
        qrData: _qrLink,
        coin: _doge,
        ownedCoins: [_doge, ...owned],
      );

      expect(result, isA<OpenCryptoPayUnsupported>());
      final unsupported = result as OpenCryptoPayUnsupported;
      final names = unsupported.alternatives!.map((c) => c.prettyName).toSet();
      expect(names, containsAll(<String>['Bitcoin', 'Ethereum', 'Monero']));
      expect(names, isNot(contains('Dogecoin')));
      // Doge is not in the supported list, so the controller short-circuits
      // after the first request (no second request needed).
      expect(calls, 1);
    });

    test('coin not in supported list short-circuits before second request',
        () async {
      var calls = 0;
      final controller = _controller(
        _mockHttpWithHandler((url) {
          calls++;
          final hasMethod = url.queryParameters.containsKey('method');
          if (hasMethod) {
            return _res('{"message":"unsupported"}', 400);
          }
          return _res(jsonEncode(paymentDetailsJson), 200);
        }),
      );

      // Doge is not in the provider's supported list, so the controller should
      // return unsupported after just the first request (no second request).
      final result = await controller.run(
        qrData: _qrLink,
        coin: _doge,
        ownedCoins: [_doge, ...owned],
      );

      expect(result, isA<OpenCryptoPayUnsupported>());
      // Only the first request was made.
      expect(calls, 1);
    });

    test('a rejected token asset still suggests other assets on the same method',
        () async {
      final controller = _controller(
        _mockHttpWithHandler((url) {
          final hasMethod = url.queryParameters.containsKey('method');
          if (hasMethod) {
            return _res('{"message":"unsupported"}', 400);
          }
          return _res(jsonEncode(paymentDetailsJson), 200);
        }),
      );

      // User owns ETH (native) and USDT (token) on Ethereum, plus BTC.
      // USDT is rejected, but ETH on the same method should still be offered.
      final result = await controller.run(
        qrData: _qrLink,
        coin: _usdt,
        ownedCoins: [_usdt, _eth, _btc],
      );

      expect(result, isA<OpenCryptoPayUnsupported>());
      final unsupported = result as OpenCryptoPayUnsupported;
      final tickers =
          unsupported.alternatives!.map((c) => c.ticker.toUpperCase()).toSet();
      // ETH (same method, different asset) should be offered.
      expect(tickers, contains('ETH'));
      // USDT (the rejected asset) should NOT be offered.
      expect(tickers, isNot(contains('USDT')));
      // BTC should also be offered.
      expect(tickers, contains('BTC'));
    });

    test('invalid link maps to a decode error', () async {
      final controller = _controller(
        _mockHttpReturning(_res('{}', 200)),
      );

      final result = await controller.run(
        qrData: 'https://app.dfx.swiss/pl/?lightning=not-a-valid-lnurl',
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayError>());
      expect((result as OpenCryptoPayError).isDecodeError, isTrue);
      expect(result.message, OpenCryptoPayStrings.decodeFailedMessage);
    });

    test('session.submitProof completes on success, retains on failure',
        () async {
      await withClock(fixedClock, () async {
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: _btcDetails,
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        final failing = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpReturning(_res('bad', 500)),
          ),
        );
        expect(await failing.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofFailed>());
        // Retained for retry.
        expect(failing.isCompleted, isFalse);
        expect(failing.isActivePaymentFor(success.address), isTrue);

        final ok = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpReturning(_res('ok', 200)),
          ),
        );
        expect(await ok.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofAccepted>());
        expect(ok.isCompleted, isTrue);
        expect(ok.isActivePaymentFor(success.address), isFalse);

        // Completed sessions are no-ops.
        expect(await ok.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofAccepted>());
      });
    });

    test('submitProof sends the signed HEX to the /tx endpoint derived from '
        'the callback', () async {
      await withClock(fixedClock, () async {
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: _btcDetails,
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpWithHandler((url) {
              proofUrl = url;
              return _res('ok', 200);
            }),
          ),
        );

        // _btcDetails carries the HEX hint → proof is the signed tx hex.
        expect(await session.submitProof('signedHexDummy'),
            isA<OpenCryptoPayProofAccepted>());
        expect(proofUrl, isNotNull);
        expect(proofUrl!.path, '/v1/lnurlp/tx/pl_beeddb41cd4b6d9e');
        expect(proofUrl!.queryParameters['quote'], 'plq_62b1865ed28358be');
        expect(proofUrl!.queryParameters['method'], 'Bitcoin');
        expect(proofUrl!.queryParameters['hex'], 'signedHexDummy');
        expect(proofUrl!.queryParameters.containsKey('tx'), isFalse);
      });
    });

    test('submitProof sends the transaction hash to the /tx endpoint derived '
        'from the callback', () async {
      await withClock(fixedClock, () async {
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: {
            'expiryDate': '2026-06-25T08:59:05.950Z',
            'blockchain': 'Monero',
            'uri':
                'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
            'hint':
                'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
          },
        )).run(qrData: _qrLink, coin: _xmr, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpWithHandler((url) {
              proofUrl = url;
              return _res('ok', 200);
            }),
          ),
        );

        expect(await session.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofAccepted>());
        expect(proofUrl, isNotNull);
        expect(proofUrl!.path, '/v1/lnurlp/tx/pl_beeddb41cd4b6d9e');
        expect(proofUrl!.queryParameters['quote'], 'plq_62b1865ed28358be');
        expect(proofUrl!.queryParameters['method'], 'Monero');
        expect(proofUrl!.queryParameters['tx'], 'txHashDummy');
        expect(proofUrl!.queryParameters.containsKey('hex'), isFalse);
      });
    });

    test('proof failure message depends on whether the wallet broadcast',
        () async {
      await withClock(fixedClock, () async {
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: _btcDetails,
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        // _btcDetails carries the HEX hint → provider broadcasts.
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpReturning(_res('bad', 500)),
          ),
        );
        final failed =
            await session.submitProof('signedHexDummy') as OpenCryptoPayProofFailed;
        expect(failed.message, contains('Could not deliver the payment'));
      });
    });

    test('session.submitProof refuses signed tx hex when quote is expired',
        () async {
      final success = await _controller(_mockTwoRequestFlow(
        txDetailsJson: _btcDetails,
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
          as OpenCryptoPaySuccess;

      // Force an expired quote on the details (Bitcoin uses signedTransactionHex).
      final expiredDetails = OpenCryptoPayTransactionDetails(
        apiUrl: success.details.apiUrl,
        displayName: success.details.displayName,
        quoteId: success.details.quoteId,
        callback: success.details.callback,
        quoteExpiration: DateTime(2020, 1, 1),
        expiryDate: success.details.expiryDate,
        blockchain: success.details.blockchain,
        uri: success.details.uri,
        hint: success.details.hint,
        lightningInvoice: success.details.lightningInvoice,
        raw: success.details.raw,
      );

      // No HTTP mock needed — the guard fires before any request.
      final session = OpenCryptoPaySession(
        details: expiredDetails,
        coin: success.coin,
        service: OpenCryptoPayService(
          client: _mockHttpReturning(_res('ok', 200)),
        ),
      );
      final result = await session.submitProof('signedHexDummy');
      expect(result, isA<OpenCryptoPayProofQuoteExpired>());
      expect((result as OpenCryptoPayProofQuoteExpired).error,
          isA<OpenCryptoPayQuoteExpiredException>());
      expect(session.isCompleted, isFalse);
    });

    test('session.submitProof allows transaction hash even when quote is '
        'expired', () async {
      final success = await _controller(_mockTwoRequestFlow(
        txDetailsJson: {
          'expiryDate': '2026-06-25T08:59:05.950Z',
          'blockchain': 'Monero',
          'uri':
              'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
          'hint':
              'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
        },
      )).run(qrData: _qrLink, coin: _xmr, ownedCoins: owned)
          as OpenCryptoPaySuccess;

      // Monero uses transactionHash → broadcast yourself → quote expiry
      // does NOT block submission.
      final expiredDetails = OpenCryptoPayTransactionDetails(
        apiUrl: success.details.apiUrl,
        displayName: success.details.displayName,
        quoteId: success.details.quoteId,
        callback: success.details.callback,
        quoteExpiration: DateTime(2020, 1, 1),
        expiryDate: success.details.expiryDate,
        blockchain: success.details.blockchain,
        uri: success.details.uri,
        hint: success.details.hint,
        lightningInvoice: success.details.lightningInvoice,
        raw: success.details.raw,
      );

      final session = OpenCryptoPaySession(
        details: expiredDetails,
        coin: success.coin,
        service: OpenCryptoPayService(
          client: _mockHttpReturning(_res('ok', 200)),
        ),
      );
      expect(await session.submitProof('txHashDummy'),
          isA<OpenCryptoPayProofAccepted>());
    });
  });
}
