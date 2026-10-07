import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'sample_data/open_crypto_pay_payment_details_json.dart';

void main() {
  group('OpenCryptoPay method mapping', () {
    test('derives method (pretty name) and asset (ticker) from a coin', () {
      final btcMethod = openCryptoPayMethodFor(btc);
      expect(btcMethod.method, 'Bitcoin');
      expect(btcMethod.asset, 'BTC');

      final ethMethod = openCryptoPayMethodFor(eth);
      expect(ethMethod.method, 'Ethereum');
      expect(ethMethod.asset, 'ETH');

      final xmrMethod = openCryptoPayMethodFor(xmr);
      expect(xmrMethod.method, 'Monero');
      expect(xmrMethod.asset, 'XMR');
    });

    test('suggests owned wallets whose coin the provider supports', () {
      final owned = <CryptoCoin>[ltc, btc];
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
        btc, // supported
        eth, // supported
        xmr, // supported
        firo, // supported
        ada, // supported
        sol, // supported
        doge, // NOT in provider list
        ltc, // NOT in provider list
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
        eth, // ETH asset on Ethereum method — supported
        usdt, // USDT asset on Ethereum method — supported
        doge, // not supported
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
}
