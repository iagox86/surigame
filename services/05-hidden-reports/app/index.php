<?php
// app/public/index.php
session_start();

$error = null; // Initialize error variable

function is_authenticated() {
    return isset($_SESSION['authenticated']) && $_SESSION['authenticated'];
}

function verify_credentials($password) {
  $query = "SELECT count(*) FROM agents WHERE username = 'dragonwatch' and password = '" . $password . "'";
  try {
    $db = new PDO('sqlite:/data/secrets.db');
    $stmt = $db->prepare($query);
    $stmt->execute();
    $count = $stmt->fetchColumn();

    return $count > 0;
  } catch (PDOException $e) {
    echo "An error occurred while accessing the database.\n";
    echo "Your query:\n";
    echo "\n";
    echo "$query\n";
    exit(0);
  }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['logout'])) {
        session_destroy();
        header('Location: /');
        exit;
    }

    if (!empty($_POST['passphrase'])) {
        if (verify_credentials($_POST['passphrase'])) {
          $_SESSION['authenticated'] = true;
        } else {
          echo "⚠️ Incorrect password. Access denied!"; // Set error message
          exit(0);
        }
    }
}

if (is_authenticated()) {
    display_classified_dossier();
} else {
    show_login_form($error); // Pass error to login form
}

function display_classified_dossier() {
    echo <<<HTML
      🐉 TOP SECRET: DRAGON INCURSION IMMINENT 🐉

      Codename: Operation Firestorm
      Threat Level: Apocalyptic
      ETA: 2025-08-15T18:00:00Z
      Primary Entry Point: Mount St. Helens Caldera
      Estimated Hostiles: 12 Ancient Wyrms + Support

      Recommended Countermeasures:
      * Mobilize Dragon Slayer Division
      * Activate Arcane Shield Grid
      * Deploy Anti-Air Ballistae
HTML;
}

function show_login_form($error = null) {
    $errorMessage = $error ? "<div class='error'>$error</div>" : ""; // Display error if exists
    echo <<<HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="style.css">
        <title>Secret Dragon Dossier Login</title>
    </head>
    <body>
        <div class="container">
            <div class="dossier">
                $errorMessage
                <h1>🔒 CLASSIFIED EYES ONLY</h1>
                <p>This portal grants access to the secret dragon dossier.</p>
                <p><strong>Please avoid using an apostrophe (<tt>'</tt>) in your password, it causes weird errors!</strong></p>
                <form method="post">
                    <input type="password" name="passphrase" placeholder="Enter Authorization Code" required>
                    <button type="submit">Authenticate</button>
                </form>
                <div class="warning">⚠️ Unauthorized access will be met with extreme prejudice.</div>
            </div>
        </div>
    </body>
    </html>
HTML;
}
