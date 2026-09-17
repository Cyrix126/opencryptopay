# Changelog

## 0.4.0

- error handling: separate exception from the error message.
- Add `OpenCryptoPayInvalidAmount` for a payment URI whose amount cannot be parsed
- `OpenCryptoPayProofFailed.providerAnswered` tells a provider rejection from a lost response; `proofFailure` words the latter as unconfirmed
- Carry the per-method `minFee` on `SupportedMethod` and `OpenCryptoPaySession`
- Decode LNURL with `blockchain_utils`, dropping the `bech32` git dependency

## 0.3.0

- Expose recipient contact details as `postalAddress`, `phoneUri`, `mailUri` and `websiteUri`
- Add `legalName` to the transaction details

## 0.2.0

- Add the merchant `recipient` details of a payment

## 0.1.0

- Provider agnostic OpenCryptoPay library
