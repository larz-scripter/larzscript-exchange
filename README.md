# LarzExchange

A real limit order book, written entirely in Larzscript, the
money-native language. Different in *kind* from the sibling flagship
projects — those are each about one `require` doing something a single
`pay` can't; this one is about a real, non-trivial **algorithm**
(continuous matching by price-time priority, with partial fills) where
every single fill still has to move real money and real inventory
correctly, including the case where one incoming order sweeps through
several resting orders at *different* prices in a single call.

Part of the [Larzscript ecosystem growth plan](https://github.com/larz-scripter/larzscript/blob/main/GROWTH.md)'s
flagship-app track (alongside [`LarzBank`](https://github.com/larz-scripter/larzscript-bank),
[`LarzBounty`](https://github.com/larz-scripter/larzscript-bounty),
[`LarzCrowd`](https://github.com/larz-scripter/larzscript-crowd),
[`LarzInsure`](https://github.com/larz-scripter/larzscript-insure),
[`LarzGig`](https://github.com/larz-scripter/larzscript-gig), and
[`LarzDAO`](https://github.com/larz-scripter/larzscript-dao)).

## Why placing an order has to move real money immediately

A limit order sitting in the book is a real commitment, not a database
row — so the moment you place one, this locks the funds/inventory it
could need for real, the same `escrow.open()` shape as LarzBounty's
`post()`:

```larzscript
escrow.open(moneyx.of(quantity * limit_price), user_w, holding)
```

That's what stops a user from placing several buy orders that
*together* commit more money than they actually have — a "check the
balance at match time" design would let every one of those orders sit
in the book looking fully funded until they all try to fill at once.

## Why a fill settles at the resting order's price, not the taker's own limit

Matching always executes at whichever order was **already in the
book** — real price-time priority, the standard "maker sets the price"
rule. That means a buy order can fill at a genuinely *better* price
than its own limit, which leaves slack in its holding wallet — and that
slack gets released back to the buyer **immediately after every fill**,
not just on cancellation:

```larzscript
let still_needed = buy_order["remaining"] * buy_order["price"]
if buy_order["holding_balance"] > still_needed {
  let slack = buy_order["holding_balance"] - still_needed
  escrow.refund(moneyx.of(slack), holding2, buyer_w)
  ...
}
```

Found live, building this: without that release, a $100-escrowed order
that fills 10 units at $9.50 instead of its own $10.00 limit leaves
$5.00 stuck in a completed order's holding wallet forever — `cancel`
only refunds *open* orders, so a filled order's leftover escrow had
nowhere left to go. The demo below shows the correct behavior: alice
escrows $100 for a 10-unit order, the book fills her at $9.00 and $9.50
across two sellers, and she ends up paying exactly $92.50 — not $95,
not $100.

## Quickstart

```bash
larzscript bin/larzexchange.lz fund alice 1000
larzscript bin/larzexchange.lz create-market Widgets widgets
larzscript bin/larzexchange.lz supply <market_id> bob 50
larzscript bin/larzexchange.lz sell <market_id> bob 10 9.50
larzscript bin/larzexchange.lz buy <market_id> alice 10 10.00
larzscript bin/larzexchange.lz book <market_id>
```

State (USD wallets, commodity inventory, markets) persists to
`board.json` in the current directory across runs — each command is a
fresh process; see "How it's built" below for how that's made to work
with a native `wallet` value, which isn't something JSON can hold.
Override the state file with `--board=path/to/file.json`.

## Real transcript (`sh examples/demo.sh`, copy-pasted, not invented)

```
--- fund three traders and open a market (demo-only faucets) ---
alice balance is now $1000
bob balance is now $1000
carol balance is now $1000
created market 8f7b31e6  "Widgets"  (widgets)
full id: 8f7b31e6-02a8-4714-904e-9b6f33339fe6
bob now has 50 widgets
carol now has 50 widgets
--- bob and carol rest sell orders at two different prices ---
sell order cfe0a071  status=open  remaining=5
full id: cfe0a071-a653-4117-adf9-0a00ada74d70
sell order fd6f7083  status=open  remaining=5
full id: fd6f7083-c7db-458a-b458-4cb9c75be53c
Widgets (widgets)
bids (buy orders):
asks (sell orders):
  cfe0a071  bob  5 @ $9
  fd6f7083  carol  5 @ $9.5
trades:

--- alice buys 10 at a 10.00 limit - crosses BOTH resting orders in one call ---
buy order 00fc8a3a  status=filled  remaining=0
full id: 00fc8a3a-bdc2-44d0-8b6b-ee4dfab24b61
--- settled at each seller's OWN price (9.00 and 9.50), not alice's 10.00 limit ---
alice: $907.5
bob: $1045
carol: $1047.5
Widgets (widgets)
bids (buy orders):
asks (sell orders):
trades:
  5 @ $9
  5 @ $9.5

--- bob rests a bigger order than the next buy can fully take ---
sell order d467ee4e  status=open  remaining=20
full id: d467ee4e-1b8b-49c7-adf8-09a23f50a272
buy order a778ce70  status=filled  remaining=0
full id: a778ce70-4105-4630-90b8-847d735bf673
--- bob's order partially fills - 15 still resting in the book ---
Widgets (widgets)
bids (buy orders):
asks (sell orders):
  d467ee4e  bob  15 @ $8
trades:
  5 @ $9
  5 @ $9.5
  5 @ $8

--- alice places an order too cheap to ever match, then cancels it ---
buy order 54e1c0db  status=open  remaining=3
full id: 54e1c0db-0a3b-4c26-ad7c-b596c73b636c
alice: $864.5
cancelled
--- full refund - nothing was ever going to match it ---
alice: $867.5
```

## Commands

| Command | What it does |
|---|---|
| `fund <name> <amount>` | Demo-only USD faucet. |
| `create-market <name> <commodity>` | Opens a market trading USD against a named commodity (e.g. `widgets`). |
| `supply <market_id> <name> <qty>` | Demo-only commodity faucet — credits a trader's inventory directly. |
| `buy <market_id> <user> <quantity> <price>` | Places a limit buy order. Escrows `quantity*price` immediately, matches against the book right away, rests any unfilled remainder. |
| `sell <market_id> <user> <quantity> <price>` | Places a limit sell order. Reserves `quantity` of inventory immediately, matches the same way. |
| `cancel <market_id> <order_id> <buy\|sell>` | Cancels an open order — refunds whatever's left escrowed (buy) or reserved (sell) in full. |
| `list` | Lists every market with its open order counts and trade count. |
| `book <market_id>` | Shows every open bid and ask, plus the full trade log. `<id>` may be the short 8-character prefix any `full id:` line prints. |
| `balance <name>` | Shows a trader's USD balance. |
| `inventory <market_id> <name>` | Shows a trader's available (unreserved) inventory in one market. |

## How it's built

- **`lib/moneyx.lz`** — the bridge between the native `wallet`/Money
  type and a plain float, for persisting balances to JSON. There is no
  `float(money)` builtin; stripping the leading `"$"` off `str(m)` is
  the real, working conversion.
- **`lib/exchange.lz`** — markets, orders, and the matching/settlement
  logic described above. `place_buy()`/`place_sell()` cross the book in
  a `while` loop, taking the best resting opposite-side order
  (lowest-price-first for asks, highest-price-first for bids, ties
  broken by placement time) one fill at a time until the incoming
  order's own limit stops clearing or it's fully filled, then rests
  whatever's left. Every fill is a real `escrow.release()` to the
  seller plus a real inventory transfer to the buyer, immediately.
- **`bin/larzexchange.lz`** — the CLI. Each invocation loads
  `board.json`, does one thing, saves it back. Both
  `_find_market_by_prefix()` and `_find_order_by_prefix()` reject a
  too-short/empty id outright rather than risk matching the wrong
  record — the latter fixed a real bug found while building this: the
  short id `book` prints was being passed straight to
  `exchange.cancel_order()`, which only ever does an exact match, so
  every cancel failed with "no such order" until the prefix lookup was
  added (same class of bug as the sibling projects' `_find_by_prefix`,
  just missed here at first because cancel was added after the market
  lookup and nobody had exercised it yet).

## Limitations (read before treating this as more than a toy)

- **`fund`/`supply` are faucets, not real payment/inventory rails.**
  There's no real deposit or custody flow behind either.
- **No market orders, stop orders, or order expiry** — every order is a
  plain resting-until-filled-or-cancelled limit order.
- **O(n) matching, not a real price-level order book.** `_best_sell()`/
  `_best_buy()` linearly scan every order in the market on every
  match attempt — fine for a toy CLI, not for a market with thousands
  of resting orders.
- **No identity/authorization model.** Anyone running the CLI can place
  or cancel an order as anyone.
- **Floating-point, not arbitrary-precision.** Larzscript's only numeric
  type is a double, the same limitation every Larz Stack money package
  documents.
- **Single-process, no concurrent access.** Two `larzexchange`
  invocations racing against the same `board.json` can clobber each
  other — fine for a personal CLI tool, not for anything multi-user.
- **`board.json` is not encrypted or access-controlled.** Don't put real
  financial data in it.

## Tests

```bash
sh tests/run_tests.sh
```

Real CLI output, diffed against `tests/*.expected`, `uuid.v4()` ids
normalized like the sibling projects. Covers: a simple cross with price
improvement correctly refunded, a single order sweeping two resting
orders at different prices plus a partial fill and a full-refund
cancellation, and the too-short-id-prefix guard plus insufficient-funds
and insufficient-inventory rejections.

## License

MIT
