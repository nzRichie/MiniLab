<?php
// Stock check for the Harkness Tools storefront.
//
// The product page calls this endpoint with a product id and prints whatever it
// says beside the Add to basket button. It prints exactly one of two strings and
// never a row, a column name, a count or an error message, which is the whole of
// its contract with the page that calls it.
//
// It carries the same bug as search.php and one difference: the id is pasted
// into a numeric comparison rather than between quote characters, so a payload
// here supplies no quote of its own.

require '/etc/minilabs/db.inc.php';

header('Content-Type: text/plain');

$sku = isset($_GET['sku']) ? $_GET['sku'] : '0';

try {
    $db = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
    $sql = "SELECT stock FROM product WHERE id = " . $sku;   // the vulnerable line
    $res = $db->query($sql);
    $row = $res->fetch_row();
} catch (mysqli_sql_exception $e) {
    echo "OUT OF STOCK\n";
    exit;
}

if ($row && (int)$row[0] > 0) {
    echo "IN STOCK\n";
} else {
    echo "OUT OF STOCK\n";
}
