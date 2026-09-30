#!/bin/sh
# A too-short/empty id must fail cleanly, not silently match the first
# market iterated over - see bin/larzexchange.lz's
# _find_market_by_prefix(). Also covers a sell order correctly refused
# for insufficient inventory, and a buy order correctly refused for
# insufficient funds.
set -e
DB="tests/data/guard.json"
rm -f "$DB"
E="$LARZEXCHANGE --board=$DB"

$E fund alice 10
$E create-market Widgets widgets
mid="$($E list | awk 'NR==3{print $2}')"
$E book "" || true
$E book "ab" || true

echo "--- selling widgets nobody has ---"
$E sell "$mid" bob 5 9.00 || true

echo "--- buying more than alice can afford ---"
$E buy "$mid" alice 100 1.00 || true
$E balance alice
