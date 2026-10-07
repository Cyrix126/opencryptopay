import 'dart:convert';

import 'package:blockchain_utils/bech32/bech32_base.dart';
import 'package:http/testing.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'sample_data/open_crypto_pay_payment_details_json.dart';

void main() {
  group('OpenCryptoPayController', () {
    test('success: classifies a payable Bitcoin payment and labels it',
        () async {
      final controller = controllerFor(mockTwoRequestFlow(
        txDetailsJson: btcDetails,
      ));

      final result = await controller.run(
        qrData: qrLink,
        coin: btc,
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
      expect(success.details.recipient?.name, 'hier könnte Viktor stehen');
      expect(success.details.recipient?.city, 'Zug');
      // Bitcoin hint asks for HEX → wallet must NOT broadcast.
      expect(success.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
      expect(success.isBroadcastRequired, isFalse);
    });

    test('check that the transaction detail url is constructed with the same quoteId'
      'found in the payment detail response', () async {
      final fetched = <Uri>[];
      final controller = controllerFor(
        mockHttpWithHandler((url) {
          fetched.add(url);
          if (!url.queryParameters.containsKey('method')) {
            return res(jsonEncode(paymentDetailsJson), 200);
          }
          return res(jsonEncode(btcDetails), 200);
        }),
      );

      final result = await controller.run(
        qrData: qrLink,
        coin: btc,
        ownedCoins: owned,
      );
      expect(result, isA<OpenCryptoPaySuccess>());
      expect(fetched, hasLength(2));
      expect(fetched[0].toString(), decodedApiUrl);

      final detailsUrl = fetched[1];
      expect(detailsUrl.host, Uri.parse(callbackUrl).host);
      expect(detailsUrl.path, Uri.parse(callbackUrl).path);
      expect(
        detailsUrl.queryParameters['quote'],
        paymentDetailsJson['quote']['id'],
      );
      expect(detailsUrl.queryParameters['method'], btc.prettyName);
      expect(detailsUrl.queryParameters['asset'], btc.ticker);
    });

    test('success: Monero hash flow requires broadcast', () async {
      final controller = controllerFor(mockTwoRequestFlow(
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
        qrData: qrLink,
        coin: xmr,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPaySuccess>());
      final success = result as OpenCryptoPaySuccess;
      expect(success.proofType, OpenCryptoPayProofType.transactionHash);
      expect(success.isBroadcastRequired, isTrue);
    });

    test('404 on first request maps to no pending payment', () async {
      final controller = controllerFor(
        mockHttpReturning(res('{"message":"none"}', 404)),
      );

      final result = await controller.run(
        qrData: qrLink,
        coin: btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayNoPending>());
    });

    test('missing address maps to an invalid address result', () async {
      final controller = controllerFor(mockTwoRequestFlow(
        txDetailsJson: {'blockchain': 'Bitcoin', 'hint': dfxHexHint},
      ));

      final result = await controller.run(
        qrData: qrLink,
        coin: btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayInvalidAddress>());
    });

    test('unparsable amount maps to an invalid amount result', () async {
      for (final uri in [
        'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=abc',
        'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=1e10000000',
        'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=-0.5',
        'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1?value=0x10',
        'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1?value=%2016',
        'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1?value=1e100',
        'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer'
            '?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC&uint256=1.5',
      ]) {
        final controller = controllerFor(mockTwoRequestFlow(
          txDetailsJson: {
            'blockchain': 'Bitcoin',
            'uri': uri,
            'hint': dfxHexHint,
          },
        ));

        final result = await controller.run(
          qrData: qrLink,
          coin: btc,
          ownedCoins: owned,
        );

        expect(result, isA<OpenCryptoPayInvalidAmount>(), reason: uri);
        expect(
          OpenCryptoPayStrings.failure(result as OpenCryptoPayFailure).title,
          OpenCryptoPayStrings.invalidAmountTitle,
        );
      }
    });

    test('the smallest unit amount covers the requested amount', () async {
      for (final (coin, uri, fractionDigits, smallest) in [
        (
          btc,
          'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.00001947',
          8,
          BigInt.from(1947),
        ),
        (
          btc,
          'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.123456789',
          8,
          BigInt.from(12345679),
        ),
        (
          btc,
          'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.000000004',
          8,
          BigInt.one,
        ),
        (
          eth,
          'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1'
              '?value=2.014e18',
          18,
          BigInt.parse('2014000000000000000'),
        ),
      ]) {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: {...btcDetails, 'uri': uri},
        )).run(qrData: qrLink, coin: coin, ownedCoins: owned);

        expect(
          (success as OpenCryptoPaySuccess)
              .amountInSmallestUnit(fractionDigits),
          smallest,
          reason: uri,
        );
      }
    });

    test('an undecodable payment URI query maps to an error', () async {
      final result = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: {
          ...btcDetails,
          'uri': 'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.5&label=Caf%E9',
        },
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayError>());
    });

    test('a hint naming no proof type maps to an unknown proof type', () async {
      final result = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: {...btcDetails, 'hint': 'Pay this request.'},
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayUnknownProofType>());
      expect(
        OpenCryptoPayStrings.failure(result as OpenCryptoPayFailure).message,
        OpenCryptoPayStrings.unknownProofTypeMessage,
      );
    });

    test('an unknown proof type is reported before the payment URI is read',
        () async {
      // BinancePay details from the spec: a deep link without an amount.
      const link = 'bnc://app.binance.com/payment/secpay'
          '?tempToken=IzjFLlGOoHAdeUth9FurNGjONDeI5Hq9';
      final result = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: {
          'expiryDate': '2025-05-01T14:34:40.881Z',
          'uri': link,
          'hint': 'Pay in the Binance app by following the deep link $link.',
        },
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayUnknownProofType>());
    });

    test('a callback the proof URL cannot be built from maps to an error',
        () async {
      final result = await controllerFor(mockTwoRequestFlow(
        paymentInfoJson: {...paymentDetailsJson, 'callback': decodedApiUrl},
        txDetailsJson: btcDetails,
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayError>());
    });

    test('a 400 for a listed asset maps to an error', () async {
      final result = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: {'message': 'Failed to create order'},
        txDetailsStatus: 400,
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayError>());
    });

    test('a 400 for a method without an asset list maps to unsupported',
        () async {
      final result = await controllerFor(mockTwoRequestFlow(
        paymentInfoJson: {
          ...paymentDetailsJson,
          'transferAmounts': [
            {'method': 'Bitcoin', 'minFee': 0, 'available': true},
          ],
        },
        txDetailsJson: {'message': 'unsupported'},
        txDetailsStatus: 400,
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayUnsupported>());
    });

    test('unsupported coin maps to unsupported result with alternatives',
        () async {
      var calls = 0;
      final controller = controllerFor(
        mockHttpWithHandler((url) {
          calls++;
          final hasMethod = url.queryParameters.containsKey('method');
          if (hasMethod) {
            return res('{"message":"unsupported"}', 400);
          }
          return res(jsonEncode(paymentDetailsJson), 200);
        }),
      );

      // Use a coin the provider does not list so the rejected coin is excluded
      // and only owned, supported alternatives come back.
      final result = await controller.run(
        qrData: qrLink,
        coin: doge,
        ownedCoins: [doge, ...owned],
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
      final controller = controllerFor(
        mockHttpWithHandler((url) {
          calls++;
          final hasMethod = url.queryParameters.containsKey('method');
          if (hasMethod) {
            return res('{"message":"unsupported"}', 400);
          }
          return res(jsonEncode(paymentDetailsJson), 200);
        }),
      );

      // Doge is not in the provider's supported list, so the controller should
      // return unsupported after just the first request (no second request).
      final result = await controller.run(
        qrData: qrLink,
        coin: doge,
        ownedCoins: [doge, ...owned],
      );

      expect(result, isA<OpenCryptoPayUnsupported>());
      // Only the first request was made.
      expect(calls, 1);
    });

    test('an unlisted token asset still suggests other assets on the same method',
        () async {
      final paymentInfo =
          jsonDecode(jsonEncode(paymentDetailsJson)) as Map<String, dynamic>;
      final ethereum = (paymentInfo['transferAmounts'] as List)
          .firstWhere((entry) => entry['method'] == 'Ethereum') as Map;
      (ethereum['assets'] as List).removeWhere((a) => a['asset'] == 'USDT');
      final controller = controllerFor(mockTwoRequestFlow(
        paymentInfoJson: paymentInfo,
        txDetailsJson: {'message': 'unsupported'},
        txDetailsStatus: 400,
      ));

      // User owns ETH (native) and USDT (token) on Ethereum, plus BTC.
      // USDT is not listed, but ETH on the same method should still be offered.
      final result = await controller.run(
        qrData: qrLink,
        coin: usdt,
        ownedCoins: [usdt, eth, btc],
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
      final controller = controllerFor(
        mockHttpReturning(res('{}', 200)),
      );

      final result = await controller.run(
        qrData: 'https://app.dfx.swiss/pl/?lightning=not-a-valid-lnurl',
        coin: btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayError>());
      expect((result as OpenCryptoPayError).isDecodeError, isTrue);
    });

    test('network failure maps to a non-decode error', () async {
      final controller = controllerFor(
        MockClient((_) async => throw Exception('socket closed')),
      );

      final result = await controller.run(
        qrData: qrLink,
        coin: btc,
        ownedCoins: owned,
      );

      expect(result, isA<OpenCryptoPayError>());
      expect((result as OpenCryptoPayError).isDecodeError, isFalse);
      expect(result.error, isNotNull);
      expect(
        OpenCryptoPayStrings.failure(result).message,
        OpenCryptoPayStrings.genericErrorMessage,
      );
    });

    test('an LNURL with another prefix, no web URL or host is a decode error',
        () async {
      for (final lnurl in [
        Bech32Encoder.encode('lnbc', utf8.encode(decodedApiUrl)),
        Bech32Encoder.encode('lnurl', utf8.encode('api.dfx.swiss/pl_x')),
        Bech32Encoder.encode('lnurl', utf8.encode('https:///pl_x')),
      ]) {
        final result = await controllerFor(
          mockHttpReturning(res(jsonEncode(paymentDetailsJson), 200)),
        ).run(
          qrData: 'https://app.dfx.swiss/pl/?lightning=$lnurl',
          coin: btc,
          ownedCoins: owned,
        );

        expect(result, isA<OpenCryptoPayError>(), reason: lnurl);
        expect((result as OpenCryptoPayError).isDecodeError, isTrue);
      }
    });
  });
}
