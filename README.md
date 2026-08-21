Berikut adalah skrip utama yang menghubungkan semua komponen instalasi server Termux, manajemen layanan, tunnel Cloudflared, dan uninstall. Skrip ini dirancang sebagai satu titik masuk untuk mengelola seluruh lingkungan.

### Fitur
- **Instalasi penuh** (memanggil `install-server.sh`)
- **Manajemen layanan** (nginx, php-fpm, mariadb) via wrapper ke `server-manager.sh`
- **Manajemen tunnel Cloudflared** (start, stop, status, logs)
- **Uninstall** (memanggil `uninstall-server.sh`)
- **Diagnostik** dan **test web**
- **Help** terintegrasi

---

## Skrip Utama: `termux-server-ctl`

Simpan file ini dengan nama `termux-server-ctl` di direktori yang sama dengan keempat skrip lainnya (`install-server.sh`, `server-manager.sh`, `uninstall-server.sh`, `cloudflared.sh`). Beri izin eksekusi:

```bash
chmod +x termux-server-ctl
```

### Isi Skrip

```bash
#!/data/data/com.termux/files/usr/bin/bash

###############################################################################
# TERMUX SERVER CONTROL
# Titik masuk tunggal untuk instalasi, manajemen layanan, tunnel, dan uninstall
###############################################################################

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Lokasi skrip dan file pendukung
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_MANAGER="$SCRIPT_DIR/server-manager.sh"
INSTALL_SCRIPT="$SCRIPT_DIR/install-server.sh"
UNINSTALL_SCRIPT="$SCRIPT_DIR/uninstall-server.sh"
TUNNEL_SCRIPT="$SCRIPT_DIR/cloudflared.sh"

# -----------------------------------------------------------------------------
# Konfigurasi tunnel
# -----------------------------------------------------------------------------
TUNNEL_PID_FILE="$HOME/.config/termux-server/cloudflared.pid"
TUNNEL_LOG_FILE="$HOME/server/logs/cloudflared.log"
TUNNEL_TOKEN_FILE="$SCRIPT_DIR/cloudflared.sh"   # sumber token

# -----------------------------------------------------------------------------
# Warna
# -----------------------------------------------------------------------------
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'

info()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*" >&2; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# -----------------------------------------------------------------------------
# Fungsi bantu
# -----------------------------------------------------------------------------
command_exists() { command -v "$1" >/dev/null 2>&1; }

check_script() {
    local script="$1"
    [ -f "$script" ] || die "Skrip tidak ditemukan: $script"
    [ -x "$script" ] || chmod +x "$script"
}

# -----------------------------------------------------------------------------
# Ekstrak token dari cloudflared.sh
# -----------------------------------------------------------------------------
extract_tunnel_token() {
    [ -f "$TUNNEL_TOKEN_FILE" ] || die "cloudflared.sh tidak ditemukan."
    local token
    token=$(grep -oP '(?<=--token )\S+' "$TUNNEL_TOKEN_FILE" | head -1)
    [ -n "$token" ] || die "Token tidak ditemukan di cloudflared.sh"
    echo "$token"
}

# -----------------------------------------------------------------------------
# Manajemen Tunnel
# -----------------------------------------------------------------------------
tunnel_start() {
    command_exists cloudflared || die "cloudflared tidak terinstal. Jalankan: pkg install cloudflared"

    if [ -f "$TUNNEL_PID_FILE" ] && kill -0 "$(cat "$TUNNEL_PID_FILE")" 2>/dev/null; then
        ok "Tunnel sudah berjalan (PID $(cat "$TUNNEL_PID_FILE"))."
        return 0
    fi

    rm -f "$TUNNEL_PID_FILE"
    mkdir -p "$(dirname "$TUNNEL_LOG_FILE")"

    local token
    token="$(extract_tunnel_token)"

    info "Menjalankan Cloudflared tunnel..."
    nohup cloudflared tunnel run --token "$token" >> "$TUNNEL_LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$TUNNEL_PID_FILE"

    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        ok "Tunnel started (PID $pid). Log: $TUNNEL_LOG_FILE"
    else
        error "Tunnel gagal dimulai. Periksa log: $TUNNEL_LOG_FILE"
        return 1
    fi
}

tunnel_stop() {
    if [ ! -f "$TUNNEL_PID_FILE" ]; then
        warn "Tunnel tidak berjalan (PID file tidak ada)."
        return 0
    fi
    local pid
    pid="$(cat "$TUNNEL_PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
        info "Menghentikan tunnel (PID $pid)..."
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
        rm -f "$TUNNEL_PID_FILE"
        ok "Tunnel dihentikan."
    else
        warn "Tunnel tidak berjalan (PID $pid sudah mati)."
        rm -f "$TUNNEL_PID_FILE"
    fi
}

tunnel_status() {
    if [ -f "$TUNNEL_PID_FILE" ] && kill -0 "$(cat "$TUNNEL_PID_FILE")" 2>/dev/null; then
        echo "Cloudflared : RUNNING (PID $(cat "$TUNNEL_PID_FILE"))"
        echo "Log         : $TUNNEL_LOG_FILE"
    else
        echo "Cloudflared : STOPPED"
        [ -f "$TUNNEL_PID_FILE" ] && rm -f "$TUNNEL_PID_FILE"
    fi
}

tunnel_logs() {
    if [ -f "$TUNNEL_LOG_FILE" ]; then
        tail -f "$TUNNEL_LOG_FILE"
    else
        die "Log file tidak ditemukan: $TUNNEL_LOG_FILE"
    fi
}

# -----------------------------------------------------------------------------
# Wrapper untuk server-manager.sh
# -----------------------------------------------------------------------------
run_server_manager() {
    check_script "$SERVER_MANAGER"
    bash "$SERVER_MANAGER" "$@"
}

# -----------------------------------------------------------------------------
# Instalasi
# -----------------------------------------------------------------------------
cmd_install() {
    check_script "$INSTALL_SCRIPT"
    info "Memulai instalasi server..."
    bash "$INSTALL_SCRIPT"
    ok "Instalasi selesai."
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
cmd_uninstall() {
    check_script "$UNINSTALL_SCRIPT"
    info "Memulai penghapusan server..."
    # Stop tunnel terlebih dahulu
    tunnel_stop || true
    bash "$UNINSTALL_SCRIPT"
    ok "Uninstall selesai."
}

# -----------------------------------------------------------------------------
# Diagnostik & Test
# -----------------------------------------------------------------------------
cmd_diagnose() {
    run_server_manager diagnose
}

cmd_webtest() {
    run_server_manager webtest
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
show_help() {
    cat <<EOF
============================================================
 TERMUX SERVER CONTROL
============================================================

Penggunaan:
  termux-server-ctl <command> [args]

COMMANDS:

  INSTALASI / UNINSTALL
    install           Instalasi lengkap server (Nginx, PHP-FPM, MariaDB)
    uninstall         Hapus konfigurasi server (package tidak dihapus)

  MANAJEMEN LAYANAN   (sama seperti server-manager.sh)
    <service> <action>
    service: nginx | php | mariadb | all
    action : start | stop | restart | status | enable | disable | logs | test

    Contoh:
      termux-server-ctl nginx start
      termux-server-ctl all status
      termux-server-ctl mariadb logs

  TUNNEL CLOUDFLARED
    tunnel start      Jalankan tunnel di background
    tunnel stop       Hentikan tunnel
    tunnel status     Tampilkan status tunnel
    tunnel logs       Tampilkan log tunnel secara realtime

  DIAGNOSTIK
    diagnose          Tampilkan informasi sistem dan status
    webtest           Tes koneksi HTTP ke localhost:8080

  BANTUAN
    help              Tampilkan pesan ini

============================================================
EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    [ $# -eq 0 ] && { show_help; exit 0; }

    local cmd="$1"
    shift || true

    case "$cmd" in
        install)
            cmd_install
            ;;
        uninstall)
            cmd_uninstall
            ;;
        tunnel)
            case "${1:-}" in
                start)
                    tunnel_start
                    ;;
                stop)
                    tunnel_stop
                    ;;
                status)
                    tunnel_status
                    ;;
                logs)
                    tunnel_logs
                    ;;
                *)
                    error "Subcommand tunnel tidak dikenal: ${1:-}"
                    echo "Gunakan: tunnel {start|stop|status|logs}"
                    exit 1
                    ;;
            esac
            ;;
        diagnose)
            cmd_diagnose
            ;;
        webtest)
            cmd_webtest
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            # Delegasikan ke server-manager jika service + action
            if [ $# -ge 1 ]; then
                run_server_manager "$cmd" "$@"
            else
                error "Perintah tidak dikenal: $cmd"
                show_help
                exit 1
            fi
            ;;
    esac
}

main "$@"
```

---

## Cara Penggunaan

1. **Pastikan semua file** (`install-server.sh`, `server-manager.sh`, `uninstall-server.sh`, `cloudflared.sh`) berada di direktori yang sama dengan `termux-server-ctl`.

2. **Beri izin eksekusi** pada skrip utama:
   ```bash
   chmod +x termux-server-ctl
   ```

3. **Jalankan instalasi** (otomatis menjalankan `install-server.sh`):
   ```bash
   ./termux-server-ctl install
   ```

4. **Kelola layanan** (contoh):
   ```bash
   ./termux-server-ctl all start
   ./termux-server-ctl nginx status
   ./termux-server-ctl mariadb logs
   ```

5. **Kelola tunnel Cloudflared**:
   ```bash
   ./termux-server-ctl tunnel start
   ./termux-server-ctl tunnel status
   ./termux-server-ctl tunnel logs
   ./termux-server-ctl tunnel stop
   ```

6. **Diagnostik**:
   ```bash
   ./termux-server-ctl diagnose
   ./termux-server-ctl webtest
   ```

7. **Uninstall** (hentikan layanan dan hapus konfigurasi):
   ```bash
   ./termux-server-ctl uninstall
   ```

8. **Bantuan**:
   ```bash
   ./termux-server-ctl help
   ```

---

## Keuntungan

- **Satu titik masuk** – semua perintah terkonsentrasi.
- **Integrasi tunnel** – manajemen Cloudflared terpisah namun mudah digunakan.
- **Kompatibel** – tetap memanfaatkan skrip asli yang sudah dibuat.
- **Maintenance mudah** – jika ada perubahan pada skrip bawaan, skrip utama tidak perlu diubah.

Skrip utama ini akan memeriksa keberadaan dan hak eksekusi skrip pendukung, sehingga aman digunakan.
