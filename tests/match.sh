#!/bin/sh
# A crossing buy order fills against a cheaper resting sell at the
# SELLER's price, not the buyer's own limit - and the resulting price-
# improvement slack lands back in the buyer's wallet immediately.
set -e
DB="tests/data/match.json"
rm -f "$DB"
E="$LARZEXCHANGE --board=$DB"

$E fund alice 1000
$E fund bob 1000
$E create-market Widgets widgets
mid="$($E list | awk 'NR==3{print $2}')"
$E supply "$mid" bob 50
$E sell "$mid" bob 10 9.50
$E book "$mid"
$E buy "$mid" alice 10 10.00
$E balance alice
$E balance bob
$E book "$mid"
