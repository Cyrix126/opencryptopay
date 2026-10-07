import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Proof type detection from hint', () {
    test('HEX hint -> signedTransactionHex, isBroadcastRequired false', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        btcDetails,
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );
      expect(details.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
      expect(details.isBroadcastRequired, isFalse);
    });

    test('hash hint -> transactionHash, isBroadcastRequired true', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'expiryDate': '2026-06-25T08:59:05.950Z',
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
      expect(details.proofType, OpenCryptoPayProofType.transactionHash);
      expect(details.isBroadcastRequired, isTrue);
    });

    test('case-insensitive "as hex" detection', () {
      final details = OpenCryptoPayTransactionDetails.fromJson(
        {
          'blockchain': 'Ethereum',
          'uri': 'ethereum:0xabc@1?value=1',
          'hint':
              'Send the signed transaction back as hex via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_x',
        },
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
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
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: callbackUrl,
        quoteExpiration: DateTime.parse(quoteExpiration),
      );
      expect(details.proofType,
          OpenCryptoPayProofType.signedTransactionHex);
      expect(details.isBroadcastRequired, isFalse);
    });

    // Hints returned by the DFX demo payment link for each method, with the
    // proof type the library must detect. Lightning returns no hint and
    // BinancePay returned an error.
    const hex = OpenCryptoPayProofType.signedTransactionHex;
    const hash = OpenCryptoPayProofType.transactionHash;
    const sender = OpenCryptoPayProofType.senderPrincipal;
    const dfxHints = {
      'Ethereum': (dfxHexHint, hex),
      'Polygon': (dfxHexHint, hex),
      'Arbitrum': (dfxHexHint, hex),
      'Optimism': (dfxHexHint, hex),
      'Base': (dfxHexHint, hex),
      'BinanceSmartChain': (dfxHexHint, hex),
      'Bitcoin': (dfxHexHint, hex),
      'Firo': (dfxFiroHint, hex),
      'Monero': (dfxHashHint, hash),
      'Solana': (dfxHashHint, hash),
      'Tron': (dfxHashHint, hash),
      'Cardano': (dfxHashHint, hash),
      'Spark': (dfxSparkHint, hash),
      'InternetComputer': (dfxInternetComputerHint, sender),
    };
    for (final MapEntry(key: method, value: (hint, proofType))
        in dfxHints.entries) {
      test('DFX $method hint -> ${proofType.name}', () {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          {'blockchain': method, 'hint': hint},
          apiUrl: decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: callbackUrl,
          quoteExpiration: DateTime.parse(quoteExpiration),
        );
        expect(details.proofType, proofType);
      });
    }
  });
}
