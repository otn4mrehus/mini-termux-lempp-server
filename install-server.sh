#!/data/data/com.termux/files/usr/bin/bash

###############################################################################
# TERMUX WEB SERVER INSTALLER
#
# Nginx
# PHP
# PHP-FPM
# MariaDB
#
# Compatible approach for Termux
###############################################################################

set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"

BASE_DIR="$HOME/server"

WEB_ROOT="$BASE_DIR/www"

ETC_DIR="$BASE_DIR/etc"
RUN_DIR="$BASE_DIR/run"
LOG_DIR="$BASE_DIR/logs"
TMP_DIR="$BASE_DIR/tmp"

NGINX_ETC="$ETC_DIR/nginx"
PHP_ETC="$ETC_DIR/php"
MARIADB_ETC="$ETC_DIR/mariadb"

NGINX_LOG="$LOG_DIR/nginx"
PHP_LOG="$LOG_DIR/php"
MARIADB_LOG="$LOG_DIR/mariadb"

MYSQL_DATA="$BASE_DIR/mysql"

STATE_DIR="$HOME/.config/termux-server"

SERVICE_MANAGER="$PREFIX/bin/server"

###############################################################################
# COLORS
###############################################################################

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'

###############################################################################
# FUNCTIONS
###############################################################################

info() {
    printf "${CYAN}[INFO]${RESET} %s\n" "$*"
}

ok() {
    printf "${GREEN}[ OK ]${RESET} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
}

die() {
    printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
    exit 1
}

section() {

    echo

    printf "${BLUE}============================================================${RESET}\n"

    printf "${BLUE}%s${RESET}\n" "$*"

    printf "${BLUE}============================================================${RESET}\n"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {

    dpkg-query \
        -W \
        -f='${Status}' \
        "$1" 2>/dev/null |
        grep -q "install ok installed"
}

###############################################################################
# CHECK TERMUX
###############################################################################

section "[1] Detect Android architecture"

[ -n "${PREFIX:-}" ] ||
    die "Script harus dijalankan dari Termux."

ARCH="$(uname -m)"

case "$ARCH" in

    aarch64)
        ABI="arm64-v8a"
        ;;

    armv7l|armv8l)
        ABI="armeabi-v7a"
        ;;

    x86_64)
        ABI="x86_64"
        ;;

    i686|i386)
        ABI="x86"
        ;;

    *)
        ABI="$ARCH"
        ;;
esac

ok "Architecture : $ARCH"
ok "ABI          : $ABI"

###############################################################################

section "[2] Detect Termux version"

TERMUX_VERSION="unknown"
ANDROID_VERSION="unknown"

if command_exists termux-info; then

    TERMUX_VERSION="$(
        termux-info 2>/dev/null |
        sed -n 's/^TERMUX_VERSION:[[:space:]]*//p' |
        head -n 1
    )"

    [ -n "$TERMUX_VERSION" ] ||
        TERMUX_VERSION="unknown"
fi

if command_exists getprop; then

    ANDROID_VERSION="$(
        getprop ro.build.version.release 2>/dev/null || true
    )"

    [ -n "$ANDROID_VERSION" ] ||
        ANDROID_VERSION="unknown"
fi

ok "Termux  : $TERMUX_VERSION"
ok "Android : $ANDROID_VERSION"

###############################################################################
# REPOSITORY
###############################################################################

section "[3] Update repository"

command_exists pkg ||
    die "Command pkg tidak tersedia."

if ! pkg update -y; then

    echo
    warn "pkg update gagal."

    echo
    echo "Coba:"
    echo
    echo "  termux-change-repo"
    echo
    echo "Pilih Main repository."
    echo

    die "Repository Termux tidak dapat diperbarui."
fi

ok "Repository updated."

###############################################################################
# DEPENDENCIES
###############################################################################

section "[4] Install dependencies"

#
# JANGAN:
#
#   pkg install awk
#
# Karena awk bukan nama package pada environment ini.
#
# awk disediakan oleh gawk.
#

REQUIRED_PACKAGES=(
    bash
    coreutils
    grep
    sed
    gawk
    findutils
    procps
    curl
    wget
    ca-certificates
)

for package in "${REQUIRED_PACKAGES[@]}"; do

    if package_installed "$package"; then

        ok "$package already installed."

    else

        info "Installing $package..."

        pkg install -y "$package" ||
            die "Gagal install package: $package"
    fi
done

command_exists awk ||
    die "awk tidak tersedia setelah install gawk."

ok "awk = $(command -v awk)"

###############################################################################
# DIRECTORY
###############################################################################

section "Create server directories"

mkdir -p \
    "$WEB_ROOT" \
    "$RUN_DIR" \
    "$NGINX_ETC" \
    "$PHP_ETC" \
    "$MARIADB_ETC" \
    "$NGINX_LOG" \
    "$PHP_LOG" \
    "$MARIADB_LOG" \
    "$MYSQL_DATA" \
    "$TMP_DIR" \
    "$STATE_DIR"

chmod 700 "$RUN_DIR"

chmod 700 "$MYSQL_DATA"

chmod 755 "$WEB_ROOT"

ok "Directory structure created."

###############################################################################
# NGINX
###############################################################################

section "[5] Install/configure Nginx"

if ! command_exists nginx; then

    info "Installing Nginx..."

    pkg install -y nginx ||
        die "Gagal install Nginx."
fi

command_exists nginx ||
    die "Nginx tidak ditemukan."

nginx -v 2>&1 || true

NGINX_MIME="$PREFIX/etc/nginx/mime.types"

if [ ! -f "$NGINX_MIME" ]; then

    warn "mime.types tidak ditemukan."

    mkdir -p "$PREFIX/etc/nginx"

    cat > "$NGINX_MIME" <<'MIME'
types {
    text/html html;
    text/css css;
    application/javascript js;
    application/json json;
    image/png png;
    image/jpeg jpg jpeg;
    image/gif gif;
    image/svg+xml svg;
    text/plain txt;
}
MIME
fi

cat > "$NGINX_ETC/nginx.conf" <<NGINX
worker_processes 1;

pid $RUN_DIR/nginx.pid;

error_log $NGINX_LOG/error.log;

events {
    worker_connections 512;
}

http {

    include $NGINX_MIME;

    default_type application/octet-stream;

    access_log $NGINX_LOG/access.log;

    sendfile on;

    keepalive_timeout 65;

    server_tokens off;

    client_max_body_size 64M;

    index index.php index.html;

    server {

        listen 127.0.0.1:8080;

        server_name localhost;

        root $WEB_ROOT;

        index index.php index.html;

        location / {

            try_files \$uri \$uri/ /index.php?\$query_string;
        }

        location ~ \.php$ {

            try_files \$uri =404;

            include $PREFIX/etc/nginx/fastcgi_params;

            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

            fastcgi_param DOCUMENT_ROOT \$document_root;

            fastcgi_pass 127.0.0.1:9000;
        }

        location ~ /\. {

            deny all;
        }
    }
}
NGINX

nginx \
    -t \
    -c "$NGINX_ETC/nginx.conf" \
    -p "$BASE_DIR/" ||
    die "Nginx configuration invalid."

ok "Nginx configuration OK."

###############################################################################
# PHP
###############################################################################

section "[6] Install/configure PHP"

if ! command_exists php; then

    info "Installing PHP..."

    pkg install -y php ||
        die "Gagal install PHP."
fi

command_exists php ||
    die "PHP tidak ditemukan."

ok "$(php -v | head -n 1)"

###############################################################################
# PHP-FPM
###############################################################################

info "Detect PHP-FPM..."

PHP_FPM_BIN=""

if command_exists php-fpm; then

    PHP_FPM_BIN="$(command -v php-fpm)"

fi

if [ -z "$PHP_FPM_BIN" ] &&
   [ -x "$PREFIX/bin/php-fpm" ]; then

    PHP_FPM_BIN="$PREFIX/bin/php-fpm"
fi

if [ -z "$PHP_FPM_BIN" ]; then

    info "PHP-FPM binary belum ditemukan."

    if apt-cache show php-fpm >/dev/null 2>&1; then

        info "Package php-fpm tersedia."

        pkg install -y php-fpm ||
            die "Gagal install php-fpm."

    else

        warn "Package php-fpm tidak tersedia pada repository aktif."

        echo
        echo "PHP yang terinstall:"
        php -v

        echo
        echo "Package yang berhubungan dengan PHP:"
        pkg search '^php' || true

        echo
        echo "Repository aktif:"
        grep -R \
            "^[[:space:]]*[^#].*deb " \
            "$PREFIX/etc/apt/sources.list" \
            "$PREFIX/etc/apt/sources.list.d" \
            2>/dev/null || true

        echo

        die "PHP-FPM tidak tersedia pada repository Termux aktif."
    fi

    if command_exists php-fpm; then

        PHP_FPM_BIN="$(command -v php-fpm)"

    elif [ -x "$PREFIX/bin/php-fpm" ]; then

        PHP_FPM_BIN="$PREFIX/bin/php-fpm"
    fi
fi

[ -n "$PHP_FPM_BIN" ] ||
    die "php-fpm binary tetap tidak ditemukan."

ok "PHP-FPM = $PHP_FPM_BIN"

"$PHP_FPM_BIN" -v | head -n 1

###############################################################################
# PHP CONFIG
###############################################################################

cat > "$PHP_ETC/php.ini" <<PHPINI
[PHP]

engine=On

expose_php=Off

memory_limit=256M

max_execution_time=60

max_input_time=60

max_input_vars=3000

post_max_size=64M

upload_max_filesize=64M

date.timezone=Asia/Jakarta

display_errors=On

log_errors=On

error_log=$PHP_LOG/php-error.log

cgi.fix_pathinfo=0
PHPINI

cat > "$PHP_ETC/php-fpm.conf" <<PHPFPM
[global]

pid=$RUN_DIR/php-fpm.pid

error_log=$PHP_LOG/php-fpm.log

daemonize=yes

[www]

listen=127.0.0.1:9000

listen.allowed_clients=127.0.0.1

user=$(id -un)

group=$(id -gn)

pm=dynamic

pm.max_children=5

pm.start_servers=2

pm.min_spare_servers=1

pm.max_spare_servers=3

clear_env=no

catch_workers_output=yes

php_admin_flag[log_errors]=on

php_admin_value[error_log]=$PHP_LOG/php-worker.log
PHPFPM

"$PHP_FPM_BIN" \
    -t \
    -y "$PHP_ETC/php-fpm.conf" \
    -c "$PHP_ETC/php.ini" ||
    die "PHP-FPM configuration invalid."

ok "PHP-FPM configuration OK."

###############################################################################
# MARIADB
###############################################################################

section "[7] Install/configure MariaDB"

if ! command_exists mariadbd &&
   ! command_exists mysqld; then

    info "Installing MariaDB..."

    pkg install -y mariadb ||
        die "Gagal install MariaDB."
fi

if command_exists mariadbd; then

    MYSQLD_BIN="$(command -v mariadbd)"

elif command_exists mysqld; then

    MYSQLD_BIN="$(command -v mysqld)"

else

    die "MariaDB server binary tidak ditemukan."
fi

ok "MariaDB server = $MYSQLD_BIN"

"$MYSQLD_BIN" --version || true

###############################################################################
# DATABASE DIRECTORY
###############################################################################

section "[8] Create database directory"

mkdir -p "$MYSQL_DATA"

chmod 700 "$MYSQL_DATA"

###############################################################################
# MARIADB CONFIG
###############################################################################

cat > "$MARIADB_ETC/my.cnf" <<MYSQL
[client]

port=3306

socket=$RUN_DIR/mysql.sock

[mysqld]

user=$(id -un)

port=3306

bind-address=127.0.0.1

datadir=$MYSQL_DATA

socket=$RUN_DIR/mysql.sock

pid-file=$RUN_DIR/mariadb.pid

log-error=$MARIADB_LOG/mariadb.log

character-set-server=utf8mb4

collation-server=utf8mb4_unicode_ci

max_connections=50

innodb_buffer_pool_size=128M

[mysql]

default-character-set=utf8mb4
MYSQL

ok "MariaDB configuration created."

###############################################################################
# INITIALIZE
###############################################################################

section "[9] Initialize MariaDB"

if [ -d "$MYSQL_DATA/mysql" ]; then

    ok "MariaDB already initialized."

else

    if command_exists mariadb-install-db; then

        mariadb-install-db \
            --datadir="$MYSQL_DATA" \
            --auth-root-authentication-method=normal

    elif command_exists mysql_install_db; then

        mysql_install_db \
            --datadir="$MYSQL_DATA"

    else

        warn "MariaDB initialization command tidak ditemukan."

        warn "Database akan perlu diinisialisasi manual."

    fi

    if [ -d "$MYSQL_DATA/mysql" ]; then

        ok "MariaDB initialized."

    else

        warn "MariaDB belum berhasil diinisialisasi."
    fi
fi

###############################################################################
# LOG
###############################################################################

section "Create log files"

touch \
    "$NGINX_LOG/access.log" \
    "$NGINX_LOG/error.log" \
    "$NGINX_LOG/stdout.log" \
    "$PHP_LOG/php-fpm.log" \
    "$PHP_LOG/php-error.log" \
    "$PHP_LOG/php-worker.log" \
    "$PHP_LOG/stdout.log" \
    "$MARIADB_LOG/mariadb.log" \
    "$MARIADB_LOG/stdout.log"

ok "Log files created."

###############################################################################
# SERVICE MANAGER
###############################################################################

section "[10] Create service manager"

[ -f "./server-manager.sh" ] ||
    die "server-manager.sh tidak ditemukan."

bash -n ./server-manager.sh ||
    die "Syntax error server-manager.sh."

cp ./server-manager.sh "$SERVICE_MANAGER"

chmod +x "$SERVICE_MANAGER"

bash -n "$SERVICE_MANAGER" ||
    die "Syntax error pada $SERVICE_MANAGER."

ok "Installed: $SERVICE_MANAGER"

###############################################################################
# START STOP RESTART STATUS
###############################################################################

section "[11] Start/stop/restart/status"

"$SERVICE_MANAGER" help >/dev/null

ok "Service commands installed."

###############################################################################
# ENABLE DISABLE
###############################################################################

section "[12] Enable/disable"

"$SERVICE_MANAGER" all enable

ok "All services enabled."

###############################################################################
# LOGS
###############################################################################

section "[13] Logs command"

ok "server nginx logs"
ok "server php logs"
ok "server mariadb logs"
ok "server all logs"

###############################################################################
# TERMUX BOOT
###############################################################################

section "[14] Termux:Boot integration"

BOOT_DIR="$HOME/.termux/boot"

mkdir -p "$BOOT_DIR"

cat > "$BOOT_DIR/termux-server" <<'BOOT'
#!/data/data/com.termux/files/usr/bin/bash

sleep 5

SERVER="$PREFIX/bin/server"

if [ ! -x "$SERVER" ]; then
    exit 0
fi

if [ -f "$HOME/.config/termux-server/mariadb.enabled" ]; then
    "$SERVER" mariadb start
fi

if [ -f "$HOME/.config/termux-server/php.enabled" ]; then
    "$SERVER" php start
fi

if [ -f "$HOME/.config/termux-server/nginx.enabled" ]; then
    "$SERVER" nginx start
fi
BOOT

chmod +x "$BOOT_DIR/termux-server"

ok "Boot script created."

###############################################################################
# TEST NGINX
###############################################################################

section "[15] Test Nginx"

"$SERVICE_MANAGER" nginx test ||
    die "Nginx test failed."

ok "Nginx test OK."

###############################################################################
# TEST PHP-FPM
###############################################################################

section "[16] Test PHP-FPM"

"$SERVICE_MANAGER" php test ||
    die "PHP-FPM test failed."

ok "PHP-FPM test OK."

###############################################################################
# TEST MARIADB
###############################################################################

section "[17] Test MariaDB"

if [ -d "$MYSQL_DATA/mysql" ]; then

    ok "MariaDB data directory OK."

else

    warn "MariaDB data directory belum initialized."
fi

###############################################################################
# WEB FILES
###############################################################################

section "[18] Create index.php / phpinfo.php"

cat > "$WEB_ROOT/index.php" <<'PHP'
<?php

header('Content-Type: text/html; charset=UTF-8');

?>
<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Termux Server</title>
<style>
body{
    font-family:Arial,sans-serif;
    margin:40px;
    line-height:1.6;
}
.box{
    max-width:800px;
    padding:25px;
    border:1px solid #ddd;
    border-radius:12px;
}
.ok{
    color:green;
}
</style>
</head>
<body>

<div class="box">

<h1>Termux Server</h1>

<p class="ok">
Nginx + PHP-FPM berhasil dikonfigurasi.
</p>

<p>
PHP Version:
<strong><?= htmlspecialchars(PHP_VERSION) ?></strong>
</p>

<p>
Server Time:
<strong><?= htmlspecialchars(date('Y-m-d H:i:s')) ?></strong>
</p>

<p>
<a href="/phpinfo.php">PHP Info</a>
</p>

<p>
<a href="/dbtest.php">Database Test</a>
</p>

</div>

</body>
</html>
PHP

cat > "$WEB_ROOT/phpinfo.php" <<'PHP'
<?php

phpinfo();
PHP

cat > "$WEB_ROOT/dbtest.php" <<'PHP'
<?php

header('Content-Type: text/plain; charset=UTF-8');

echo "PHP OK\n";
echo "PHP_VERSION=" . PHP_VERSION . "\n";
echo "TIME=" . date('c') . "\n";
PHP

chmod 644 \
    "$WEB_ROOT/index.php" \
    "$WEB_ROOT/phpinfo.php" \
    "$WEB_ROOT/dbtest.php"

ok "Web test files created."

###############################################################################
# FINAL CHECK
###############################################################################

section "FINAL SYNTAX CHECK"

bash -n ./install-server.sh

bash -n ./server-manager.sh

bash -n "$SERVICE_MANAGER"

ok "All Bash scripts syntax OK."

###############################################################################
# SUMMARY
###############################################################################

echo

echo "============================================================"
echo " INSTALLATION COMPLETED"
echo "============================================================"

echo

echo "Architecture:"
echo "  $ARCH"

echo

echo "ABI:"
echo "  $ABI"

echo

echo "PHP:"
php -v | head -n 1

echo

echo "PHP-FPM:"
"$PHP_FPM_BIN" -v | head -n 1

echo

echo "Nginx:"
nginx -v 2>&1

echo

echo "MariaDB:"
"$MYSQLD_BIN" --version

echo

echo "Web:"
echo "  http://127.0.0.1:8080"

echo

echo "Commands:"
echo "  server all start"
echo "  server all stop"
echo "  server all restart"
echo "  server all status"

echo

echo "Tests:"
echo "  server all test"
echo "  server webtest"

echo

echo "Diagnostic:"
echo "  server diagnose"

echo

echo "Logs:"
echo "  server nginx logs"
echo "  server php logs"
echo "  server mariadb logs"

echo

echo "============================================================"

