Berikut adalah skrip utama yang menghubungkan semua komponen instalasi server Termux, manajemen layanan, tunnel Cloudflared, dan uninstall. Skrip ini dirancang sebagai satu titik masuk untuk mengelola seluruh lingkungan.

### Fitur
- **Instalasi penuh** (memanggil `install-server.sh`)
- **Manajemen layanan** (nginx, php-fpm, mariadb) via wrapper ke `server-manager.sh`
- **Manajemen tunnel Cloudflared** (start, stop, status, logs)
- **Uninstall** (memanggil `uninstall-server.sh`)
- **Diagnostik** dan **test web**
- **Help** terintegrasi

---

## Skrip Utama: `termux-main.sh`

Simpan file ini dengan nama `termux-main.sh` di direktori yang sama dengan keempat skrip lainnya (`install-server.sh`, `server-manager.sh`, `uninstall-server.sh`, `cloudflared.sh`). Beri izin eksekusi:

```bash
chmod +x termux-main.sh
```

### Isi Skrip
#### Ada lampiran
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
