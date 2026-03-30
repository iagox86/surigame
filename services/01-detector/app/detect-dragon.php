<?php
  if(isset($_REQUEST['ip'])) {
    $ip = $_REQUEST['ip'];

    system("bash /app/dragon-detector-ai $ip");
    echo "\n";
  } else {
    echo "ip= parameter not found!\n";
  }

  echo "\n<br>\n<a href=\"/\">Check another IP</a>\n";
?>
