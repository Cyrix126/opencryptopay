import 'dart:convert';

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
}

const _btc = _Coin('BTC', 'Bitcoin');
const _eth = _Coin('ETH', 'Ethereum');
const _xmr = _Coin('XMR', 'Monero');
const _firo = _Coin('FIRO', 'Firo');
const _ada = _Coin('ADA', 'Cardano');
const _sol = _Coin('SOL', 'Solana');
const _doge = _Coin('DOGE', 'Dogecoin');
const _ltc = _Coin('LTC', 'Litecoin');

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
  'expiryDate': '2026-06-25T09:15:59.594Z',
  'blockchain': 'Bitcoin',
  'displayName': 'Test Shop',
  'uri': 'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=0.00002019',
  'hint': 'Send the transaction hash back via the endpoint '
      'https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
};

void main() {
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

  group('OpenCryptoPay simplified flow URL building', () {
    test('appends method and asset query parameters', () {
      final url = OpenCryptoPayService.buildSimplifiedFlowUrl(
        apiUrl: _decodedApiUrl,
        method: 'Monero',
        asset: 'XMR',
      );
      expect(url.path, '/v1/lnurlp/pl_beeddb41cd4b6d9e');
      expect(url.queryParameters['method'], 'Monero');
      expect(url.queryParameters['asset'], 'XMR');
    });
  });

  group('Parsing payment details correctly', () {
    test('parses a Bitcoin details response', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-06-25T09:15:59.594Z',
          'blockchain': 'Bitcoin',
          'uri':
              'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=0.00002019&label=Payment',
          'hint':
              'Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain.',
        },
        apiUrl: _decodedApiUrl,
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Bitcoin');
      expect(
        details.address,
        'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
      );
      expect(details.amount, '0.00002019');
      expect(
        details.txSubmissionEndpoint,
        'https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
      );
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
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Monero');
      expect(
        details.address,
        '88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u',
      );
      expect(details.amount, '0.00394642');
      expect(
        details.txSubmissionEndpoint,
        'https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
      );
    });

    test('parses an EVM details response', () {
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
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Ethereum');
      expect(
        details.address,
        '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
      );
      expect(details.amount, '753470000000000');
      expect(
        details.txSubmissionEndpoint,
        'https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
      );
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
        supportedMethods: {'Bitcoin', 'Ethereum'},
      );
      expect(supported.map((e) => e.prettyName), ['Bitcoin']);
    });
  });

  group('detect the provider supported coins', () {
    test('detects every available method and excludes unavailable ones', () {
      final methods =
          OpenCryptoPayService.parseSupportedMethods(paymentDetailsJson);

      expect(
        methods,
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
      expect(methods.length, 16);
      expect(methods, isNot(contains('TaprootAsset')));
      expect(methods, isNot(contains('Spark')));
      expect(methods, isNot(contains('Arkade')));
    });

    test('maps supported methods to the user\'s payable wallets', () {
      final supportedMethods =
          OpenCryptoPayService.parseSupportedMethods(paymentDetailsJson)
              .toSet();

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
  });

  group('OpenCryptoPayController', () {
    final owned = <CryptoCoin>[_btc, _eth, _xmr];

    test('success: classifies a payable Bitcoin payment and labels it',
        () async {
      final controller = _controller(
        _mockHttpReturning(_res(jsonEncode(_btcDetails), 200)),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPaySuccess>());
      final success = result as OpenCryptoPaySuccess;
      expect(success.address, 'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6');
      expect(success.amount.toString(), '0.00002019');
      expect(success.recipientLabel, 'Test Shop');
      expect(success.method, 'Bitcoin');
    });

    test('success: falls back to address when displayName is absent', () async {
      final noName = Map<String, dynamic>.from(_btcDetails)
        ..remove('displayName');
      final controller = _controller(
        _mockHttpReturning(_res(jsonEncode(noName), 200)),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      final success = result as OpenCryptoPaySuccess;
      expect(success.recipientLabel, success.address);
    });

    test('404 maps to no pending payment', () async {
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
      final controller = _controller(
        _mockHttpReturning(_res('{"pr":"lnbc1..."}', 200)),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayLightning>());
    });

    test('missing address maps to an invalid address result', () async {
      final controller = _controller(
        _mockHttpReturning(_res('{"blockchain":"Bitcoin","hint":"x"}', 200)),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayInvalidAddress>());
    });

    test('a 400 error code will trigger another request to get available coins',
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
      final names = unsupported.alternatives.map((c) => c.prettyName).toSet();
      expect(names, containsAll(<String>['Bitcoin', 'Ethereum', 'Monero']));
      expect(names, isNot(contains('Dogecoin')));
      expect(calls, 2);
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

    test('submitProof returns null on success, error on failure', () async {
      final success = await _controller(
        _mockHttpReturning(_res(jsonEncode(_btcDetails), 200)),
      ).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
          as OpenCryptoPaySuccess;

      final okController = _controller(_mockHttpReturning(_res('ok', 200)));
      final ok = await okController.submitProof(
        details: success.details,
        method: success.method,
        txHash: 'txHashDummy',
      );
      expect(ok, isNull);

      final failController = _controller(_mockHttpReturning(_res('bad', 500)));
      final err = await failController.submitProof(
        details: success.details,
        method: success.method,
        txHash: 'txHashDummy',
      );
      expect(err, isNotNull);
    });
  });
}
