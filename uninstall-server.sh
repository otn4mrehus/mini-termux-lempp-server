#!/data/data/com.termux/files/usr/bin/bash

set -u

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"

BASE_DIR="$HOME/server"
STATE_DIR="$HOME/.config/termux-server"
BOOT_SCRIPT="$HOME/.termux/boot/termux-server"

SERVER="$PREFIX/bin/server"

echo
echo "=================================================="
echo " Termux Server Uninstaller"
echo "=================================================="
echo

echo "Script ini akan menghapus:"
echo
echo "  $BASE_DIR"
echo "  $STATE_DIR"
echo "  $BOOT_SCRIPT"
echo "  $SERVER"
echo

printf "Lanjutkan? [y/N]: "

read -r answer

case "$answer" in

    y|Y|yes|YES)

        ;;

    *)

        echo "Dibatalkan."

        exit 0

        ;;
esac

if [ -x "$SERVER" ]; then

    "$SERVER" all stop >/dev/null 2>&1 || true

fi

rm -rf "$BASE_DIR"

rm -rf "$STATE_DIR"

rm -f "$BOOT_SCRIPT"

rm -f "$SERVER"

echo
echo "Server configuration removed."
echo
echo "Catatan:"
echo "Package Nginx/PHP/MariaDB TIDAK dihapus."
echo
echo "Jika ingin menghapus package:"
echo
echo "  pkg uninstall nginx"
echo "  pkg uninstall php"
echo "  pkg uninstall mariadb"
echo

