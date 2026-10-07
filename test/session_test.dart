import 'package:clock/clock.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('OpenCryptoPaySession', () {
    test('the session carries the matched method minFee and its unit',
        () async {
      final success = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: btcDetails,
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
          as OpenCryptoPaySuccess;

      expect(success.session.minFee, 2.146);
      expect(success.minFeeUnit, OpenCryptoPayFeeUnit.satsPerVByte);

      // The unit follows the chain type of the coin.
      OpenCryptoPayFeeUnit unitFor(CryptoCoin coin) => OpenCryptoPaySession(
            details: success.details,
            coin: coin,
            service: OpenCryptoPayService(
              client: mockHttpReturning(res('{}', 200)),
            ),
          ).minFeeUnit;
      expect(unitFor(eth), OpenCryptoPayFeeUnit.weiPerGas);
      expect(unitFor(xmr), OpenCryptoPayFeeUnit.unknown);
    });

    test('session.submitProof completes on success, retains on failure',
        () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: btcDetails,
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        final failing = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: mockHttpReturning(res('bad', 500)),
          ),
        );
        expect(await failing.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofFailed>());
        // Retained for retry.
        expect(failing.isCompleted, isFalse);
        expect(failing.isActivePaymentFor(success.address), isTrue);

        var requests = 0;
        final ok = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((_) {
              requests++;
              return res('ok', 200);
            }),
          ),
        );
        expect(await ok.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofAccepted>());
        expect(ok.isCompleted, isTrue);
        expect(ok.isActivePaymentFor(success.address), isFalse);

        // Completed sessions are no-ops.
        expect(await ok.submitProof('txHashDummy'),
            isA<OpenCryptoPayProofAccepted>());
        expect(requests, 1);
      });
    });

    test('overlapping proof submissions send one request', () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: btcDetails,
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        var requests = 0;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((_) {
              requests++;
              return res('ok', 200);
            }),
          ),
        );
        final results = await Future.wait([
          session.submitProof('signedTxHex'),
          session.submitProof('signedTxHex'),
        ]);

        expect(results, everyElement(isA<OpenCryptoPayProofAccepted>()));
        expect(requests, 1);
      });
    });

    test('a failed hash proof marks the broadcast payment as possibly held',
        () async {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'blockchain': 'Monero',
          'uri':
              'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
          'hint':
              'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
        },
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );
      final session = OpenCryptoPaySession(
        details: details,
        coin: xmr,
        service: OpenCryptoPayService(
          client: mockHttpReturning(res('down', 503)),
        ),
      );

      expect(await session.submitProof('txHashDummy'),
          isA<OpenCryptoPayProofFailed>());
      expect(session.mayHoldPayment, isTrue);
      expect(
        OpenCryptoPayStrings.proofFailure(session).message,
        contains('do not pay again'),
      );
      expect(
        OpenCryptoPayStrings.quoteExpiredAtSend(session).title,
        OpenCryptoPayStrings.deliveryUnconfirmedTitle,
      );
    });

    test('submitProof sends the signed HEX to the /tx endpoint derived from '
        'the callback', () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: btcDetails,
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((url) {
              proofUrl = url;
              return res('ok', 200);
            }),
          ),
        );

        // btcDetails carries the HEX hint → proof is the signed tx hex.
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

    test('submitProof sends an EVM hex with one 0x prefix', () async {
      for (final hex in ['f86c', '0xf86c']) {
        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: OpenCryptoPayTransactionDetails.fromJson(
            {'hint': dfxHexHint},
            apiUrl: decodedApiUrl,
            displayName: 'Test Shop',
            quoteId: 'plq_62b1865ed28358be',
            callback: callbackUrl,
            quoteExpiration: DateTime.parse(quoteExpiration),
          ),
          coin: eth,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((url) {
              proofUrl = url;
              return res('', 200);
            }),
          ),
        );

        await withClock(fixedClock, () => session.submitProof(hex));
        expect(proofUrl!.queryParameters['hex'], '0xf86c', reason: hex);
      }
    });

    test('submitProof sends the transaction hash to the /tx endpoint derived '
        'from the callback', () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: {
            'expiryDate': '2026-06-25T08:59:05.950Z',
            'blockchain': 'Monero',
            'uri':
                'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
            'hint':
                'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
          },
        )).run(qrData: qrLink, coin: xmr, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((url) {
              proofUrl = url;
              return res('ok', 200);
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

    test('submitProof sends the sender principal to the /tx endpoint derived '
        'from the callback', () async {
      await withClock(fixedClock, () async {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          {
            'blockchain': 'InternetComputer',
            'uri': 'icp:ryjl3-tyaaa-aaaaa-aaaba-cai/transfer'
                '?to=ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae'
                '&amount=0.34772601',
            'hint': dfxInternetComputerHint,
          },
          apiUrl: decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: callbackUrl,
          quoteExpiration: DateTime.parse(quoteExpiration),
        );
        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: details,
          coin: icp,
          service: OpenCryptoPayService(
            client: mockHttpWithHandler((url) {
              proofUrl = url;
              return res('ok', 200);
            }),
          ),
        );

        expect(await session.submitProof('principalDummy'),
            isA<OpenCryptoPayProofAccepted>());
        expect(proofUrl!.path, '/v1/lnurlp/tx/pl_beeddb41cd4b6d9e');
        expect(proofUrl!.queryParameters['method'], 'InternetComputer');
        expect(proofUrl!.queryParameters['asset'], 'ICP');
        expect(proofUrl!.queryParameters['sender'], 'principalDummy');
        expect(proofUrl!.queryParameters.containsKey('hex'), isFalse);
        expect(proofUrl!.queryParameters.containsKey('tx'), isFalse);
      });
    });

    test('proof failure message depends on whether the wallet broadcast',
        () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: btcDetails,
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        // btcDetails carries the HEX hint → provider broadcasts.
        OpenCryptoPaySession sessionWith(Client client) => OpenCryptoPaySession(
              details: success.details,
              coin: success.coin,
              service: OpenCryptoPayService(client: client),
            );
        Future<OpenCryptoPayProofFailed> fail(
                OpenCryptoPaySession session) async =>
            await session.submitProof('signedHexDummy')
                as OpenCryptoPayProofFailed;

        final refusing = sessionWith(mockHttpReturning(res('bad', 400)));
        final refused = await fail(refusing);
        expect(refused.error, isA<OpenCryptoPayApiException>());
        expect(refused.isRejectedByProvider, isTrue);
        expect(refusing.mayHoldPayment, isFalse);
        expect(OpenCryptoPayStrings.proofFailure(refusing).title,
            OpenCryptoPayStrings.deliveryFailedTitle);

        // A server error may come after the provider broadcast.
        final failing = sessionWith(mockHttpReturning(res('bad', 503)));
        expect((await fail(failing)).isRejectedByProvider, isFalse);
        expect(failing.mayHoldPayment, isTrue);
        expect(OpenCryptoPayStrings.proofFailure(failing).title,
            OpenCryptoPayStrings.deliveryUnconfirmedTitle);

        final unreachable = sessionWith(
            MockClient((_) async => throw Exception('socket closed')));
        expect((await fail(unreachable)).isRejectedByProvider, isFalse);
        expect(unreachable.mayHoldPayment, isTrue);
        expect(OpenCryptoPayStrings.proofFailure(unreachable).title,
            OpenCryptoPayStrings.deliveryUnconfirmedTitle);
      });
    });

    test('a refusal after a possibly delivered proof stays unconfirmed',
        () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: btcDetails,
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;
        var attempts = 0;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: MockClient((_) async {
              if (attempts++ == 0) throw Exception('socket closed');
              return res('bad', 400);
            }),
          ),
        );

        await session.submitProof('signedHexDummy');
        final refused = await session.submitProof('signedHexDummy')
            as OpenCryptoPayProofFailed;
        expect(refused.isRejectedByProvider, isTrue);
        expect(session.mayHoldPayment, isTrue);
        expect(OpenCryptoPayStrings.proofFailure(session).title,
            OpenCryptoPayStrings.deliveryUnconfirmedTitle);
      });
    });

    test('an expired quote at send reports a possibly delivered proof',
        () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: btcDetails,
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: MockClient((_) async => throw Exception('socket closed')),
          ),
        );

        final notSent = OpenCryptoPayStrings.quoteExpiredAtSend(session);
        expect(notSent.title, OpenCryptoPayStrings.quoteExpiredTitle);
        expect(notSent.message, contains('NOT sent'));

        await session.submitProof('signedHexDummy');
        expect(OpenCryptoPayStrings.quoteExpiredAtSend(session).title,
            OpenCryptoPayStrings.deliveryUnconfirmedTitle);
      });
    });

    test('an expired quote at send reports a possibly sent broadcast',
        () async {
      await withClock(fixedClock, () async {
        final success = await controllerFor(mockTwoRequestFlow(
          txDetailsJson: {
            ...btcDetails,
            'hint': 'Broadcast the signed transaction to the blockchain and '
                'send the transaction hash back.',
          },
        )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: mockHttpReturning(res('ok', 200)),
          ),
        );
        expect(session.isBroadcastRequired, isTrue);
        expect(OpenCryptoPayStrings.quoteExpiredAtSend(session).title,
            OpenCryptoPayStrings.quoteExpiredTitle);

        session.recordFailedBroadcast();
        expect(session.mayHoldPayment, isTrue);
        expect(OpenCryptoPayStrings.quoteExpiredAtSend(session).title,
            OpenCryptoPayStrings.deliveryUnconfirmedTitle);
      });
    });

    test('session.submitProof refuses signed tx hex when quote is expired',
        () async {
      final success = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: btcDetails,
      )).run(qrData: qrLink, coin: btc, ownedCoins: owned)
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
          client: mockHttpReturning(res('ok', 200)),
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
      final success = await controllerFor(mockTwoRequestFlow(
        txDetailsJson: {
          'expiryDate': '2026-06-25T08:59:05.950Z',
          'blockchain': 'Monero',
          'uri':
              'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u?tx_amount=0.00394642',
          'hint':
              'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e',
        },
      )).run(qrData: qrLink, coin: xmr, ownedCoins: owned)
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
          client: mockHttpReturning(res('ok', 200)),
        ),
      );
      expect(await session.submitProof('txHashDummy'),
          isA<OpenCryptoPayProofAccepted>());
    });
  });
}
