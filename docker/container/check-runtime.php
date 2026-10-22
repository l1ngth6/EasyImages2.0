<?php
// Used during image build, at startup, and by CI. No application files are loaded.
if (PHP_MAJOR_VERSION !== 8 || PHP_MINOR_VERSION !== 4 || version_compare(PHP_VERSION, '8.4.27', '<')) {
    fwrite(STDERR, "PHP 8.4.27 or a newer PHP 8.4 patch release is required.\n");
    exit(1);
}

foreach (['gd', 'mbstring', 'zip', 'bcmath', 'curl', 'ftp', 'exif', 'fileinfo', 'iconv', 'openssl', 'Zend OPcache'] as $extension) {
    if (!extension_loaded($extension)) {
        fwrite(STDERR, "Missing PHP extension: $extension\n");
        exit(1);
    }
}

$gd = gd_info();
foreach (['JPEG Support', 'PNG Support', 'WebP Support', 'FreeType Support'] as $format) {
    if (empty($gd[$format])) {
        fwrite(STDERR, "Missing GD feature: $format\n");
        exit(1);
    }
}

fwrite(STDOUT, 'Runtime OK: PHP ' . PHP_VERSION . "\n");
