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
- `isOpenCryptoPayUri` returns false for a link whose query is not valid UTF-8, where it threw a `FormatException`; `run()` returns `OpenCryptoPayError` for a payment URI with such a query, where it threw too
- Rename `requiresBroadcast` to `isBroadcastRequired`, and the `paymentNotSent` parameter of `OpenCryptoPayStrings.quoteExpiredMessage` to `isPaymentUnsent`
- `submitTransactionProof` no longer returns `bool`
- Fetch the transaction details from the callback URL, as the spec requires; `buildTransactionDetailsUrl` takes the `callback`
- Upgrade http API, callback and proof URLs to https, except for onion hosts
- An LNURL must carry the `lnurl` prefix and encode a web URL
- Accept `blockchain_utils` up to 7.x
- `run()` returns `OpenCryptoPayError` when the proof URL cannot be built from the callback
- A transfer URI needs a recipient in `address` or `to`, and `/transfer` counts only before the query
- `amount` and `isRawAmount` come from the same query key, with `uint256` before `value`
- `amountInSmallestUnit` rounds an amount finer than the coin's precision up
- Reject negative, hexadecimal, padded and exponent decimal amounts; accept EIP-681 scientific notation for raw amounts
- Read malformed optional fields as absent, and exclude a method whose `minFee` is not a finite, non-negative number
- A 400 on the details request maps to `OpenCryptoPayUnsupported` only for a method without an asset list
- `submitProof` returns the in-flight submission to an overlapping call
- The proof type comes from a hint that mentions hex, a hash or the tx parameter; `proofType` is null otherwise and `run()` returns the new `OpenCryptoPayUnknownProofType` before reading the payment URI

## 0.3.0

- Expose recipient contact details as `postalAddress`, `phoneUri`, `mailUri` and `websiteUri`
- Add `legalName` to the transaction details

## 0.2.0

- Add the merchant `recipient` details of a payment

## 0.1.0

- Provider agnostic OpenCryptoPay library
