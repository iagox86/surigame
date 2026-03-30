<?php
// index.php
$db = new SQLite3('/data/dragons.db');

// Search functionality
$search = $_GET['search'] ?? '';

if($search == '') {
  $sql = "SELECT * FROM dragons WHERE is_classified = 0";
  $result = $db->query($sql);
} else {
  $sql = "SELECT * FROM dragons WHERE (name LIKE '%$search%' OR color LIKE '%$search%' OR size LIKE '%$search%' OR habitat LIKE '%$search%') AND is_classified = 0";
}

$result = $db->query($sql);

if(!$result) {
  echo "An error occurred while accessing the database. Please try again later.\n";
  echo "Your query:\n\n";
  echo "$sql";
  exit(0);
}
?>

Search: <?= $search ?>

Name           Color           Size           Habitat
<?php
while ($row = $result->fetchArray(SQLITE3_ASSOC)) {
  echo "# " . $row['name'] . "\n";
  echo "* Color: " . $row['color'] . "\n";
  echo "* Size: " . $row['size'] . "\n";
  echo "* Habitat: " . $row['habitat'] . "\n";
  echo "\n";
}
