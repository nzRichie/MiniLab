<?php
// Document viewer for the Brindle Logistics customer portal.
//
// The page takes a document name in the `file` query parameter, reads that
// document out of the portal's document directory, and prints it under the
// title the database holds for it.
//
// The bug is on the line marked below. The value of `file` is joined to the
// document directory and the result is handed to file_get_contents() as it
// stands. Nothing resolves the joined path and compares it against the
// directory it is supposed to stay inside, so a value containing `../` names a
// file outside that directory and the function opens it.
//
// The database lookup below is NOT the bug: it binds the parameter rather than
// pasting it into the statement text, so the document name reaches the server
// as a value and never as SQL.

require '/etc/minilabs/db.inc.php';

header('Content-Type: text/plain');

define('DOC_DIR', '/srv/docs/');

$file = isset($_GET['file']) ? $_GET['file'] : '';

$path = DOC_DIR . $file;                              // the vulnerable line

try {
    $db = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
} catch (mysqli_sql_exception $e) {
    echo "database unavailable\n";
    exit;
}

$title = '(untitled document)';
try {
    $st = $db->prepare('SELECT title FROM document WHERE name = ?');
    $st->bind_param('s', $file);
    $st->execute();
    $st->bind_result($t);
    if ($st->fetch()) {
        $title = $t;
    }
    $st->close();
} catch (mysqli_sql_exception $e) {
    echo "database unavailable\n";
    exit;
}

// The warning file_get_contents() raises on a path it may not open is
// suppressed, so a caller learns only that the read did not happen. That is
// what makes a blocked read and a missing file look the same from outside.
$body = @file_get_contents($path);
if ($body === false) {
    echo "== " . $title . " ==\n";
    echo "cannot open document\n";
    exit;
}

echo "== " . $title . " ==\n";
echo $body;
