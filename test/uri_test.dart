import 'dart:convert';

import 'package:blockchain_utils/bech32/bech32_base.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('OpenCryptoPay URI handling', () {
    test('recognizes Open CryptoPay QR links from any provider host', () {
      expect(OpenCryptoPayService.isOpenCryptoPayUri(qrLink), isTrue);
      // A different provider host must also be detected.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://pay.example.com/pl/?lightning=$lnurl',
        ),
        isTrue,
      );
      // Path "/pl" without a trailing slash is still valid.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://pay.example.com/pl?lightning=$lnurl',
        ),
        isTrue,
      );
      // Wrong path must be rejected even with a lightning param.
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://app.dfx.swiss/other/?lightning=$lnurl',
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

    test('rejects a link whose query is not valid UTF-8', () {
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://shop.example/?n=Caf%E9',
        ),
        isFalse,
      );
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://pay.example.com/pl/?lightning=$lnurl&n=Caf%E9',
        ),
        isFalse,
      );
    });

    test('upgrades an http API URL to https', () {
      final lnurl = Bech32Encoder.encode(
        'lnurl',
        utf8.encode('http://api.dfx.swiss/v1/lnurlp/pl_beeddb41cd4b6d9e'),
      );
      expect(OpenCryptoPayService.decodeLnurl(lnurl), decodedApiUrl);
    });
  });
}
