<?php
header('Content-Type: text/plain; charset=utf-8');
// سعی می‌کنیم IP واقعی را از هدرهای رایج پیدا کنیم
$keys = [
    'HTTP_CF_CONNECTING_IP', // Cloudflare
    'HTTP_X_FORWARDED_FOR',  // Proxies/Load Balancers
    'HTTP_X_REAL_IP',        // Nginx proxy
    'REMOTE_ADDR'            // Direct connection
];
$ip = '';
foreach ($keys as $key) {
    if (!empty($_SERVER[$key])) {
        $ip = $_SERVER[$key];
        // اگر X-Forwarded-For باشد، اولین IP را برمی‌داریم
        if ($key === 'HTTP_X_FORWARDED_FOR') {
            $ip_list = explode(',', $ip);
            $ip = trim($ip_list[0]);
        }
        break; // اولین IP معتبر را پیدا کردیم
    }
}
echo $ip;
?>
