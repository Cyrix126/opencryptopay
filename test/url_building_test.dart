import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('OpenCryptoPay transaction details URL building', () {
    test('appends quote, method and asset query parameters to the callback',
        () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: callbackUrl,
        coin: xmr,
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.path, '/v1/lnurlp/cb/pl_beeddb41cd4b6d9e');
      expect(url.queryParameters['quote'], 'plq_62b1865ed28358be');
      expect(url.queryParameters['method'], 'Monero');
      expect(url.queryParameters['asset'], 'XMR');
    });

    test('strips spaces from the method derived from the coin pretty name',
        () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: callbackUrl,
        coin: const TestCoin('BNB', 'Binance Smart Chain'),
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.queryParameters['method'], 'BinanceSmartChain');
      expect(url.queryParameters['asset'], 'BNB');
    });

    test('upgrades an http callback to https', () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: 'http://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e',
        coin: xmr,
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.scheme, 'https');
    });

    test('keeps http for an onion callback', () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: 'http://pay.example.onion/v1/lnurlp/cb/pl_beeddb41cd4b6d9e',
        coin: xmr,
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.scheme, 'http');
    });
  });

  group('OpenCryptoPay transaction proof URL building', () {
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
        () => OpenCryptoPayService.buildTransactionProofUrl(decodedApiUrl),
        throwsA(isA<OpenCryptoPayApiException>()),
      );
    });

    test('throws when the callback has no host', () {
      expect(
        () => OpenCryptoPayService.buildTransactionProofUrl(
          '/v1/lnurlp/cb/pl_beeddb41cd4b6d9e',
        ),
        throwsA(isA<OpenCryptoPayApiException>()),
      );
    });

    test('upgrades an http callback to https', () {
      final url = OpenCryptoPayService.buildTransactionProofUrl(
        'http://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e',
      );
      expect(
        url.toString(),
        'https://api.dfx.swiss/v1/lnurlp/tx/pl_beeddb41cd4b6d9e',
      );
    });
  });
}
