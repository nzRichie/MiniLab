<?php
// Product search for the Harkness Tools storefront.
//
// The page takes a search term in the `q` query parameter and prints one line
// per matching product. It is meant to show published products only: the
// `published = 1` condition is the whole of that policy, and there is nothing
// else in the application that hides an unreleased line from a customer.
//
// The bug is on the line marked below. The search term is pasted into the SQL
// text between two characters this file supplies, a quote and a per cent sign
// before it and a per cent sign and a quote after it, so a quote character in
// the term ends the string literal early and everything after it is read by the
// server as more SQL. mysqli::real_escape_string() is never called and no
// prepared statement is used.

require '/etc/minilabs/db.inc.php';

header('Content-Type: text/plain');

$q = isset($_GET['q']) ? $_GET['q'] : '';

try {
    $db = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
} catch (mysqli_sql_exception $e) {
    echo "database unavailable\n";
    exit;
}

$sql = "SELECT id, name, category, price FROM product"
     . " WHERE published = 1 AND name LIKE '%" . $q . "%'";   // the vulnerable line

// The server's own error text is caught and thrown away. A caller learns only
// that the statement did not run, which is why the column count has to be
// established by probing rather than read off an error message.
try {
    $res = $db->query($sql);
} catch (mysqli_sql_exception $e) {
    echo "query failed\n";
    exit;
}

$n = 0;
while ($row = $res->fetch_row()) {
    echo implode(' | ', $row), "\n";
    $n++;
}
if ($n === 0) {
    echo "no products matched\n";
}
