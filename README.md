Provider agnostic Dart implementation of the [OpenCryptoPay](https://github.com/openCryptoPay/landingPage) payment flow for crypto wallets.

## Features

- [x] Decode scanned OpenCryptoPay QR links
- [x] Fetch pending payment details for a given coin
- [x] Fetch coins supported from provider
- [x] Submit proof of payment
- [x] Detect proof type (signed TX HEX, tx hash or sender principal) and instruct wallet accordingly
- [x] Let wallet plug their own HTTP client (`package:http` `Client`) and coin type

## Install

```sh
dart pub add opencryptopay --git-url=https://github.com/cyrix126/opencryptopay
```

## Usage

```dart
import 'package:http/http.dart';
import 'package:opencryptopay/opencryptopay.dart';

// 1. Describe your wallet's coin. An EVM coin also sets its chainId
//    (ex: chainId: 1 for Ethereum).
const coin = CryptoCoin(
  ticker: 'BTC',
  prettyName: 'Bitcoin',
  chainType: CryptoChainType.bitcoinDerived,
);

// 2. Provide a package:http Client.
//    Configure Tor / SOCKS routing at the client level (ex: with an
//    IOClient wrapping a SOCKS-assigned HttpClient).
final client = Client();

// 3. Build the service + controller.
final controller = OpenCryptoPayController(
  service: OpenCryptoPayService(client: client),
);

// 4. Run the controller
final result = await controller.run(
  qrData: scannedQrData,
  coin: coin,
  ownedCoins: [ /* the user's coins */ ],
);

switch (result) {
  case final OpenCryptoPaySuccess success:
    // Prefill your send form with success.address and
    // success.amountInSmallestUnit(decimals), use a fee of at least
    // success.minFee (in success.minFeeUnit), then sign the transaction.
    // Right before sending it, stop when the quote has expired.
    if (success.session.isQuoteExpired) {
      showError(OpenCryptoPayStrings.quoteExpiredAtSend(success.session));
      break;
    }
    final proof = await success.session.submitProof(
      switch (success.proofType!) {
        // Broadcast the transaction and submit its hash.
        OpenCryptoPayProofType.transactionHash => txHash,
        // Submit the signed transaction HEX, which the provider broadcasts.
        OpenCryptoPayProofType.signedTransactionHex => signedTxHex,
        // Approve success.address on the token's ICRC-2 ledger for the
        // amount plus the transfer fee, then submit your principal.
        OpenCryptoPayProofType.senderPrincipal => principal,
      },
    );
    if (proof is OpenCryptoPayProofFailed) {
      showError(OpenCryptoPayStrings.proofFailure(success.session));
    }
  case OpenCryptoPayUnsupported(:final alternatives):
    // Offer the user to pay with one of the alternatives.
    showAlternatives(alternatives);
  case final OpenCryptoPayFailure failure:
    showError(OpenCryptoPayStrings.failure(failure));
}
```
