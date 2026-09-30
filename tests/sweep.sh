#!/bin/sh
# A single large buy order crosses TWO resting sell orders at DIFFERENT
# prices in one call - the real "not just a single require" showcase.
# Also covers a partial fill leaving a resting order's remainder in the
# book, and cancelling an unmatched order for a full refund.
set -e
DB="tests/data/sweep.json"
rm -f "$DB"
E="$LARZEXCHANGE --board=$DB"

$E fund alice 1000
$E fund bob 1000
$E fund carol 1000
$E create-market Widgets widgets
mid="$($E list | awk 'NR==3{print $2}')"
$E supply "$mid" bob 50
$E supply "$mid" carol 50
$E sell "$mid" bob 5 9.00
$E sell "$mid" carol 5 9.50
$E book "$mid"
$E buy "$mid" alice 10 10.00
$E balance alice
$E balance bob
$E balance carol
$E book "$mid"

echo "--- partial fill: a 20-unit sell only partly matched by a 5-unit buy ---"
$E sell "$mid" bob 20 8.00
$E buy "$mid" alice 5 8.00
$E book "$mid"

echo "--- cancel an unmatched order for a full refund ---"
$E buy "$mid" alice 3 1.00
bid="$($E book "$mid" | grep "3 @" | awk '{print $1}')"
$E balance alice
$E cancel "$mid" "$bid" buy
$E balance alice
