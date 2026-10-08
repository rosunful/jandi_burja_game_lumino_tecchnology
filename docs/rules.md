# Janda Burja — rules and economics

Janda Burja (also called Crown and Anchor) is a six-dice game of chance. This
document is the single source of truth for how the game is scored and why the
payout table is what it is. The code in `lib/logic/` implements exactly what is
written here, and the tests in `test/` assert every figure below.

## The round

1. Six dice are thrown.
2. Each die shows one of six symbols, each equally likely.
3. Before the throw the player stages wagers: one or more chips on any of the
   six symbols.
4. After the throw, each wager is settled on its own.

The symbols, in betting-board order:

| Symbol   | Local name |
| -------- | ---------- |
| Crown    | burja      |
| Flag     | jhanda     |
| Heart    | paan       |
| Diamond  | itta       |
| Club     | chidi      |
| Spade    | hukum      |

## Settlement

A wager of `A` coins on symbol `s` wins when at least **two** of the six dice
show `s`. If `k` dice match, the net profit is `k × A`. Losing wagers cost
`A` coins.

| Matching dice | Result    | Payout        |
| ------------- | --------- | ------------- |
| 0             | lose      | `0`           |
| 1             | lose      | `0`           |
| 2             | win       | profit `2×A`  |
| 3             | win       | profit `3×A`  |
| 4             | win       | profit `4×A`  |
| 5             | win       | profit `5×A`  |
| 6             | win       | profit `6×A`  |

Several symbols can be backed in the same throw, and each is settled
independently. Backing three symbols does not raise the house edge: every wager
is priced separately against the same 86.13% return.

## Why two matches are required

For one symbol, the probability of exactly `k` of six dice matching is

```
C(6, k) × (1/6)^k × (5/6)^(6-k)
```

| k | Probability |
| - | ----------- |
| 0 | 33.4898%    |
| 1 | 40.1878%    |
| 2 | 20.0939%    |
| 3 | 5.3584%     |
| 4 | 0.8038%     |
| 5 | 0.0643%     |
| 6 | 0.0021%     |

Nearly 74% of throws produce at most one match. The expected value of a
one-unit wager is therefore

```
EV = Σ P(k) × profit(k)
   = 0.334898×(-1) + 0.401878×(-1) + 0.200939×(2) + 0.053584×(3)
     + 0.008038×(4) + 0.000643×(5) + 0.000021×(6)
   = -0.138653
```

- **Return to player: 86.13%**
- **House edge: 13.87%**

Both figures are asserted exactly in `test/payout_table_test.dart`, and the RTP
is independently re-derived by a 200 000-round Monte-Carlo simulation in
`test/dice_distribution_test.dart`, so the table cannot silently drift away
from these numbers.

### Why the threshold is not one

Paying on a single match would give `EV = +0.665102`, a return to player of
166.51%. The player's balance would grow without bound, they would never run
out of coins, and the watch-an-ad refill would never be needed. That is a
broken economy rather than a generous game.

A house edge of 13.87% is deliberately steep. The point of this app is that a
player genuinely can lose their balance, and that running out of coins and
watching an ad for more is a real, normal part of playing. The alternative — a
gentle edge that never quite drains a balance — makes the ad loop decorative.

## Limits

| Setting                    | Value    |
| -------------------------- | -------- |
| Starting balance           | 5000     |
| Smallest wager             | 10       |
| Largest wager, one symbol  | 2000     |
| Largest total, one throw   | 6000     |
| Chip denominations         | 10, 50, 100, 500, 1000 |
| Coins per rewarded ad      | 500      |

## Fairness

- Dice are drawn from `Random.secure()`, the platform CSPRNG, and are never
  seeded from or influenced by ad state, balance, or anything else the player
  does.
- The RNG is injectable so tests can pin an exact sequence, but the app
  instance always uses the secure generator.
- Watching an ad grants a flat 500 coins. It cannot change a roll's outcome,
  because the roll is already determined before the ad is even offered.
- An ad must be watched to completion to be paid. Dismissing early grants
  nothing, so the refill cannot be farmed.

## No real money

Coins exist only inside the app. There is no purchase, no deposit, no
withdrawal, no cash-out and no prize of any kind, and winning has no monetary
value. Rewarded ads are the only way to add coins, and they are optional — the
game is fully playable offline.

The app is rated 18+ because it simulates gambling. It is not a real-money
gambling product.
