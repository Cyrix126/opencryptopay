import 'dart:convert';

import 'package:blockchain_utils/bech32/bech32_base.dart';
import 'package:clock/clock.dart';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:kiri_check/stateful_test.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'sample_data/open_crypto_pay_payment_details_json.dart';

/// Minimal [CryptoCoin] for tests.
class _Coin implements CryptoCoin {
  const _Coin(this.ticker, this.prettyName,
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

const _btc = _Coin('BTC', 'Bitcoin', CryptoChainType.bitcoinDerived);
const _eth = _Coin('ETH', 'Ethereum', CryptoChainType.evm, 1);
const _xmr = _Coin('XMR', 'Monero');
const _firo = _Coin('FIRO', 'Firo', CryptoChainType.bitcoinDerived);
const _ada = _Coin('ADA', 'Cardano');
const _sol = _Coin('SOL', 'Solana');
const _doge = _Coin('DOGE', 'Dogecoin', CryptoChainType.bitcoinDerived);
const _ltc = _Coin('LTC', 'Litecoin', CryptoChainType.bitcoinDerived);
const _usdt = _Coin('USDT', 'Ethereum', CryptoChainType.evm, 1);
const _zchf = _Coin('ZCHF', 'Polygon', CryptoChainType.evm, 137);
const _bnb = _Coin('BNB', 'Binance Smart Chain', CryptoChainType.evm, 56);
const _trx = _Coin('TRX', 'Tron');
const _spark = _Coin('BTC', 'Spark');
const _icp = _Coin('ICP', 'Internet Computer');
const _lightning = _Coin('BTC', 'Lightning');
const _binancePay = _Coin('USDT', 'Binance Pay');

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

// Hints of the DFX demo payment link.
const _dfxHexHint =
    'Use this data to create a transaction and sign it. Send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e. We check the transferred HEX and broadcast the transaction to the blockchain.';
const _dfxFiroHint =
    'Use this data to create a transaction and sign it. Either send the signed transaction back as HEX via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e, or broadcast the transaction yourself and send the transaction hash (txId) back via the same endpoint.';
const _dfxHashHint =
    'Use this data to create a transaction and sign it. Broadcast the signed transaction to the blockchain and send the transaction hash back via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e';
const _dfxSparkHint =
    'Pay the URI on Spark and send the transfer ID back as the tx parameter via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e';
const _dfxInternetComputerHint =
    'Approve the address from the URI for the required amount plus transfer fee using icrc2_approve. Then send your Principal ID as the sender parameter via the endpoint https://api.dfx.swiss/v1/lnurlp/tx/plp_f1ba466e2f1c0a4e.';

void main() {
  final fixedTime = DateTime.utc(2026, 6, 24, 8);
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

    test('rejects a link whose query is not valid UTF-8', () {
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://shop.example/?n=Caf%E9',
        ),
        isFalse,
      );
      expect(
        OpenCryptoPayService.isOpenCryptoPayUri(
          'https://pay.example.com/pl/?lightning=$_lnurl&n=Caf%E9',
        ),
        isFalse,
      );
    });

    test('upgrades an http API URL to https', () {
      final lnurl = Bech32Encoder.encode(
        'lnurl',
        utf8.encode('http://api.dfx.swiss/v1/lnurlp/pl_beeddb41cd4b6d9e'),
      );
      expect(OpenCryptoPayService.decodeLnurl(lnurl), _decodedApiUrl);
    });
  });

  group('OpenCryptoPay transaction details URL building', () {
    test('appends quote, method and asset query parameters to the callback',
        () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: _callbackUrl,
        coin: _xmr,
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
        callback: _callbackUrl,
        coin: const _Coin('BNB', 'Binance Smart Chain'),
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.queryParameters['method'], 'BinanceSmartChain');
      expect(url.queryParameters['asset'], 'BNB');
    });

    test('upgrades an http callback to https', () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: 'http://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e',
        coin: _xmr,
        quoteId: 'plq_62b1865ed28358be',
      );
      expect(url.scheme, 'https');
    });

    test('keeps http for an onion callback', () {
      final url = OpenCryptoPayService.buildTransactionDetailsUrl(
        callback: 'http://pay.example.onion/v1/lnurlp/cb/pl_beeddb41cd4b6d9e',
        coin: _xmr,
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
        () => OpenCryptoPayService.buildTransactionProofUrl(_decodedApiUrl),
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
      expect(eth.minFee, 98965874);
      final btc = info.supportedMethods.firstWhere((e) => e.method == 'Bitcoin');
      expect(btc.minFee, 2.146);
      final xmr = info.supportedMethods.firstWhere((e) => e.method == 'Monero');
      expect(xmr.minFee, 0);
      });
    });

    test('a method without minFee parses as zero', () {
      final methods = parseSupportedMethodsFromJson({
        'transferAmounts': [
          {'method': 'Bitcoin', 'assets': [{'asset': 'BTC'}]},
        ],
      });
      expect(methods.single.minFee, 0);
    });

    test('a method with an unusable minFee is excluded', () {
      final methods = parseSupportedMethodsFromJson({
        'transferAmounts': [
          {'method': 'Ethereum', 'minFee': '1'},
          {'method': 'Polygon', 'minFee': double.infinity},
          {'method': 'Arbitrum', 'minFee': -1},
          {'method': 'Bitcoin', 'minFee': 2},
        ],
      });
      expect(methods.single.method, 'Bitcoin');
    });

    test('parses the recipient block', () {
      final info = OpenCryptoPayPaymentInfo.fromJson(
        paymentDetailsJson,
        apiUrl: _decodedApiUrl,
      );

      final recipient = info.recipient!;
      expect(recipient.name, 'hier könnte Viktor stehen');
      expect(recipient.street, 'Bahnhofstrasse');
      expect(recipient.houseNumber, '7');
      expect(recipient.zip, '6300');
      expect(recipient.city, 'Zug');
      expect(recipient.country, 'CH');
      expect(recipient.phone, '+41792684224');
      expect(recipient.mail, 'mail@ammer.group');
      expect(recipient.website, 'https://ammer.group/');
      expect(recipient.registrationNumber, 'CHE-429.856.521');
    });

    test('formats the recipient contact details', () {
      final recipient = OpenCryptoPayPaymentInfo.fromJson(
        paymentDetailsJson,
        apiUrl: _decodedApiUrl,
      ).recipient!;

      expect(recipient.postalAddress, 'Bahnhofstrasse 7\n6300 Zug\nCH');
      expect(recipient.phoneUri, Uri.parse('tel:+41792684224'));
      expect(recipient.mailUri, Uri.parse('mailto:mail@ammer.group'));
      expect(recipient.websiteUri, Uri.parse('https://ammer.group/'));
    });

    test('recipient contact details skip empty fields', () {
      const recipient = OpenCryptoPayRecipient(
        street: 'Bahnhofstrasse',
        houseNumber: '',
        city: 'Zug',
        phone: '',
        website: 'ammer.group',
      );

      expect(recipient.postalAddress, 'Bahnhofstrasse\nZug');
      expect(recipient.phoneUri, isNull);
      expect(recipient.mailUri, isNull);
      expect(recipient.websiteUri, isNull);
      expect(const OpenCryptoPayRecipient().postalAddress, isNull);
    });

    test('legal name is null when the recipient has none', () {
      OpenCryptoPayTransactionDetails details(OpenCryptoPayRecipient? r) =>
          OpenCryptoPayTransactionDetails(
            apiUrl: _decodedApiUrl,
            displayName: 'Test Shop',
            quoteId: 'plq',
            callback: _callbackUrl,
            quoteExpiration: DateTime.parse(_quoteExpiration),
            recipient: r,
          );

      expect(
        details(const OpenCryptoPayRecipient(name: 'Test Shop AG')).legalName,
        'Test Shop AG',
      );
      expect(details(const OpenCryptoPayRecipient(name: '')).legalName, isNull);
      expect(details(null).legalName, isNull);
    });

    test('recipient is null when absent', () {
      final json = Map<String, dynamic>.from(paymentDetailsJson)
        ..remove('recipient');
      final info = OpenCryptoPayPaymentInfo.fromJson(
        json,
        apiUrl: _decodedApiUrl,
      );

      expect(info.recipient, isNull);
    });

    test('malformed optional fields read as absent', () {
      final info = OpenCryptoPayPaymentInfo.fromJson(
        {
          ...paymentDetailsJson,
          'recipient': {
            'name': 7,
            'address': 'Bahnhofstrasse 7',
            'phone': 41792684224,
            'mail': 'mail@ammer.group',
          },
        }..remove('displayName'),
        apiUrl: _decodedApiUrl,
      );

      expect(info.displayName, isEmpty);
      final recipient = info.recipient!;
      expect(recipient.name, isNull);
      expect(recipient.street, isNull);
      expect(recipient.phone, isNull);
      expect(recipient.mail, 'mail@ammer.group');
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

    test('a token transfer URI without a recipient has no address', () {
      for (final uri in [
        'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer'
            '?uint256=1246858',
        'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer'
            '?address=&uint256=1246858',
      ]) {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          {'blockchain': 'Ethereum', 'uri': uri},
          apiUrl: _decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: _callbackUrl,
          quoteExpiration: DateTime.parse(_quoteExpiration),
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
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
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
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
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
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
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
          apiUrl: _decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: _callbackUrl,
          quoteExpiration: DateTime.parse(_quoteExpiration),
        );
        expect(details.amount, amount, reason: uri);
        expect(details.isRawAmount, isRaw, reason: uri);
      }
    });
  });

  group('Proof type detection from hint', () {
    test('HEX hint -> signedTransactionHex, isBroadcastRequired false', () {
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
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
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
      expect(details.isBroadcastRequired, isFalse);
    });

    // Hints returned by the DFX demo payment link for each method, with the
    // proof type the library must detect. Lightning returns no hint and
    // BinancePay returned an error.
    const hex = OpenCryptoPayProofType.signedTransactionHex;
    const hash = OpenCryptoPayProofType.transactionHash;
    const dfxHints = {
      'Ethereum': (_dfxHexHint, hex),
      'Polygon': (_dfxHexHint, hex),
      'Arbitrum': (_dfxHexHint, hex),
      'Optimism': (_dfxHexHint, hex),
      'Base': (_dfxHexHint, hex),
      'BinanceSmartChain': (_dfxHexHint, hex),
      'Bitcoin': (_dfxHexHint, hex),
      'Firo': (_dfxFiroHint, hex),
      'Monero': (_dfxHashHint, hash),
      'Solana': (_dfxHashHint, hash),
      'Tron': (_dfxHashHint, hash),
      'Cardano': (_dfxHashHint, hash),
      'Spark': (_dfxSparkHint, hash),
      'InternetComputer': (_dfxInternetComputerHint, null),
    };
    for (final MapEntry(key: method, value: (hint, proofType))
        in dfxHints.entries) {
      test('DFX $method hint -> ${proofType?.name ?? 'no proof type'}', () {
        final details = OpenCryptoPayTransactionDetails.fromJson(
          {'blockchain': method, 'hint': hint},
          apiUrl: _decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: _callbackUrl,
          quoteExpiration: DateTime.parse(_quoteExpiration),
        );
        expect(details.proofType, proofType);
      });
    }
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
      Map<String, dynamic> paymentInfoJson = paymentDetailsJson,
    }) {
      return _mockHttpWithHandler((url) {
        final hasMethod = url.queryParameters.containsKey('method');
        if (!hasMethod) {
          return _res(jsonEncode(paymentInfoJson), 200);
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
      expect(detailsUrl.host, Uri.parse(_callbackUrl).host);
      expect(detailsUrl.path, Uri.parse(_callbackUrl).path);
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
      expect(success.isBroadcastRequired, isTrue);
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

    test('missing address maps to an invalid address result', () async {
      final controller = _controller(_mockTwoRequestFlow(
        txDetailsJson: {'blockchain': 'Bitcoin', 'hint': _dfxHexHint},
      ));

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
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
        final controller = _controller(_mockTwoRequestFlow(
          txDetailsJson: {
            'blockchain': 'Bitcoin',
            'uri': uri,
            'hint': _dfxHexHint,
          },
        ));

        final result = await controller.run(
          qrData: _qrLink,
          coin: _btc,
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
          _btc,
          'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.00001947',
          8,
          BigInt.from(1947),
        ),
        (
          _btc,
          'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.123456789',
          8,
          BigInt.from(12345679),
        ),
        (
          _btc,
          'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.000000004',
          8,
          BigInt.one,
        ),
        (
          _eth,
          'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1'
              '?value=2.014e18',
          18,
          BigInt.parse('2014000000000000000'),
        ),
      ]) {
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: {..._btcDetails, 'uri': uri},
        )).run(qrData: _qrLink, coin: coin, ownedCoins: owned);

        expect(
          (success as OpenCryptoPaySuccess)
              .amountInSmallestUnit(fractionDigits),
          smallest,
          reason: uri,
        );
      }
    });

    test('an undecodable payment URI query maps to an error', () async {
      final result = await _controller(_mockTwoRequestFlow(
        txDetailsJson: {
          ..._btcDetails,
          'uri': 'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6'
              '?amount=0.5&label=Caf%E9',
        },
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayError>());
    });

    test('a hint naming no proof type maps to an unknown proof type', () async {
      final result = await _controller(_mockTwoRequestFlow(
        txDetailsJson: {..._btcDetails, 'hint': 'Pay this request.'},
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned);

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
      final result = await _controller(_mockTwoRequestFlow(
        txDetailsJson: {
          'expiryDate': '2025-05-01T14:34:40.881Z',
          'uri': link,
          'hint': 'Pay in the Binance app by following the deep link $link.',
        },
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayUnknownProofType>());
    });

    test('a callback the proof URL cannot be built from maps to an error',
        () async {
      final result = await _controller(_mockTwoRequestFlow(
        paymentInfoJson: {...paymentDetailsJson, 'callback': _decodedApiUrl},
        txDetailsJson: _btcDetails,
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayError>());
    });

    test('a 400 for a listed asset maps to an error', () async {
      final result = await _controller(_mockTwoRequestFlow(
        txDetailsJson: {'message': 'Failed to create order'},
        txDetailsStatus: 400,
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayError>());
    });

    test('a 400 for a method without an asset list maps to unsupported',
        () async {
      final result = await _controller(_mockTwoRequestFlow(
        paymentInfoJson: {
          ...paymentDetailsJson,
          'transferAmounts': [
            {'method': 'Bitcoin', 'minFee': 0, 'available': true},
          ],
        },
        txDetailsJson: {'message': 'unsupported'},
        txDetailsStatus: 400,
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned);

      expect(result, isA<OpenCryptoPayUnsupported>());
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

    test('an unlisted token asset still suggests other assets on the same method',
        () async {
      final paymentInfo =
          jsonDecode(jsonEncode(paymentDetailsJson)) as Map<String, dynamic>;
      final ethereum = (paymentInfo['transferAmounts'] as List)
          .firstWhere((entry) => entry['method'] == 'Ethereum') as Map;
      (ethereum['assets'] as List).removeWhere((a) => a['asset'] == 'USDT');
      final controller = _controller(_mockTwoRequestFlow(
        paymentInfoJson: paymentInfo,
        txDetailsJson: {'message': 'unsupported'},
        txDetailsStatus: 400,
      ));

      // User owns ETH (native) and USDT (token) on Ethereum, plus BTC.
      // USDT is not listed, but ETH on the same method should still be offered.
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
    });

    test('network failure maps to a non-decode error', () async {
      final controller = _controller(
        MockClient((_) async => throw Exception('socket closed')),
      );

      final result = await controller.run(
        qrData: _qrLink,
        coin: _btc,
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
        Bech32Encoder.encode('lnbc', utf8.encode(_decodedApiUrl)),
        Bech32Encoder.encode('lnurl', utf8.encode('api.dfx.swiss/pl_x')),
        Bech32Encoder.encode('lnurl', utf8.encode('https:///pl_x')),
      ]) {
        final result = await _controller(
          _mockHttpReturning(_res(jsonEncode(paymentDetailsJson), 200)),
        ).run(
          qrData: 'https://app.dfx.swiss/pl/?lightning=$lnurl',
          coin: _btc,
          ownedCoins: owned,
        );

        expect(result, isA<OpenCryptoPayError>(), reason: lnurl);
        expect((result as OpenCryptoPayError).isDecodeError, isTrue);
      }
    });

    test('the session carries the matched method minFee and its unit',
        () async {
      final success = await _controller(_mockTwoRequestFlow(
        txDetailsJson: _btcDetails,
      )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
          as OpenCryptoPaySuccess;

      expect(success.session.minFee, 2.146);
      expect(success.minFeeUnit, OpenCryptoPayFeeUnit.satsPerVByte);

      // The unit follows the chain type of the coin.
      OpenCryptoPayFeeUnit unitFor(CryptoCoin coin) => OpenCryptoPaySession(
            details: success.details,
            coin: coin,
            service: OpenCryptoPayService(
              client: _mockHttpReturning(_res('{}', 200)),
            ),
          ).minFeeUnit;
      expect(unitFor(_eth), OpenCryptoPayFeeUnit.weiPerGas);
      expect(unitFor(_xmr), OpenCryptoPayFeeUnit.unknown);
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

        var requests = 0;
        final ok = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpWithHandler((_) {
              requests++;
              return _res('ok', 200);
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
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: _btcDetails,
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;

        var requests = 0;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpWithHandler((_) {
              requests++;
              return _res('ok', 200);
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
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_62b1865ed28358be',
        callback: _callbackUrl,
        quoteExpiration: DateTime.parse(_quoteExpiration),
      );
      final session = OpenCryptoPaySession(
        details: details,
        coin: _xmr,
        service: OpenCryptoPayService(
          client: _mockHttpReturning(_res('down', 503)),
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

    test('submitProof sends an EVM hex with one 0x prefix', () async {
      for (final hex in ['f86c', '0xf86c']) {
        Uri? proofUrl;
        final session = OpenCryptoPaySession(
          details: OpenCryptoPayTransactionDetails.fromJson(
            {'hint': _dfxHexHint},
            apiUrl: _decodedApiUrl,
            displayName: 'Test Shop',
            quoteId: 'plq_62b1865ed28358be',
            callback: _callbackUrl,
            quoteExpiration: DateTime.parse(_quoteExpiration),
          ),
          coin: _eth,
          service: OpenCryptoPayService(
            client: _mockHttpWithHandler((url) {
              proofUrl = url;
              return _res('', 200);
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
        OpenCryptoPaySession sessionWith(Client client) => OpenCryptoPaySession(
              details: success.details,
              coin: success.coin,
              service: OpenCryptoPayService(client: client),
            );
        Future<OpenCryptoPayProofFailed> fail(
                OpenCryptoPaySession session) async =>
            await session.submitProof('signedHexDummy')
                as OpenCryptoPayProofFailed;

        final refusing = sessionWith(_mockHttpReturning(_res('bad', 400)));
        final refused = await fail(refusing);
        expect(refused.error, isA<OpenCryptoPayApiException>());
        expect(refused.isRejectedByProvider, isTrue);
        expect(refusing.mayHoldPayment, isFalse);
        expect(OpenCryptoPayStrings.proofFailure(refusing).title,
            OpenCryptoPayStrings.deliveryFailedTitle);

        // A server error may come after the provider broadcast.
        final failing = sessionWith(_mockHttpReturning(_res('bad', 503)));
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
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: _btcDetails,
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;
        var attempts = 0;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: MockClient((_) async {
              if (attempts++ == 0) throw Exception('socket closed');
              return _res('bad', 400);
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
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: _btcDetails,
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
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
        final success = await _controller(_mockTwoRequestFlow(
          txDetailsJson: {
            ..._btcDetails,
            'hint': 'Broadcast the signed transaction to the blockchain and '
                'send the transaction hash back.',
          },
        )).run(qrData: _qrLink, coin: _btc, ownedCoins: owned)
            as OpenCryptoPaySuccess;
        final session = OpenCryptoPaySession(
          details: success.details,
          coin: success.coin,
          service: OpenCryptoPayService(
            client: _mockHttpReturning(_res('ok', 200)),
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

  // One test per statement of the OpenCryptoPay README, checking that the user
  // neither pays twice nor pays for nothing. Where DFX production answers
  // differently, the test follows production.
  group('README', () {
    final beforeQuoteExpiry = Clock.fixed(DateTime.utc(2025, 7, 16, 1));

    group('1. QR code decoding', () {
      test('the lightning parameter of the QR link holds the LNURL', () {
        expect(OpenCryptoPayService.isOpenCryptoPayUri(_qrLink), isTrue);
        expect(OpenCryptoPayService.extractLnurl(_qrLink), _lnurl);
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
          _eth,
          qrData: 'https://pay.example.com/pl/?lightning=$lnurl',
        ) as OpenCryptoPaySuccess;
        await withClock(
            beforeQuoteExpiry, () => success.session.submitProof('0xsigned'));

        // The proof reaches the provider that priced the payment.
        expect(provider.requests.map((url) => url.host),
            everyElement('api.example.com'));
        expect(provider.requests.where(_isProof), hasLength(1));
      });
    });

    group('2. Payment details', () {
      test('the LNURL decodes to the API URL', () {
        expect(OpenCryptoPayService.decodeLnurl(_lnurl), _decodedApiUrl);
      });

      test(
          'the payment details carry the recipient, quote, methods and callback',
          () {
        final info = OpenCryptoPayPaymentInfo.fromJson(
          _readmeInfo,
          apiUrl: _decodedApiUrl,
        );

        expect(info.recipient?.name, 'My Company');
        expect(info.quoteId, 'plq_d170b11b44340eb1');
        expect(info.quoteExpiration, DateTime.utc(2025, 7, 16, 1, 20, 6, 476));
        expect(info.supportedMethods.map((method) => method.method),
            contains('Ethereum'));
        expect(info.callback, _callbackUrl);
      });

      test('an unavailable method is not offered', () async {
        final provider = _Provider();

        expect(await provider.run(const _Coin('BTC', 'Taproot Asset')),
            isA<OpenCryptoPayUnsupported>());
        expect(provider.requests, hasLength(1));
      });

      test('the recipient carries its registration number', () {
        final info = OpenCryptoPayPaymentInfo.fromJson(
          _readmeInfo,
          apiUrl: _decodedApiUrl,
        );

        expect(info.recipient?.registrationNumber, 'CHE-123.456.789');
      });

      test('an expired quote is not used, and the user scans again', () async {
        final provider = _Provider(details: _readmeEthereum);
        final hex = await provider.run(_eth) as OpenCryptoPaySuccess;
        final hash = await _Provider(details: _readmeCardano).run(_ada)
            as OpenCryptoPaySuccess;

        await withClock(Clock.fixed(DateTime.utc(2025, 7, 17)), () async {
          // The wallet checks the quote before it pays.
          expect(hex.session.isQuoteExpired, isTrue);
          expect(hash.session.isQuoteExpired, isTrue);
          expect(await hex.session.submitProof('0xsigned'),
              isA<OpenCryptoPayProofQuoteExpired>());
        });
        expect(provider.requests.where(_isProof), isEmpty);
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
        await provider.run(_eth);

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

        expect(await provider.run(_eth), isA<OpenCryptoPayNoPending>());
      });
    });

    group('3. Transaction details', () {
      test('the details URL is the callback with the quote, method and asset',
          () {
        final url = OpenCryptoPayService.buildTransactionDetailsUrl(
          callback: _callbackUrl,
          coin: _eth,
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
            _eth,
            _readmeEthereum,
            '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
            null,
            18,
            '660720000000000',
          ),
          // DFX production
          (
            _btc,
            _btcDetails,
            'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
            null,
            8,
            '1947',
          ),
          (
            _zchf,
            {
              'blockchain': 'Polygon',
              'uri': 'ethereum:0x02567e4b14b25549331fcee2b56c647a8bab16fd@137'
                  '/transfer?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC'
                  '&uint256=1000000000000000000',
              'hint': _dfxHexHint,
            },
            '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC',
            '0x02567e4b14b25549331fcee2b56c647a8bab16fd',
            18,
            '1000000000000000000',
          ),
          // Production Firo also takes the transaction hash.
          (
            _firo,
            {
              'blockchain': 'Firo',
              'uri':
                  'firo:aCPrA7sqb3QN2EH8q6XUVqE9kEGJsqq5wn?amount=1.14487149',
              'hint': _dfxFiroHint,
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
            _ada,
            _readmeCardano,
            'addr1qyqjzchnayplhgueg33gukpp2max9gkge4gh6jly93a0dzcm67tl9f0pkykty8my4j4hg8e9suj8nzdrjygmfy6c8d0skmaq5q',
            6,
            '4883112',
          ),
          // DFX production
          (
            _xmr,
            {
              'blockchain': 'Monero',
              'uri':
                  'monero:88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4zn'
                      'Q2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u'
                      '?tx_amount=0.00215578',
              'hint': _dfxHashHint,
            },
            '88fWDB31A4s5bV46r7zxKnVqmrh3T1Lk1EF3A9KzEEaFfHF1n4znQ2U9qK5PJxR2RSSQshkxLZVnSdZe2ZwLSPVqGxxnq9u',
            12,
            '2155780000',
          ),
          (
            _sol,
            {
              'blockchain': 'Solana',
              'uri': 'solana:2eQ2Somiat63oqSPwzQLrrNiceC8F6TH85dt2qDe3z36'
                  '?amount=0.01009715',
              'hint': _dfxHashHint,
            },
            '2eQ2Somiat63oqSPwzQLrrNiceC8F6TH85dt2qDe3z36',
            9,
            '10097150',
          ),
          (
            _trx,
            {
              'blockchain': 'Tron',
              'uri': 'tron:TMBbmTrNYj16HjKzN1tsm2EaT7mzuTvSAL?amount=3.61011',
              'hint': _dfxHashHint,
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
        final success = await _Provider(details: _productionSpark).run(_spark)
            as OpenCryptoPaySuccess;

        expect(success.address,
            'spark1pgss9cx833p3ls8s4536eav8vh0q6c8ctjd7a75666r2jmvrj4rgpuqe0xfm9r');
        expect(success.proofType, OpenCryptoPayProofType.transactionHash);
      });

      test('Internet Computer is reported as unsupported', () async {
        for (final uri in [
          'icp:6bf47-...-cai?amount=0.08415',
          // DFX production
          'icp:ryjl3-tyaaa-aaaaa-aaaba-cai/transfer'
              '?to=ygf2v-iniac-cojwe-damoz-s4act-k4xft-xgpjy-776wl-wr754-qxkgo-4ae'
              '&amount=0.34772601',
        ]) {
          final result = await _Provider(details: {
            'blockchain': 'InternetComputer',
            'uri': uri,
            'hint': _dfxInternetComputerHint,
          }).run(_icp);

          expect(result, isA<OpenCryptoPayUnknownProofType>(), reason: uri);
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

        expect(await provider.run(_lightning), isA<OpenCryptoPayLightning>());
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

        expect(await readme.run(_binancePay),
            isA<OpenCryptoPayUnknownProofType>());
        expect(await production.run(_binancePay), isA<OpenCryptoPayError>());
      });

      test('the transaction details share the quote and its expiration',
          () async {
        final success = await _Provider(details: _readmeEthereum).run(_eth)
            as OpenCryptoPaySuccess;

        expect(success.details.quoteId, 'plq_d170b11b44340eb1');
        expect(success.details.quoteExpiration,
            DateTime.utc(2025, 7, 16, 1, 20, 6, 476));
      });
    });

    group('4. Crypto transaction', () {
      test('the minimum fee is in wei for EVM chains and sat/vB for Bitcoin',
          () async {
        final eth = await _Provider(details: _readmeEthereum).run(_eth)
            as OpenCryptoPaySuccess;
        final btc = await _Provider(details: _btcDetails).run(_btc)
            as OpenCryptoPaySuccess;

        expect((eth.minFee, eth.minFeeUnit),
            (1682009661, OpenCryptoPayFeeUnit.weiPerGas));
        expect((btc.minFee, btc.minFeeUnit),
            (4.5, OpenCryptoPayFeeUnit.satsPerVByte));
      });

      // DFX wallets build the proof URL this way. The README examples and the
      // DFX hints show the payment ID.
      test('the proof URL is the callback with /cb replaced by /tx', () async {
        expect(
          OpenCryptoPayService.buildTransactionProofUrl(_callbackUrl)
              .toString(),
          'https://api.dfx.swiss/v1/lnurlp/tx/pl_beeddb41cd4b6d9e',
        );

        // The wallet pays only when it can send the proof.
        final provider = _Provider(
          info: {..._readmeInfo, 'callback': _decodedApiUrl},
          details: _readmeCardano,
        );
        expect(await provider.run(_ada), isA<OpenCryptoPayError>());
      });

      test('a URI without a recipient or a positive amount is not paid',
          () async {
        for (final (coin, uri, failure) in [
          (
            _btc,
            'bitcoin:?amount=0.00001947',
            isA<OpenCryptoPayInvalidAddress>(),
          ),
          (
            _btc,
            'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
            isA<OpenCryptoPayInvalidAmount>(),
          ),
          (
            _btc,
            'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6?amount=0',
            isA<OpenCryptoPayInvalidAmount>(),
          ),
          // The value of an ERC-20 transfer is the ether sent with the call.
          (
            _zchf,
            'ethereum:0x02567e4b14b25549331fcee2b56c647a8bab16fd@137/transfer'
                '?address=0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC'
                '&value=1000000000000000000',
            isA<OpenCryptoPayInvalidAmount>(),
          ),
        ]) {
          final result = await _Provider(details: {
            'uri': uri,
            'hint': _dfxHexHint,
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
              _bnb,
              _productionBsc,
              {'method': 'BinanceSmartChain', 'asset': 'BNB', 'hex': '0xproof'},
            ),
            (
              _ada,
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
          final success = await _Provider(details: _readmeEthereum).run(_eth)
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
        final success = await provider.run(_bnb) as OpenCryptoPaySuccess;

        expect(success.details.chainId, 56);
        expect(success.address, '0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC');
        expect(success.amountInSmallestUnit(18), BigInt.from(1553320000000000));
        // Only a coin on chain 56 pays it.
        expect(await provider.run(_eth), isA<OpenCryptoPayWrongChain>());
        expect(
          await provider.run(
              const _Coin('BNB', 'Binance Smart Chain', CryptoChainType.evm)),
          isA<OpenCryptoPayWrongChain>(),
        );
      });

      test(
          'Monero, Zano, Solana, Tron and Cardano: the wallet broadcasts, and '
          'a success code completes the payment', () async {
        final success = await _Provider(details: _readmeCardano).run(_ada)
            as OpenCryptoPaySuccess;

        expect(success.isBroadcastRequired, isTrue);
        expect(await success.session.submitProof('txHash'),
            isA<OpenCryptoPayProofAccepted>());
        expect(success.session.isCompleted, isTrue);
      });

      test('Spark: the transfer pays exactly the URI amount', () async {
        final success = await _Provider(details: _productionSpark).run(_spark)
            as OpenCryptoPaySuccess;

        expect(success.amountInSmallestUnit(8), BigInt.from(1418));
      });

      test(
          'Spark: the transfer ID goes in the tx parameter, and a success code '
          'accepts it', () async {
        const transferId = '0198c2f4-7a1b-7c3d-9e2f-5a6b7c8d9e0f';
        final provider = _Provider(details: _productionSpark);
        final success = await provider.run(_spark) as OpenCryptoPaySuccess;

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
          apiUrl: _decodedApiUrl,
          displayName: 'Test Shop',
          quoteId: 'plq_62b1865ed28358be',
          callback: _callbackUrl,
          quoteExpiration: DateTime.parse(_quoteExpiration),
        );
        final requests = <Uri>[];
        final session = OpenCryptoPaySession(
          details: details,
          coin: _spark,
          service: OpenCryptoPayService(
            client: _mockHttpWithHandler((url) {
              requests.add(url);
              if (url.toString() == _decodedApiUrl) {
                return _res(
                  jsonEncode({
                    ...paymentDetailsJson,
                    'quote': {'id': 'plq_new', 'expiration': _quoteExpiration},
                  }),
                  200,
                );
              }
              // The first quote rejected the transfer.
              final isNewQuote = url.queryParameters['quote'] == 'plq_new';
              return _res('{}', isNewQuote ? 200 : 400);
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

  group('Properties', () {
    for (final flow in _Flow.values) {
      property('a ${flow.name} session stays safe under any provider answers',
          () {
        runBehavior(_SessionBehavior(flow));
      });
    }

    property('run returns a result for any provider answer', () {
      forAll(
        combine3(
          constantFrom<CryptoCoin>([_btc, _eth, _xmr, _usdt, _doge]),
          combine2(_status, _paymentInfoBody),
          combine2(_status, _detailsBody),
        ),
        (args) async {
          final (coin, (infoStatus, info), (detailsStatus, details)) = args;
          final result = await _controller(_mockHttpWithHandler((url) =>
              url.queryParameters.containsKey('method')
                  ? _res(details, detailsStatus)
                  : _res(info, infoStatus))).run(
            qrData: _qrLink,
            coin: coin,
            ownedCoins: [_btc, _eth],
          );

          if (result is OpenCryptoPaySuccess) {
            expect(result.address, isNotEmpty);
            expect(result.proofType, isNotNull);
            expect(result.amountInSmallestUnit(8), greaterThan(BigInt.zero));
            expect(result.details.chainId, anyOf(isNull, coin.chainId));
          }
        },
        // kiri_check does not await an async block while shrinking.
        shrinkingPolicy: ShrinkingPolicy.off,
      );
    });

    property('the smallest unit amount rounds up by less than one unit', () {
      forAll(
        combine3(
          integer(min: 0),
          integer(min: 0, max: 30),
          integer(min: 0, max: 30),
        ),
        (args) {
          final (unscaled, scale, fractionDigits) = args;
          final amount = Decimal.fromInt(unscaled).shift(-scale);
          final success = OpenCryptoPaySuccess(
            session: _Payment(_Flow.hex).session,
            address: 'bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
            recipientLabel: 'Test Shop',
            amount: amount,
          );

          final exact = amount.shift(fractionDigits);
          final smallest = Decimal.fromBigInt(
            success.amountInSmallestUnit(fractionDigits),
          );
          expect(smallest, greaterThanOrEqualTo(exact));
          expect(smallest - exact, lessThan(Decimal.one));
        },
      );
    });
  });
}

/// The README payment details, cut to the fields these tests read. DFX
/// production fills the asset lists the README leaves out.
final _readmeInfo = {
  'callback': _callbackUrl,
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
  'hint': _dfxHexHint,
};

const _readmeCardano = {
  'expiryDate': '2025-05-01T14:34:40.881Z',
  'blockchain': 'Cardano',
  'uri': 'cardano:addr1qyqjzchnayplhgueg33gukpp2max9gkge4gh6jly93a0dzcm67tl9f'
      '0pkykty8my4j4hg8e9suj8nzdrjygmfy6c8d0skmaq5q?amount=4.883112',
  'hint': _dfxHashHint,
};

const _productionBsc = {
  'expiryDate': '2026-10-06T08:50:24.520Z',
  'blockchain': 'BinanceSmartChain',
  'uri': 'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@56'
      '?value=1553320000000000',
  'hint': _dfxHexHint,
};

const _productionSpark = {
  'expiryDate': '2026-10-06T08:50:24.520Z',
  'blockchain': 'Spark',
  'uri': 'spark:spark1pgss9cx833p3ls8s4536eav8vh0q6c8ctjd7a75666r2jmvrj4rgpuqe'
      '0xfm9r?amount=0.00001418',
  'hint': _dfxSparkHint,
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
    String qrData = _qrLink,
  }) {
    final client = MockClient((request) async {
      requests.add(request.url);
      if (_isProof(request.url)) return _res('', 200);
      return request.url.queryParameters.containsKey('method')
          ? _res(jsonEncode(details), detailsStatus)
          : _res(jsonEncode(info), infoStatus);
    });
    return _controller(client).run(qrData: qrData, coin: coin);
  }
}

final _status = constantFrom([200, 400, 404, 500]);

/// The sample payment info with up to three fields set to a malformed value,
/// or any body.
final _paymentInfoBody = oneOf([
  combine2(
    list(
      constantFrom(
          ['quote', 'callback', 'displayName', 'recipient', 'transferAmounts']),
      maxLength: 3,
    ),
    constantFrom<Object?>([null, 7, 'x', [], {}]),
  ).map((args) => jsonEncode({
        ...paymentDetailsJson,
        for (final key in args.$1) key: args.$2,
      })),
  string(maxLength: 20),
]).cast<String>();

/// Transaction details whose payment URI carries arbitrary amount-like
/// parameters.
final _detailsBody = combine4(
  constantFrom([
    'bitcoin:bc1qzx3ug7j0e64207fe2m424hvxmvd496q8gdytt6',
    'ethereum:0x9C2242a0B71FD84661Fd4bC56b75c90Fac6d10FC@1',
    'ethereum:0xdac17f958d2ee523a2206206994597c13d831ec7@1/transfer',
    'x',
    '',
  ]),
  list(
    combine2(
      constantFrom(
          ['amount', 'tx_amount', 'value', 'uint256', 'address', 'label']),
      list(constantFrom('0123456789.eE-+%x '.split('')), maxLength: 8)
          .map((chars) => chars.join()),
    ),
    maxLength: 3,
  ),
  constantFrom<Object?>([
    'Send the signed transaction back as HEX.',
    'Send the transaction hash back.',
    'Pay this request.',
    null,
    7,
  ]),
  boolean(),
).map((args) {
  final (uri, params, hint, isLightning) = args;
  final query = params.map((param) => '${param.$1}=${param.$2}').join('&');
  return jsonEncode({
    'uri': query.isEmpty ? uri : '$uri?$query',
    'hint': hint,
    if (isLightning) 'pr': 'lnbc1',
  });
});

/// How the provider answers a request.
enum _Answer { ok, refused, serverError, lost }

/// A proof of payment flow, selected by the hint.
enum _Flow {
  hex(_btc, 'Send the signed transaction back as HEX.'),
  hash(_xmr, 'Broadcast it and send the transaction hash back.'),
  spark(_spark, 'Send the transfer ID as the tx parameter.');

  const _Flow(this.coin, this.hint);

  final CryptoCoin coin;
  final String hint;
}

final _quoteExpires = DateTime.parse(_quoteExpiration);

bool _isProof(Uri url) => url.pathSegments.contains('tx');

final class _SessionBehavior extends Behavior<_Flow, _Payment> {
  _SessionBehavior(this.flow);

  final _Flow flow;

  @override
  _Flow initialState() => flow;

  @override
  _Payment createSystem(_Flow flow) => _Payment(flow);

  @override
  List<Command<_Flow, _Payment>> generateCommands(_Flow flow) {
    // A submission sends two requests at most.
    final answers = list(
      constantFrom(_Answer.values),
      minLength: 2,
      maxLength: 2,
    );
    return [
      for (final isOverlapping in [false, true])
        Action(
          isOverlapping ? 'submit twice at once' : 'submit',
          answers,
          nextState: (_, __) {},
          run: (payment, answers) =>
              payment.submit(answers, isOverlapping: isOverlapping),
          postcondition: (_, __, payment) => payment.isSafe(),
        ),
      Action0(
        'quote expires',
        nextState: (_) {},
        run: (payment) => payment.expireQuote(),
        postcondition: (_, payment) => payment.isSafe(),
      ),
      if (flow != _Flow.hex)
        Action0(
          'broadcast fails',
          nextState: (_) {},
          run: (payment) => payment.failBroadcast(),
          postcondition: (_, payment) => payment.isSafe(),
        ),
    ];
  }

  @override
  void destroySystem(_Payment payment) {}
}

/// A session whose provider answers each request as told.
final class _Payment {
  _Payment(this.flow) {
    session = OpenCryptoPaySession(
      details: OpenCryptoPayTransactionDetails.fromJson(
        {'hint': flow.hint},
        apiUrl: _decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_0',
        callback: _callbackUrl,
        quoteExpiration: _quoteExpires,
      ),
      coin: flow.coin,
      service: OpenCryptoPayService(client: MockClient(_answer)),
    );
  }

  final _Flow flow;
  late final OpenCryptoPaySession session;
  final requests = <({Uri url, _Answer answer, DateTime at})>[];
  var now = DateTime.utc(2026, 6, 24, 8);
  var hasSubmitted = false;
  var hasFailedBroadcast = false;
  OpenCryptoPayProofResult? lastResult;
  var _answers = <_Answer>[];
  var _submissionStart = 0;

  Future<Response> _answer(Request request) async {
    final answer = _answers.isEmpty ? _Answer.ok : _answers.removeAt(0);
    requests.add((url: request.url, answer: answer, at: now));
    return switch (answer) {
      _Answer.ok when _isProof(request.url) => _res('', 200),
      _Answer.ok => _res(
          jsonEncode({
            ...paymentDetailsJson,
            'quote': {
              'id': 'plq_${requests.length}',
              'expiration': _quoteExpiration,
            },
          }),
          200,
        ),
      _Answer.refused => _res('', 400),
      _Answer.serverError => _res('', 503),
      _Answer.lost => throw ClientException('Connection closed'),
    };
  }

  Future<_Payment> submit(
    List<_Answer> answers, {
    required bool isOverlapping,
  }) async {
    _answers = [...answers];
    _submissionStart = requests.length;
    hasSubmitted = true;
    final results = await withClock(
      Clock(() => now),
      () => Future.wait([
        session.submitProof('proof'),
        if (isOverlapping) session.submitProof('proof'),
      ]),
    );
    lastResult = results.first;
    return this;
  }

  _Payment expireQuote() {
    now = _quoteExpires.add(const Duration(minutes: 1));
    return this;
  }

  _Payment failBroadcast() {
    hasFailedBroadcast = true;
    session.recordFailedBroadcast();
    return this;
  }

  /// Checks the requests sent so far and what the session tells the user.
  bool isSafe() {
    final proofs = requests.where((request) => _isProof(request.url));
    final accepted = proofs.where((proof) => proof.answer == _Answer.ok);
    expect(session.isCompleted, accepted.isNotEmpty,
        reason: 'completed once a proof is accepted');
    expect(lastResult is OpenCryptoPayProofAccepted, session.isCompleted,
        reason: 'accepted once completed');
    expect(
      requests.skip(_submissionStart).where((r) => _isProof(r.url)),
      hasLength(lessThanOrEqualTo(1)),
      reason: 'one proof per submission',
    );
    if (accepted.isNotEmpty) {
      expect(requests.last, accepted.first,
          reason: 'no request after the accepted proof');
    }

    final failedQuotes = <String>{};
    for (final proof in proofs) {
      final quote = proof.url.queryParameters['quote']!;
      if (flow == _Flow.spark) {
        expect(failedQuotes, isNot(contains(quote)),
            reason: 'no Spark report under a quote that failed one');
        if (proof.answer != _Answer.ok) failedQuotes.add(quote);
      } else {
        expect(quote, 'plq_0', reason: 'one quote outside Spark');
      }
      if (flow == _Flow.hex) {
        expect(proof.at.isAfter(_quoteExpires), isFalse,
            reason: 'no signed transaction after the quote expired');
      }
    }

    if (session.isCompleted) return true;
    // The wallet sends a hash or Spark payment before its proof.
    final maySent = hasFailedBroadcast ||
        (flow == _Flow.hex
            ? proofs.any((proof) => proof.answer != _Answer.refused)
            : hasSubmitted);
    expect(
      OpenCryptoPayStrings.quoteExpiredAtSend(session).message,
      maySent ? isNot(contains('NOT sent')) : contains('NOT sent'),
      reason: 'expired quote message',
    );
    if (lastResult is OpenCryptoPayProofFailed) {
      final message = OpenCryptoPayStrings.proofFailure(session).message;
      if (flow != _Flow.hex) {
        expect(message, contains('do not pay again'),
            reason: 'proof failure message');
      } else {
        expect(
          message,
          maySent
              ? isNot(contains('Nothing was sent'))
              : contains('Nothing was sent'),
          reason: 'proof failure message',
        );
      }
    }
    return true;
  }
}
