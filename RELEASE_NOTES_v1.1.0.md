## Si-Hemat v1.1.0 — Dukungan BYOK 9Router & Notifikasi Tagihan Background (H-2 & Hari-H)

Pembaruan **v1.1.0** dapat langsung di-install di atas `v1.0.0` (ditandatangani *release keystore* yang sama — seluruh data lokal Anda tetap aman).

### Apa yang Baru di v1.1.0
1. **Dukungan BYOK 9Router (OpenAI-Compatible) Selain Gemini:**
   - Pilih penyedia AI di **Pengaturan AI (BYOK)**: **Gemini (Gratis)** atau **9Router (OpenAI)** — kredensial masing-masing tersimpan terpisah sehingga bebas berpindah tanpa input ulang.
   - Mendukung Base URL lokal/LAN (`http://<IP_PC>:20128/v1`) maupun domain HTTPS, Master API Key (`Authorization: Bearer`), tombol **Muat Daftar Model / Combo (`/v1/models`)**, fallback otomatis JSON untuk model beragam, pembersihan tag `<think>`, serta multimodal Vision untuk Scan Struk.
2. **Notifikasi Tagihan di HP Saat Aplikasi Tertutup (H-2 & Hari-H):**
   - Penjadwalan notifikasi Android 100% offline (*tetap muncul meski aplikasi tertutup & tahan restart HP*) pada **2 hari sebelum jatuh tempo (H-2)** dan **tepat hari jatuh tempo (Hari-H)**.
   - Otomatis dijadwalkan ulang saat menambah/mengubah/membayar/menghentikan tagihan, setelah Sync Wi-Fi, maupun setelah Restore Backup (tagihan yang sudah dibayar bulan ini tidak akan memunculkan pengingat).
   - Dilengkapi pengaturan **Aktif/Nonaktif**, **Jam Notifikasi** (`07:00`–`19:00`), dan tombol **Kirim Notifikasi Tes Sekarang** di menu **Pengaturan & Keamanan**.

### File Unduhan
- **`Si-Hemat-v1.1.0-arm64-v8a.apk`** — Disarankan untuk HP Android modern 64-bit (Samsung, Xiaomi, Oppo, Vivo, Pixel, dll.).
- **`SHA256SUMS.txt`** — Checksum SHA-256 verifikasi file APK.
