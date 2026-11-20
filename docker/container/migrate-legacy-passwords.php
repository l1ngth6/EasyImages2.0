<?php
// Startup migration for password hashes written before EasyImage 2.8.7.
//
// Older releases stored SHA256(password) as 64 hex characters. 2.8.7 accepts only
// bcrypt(SHA256(password)) and has no migration path. The login form still submits
// SHA256(password), so applying bcrypt to the stored digest keeps every existing
// password working. Only password values change; every other byte stays the same.
//
// Usage: php migrate-legacy-passwords.php [config-dir] [bundled-defaults-dir]
// Run it as the application user, never as root: the config files are PHP code
// that the application itself can write.

declare(strict_types=1);

const BCRYPT_COST = 12; // Same as EASYIMAGE_BCRYPT_COST in app/base.php.
// Example uploader shipped by older releases; its password is publicly known.
const SAMPLE_GUEST_DIGEST = '84983c60f7daadc1cb8698621f802c0d9f9a3c3c295c810748fb048115c186ec';
const LEGACY_PATTERN = '/^[0-9a-f]{64}$/i';

function say(string $message): void
{
    fwrite(STDERR, "easyimage-migrate: $message\n");
}

function load_array(string $file, string $variable): ?array
{
    $vars = (static function (string $__file): array {
        include $__file;
        return get_defined_vars();
    })($file);
    return is_array($vars[$variable] ?? null) ? $vars[$variable] : null;
}

function is_legacy($value): bool
{
    return is_string($value) && preg_match(LEGACY_PATTERN, $value) === 1;
}

/** True when $new equals $old except migrated passwords, which must verify. */
function matches_after_migration(array $old, array $new, array $hashes): bool
{
    if (array_keys($old) !== array_keys($new)) {
        return false;
    }
    foreach ($old as $key => $value) {
        if (is_array($value)) {
            if (!is_array($new[$key]) || !matches_after_migration($value, $new[$key], $hashes)) {
                return false;
            }
        } elseif ($key === 'password' && is_legacy($value) && isset($hashes[strtolower($value)])) {
            if (!is_string($new[$key]) || !password_verify(strtolower($value), $new[$key])) {
                return false;
            }
        } elseif ($new[$key] !== $value) {
            return false;
        }
    }
    return true;
}

/** @param string[] $digests legacy digests to migrate */
function migrate_file(string $file, string $variable, array $old, array $digests): void
{
    if (is_link($file)) {
        throw new RuntimeException('file is a symbolic link; migrate it manually');
    }
    $hashes = [];
    foreach (array_unique(array_map('strtolower', $digests)) as $digest) {
        $hashes[$digest] = password_hash($digest, PASSWORD_BCRYPT, ['cost' => BCRYPT_COST]);
    }

    $text = file_get_contents($file);
    if ($text === false) {
        throw new RuntimeException('cannot read file');
    }
    $text = preg_replace_callback(
        '/(([\'"])password\2\s*=>\s*)([\'"])([0-9a-fA-F]{64})\3/',
        static fn (array $m): string => isset($hashes[strtolower($m[4])])
            ? $m[1] . "'" . $hashes[strtolower($m[4])] . "'"
            : $m[0],
        $text
    );
    if ($text === null) {
        throw new RuntimeException('cannot parse the file text');
    }

    // tempnam() silently falls back to the system temporary directory.
    $temp = @tempnam(dirname($file), '.migrate-');
    if ($temp === false || dirname($temp) !== dirname($file)) {
        if ($temp !== false) {
            unlink($temp);
        }
        throw new RuntimeException('cannot create a temporary file next to it');
    }
    try {
        if (file_put_contents($temp, $text) !== strlen($text)) {
            throw new RuntimeException('cannot write the temporary file');
        }
        $new = load_array($temp, $variable);
        if ($new === null || !matches_after_migration($old, $new, $hashes)) {
            throw new RuntimeException('rewritten file did not verify');
        }
        $backup = $file . '.legacy-sha256.bak';
        if (file_exists($backup)) {
            $backup = $file . '.legacy-sha256.' . date('YmdHis') . '.bak';
        }
        if (!copy($file, $backup) || !chmod($backup, 0600)) {
            throw new RuntimeException('cannot write the backup');
        }
        chmod($temp, fileperms($file) & 0777);
        if (!rename($temp, $file)) {
            throw new RuntimeException('cannot replace the file');
        }
    } finally {
        if (is_file($temp)) {
            unlink($temp);
        }
    }
    say(sprintf(
        '%s: converted %d legacy SHA256 password(s) to bcrypt; the original is saved as %s. '
            . 'Existing passwords keep working; changing them after login is recommended.',
        basename($file),
        count($digests),
        basename($backup)
    ));
}

umask(0077); // Backups hold the old hashes; never create them readable by others.
$configDir = rtrim($argv[1] ?? '/app/web/config', '/');
$defaultsDir = rtrim($argv[2] ?? '/opt/easyimage-defaults/config', '/');
$failed = false;

$targets = [
    'config.php' => ['config', static function (array $config): array {
        return is_legacy($config['password'] ?? null) ? [$config['password']] : [];
    }],
    'config.guest.php' => ['guestConfig', static function (array $guests): array {
        $digests = [];
        foreach ($guests as $name => $guest) {
            $digest = is_array($guest) ? ($guest['password'] ?? null) : null;
            if (!is_legacy($digest)) {
                continue;
            }
            if (strtolower($digest) === SAMPLE_GUEST_DIGEST) {
                say("config.guest.php: left example uploader '$name' unconverted because its password is public; delete it in the admin page.");
                continue;
            }
            $digests[] = $digest;
        }
        return $digests;
    }],
];

foreach ($targets as $name => [$variable, $collect]) {
    $file = "$configDir/$name";
    if (!is_file($file)) {
        continue;
    }
    try {
        $values = load_array($file, $variable);
        if ($values === null) {
            throw new RuntimeException("\$$variable is not defined as an array");
        }
        $digests = $collect($values);
        if ($digests !== []) {
            migrate_file($file, $variable, $values, $digests);
        }
    } catch (Throwable $error) {
        say("$name: left unchanged: " . $error->getMessage());
        $failed = true;
    }
}

// Upstream only saves settings whose keys already exist, so missing keys cannot be
// added from the admin page. Report them; editing the file is left to the owner.
try {
    $defaults = load_array("$defaultsDir/config.php", 'config');
    $current = load_array("$configDir/config.php", 'config');
    if ($defaults !== null && $current !== null) {
        $missing = array_keys(array_diff_key($defaults, $current));
        if ($missing !== []) {
            say('config.php lacks settings that the bundled defaults define: ' . implode(', ', $missing)
                . '. Copy them from the bundled config.php to use them.');
        }
    }
} catch (Throwable $error) {
    say('could not compare config.php with the bundled defaults: ' . $error->getMessage());
}

exit($failed ? 1 : 0);
