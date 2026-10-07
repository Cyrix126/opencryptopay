import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Parsing transaction details correctly', () {
    test('parses a Bitcoin details response', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        btcDetails,
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Bitcoin');
      expect(details.displayName, 'Test Shop');
      expect(details.quoteId, 'plq_62b1865ed28358be');
      expect(details.callback, callbackUrl);
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
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );

      expect(details.isLightning, isFalse);
      expect(details.blockchain, 'Monero');
      expect(
        details.address,
        '88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u',
      );
      expect(details.amount, '0.00394642');
      expect(details.callback, callbackUrl);
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
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
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
      expect(details.callback, callbackUrl);
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
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
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
      expect(details.callback, callbackUrl);
    });

    test('a token transfer URI without a recipient has no address', () {
      for (final uri in [
        'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer'
            '?uint256=1246858',
        'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer'
            '?address=&uint256=1246858',
      ]) {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          {'blockchain': 'Ethereum', 'uri': uri},
          apiUrl: decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: callbackUrl,
          quoteExpiration: DateTime.parse(quoteExpiration),
        );
        expect(details.address, isNull, reason: uri);
      }
    });

    test('a transfer URI may name its recipient with to', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'blockchain': 'InternetComputer',
          'uri': 'icp:ryjl3-tyaaa-aaaaa-aaaba-cai/transfer'
              '?to=ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae'
              '&amount=0.34772601',
        },
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );
      expect(
        details.address,
        'ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae',
      );
    });

    test('a transfer URI without uint256 reads its decimal amount', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'blockchain': 'InternetComputer',
          'uri': 'icp:ryjl3-tyaaa-aaaaa-aaaba-cai/transfer'
              '?to=ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae'
              '&amount=0.34772601',
        },
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );
      expect(details.amount, '0.34772601');
      expect(details.isRawAmount, isFalse);
    });

    test('a /transfer in the query does not make a token transfer', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'blockchain': 'Bitcoin',
          'uri': 'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.001&label=Shop/transfer&address=bc1qother',
        },
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );
      expect(details.isErc20Transfer, isFalse);
      expect(details.address, 'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6');
    });

    test('takes the amount and its raw flag from the same query key', () {
      for (final (uri, amount, isRaw) in [
        (
          'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1'
              '?amount=1&value=1000000000000000000',
          '1',
          false,
        ),
        (
          'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer'
              '?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC'
              '&uint256=1246858&value=0',
          '1246858',
          true,
        ),
      ]) {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          {'blockchain': 'Ethereum', 'uri': uri},
          apiUrl: decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: callbackUrl,
          quoteExpiration: DateTime.parse(quoteExpiration),
        );
        expect(details.amount, amount, reason: uri);
        expect(details.isRawAmount, isRaw, reason: uri);
      }
    });
  });
}
