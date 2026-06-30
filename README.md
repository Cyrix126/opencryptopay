Provider agnostic Dart implementation of the [OpenCryptoPay](https://github.com/openCryptoPay/landingPage) payment flow for crypto wallets.

## Features

- [x] Decode scanned OpenCryptoPay QR links
- [x] Fetch pending payment details for a given coin
- [x] Fetch coins supported from provider
- [x] Submit proof of payment
- [x] Let wallet plug their own HTTP client (`package:http` `Client`) and coin type

## Install

```yaml
dependencies:
  opencryptopay: ^0.1.0
```

## Usage

```dart
import 'package:http/http.dart';
import 'package:opencryptopay/opencryptopay.dart';

// 1. Implement CryptoCoin for your wallet's coin type.
class MyCoin implements CryptoCoin {
  const MyCoin(this.ticker, this.prettyName);
  @override final String ticker;
  @override final String prettyName;
}

// 2. Provide a package:http Client.
//    Configure Tor / SOCKS routing at the client level (ex: with an
//    IOClient wrapping a SOCKS-assigned HttpClient) — no per-request proxy
//    plumbing is needed here.
final client = Client();

// 3. Build the service + controller.
final controller = OpenCryptoPayController(
  service: OpenCryptoPayService(client: client),
);

// 4. Run the controller
final result = await controller.run(
  qrData: scannedQrData,
  coin: MyCoin('bitcoin', 'BTC', 'Bitcoin'),
  ownedCoins: [ /* the user's coins */ ],
);

switch (result) {
  case OpenCryptoPaySuccess(:final address, :final amount):
    // prefill your send form, then submit proof after broadcasting:
    // await controller.submitProof(details: ..., method: ..., txHash: ...);
  case OpenCryptoPayUnsupported(:final alternatives):
    // offer the user to pay with an alternative wallet.
  case OpenCryptoPayNoPending():
  case OpenCryptoPayLightning():
  case OpenCryptoPayInvalidAddress():
  case OpenCryptoPayError():
}
```
