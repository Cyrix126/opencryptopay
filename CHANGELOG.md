# Changelog

## 0.4.0

- error handling: separate exception from the error message.
- Add `OpenCryptoPayInvalidAmount` for a payment URI whose amount cannot be parsed
- `OpenCryptoPayProofFailed.isRejectedByProvider` tells a proof the provider refused (4xx) from a failure after which it may hold the payment, which `OpenCryptoPaySession.mayHoldPayment` remembers
- `OpenCryptoPayStrings.proofFailure` and `quoteExpiredAtSend` word a failed submission or an expired quote from the session
- Carry the per-method `minFee` on `SupportedMethod` and `OpenCryptoPaySession`; `CryptoCoin.chainType` sets its `minFeeUnit` (sat/vB for Bitcoin-derived chains, gas price in wei for EVM chains)
- Decode LNURL with `blockchain_utils`, dropping the `bech32` git dependency
- `OpenCryptoPayStrings` words a send that needs more than one transaction, or lacks the signed transaction the provider asked for
- Remove `CryptoCoin.displayName`, which nothing read
- `OpenCryptoPaySession.recordFailedBroadcast` marks a payment whose broadcast failed as possibly sent, which `mayHoldPayment` reports; a failed hash proof does too, since the wallet broadcast the payment
- Rename `requiresBroadcast` to `isBroadcastRequired`, and the `paymentNotSent` parameter of `OpenCryptoPayStrings.quoteExpiredMessage` to `isPaymentUnsent`

## 0.3.0

- Expose recipient contact details as `postalAddress`, `phoneUri`, `mailUri` and `websiteUri`
- Add `legalName` to the transaction details

## 0.2.0

- Add the merchant `recipient` details of a payment

## 0.1.0

- Provider agnostic OpenCryptoPay library
