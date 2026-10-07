import 'dart:convert';

import 'package:blockchain_utils/bech32/bech32_base.dart';
import 'package:clock/clock.dart';
import 'package:http/testing.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'sample_data/open_crypto_pay_payment_details_json.dart';

void main() {
  // One test per statement of the OpenCryptoPay README, checking that the user
  // neither pays twice nor pays for nothing. Where DFX production answers
  // differently, the test follows production.
  group('README', () {
    final beforeQuoteExpiry = Clock.fixed(DateTime.utc(2025, 7, 16, 1));

    group('1. QR code decoding', () {
      test('the lightning parameter of the QR link holds the LNURL', () {
        expect(OpenCryptoPayService.isOpenCryptoPayUri(qrLink), isTrue);
        expect(OpenCryptoPayService.extractLnurl(qrLink), lnurl);
      });

      test('any domain can offer the service', () async {
        final lnurl = Bech32Encoder.encode(
          'lnurl',
          utf8.encode('https://api.example.com/v1/lnurlp/pl_x'),
        ).toUpperCase();
        final provider = _Provider(
          info: {
            ..._readmeInfo,
            'callback': 'https://api.example.com/v1/lnurlp/cb/pl_x',
          },
          details: _readmeEthereum,
        );

        final success = await provider.run(
          eth,
          qrData: 'https://pay.example.com/pl/?lightning=$lnurl',
        ) as OpenCryptoPaySuccess;
        await withClock(
            beforeQuoteExpiry, () => success.session.submitProof('0xsigned'));

        // The proof reaches the provider that priced the payment.
        expect(provider.requests.map((url) => url.host),
            everyElement('api.example.com'));
        expect(provider.requests.where(isProof), hasLength(1));
      });
    });

    group('2. Payment details', () {
      test('the LNURL decodes to the API URL', () {
        expect(OpenCryptoPayService.decodeLnurl(lnurl), decodedApiUrl);
      });

      test(
          'the payment details carry the recipient, quote, methods and callback',
          () {
        final info = OpenCryptoPayPaymentInfo.fromJson(
          _readmeInfo,
          apiUrl: decodedApiUrl,
        );

        expect(info.recipient?.name, 'My Company');
        expect(info.quoteId, 'plq_d170b11b44340eb1');
        expect(info.quoteExpiration, DateTime.utc(2025, 7, 16, 1, 20, 6, 476));
        expect(info.supportedMethods.map((method) => method.method),
            contains('Ethereum'));
        expect(info.callback, callbackUrl);
      });

      test('an unavailable method is not offered', () async {
        final provider = _Provider();

        expect(await provider.run(const TestCoin('BTC', 'Taproot Asset')),
            isA<OpenCryptoPayUnsupported>());
        expect(provider.requests, hasLength(1));
      });

      test('the recipient carries its registration number', () {
        final info = OpenCryptoPayPaymentInfo.fromJson(
          _readmeInfo,
          apiUrl: decodedApiUrl,
        );

        expect(info.recipient?.registrationNumber, 'CHE-123.456.789');
      });

      test('an expired quote is not used, and the user scans again', () async {
        final provider = _Provider(details: _readmeEthereum);
        final hex = await provider.run(eth) as OpenCryptoPaySuccess;
        final hash = await _Provider(details: _readmeCardano).run(ada)
            as OpenCryptoPaySuccess;

        await withClock(Clock.fixed(DateTime.utc(2025, 7, 17)), () async {
          // The wallet checks the quote before it pays.
          expect(hex.session.isQuoteExpired, isTrue);
          expect(hash.session.isQuoteExpired, isTrue);
          expect(await hex.session.submitProof('0xsigned'),
              isA<OpenCryptoPayProofQuoteExpired>());
        });
        expect(provider.requests.where(isProof), isEmpty);
        for (final session in [hex.session, hash.session]) {
          expect(
            OpenCryptoPayStrings.quoteExpiredAtSend(session).message,
            allOf(contains('NOT sent'), contains('scan the QR code again')),
          );
        }
      });

      test('the payment details request keeps the wait for a pending payment',
          () async {
        final provider = _Provider(details: _readmeEthereum);
        await provider.run(eth);

        expect(provider.requests.first.queryParameters,
            isNot(contains('timeout')));
      });

      test('a 404 means no pending payment', () async {
        final provider = _Provider(
          info: {
            'statusCode': 404,
            'message': 'No pending payment found',
            'error': 'Not Found',
          },
          infoStatus: 404,
        );

        expect(await provider.run(eth), isA<OpenCryptoPayNoPending>());
      });
    });

    group('3. Transaction details', () {
      test('the details URL is the callback with the quote, method and asset',
          () {
        final url = OpenCryptoPayService.buildTransactionDetailsUrl(
          callback: callbackUrl,
          coin: eth,
          quoteId: 'plq_9af8927afe14f2d0',
        );

        expect(
          url.toString(),
          'https://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e'
          '?quote=plq_9af8927afe14f2d0&method=Ethereum&asset=ETH',
        );
      });

      test(
          'EVM, Bitcoin and Firo details ask for a signed transaction paying '
          'the URI', () async {
        for (final (coin, details, address, token, decimals, amount) in [
          (
            eth,
            _readmeEthereum,
            '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
            null,
            18,
            '660720000000000',
          ),
          // DFX production
          (
            btc,
            btcDetails,
            'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
            null,
            8,
            '1947',
          ),
          (
            zchf,
            {
              'blockchain': 'Polygon',
              'uri': 'ethereum:0x02567e4b14b25549331fcee2b56c647a8bab16fd@137'
                  '/transfer?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC'
                  '&uint256=1000000000000000000',
              'hint': dfxHexHint,
            },
            '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
            '0x02567e4b14b25549331fcee2b56c647a8bab16fd',
            18,
            '1000000000000000000',
          ),
          // Production Firo also takes the transaction hash.
          (
            firo,
            {
              'blockchain': 'Firo',
              'uri':
                  'firo:aCPrA7sqb3QN2EH8q6XUVqE9kEGJsqq5wn?amount=1.14487149',
              'hint': dfxFiroHint,
            },
            'aCPrA7sqb3QN2EH8q6XUVqE9kEGJsqq5wn',
            null,
            8,
            '114487149',
          ),
        ]) {
          final success = await _Provider(details: details).run(coin)
              as OpenCryptoPaySuccess;

          expect(success.address, address, reason: coin.prettyName);
          expect(success.tokenContractAddress, token, reason: coin.prettyName);
          expect(success.amountInSmallestUnit(decimals), BigInt.parse(amount),
              reason: coin.prettyName);
          expect(success.proofType, OpenCryptoPayProofType.signedTransactionHex,
              reason: coin.prettyName);
        }
      });

      test(
          'Monero, Zano, Solana, Tron and Cardano details ask for the hash of '
          'a transaction paying the URI', () async {
        for (final (coin, details, address, decimals, amount) in [
          (
            ada,
            _readmeCardano,
            'addr1qyqjzchnayplhgueg33gukpp2max9gkge4gh6jly93a0dzcm67tl9f0pkykty8my4j4hg8e9suj8nzdrjygmfy6c8d0skmaq5q',
            6,
            '4883112',
          ),
          // DFX production
          (
            xmr,
            {
              'blockchain': 'Monero',
              'uri':
                  'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4zn'
                      'Q2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u'
                      '?tx_amount=0.00215578',
              'hint': dfxHashHint,
            },
            '88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u',
            12,
            '2155780000',
          ),
          (
            sol,
            {
              'blockchain': 'Solana',
              'uri': 'solana:2eQ2Somiat63oqSPwzQLrrNiceC8F6TH85dt2qDe3z36'
                  '?amount=0.01009715',
              'hint': dfxHashHint,
            },
            '2eQ2Somiat63oqSPwzQLrrNiceC8F6TH85dt2qDe3z36',
            9,
            '10097150',
          ),
          (
            trx,
            {
              'blockchain': 'Tron',
              'uri': 'tron:TMBbmTrNYj16HjKzN1tsm2EaT7mzuTvSAL?amount=3.61011',
              'hint': dfxHashHint,
            },
            'TMBbmTrNYj16HjKzN1tsm2EaT7mzuTvSAL',
            6,
            '3610110',
          ),
        ]) {
          final success = await _Provider(details: details).run(coin)
              as OpenCryptoPaySuccess;

          expect(success.address, address, reason: coin.prettyName);
          expect(success.amountInSmallestUnit(decimals), BigInt.parse(amount),
              reason: coin.prettyName);
          expect(success.proofType, OpenCryptoPayProofType.transactionHash,
              reason: coin.prettyName);
        }
      });

      test('Spark details ask for the transfer ID', () async {
        final success = await _Provider(details: _productionSpark).run(spark)
            as OpenCryptoPaySuccess;

        expect(success.address,
            'spark1pgss9cx833p3ls8s4536eav8vh0q6c8ctjd7a75666r2jmvrj4rgpuqe0xfm9r');
        expect(success.proofType, OpenCryptoPayProofType.transactionHash);
      });

      test('Internet Computer is paid by approving the provider', () async {
        for (final (uri, address) in [
          ('icp:6bf47-...-cai?amount=0.08415', '6bf47-...-cai'),
          // DFX production
          (
            'icp:ryjl3-tyaaa-aaaaa-aaaba-cai/transfer'
                '?to=ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae'
                '&amount=0.34772601',
            'ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae',
          ),
        ]) {
          final result = await _Provider(details: {
            'blockchain': 'InternetComputer',
            'uri': uri,
            'hint': dfxInternetComputerHint,
          }).run(icp);

          expect(result, isA<OpenCryptoPaySuccess>(), reason: uri);
          final success = result as OpenCryptoPaySuccess;
          expect(success.proofType, OpenCryptoPayProofType.senderPrincipal);
          expect(success.isBroadcastRequired, isFalse);
          expect(success.address, address);
        }
      });

      test('Lightning details carry an invoice, reported as unsupported',
          () async {
        final provider = _Provider(details: {
          'pr': 'lnbc12590n1p5p8p66pp5eh5manf8yj39ktlfm7h9y4uzph0wjnt6ngu2c709s9'
              'z5wndrfxkshp5kyucf7yxx97e0axrwke7xdy599csdhy67jd5pysz2n3m4d636c'
              'gqcqzzsxqzgvsp5wl7m20pwux8p49cumznt2vk3p6x08h0vshnpf2ckqzkwfw6f'
              'jdms9qyyssqy4mtye0fekxpgcjftmtqqre43xewmnsu94xmkq4yr8yfuj8se4yn'
              'd57s3etcdt3qwrrzx9x2qfm0kpz6kj9wy6ys328znrdvsq6mzrcpw0nfqs',
        });

        expect(await provider.run(lightning), isA<OpenCryptoPayLightning>());
      });

      test('BinancePay is reported as unsupported', () async {
        final readme = _Provider(details: {
          'expiryDate': '2025-05-01T14:34:40.881Z',
          'uri': 'bnc://app.binance.com/payment/secpay'
              '?tempToken=IzjFLlGOoHAdeUth9FurNGjONDeI5Hq9',
          'hint': 'Pay in the Binance app by following the deep link '
              'bnc://app.binance.com/payment/secpay'
              '?tempToken=IzjFLlGOoHAdeUth9FurNGjONDeI5Hq9.',
        });
        // DFX production fails to create the order.
        final production = _Provider(
          details: {
            'statusCode': 503,
            'message': 'Failed to create order: The sub-merchant does not '
                'exist or is in an unavailable state.',
            'error': 'Service Unavailable',
          },
          detailsStatus: 503,
        );

        expect(await readme.run(binancePay),
            isA<OpenCryptoPayUnknownProofType>());
        expect(await production.run(binancePay), isA<OpenCryptoPayError>());
      });

      test('the transaction details share the quote and its expiration',
          () async {
        final success = await _Provider(details: _readmeEthereum).run(eth)
            as OpenCryptoPaySuccess;

        expect(success.details.quoteId, 'plq_d170b11b44340eb1');
        expect(success.details.quoteExpiration,
            DateTime.utc(2025, 7, 16, 1, 20, 6, 476));
      });
    });

    group('4. Crypto transaction', () {
      test('the minimum fee is in wei for EVM chains and sat/vB for Bitcoin',
          () async {
        final ethPayment = await _Provider(details: _readmeEthereum).run(eth)
            as OpenCryptoPaySuccess;
        final btcPayment = await _Provider(details: btcDetails).run(btc)
            as OpenCryptoPaySuccess;

        expect((ethPayment.minFee, ethPayment.minFeeUnit),
            (1682009661, OpenCryptoPayFeeUnit.weiPerGas));
        expect((btcPayment.minFee, btcPayment.minFeeUnit),
            (4.5, OpenCryptoPayFeeUnit.satsPerVByte));
      });

      // DFX wallets build the proof URL this way. The README examples and the
      // DFX hints show the payment ID.
      test('the proof URL is the callback with /cb replaced by /tx', () async {
        expect(
          OpenCryptoPayService.buildTransactionProofUrl(callbackUrl)
              .toString(),
          'https://api.dfx.swiss/v1/lnurlp/tx/pl_beeddb41cd4b6d9e',
        );

        // The wallet pays only when it can send the proof.
        final provider = _Provider(
          info: {..._readmeInfo, 'callback': decodedApiUrl},
          details: _readmeCardano,
        );
        expect(await provider.run(ada), isA<OpenCryptoPayError>());
      });

      test('a URI without a recipient or a positive amount is not paid',
          () async {
        for (final (coin, uri, failure) in [
          (
            btc,
            'bitcoin:?amount=0.00001947',
            isA<OpenCryptoPayInvalidAddress>(),
          ),
          (
            btc,
            'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
            isA<OpenCryptoPayInvalidAmount>(),
          ),
          (
            btc,
            'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=0',
            isA<OpenCryptoPayInvalidAmount>(),
          ),
          // The value of an ERC-20 transfer is the ether sent with the call.
          (
            zchf,
            'ethereum:0x02567e4b14b25549331fcee2b56c647a8bab16fd@137/transfer'
                '?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC'
                '&value=1000000000000000000',
            isA<OpenCryptoPayInvalidAmount>(),
          ),
        ]) {
          final result = await _Provider(details: {
            'uri': uri,
            'hint': dfxHexHint,
          }).run(coin);

          expect(result, failure, reason: uri);
        }
      });

      test(
          'a proof carries the quote, the exact method name, the asset and '
          'the hex or tx', () async {
        await withClock(beforeQuoteExpiry, () async {
          for (final (coin, details, params) in [
            (
              bnb,
              _productionBsc,
              {'method': 'BinanceSmartChain', 'asset': 'BNB', 'hex': '0xproof'},
            ),
            (
              ada,
              _readmeCardano,
              {'method': 'Cardano', 'asset': 'ADA', 'tx': 'proof'},
            ),
          ]) {
            final provider = _Provider(details: details);
            final success = await provider.run(coin) as OpenCryptoPaySuccess;
            await success.session.submitProof('proof');

            expect(provider.requests.last.queryParameters,
                {'quote': 'plq_d170b11b44340eb1', ...params});
          }
        });
      });

      test(
          'EVM, Bitcoin and Firo: the provider broadcasts the hex, and a '
          'success code completes the payment', () async {
        await withClock(beforeQuoteExpiry, () async {
          final success = await _Provider(details: _readmeEthereum).run(eth)
              as OpenCryptoPaySuccess;

          expect(success.isBroadcastRequired, isFalse);
          expect(await success.session.submitProof('0xsigned'),
              isA<OpenCryptoPayProofAccepted>());
          expect(success.session.isCompleted, isTrue);
        });
      });

      test('BinanceSmartChain uses an ethereum: URI with chain ID 56',
          () async {
        final provider = _Provider(details: _productionBsc);
        final success = await provider.run(bnb) as OpenCryptoPaySuccess;

        expect(success.details.chainId, 56);
        expect(success.address, '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC');
        expect(success.amountInSmallestUnit(18), BigInt.from(1553320000000000));
        // Only a coin on chain 56 pays it.
        expect(await provider.run(eth), isA<OpenCryptoPayWrongChain>());
        expect(
          await provider.run(
              const TestCoin('BNB', 'Binance Smart Chain', CryptoChainType.evm)),
          isA<OpenCryptoPayWrongChain>(),
        );
      });

      test(
          'Monero, Zano, Solana, Tron and Cardano: the wallet broadcasts, and '
          'a success code completes the payment', () async {
        final success = await _Provider(details: _readmeCardano).run(ada)
            as OpenCryptoPaySuccess;

        expect(success.isBroadcastRequired, isTrue);
        expect(await success.session.submitProof('txHash'),
            isA<OpenCryptoPayProofAccepted>());
        expect(success.session.isCompleted, isTrue);
      });

      test('Spark: the transfer pays exactly the URI amount', () async {
        final success = await _Provider(details: _productionSpark).run(spark)
            as OpenCryptoPaySuccess;

        expect(success.amountInSmallestUnit(8), BigInt.from(1418));
      });

      test(
          'Spark: the transfer ID goes in the tx parameter, and a success code '
          'accepts it', () async {
        const transferId = '0198c2f4-7a1b-7c3d-9e2f-5a6b7c8d9e0f';
        final provider = _Provider(details: _productionSpark);
        final success = await provider.run(spark) as OpenCryptoPaySuccess;

        expect(await success.session.submitProof(transferId),
            isA<OpenCryptoPayProofAccepted>());
        expect(provider.requests.last.queryParameters, {
          'quote': 'plq_d170b11b44340eb1',
          'asset': 'BTC',
          'method': 'Spark',
          'tx': transferId,
        });
      });

      test(
          'Spark: after an error, the same transfer ID is reported under a '
          'new quote', () async {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          _productionSpark,
          apiUrl: decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: callbackUrl,
          quoteExpiration: DateTime.parse(quoteExpiration),
        );
        final requests = <Uri>[];
        final session = OpenCryptoPaySession(
          details: details,
          coin: spark,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((url) {
              requests.add(url);
              if (url.toString() == decodedApiUrl) {
                return res(
                  jsonEncode({
                    ...paymentDetailsJson,
                    'quote': {'id': 'plq_new', 'expiration': quoteExpiration},
                  }),
                  200,
                );
              }
              // The first quote rejected the transfer.
              final isNewQuote = url.queryParameters['quote'] == 'plq_new';
              return res('{}', isNewQuote ? 200 : 400);
            }),
          ),
        );

        expect(await session.submitProof('transferId'),
            isA<OpenCryptoPayProofFailed>());
        expect(OpenCryptoPayStrings.proofFailure(session).message,
            contains('do not pay again'));
        expect(await session.submitProof('transferId'),
            isA<OpenCryptoPayProofAccepted>());
        expect(requests.map((url) => url.path), [
          '/v1/lnurlp/tx/pl_beeddb41cd4b6d9e',
          '/v1/lnurlp/pl_beeddb41cd4b6d9e',
          '/v1/lnurlp/tx/pl_beeddb41cd4b6d9e',
        ]);
        expect(requests.last.queryParameters['tx'], 'transferId');
      });
    });
  });
}

/// The README payment details, cut to the fields these tests read. DFX
/// production fills the asset lists the README leaves out.
final _readmeInfo = {
  'callback': callbackUrl,
  'displayName': 'Test Shop',
  'recipient': {
    'name': 'My Company',
    'registrationNumber': 'CHE-123.456.789',
  },
  'quote': {
    'id': 'plq_d170b11b44340eb1',
    'expiration': '2025-07-16T01:20:06.476Z',
    'payment': 'plp_f1ba466e2f1c0a4e',
  },
  'transferAmounts': [
    _transfer('Lightning', 0, ['BTC']),
    _transfer('Polygon', 36000000139,
        ['dEURO', 'ZCHF', 'USDT', 'USDC', 'POL', 'WBTC']),
    _transfer('Ethereum', 1682009661,
        ['dEURO', 'ZCHF', 'USDT', 'USDC', 'DAI', 'ETH', 'WBTC']),
    _transfer('BinanceSmartChain', 1000000000, ['USDT', 'USDC', 'DAI', 'BNB']),
    _transfer('Bitcoin', 4.5, ['BTC']),
    _transfer('Firo', 0, ['FIRO']),
    _transfer('Monero', 0, ['XMR']),
    _transfer('Zano', 0, ['ZANO']),
    _transfer('Solana', 0, ['USDT', 'USDC', 'SOL']),
    _transfer('Tron', 0, ['USDT', 'TRX']),
    _transfer('Cardano', 0, ['ADA']),
    _transfer('BinancePay', 0, ['USDT']),
    _transfer('TaprootAsset', 0, [], isAvailable: false),
    _transfer('Spark', 0, ['BTC']),
    _transfer(
        'InternetComputer', 0, ['ICP', 'ckBTC', 'ckETH', 'ckUSDC', 'ckUSDT']),
  ],
};

Map<String, Object> _transfer(
  String method,
  num minFee,
  List<String> assets, {
  bool isAvailable = true,
}) =>
    {
      'method': method,
      'minFee': minFee,
      'assets': [
        for (final asset in assets) {'asset': asset},
      ],
      'available': isAvailable,
    };

const _readmeEthereum = {
  'expiryDate': '2025-05-01T14:34:40.881Z',
  'blockchain': 'Ethereum',
  'uri': 'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1'
      '?value=660720000000000',
  'hint': dfxHexHint,
};

const _readmeCardano = {
  'expiryDate': '2025-05-01T14:34:40.881Z',
  'blockchain': 'Cardano',
  'uri': 'cardano:addr1qyqjzchnayplhgueg33gukpp2max9gkge4gh6jly93a0dzcm67tl9f'
      '0pkykty8my4j4hg8e9suj8nzdrjygmfy6c8d0skmaq5q?amount=4.883112',
  'hint': dfxHashHint,
};

const _productionBsc = {
  'expiryDate': '2026-10-06T08:50:24.520Z',
  'blockchain': 'BinanceSmartChain',
  'uri': 'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@56'
      '?value=1553320000000000',
  'hint': dfxHexHint,
};

const _productionSpark = {
  'expiryDate': '2026-10-06T08:50:24.520Z',
  'blockchain': 'Spark',
  'uri': 'spark:spark1pgss9cx833p3ls8s4536eav8vh0q6c8ctjd7a75666r2jmvrj4rgpuqe'
      '0xfm9r?amount=0.00001418',
  'hint': dfxSparkHint,
};

/// A provider that answers the payment details with [info], the transaction
/// details with [details] and every proof with a success, and records each
/// request.
final class _Provider {
  _Provider({
    Map<String, Object?>? info,
    this.infoStatus = 200,
    this.details = const {},
    this.detailsStatus = 200,
  }) : info = info ?? _readmeInfo;

  final Map<String, Object?> info;
  final int infoStatus;
  final Map<String, Object?> details;
  final int detailsStatus;
  final requests = <Uri>[];

  Future<OpenCryptoPayResult> run(
    CryptoCoin coin, {
    String qrData = qrLink,
  }) {
    final client = MockClient((request) async {
      requests.add(request.url);
      if (isProof(request.url)) return res('', 200);
      return request.url.queryParameters.containsKey('method')
          ? res(jsonEncode(details), detailsStatus)
          : res(jsonEncode(info), infoStatus);
    });
    return controllerFor(client).run(qrData: qrData, coin: coin);
  }
}
