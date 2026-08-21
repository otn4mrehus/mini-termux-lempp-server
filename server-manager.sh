#!/data/data/com.termux/files/usr/bin/bash

###############################################################################
# Termux Server Manager
#
# Nginx
# PHP-FPM
# MariaDB
#
# No root
# No systemctl
###############################################################################

set -u

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

NGINX_CONF="$NGINX_ETC/nginx.conf"
PHP_FPM_CONF="$PHP_ETC/php-fpm.conf"
PHP_INI="$PHP_ETC/php.ini"
MYSQL_CONF="$MARIADB_ETC/my.cnf"

NGINX_PID="$RUN_DIR/nginx.pid"
PHP_PID="$RUN_DIR/php-fpm.pid"
MARIADB_PID="$RUN_DIR/mariadb.pid"

MYSQL_SOCKET="$RUN_DIR/mysql.sock"

NGINX_PORT="${NGINX_PORT:-8080}"
PHP_FPM_PORT="${PHP_FPM_PORT:-9000}"
MARIADB_PORT="${MARIADB_PORT:-3306}"

###############################################################################
# COLORS
###############################################################################

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'

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

error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

pid_is_running() {

    local pidfile="$1"

    [ -f "$pidfile" ] || return 1

    local pid

    pid="$(cat "$pidfile" 2>/dev/null || true)"

    [ -n "$pid" ] || return 1

    kill -0 "$pid" 2>/dev/null
}

remove_stale_pid() {

    local pidfile="$1"

    if [ -f "$pidfile" ] &&
       ! pid_is_running "$pidfile"; then

        rm -f "$pidfile"
    fi
}

get_mariadb_binary() {

    if command_exists mariadbd; then
        command -v mariadbd
        return 0
    fi

    if command_exists mysqld; then
        command -v mysqld
        return 0
    fi

    return 1
}

get_php_fpm_binary() {

    if command_exists php-fpm; then
        command -v php-fpm
        return 0
    fi

    if [ -x "$PREFIX/bin/php-fpm" ]; then
        echo "$PREFIX/bin/php-fpm"
        return 0
    fi

    return 1
}

###############################################################################
# NGINX
###############################################################################

nginx_test() {

    command_exists nginx ||
        return 1

    nginx \
        -t \
        -c "$NGINX_CONF" \
        -p "$BASE_DIR/"
}

nginx_start() {

    if ! command_exists nginx; then
        error "Nginx belum terinstall."
        return 1
    fi

    remove_stale_pid "$NGINX_PID"

    if pid_is_running "$NGINX_PID"; then
        ok "Nginx sudah berjalan."
        return 0
    fi

    if ! nginx_test; then
        error "Konfigurasi Nginx tidak valid."
        return 1
    fi

    nginx \
        -c "$NGINX_CONF" \
        -p "$BASE_DIR/" \
        >> "$NGINX_LOG/stdout.log" 2>&1

    sleep 1

    if pid_is_running "$NGINX_PID"; then
        ok "Nginx started."
        return 0
    fi

    error "Nginx gagal start."

    tail -n 50 "$NGINX_LOG/error.log" 2>/dev/null || true

    return 1
}

nginx_stop() {

    if ! pid_is_running "$NGINX_PID"; then

        rm -f "$NGINX_PID"

        warn "Nginx tidak sedang berjalan."

        return 0
    fi

    nginx \
        -c "$NGINX_CONF" \
        -p "$BASE_DIR/" \
        -s quit >/dev/null 2>&1 || true

    local i

    for i in $(seq 1 20); do

        if ! pid_is_running "$NGINX_PID"; then
            break
        fi

        sleep 0.25
    done

    rm -f "$NGINX_PID"

    ok "Nginx stopped."
}

nginx_restart() {

    nginx_stop

    sleep 1

    nginx_start
}

nginx_status() {

    if pid_is_running "$NGINX_PID"; then

        echo "Nginx      : RUNNING"
        echo "PID        : $(cat "$NGINX_PID")"
        echo "HTTP       : 127.0.0.1:$NGINX_PORT"

    else

        echo "Nginx      : STOPPED"
    fi
}

###############################################################################
# PHP-FPM
###############################################################################

php_test() {

    local fpm

    fpm="$(get_php_fpm_binary)" ||
        return 1

    "$fpm" \
        -t \
        -y "$PHP_FPM_CONF" \
        -c "$PHP_INI"
}

php_start() {

    local fpm

    fpm="$(get_php_fpm_binary)" || {

        error "PHP-FPM tidak ditemukan."

        echo
        echo "Coba:"
        echo "  pkg search php-fpm"
        echo "  pkg install php-fpm"

        return 1
    }

    remove_stale_pid "$PHP_PID"

    if pid_is_running "$PHP_PID"; then
        ok "PHP-FPM sudah berjalan."
        return 0
    fi

    if ! php_test; then
        error "Konfigurasi PHP-FPM tidak valid."
        return 1
    fi

    "$fpm" \
        -y "$PHP_FPM_CONF" \
        -c "$PHP_INI" \
        >> "$PHP_LOG/stdout.log" 2>&1

    sleep 1

    if pid_is_running "$PHP_PID"; then
        ok "PHP-FPM started."
        return 0
    fi

    error "PHP-FPM gagal start."

    tail -n 50 "$PHP_LOG/php-fpm.log" 2>/dev/null || true

    return 1
}

php_stop() {

    if ! pid_is_running "$PHP_PID"; then

        rm -f "$PHP_PID"

        warn "PHP-FPM tidak sedang berjalan."

        return 0
    fi

    local pid

    pid="$(cat "$PHP_PID")"

    kill -QUIT "$pid" 2>/dev/null || true

    local i

    for i in $(seq 1 20); do

        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi

        sleep 0.25
    done

    rm -f "$PHP_PID"

    ok "PHP-FPM stopped."
}

php_restart() {

    php_stop

    sleep 1

    php_start
}

php_status() {

    if pid_is_running "$PHP_PID"; then

        echo "PHP-FPM    : RUNNING"
        echo "PID        : $(cat "$PHP_PID")"

    else

        echo "PHP-FPM    : STOPPED"
    fi
}

###############################################################################
# MARIADB
###############################################################################

mariadb_test() {

    local mysqld

    mysqld="$(get_mariadb_binary)" ||
        return 1

    "$mysqld" \
        --defaults-extra-file="$MYSQL_CONF" \
        --datadir="$MYSQL_DATA" \
        --validate-config >/dev/null 2>&1
}

mariadb_start() {

    local mysqld

    mysqld="$(get_mariadb_binary)" || {

        error "MariaDB server tidak ditemukan."

        return 1
    }

    remove_stale_pid "$MARIADB_PID"

    if pid_is_running "$MARIADB_PID"; then
        ok "MariaDB sudah berjalan."
        return 0
    fi

    if [ ! -d "$MYSQL_DATA/mysql" ]; then

        error "Database MariaDB belum diinisialisasi."

        echo
        echo "Jalankan:"
        echo "  server mariadb init"

        return 1
    fi

    "$mysqld" \
        --defaults-extra-file="$MYSQL_CONF" \
        --datadir="$MYSQL_DATA" \
        >> "$MARIADB_LOG/stdout.log" 2>&1 &

    sleep 3

    if pid_is_running "$MARIADB_PID"; then

        ok "MariaDB started."

        return 0
    fi

    error "MariaDB gagal start."

    tail -n 80 "$MARIADB_LOG/mariadb.log" 2>/dev/null || true

    return 1
}

mariadb_stop() {

    if ! pid_is_running "$MARIADB_PID"; then

        rm -f "$MARIADB_PID"

        warn "MariaDB tidak sedang berjalan."

        return 0
    fi

    local pid

    pid="$(cat "$MARIADB_PID")"

    kill -TERM "$pid" 2>/dev/null || true

    local i

    for i in $(seq 1 40); do

        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi

        sleep 0.25
    done

    rm -f "$MARIADB_PID"

    ok "MariaDB stopped."
}

mariadb_restart() {

    mariadb_stop

    sleep 1

    mariadb_start
}

mariadb_status() {

    if pid_is_running "$MARIADB_PID"; then

        echo "MariaDB    : RUNNING"
        echo "PID        : $(cat "$MARIADB_PID")"
        echo "MYSQL      : 127.0.0.1:$MARIADB_PORT"

    else

        echo "MariaDB    : STOPPED"
    fi
}

mariadb_init() {

    if [ -d "$MYSQL_DATA/mysql" ]; then

        ok "MariaDB sudah diinisialisasi."

        return 0
    fi

    mkdir -p "$MYSQL_DATA"

    if command_exists mariadb-install-db; then

        mariadb-install-db \
            --datadir="$MYSQL_DATA" \
            --auth-root-authentication-method=normal

    elif command_exists mysql_install_db; then

        mysql_install_db \
            --datadir="$MYSQL_DATA"

    else

        error "mariadb-install-db tidak ditemukan."

        return 1
    fi

    ok "MariaDB database initialized."
}

###############################################################################
# ALL
###############################################################################

all_start() {

    echo
    info "Starting MariaDB..."

    mariadb_start || return 1

    echo
    info "Starting PHP-FPM..."

    php_start || return 1

    echo
    info "Starting Nginx..."

    nginx_start || return 1

    echo
    ok "All services started."
}

all_stop() {

    echo
    info "Stopping Nginx..."

    nginx_stop || true

    echo
    info "Stopping PHP-FPM..."

    php_stop || true

    echo
    info "Stopping MariaDB..."

    mariadb_stop || true

    echo
    ok "All services stopped."
}

all_restart() {

    all_stop

    sleep 1

    all_start
}

all_status() {

    echo
    echo "=================================================="
    echo " TERMUX SERVER STATUS"
    echo "=================================================="

    nginx_status

    echo

    php_status

    echo

    mariadb_status

    echo
}

all_test() {

    local result=0

    echo
    echo "===== NGINX ====="

    nginx_test || result=1

    echo
    echo "===== PHP-FPM ====="

    php_test || result=1

    echo
    echo "===== MARIADB ====="

    mariadb_test || result=1

    echo

    return "$result"
}

###############################################################################
# ENABLE / DISABLE
###############################################################################

enable_service() {

    mkdir -p "$STATE_DIR"

    case "$1" in

        nginx)
            touch "$STATE_DIR/nginx.enabled"
            ;;

        php)
            touch "$STATE_DIR/php.enabled"
            ;;

        mariadb)
            touch "$STATE_DIR/mariadb.enabled"
            ;;

        all)
            touch \
                "$STATE_DIR/nginx.enabled" \
                "$STATE_DIR/php.enabled" \
                "$STATE_DIR/mariadb.enabled"
            ;;

        *)
            error "Unknown service: $1"
            return 1
            ;;
    esac

    ok "$1 enabled."
}

disable_service() {

    case "$1" in

        nginx)
            rm -f "$STATE_DIR/nginx.enabled"
            ;;

        php)
            rm -f "$STATE_DIR/php.enabled"
            ;;

        mariadb)
            rm -f "$STATE_DIR/mariadb.enabled"
            ;;

        all)
            rm -f \
                "$STATE_DIR/nginx.enabled" \
                "$STATE_DIR/php.enabled" \
                "$STATE_DIR/mariadb.enabled"
            ;;

        *)
            error "Unknown service: $1"
            return 1
            ;;
    esac

    ok "$1 disabled."
}

###############################################################################
# LOGS
###############################################################################

logs_service() {

    case "$1" in

        nginx)
            tail -f "$NGINX_LOG/error.log"
            ;;

        php)
            tail -f "$PHP_LOG/php-fpm.log"
            ;;

        mariadb)
            tail -f "$MARIADB_LOG/mariadb.log"
            ;;

        all)

            tail -f \
                "$NGINX_LOG/error.log" \
                "$PHP_LOG/php-fpm.log" \
                "$MARIADB_LOG/mariadb.log"

            ;;

        *)
            error "Unknown service: $1"
            return 1
            ;;
    esac
}

###############################################################################
# DIAGNOSTIC
###############################################################################

diagnose() {

    echo
    echo "=================================================="
    echo " TERMUX SERVER DIAGNOSTIC"
    echo "=================================================="

    echo
    echo "[SYSTEM]"

    echo "Architecture : $(uname -m)"

    if command_exists getprop; then

        echo "Android      : $(getprop ro.build.version.release 2>/dev/null || true)"

    fi

    echo "PREFIX       : $PREFIX"
    echo "HOME         : $HOME"

    echo
    echo "[TERMUX]"

    if command_exists termux-info; then

        termux-info 2>/dev/null | head -40

    fi

    echo
    echo "[NGINX]"

    if command_exists nginx; then
        nginx -v 2>&1
    else
        echo "NOT INSTALLED"
    fi

    echo
    echo "[PHP]"

    if command_exists php; then
        php -v | head -n 1
    else
        echo "NOT INSTALLED"
    fi

    echo
    echo "[PHP-FPM]"

    if fpm="$(get_php_fpm_binary 2>/dev/null)"; then
        "$fpm" -v | head -n 1
    else
        echo "NOT FOUND"
    fi

    echo
    echo "[MARIADB]"

    if mysqld="$(get_mariadb_binary 2>/dev/null)"; then
        "$mysqld" --version
    else
        echo "NOT FOUND"
    fi

    echo
    echo "[PATHS]"

    echo "BASE        : $BASE_DIR"
    echo "WEB         : $WEB_ROOT"
    echo "MYSQL       : $MYSQL_DATA"
    echo "RUN         : $RUN_DIR"
    echo "LOG         : $LOG_DIR"

    echo
    echo "[PROCESSES]"

    ps -ef 2>/dev/null |
        grep -E 'nginx|php-fpm|mariadbd|mysqld' |
        grep -v grep || true

    echo
}

###############################################################################
# WEB TEST
###############################################################################

web_test() {

    if ! command_exists curl; then

        error "curl belum tersedia."

        return 1
    fi

    curl \
        --silent \
        --show-error \
        --fail \
        "http://127.0.0.1:$NGINX_PORT/" \
        >/dev/null

    ok "HTTP test OK."
}

###############################################################################
# HELP
###############################################################################

usage() {

    cat <<'HELP'

==========================================================
 Termux Server Manager
==========================================================

SERVICES:

  nginx
  php
  mariadb
  all

ACTIONS:

  start
  stop
  restart
  status
  enable
  disable
  logs
  test

MariaDB:

  init

OTHER:

  diagnose
  webtest
  help

EXAMPLES:

  server all start
  server all stop
  server all restart
  server all status

  server nginx start
  server nginx stop
  server nginx restart
  server nginx status
  server nginx test
  server nginx logs

  server php start
  server php stop
  server php restart
  server php status
  server php test

  server mariadb init
  server mariadb start
  server mariadb stop
  server mariadb restart
  server mariadb status
  server mariadb test

  server all enable
  server all disable

  server all test

  server diagnose

  server webtest

==========================================================

HELP
}

###############################################################################
# MAIN
###############################################################################

SERVICE="${1:-}"
ACTION="${2:-}"

if [ "$SERVICE" = "help" ] || [ -z "$SERVICE" ]; then

    usage

    exit 0
fi

case "$SERVICE:$ACTION" in

    nginx:start)
        nginx_start
        ;;

    nginx:stop)
        nginx_stop
        ;;

    nginx:restart)
        nginx_restart
        ;;

    nginx:status)
        nginx_status
        ;;

    nginx:enable)
        enable_service nginx
        ;;

    nginx:disable)
        disable_service nginx
        ;;

    nginx:logs)
        logs_service nginx
        ;;

    nginx:test)
        nginx_test
        ;;


    php:start)
        php_start
        ;;

    php:stop)
        php_stop
        ;;

    php:restart)
        php_restart
        ;;

    php:status)
        php_status
        ;;

    php:enable)
        enable_service php
        ;;

    php:disable)
        disable_service php
        ;;

    php:logs)
        logs_service php
        ;;

    php:test)
        php_test
        ;;


    mariadb:init)
        mariadb_init
        ;;

    mariadb:start)
        mariadb_start
        ;;

    mariadb:stop)
        mariadb_stop
        ;;

    mariadb:restart)
        mariadb_restart
        ;;

    mariadb:status)
        mariadb_status
        ;;

    mariadb:enable)
        enable_service mariadb
        ;;

    mariadb:disable)
        disable_service mariadb
        ;;

    mariadb:logs)
        logs_service mariadb
        ;;

    mariadb:test)
        mariadb_test
        ;;


    all:start)
        all_start
        ;;

    all:stop)
        all_stop
        ;;

    all:restart)
        all_restart
        ;;

    all:status)
        all_status
        ;;

    all:enable)
        enable_service all
        ;;

    all:disable)
        disable_service all
        ;;

    all:test)
        all_test
        ;;

    all:logs)
        logs_service all
        ;;

    diagnose:)
        diagnose
        ;;

    webtest:)
        web_test
        ;;

    *)
        usage
        exit 1
        ;;
esac

