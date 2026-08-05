<?php
/**
 * Config template for scripts/server/clip-feedback.php.
 *
 * Copy this file to config.php (same directory) and fill in real values.
 * config.php is server-only config and must NEVER be committed — the
 * private key path/ID living inside it is exactly what an attacker wants.
 *
 * Paths below match the verified cPanel layout — see
 * docs/features/app-clip-tasks.md "Ground truth" #4 and
 * docs/features/app-clip-plan.md "Hosting".
 */

return [
    /** Key ID from CloudKit Console > Tokens & Keys > Server-to-Server Keys. */
    'key_id' => 'PASTE_YOUR_KEY_ID_HERE',

    /**
     * Private key path. MUST be outside the web root.
     * Verified location on this host: /home/sesirkel/nandamochammad.xyz/cloudkit-key.pem
     * (web root is /home/sesirkel/nandamochammad.xyz/nandamochammad, NOT public_html).
     */
    'key_path' => '/home/sesirkel/nandamochammad.xyz/cloudkit-key.pem',

    /** CloudKit container and environment. */
    'container' => 'iCloud.xyz.nandamochammad.Reflect',
    'environment' => 'development', // 'development' | 'production' — flip for the AC-H3 deploy.

    /**
     * Directory for rate-limit counter files. MUST be outside the web root,
     * writable by the PHP process user, not web-reachable.
     */
    'rate_limit_dir' => '/home/sesirkel/nandamochammad.xyz/clip-feedback-ratelimit',
];
