import 'package:clock/clock.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'sample_data/open_crypto_pay_payment_details_json.dart';

void main() {
  group('Parsing payment info correctly', () {
    test('parses payment info with display name, quote id and methods', () {
      withClock(fixedClock, () {
      final info = OpenCryptoPayPaymentInfo.fromJson(
        paymentDetailsJson,
        apiUrl: decodedApiUrl,
      );

      expect(info.displayName, 'Test Shop');
      expect(info.quoteId, 'plq_62b1865ed28358be');
      expect(info.callback, callbackUrl);
      expect(info.supportedMethods, isNotEmpty);
      expect(info.quoteExpiration, DateTime.parse(quoteExpiration));

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
        apiUrl: decodedApiUrl,
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
        apiUrl: decodedApiUrl,
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
            apiUrl: decodedApiUrl,
            displayName: 'Test Shop',
            quoteId: 'plq',
            callback: callbackUrl,
            quoteExpiration: DateTime.parse(quoteExpiration),
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
        apiUrl: decodedApiUrl,
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
        apiUrl: decodedApiUrl,
      );

      expect(info.displayName, isEmpty);
      final recipient = info.recipient!;
      expect(recipient.name, isNull);
      expect(recipient.street, isNull);
      expect(recipient.phone, isNull);
      expect(recipient.mail, 'mail@ammer.group');
    });
  });
}
