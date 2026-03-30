<?php
  $correct_username = 'admin';
  $correct_password = 'admin';

  if(isset($_SERVER['HTTP_AUTHORIZATION'])) {
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'];

    if (strpos(strtolower($authHeader), 'basic ') === 0) {
      $encoded_creds = substr($authHeader, 6);
      $decoded_creds = base64_decode($encoded_creds);
      $creds_parts = explode(':', $decoded_creds);

      if (count($creds_parts) !== 2) {
        echo "⚠️ Bad base64 or missing/extra ':' in the authentication token!";
      } else {
        $username = $creds_parts[0];
        $password = $creds_parts[1];

        if ($username === $correct_username && $password == $correct_password) {
          echo "Congratulations! You've averted disaster!";
        } else {
          echo "⚡ Authentication failed with username=$username and password=$password! Dragon extinction counter: ░░░░░░░░░░] 90%'";
        }
      }

      exit(0);
    } else {
      header('HTTP/1.0 401 Unauthorized');
      header('WWW-Authenticate: Basic');
      echo "Authorization header didn't start with 'basic'";
      exit(0);
    }
  } else {
    header('HTTP/1.0 401 Unauthorized');
    header('WWW-Authenticate: Basic');
    echo 'No Authorization header';
    exit(0);
  }

  header('HTTP/1.0 401 Unauthorized');
  header('WWW-Authenticate: Basic');
  echo 'You are not authorized to access this resource.';
?>
