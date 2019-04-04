<?php
$host = 'db'; // mysql container
$user = $argv[1];
$password = $argv[2];
$database = $argv[3];
$mysqli = new mysqli($host, $user, $password, $database);
if ($mysqli->connect_errno) {
    echo 'Failed to connect to MySQL: (' . $mysqli->connect_errno . ') ' . $mysqli->connect_error;
}

$res = $mysqli->query('SELECT option_value FROM `wp_options` WHERE option_name = "active_plugins";')->fetch_assoc();
$resarr = unserialize($res['option_value']);
$basharray = '';
foreach ($resarr as $pluginstring) {
        $peices = explode('/', $pluginstring);
        $basharray .= $peices[0] . ' ';
}
echo $basharray;
