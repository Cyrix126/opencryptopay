/// OpenCryptoPay payment-flow support for crypto wallets.
///
/// Provider agnostic Dart implementation of the
/// [OpenCryptoPay](https://github.com/openCryptoPay/landingPage) payment flow for crypto wallets.
///
/// Wallets integrate by:
/// 1. Describing their coin with a [CryptoCoin].
/// 2. Building an [OpenCryptoPayService] with a `package:http` [Client]
///    (optionally configured for Tor / SOCKS routing), and driving the flow
///    via [OpenCryptoPayController].
/// 3. On [OpenCryptoPaySuccess], paying [OpenCryptoPaySuccess.address] and
///    submitting the proof through [OpenCryptoPaySuccess.session]; on an
///    [OpenCryptoPayFailure], displaying its `title`/`message`.
///
/// See the `test/` directory for a complete usage example.
library;

export 'src/coin.dart';
export 'src/exceptions.dart';
export 'src/method_map.dart';
export 'src/payment_details.dart';
export 'src/result.dart';
export 'src/service.dart';
export 'src/session.dart';
export 'src/controller.dart';
export 'src/strings.dart';
