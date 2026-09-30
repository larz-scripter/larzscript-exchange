#!/bin/sh
# A narrated walkthrough - two sellers rest orders at different prices,
# then one buy order sweeps through BOTH in a single call, settling
# each fill at its own resting price and refunding the buyer's price-
# improvement slack immediately. Then a partial fill, and cancelling an
# unmatched order for a full refund. Run from the repo root:
# sh examples/demo.sh
set -e
DB="/tmp/larzexchange-demo-$$.json"
rm -f "$DB"
LARZEXCHANGE="larzscript bin/larzexchange.lz --board=$DB"

echo "--- fund three traders and open a market (demo-only faucets) ---"
$LARZEXCHANGE fund alice 1000
$LARZEXCHANGE fund bob 1000
$LARZEXCHANGE fund carol 1000
$LARZEXCHANGE create-market Widgets widgets
mid="$($LARZEXCHANGE list | awk 'NR==3{print $2}')"
$LARZEXCHANGE supply "$mid" bob 50
$LARZEXCHANGE supply "$mid" carol 50

echo "--- bob and carol rest sell orders at two different prices ---"
$LARZEXCHANGE sell "$mid" bob 5 9.00
$LARZEXCHANGE sell "$mid" carol 5 9.50
$LARZEXCHANGE book "$mid"

echo
echo "--- alice buys 10 at a 10.00 limit - crosses BOTH resting orders in one call ---"
$LARZEXCHANGE buy "$mid" alice 10 10.00
echo "--- settled at each seller's OWN price (9.00 and 9.50), not alice's 10.00 limit ---"
$LARZEXCHANGE balance alice
$LARZEXCHANGE balance bob
$LARZEXCHANGE balance carol
$LARZEXCHANGE book "$mid"

echo
echo "--- bob rests a bigger order than the next buy can fully take ---"
$LARZEXCHANGE sell "$mid" bob 20 8.00
$LARZEXCHANGE buy "$mid" alice 5 8.00
echo "--- bob's order partially fills - 15 still resting in the book ---"
$LARZEXCHANGE book "$mid"

echo
echo "--- alice places an order too cheap to ever match, then cancels it ---"
$LARZEXCHANGE buy "$mid" alice 3 1.00
bid="$($LARZEXCHANGE book "$mid" | grep "3 @" | awk '{print $1}')"
$LARZEXCHANGE balance alice
$LARZEXCHANGE cancel "$mid" "$bid" buy
echo "--- full refund - nothing was ever going to match it ---"
$LARZEXCHANGE balance alice

rm -f "$DB"
