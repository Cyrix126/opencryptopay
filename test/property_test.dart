import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:kiri_check/stateful_test.dart';
import 'package:opencryptopay/opencryptopay.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'sample_data/open_crypto_pay_payment_details_json.dart';

void main() {
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
          constantFrom<CryptoCoin>([btc, eth, xmr, usdt, doge]),
          combine2(_status, _paymentInfoBody),
          combine2(_status, _detailsBody),
        ),
        (args) async {
          final (coin, (infoStatus, info), (detailsStatus, details)) = args;
          final result = await controllerFor(mockHttpWithHandler((url) =>
              url.queryParameters.containsKey('method')
                  ? res(details, detailsStatus)
                  : res(info, infoStatus))).run(
            qrData: qrLink,
            coin: coin,
            ownedCoins: [btc, eth],
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

// The enum value spark hides the coin of the same name inside the enum.
const _sparkCoin = spark;

/// A proof of payment flow, selected by the hint.
enum _Flow {
  hex(btc, 'Send the signed transaction back as HEX.'),
  hash(xmr, 'Broadcast it and send the transaction hash back.'),
  spark(_sparkCoin, 'Send the transfer ID as the tx parameter.');

  const _Flow(this.coin, this.hint);

  final CryptoCoin coin;
  final String hint;
}

final _quoteExpires = DateTime.parse(quoteExpiration);

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
        apiUrl: decodedApiUrl,
        displayName: 'Test Shop',
        quoteId: 'plq_0',
        callback: callbackUrl,
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
      _Answer.ok when isProof(request.url) => res('', 200),
      _Answer.ok => res(
          jsonEncode({
            ...paymentDetailsJson,
            'quote': {
              'id': 'plq_${requests.length}',
              'expiration': quoteExpiration,
            },
          }),
          200,
        ),
      _Answer.refused => res('', 400),
      _Answer.serverError => res('', 503),
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
    final proofs = requests.where((request) => isProof(request.url));
    final accepted = proofs.where((proof) => proof.answer == _Answer.ok);
    expect(session.isCompleted, accepted.isNotEmpty,
        reason: 'completed once a proof is accepted');
    expect(lastResult is OpenCryptoPayProofAccepted, session.isCompleted,
        reason: 'accepted once completed');
    expect(
      requests.skip(_submissionStart).where((r) => isProof(r.url)),
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
