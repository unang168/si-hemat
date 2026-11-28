## Si-Hemat v1.2.0 — Import Mutasi Rekening (PDF 1 Bulan & Multi-Screenshot m-Banking)

Fitur baru untuk merekap puluhan hingga ratusan transaksi mutasi rekening secara otomatis menggunakan **Gemini** maupun **9Router**, dengan pemisahan aman antara dompet **Keluarga** dan **Pribadi**. Dapat langsung di-install di atas versi sebelumnya tanpa kehilangan data.

### Fitur Baru
- **Import Mutasi PDF 1 Bulan (Berpassword & Non-Password):**
  - Mendeteksi otomatis apakah file PDF e-Statement bank terkunci password; jika terkunci, menampilkan dialog input password **100% lokal di HP** (password tidak pernah dikirim ke server AI).
  - Merender halaman PDF secara lokal dan memproses halaman demi halaman dengan *progress bar*, kompatibel penuh dengan **Gemini** maupun **9Router**.
- **Import Multi-Screenshot Mutasi Harian / Mingguan:**
  - Pilih **1–10 screenshot scroll m-banking** sekaligus (mis. Livin' Mandiri, BCA mobile, BRImo, Jago, e-Wallet) atau foto kamera.
  - Prompt OCR khusus mutasi bank Indonesia: mengabaikan baris terpotong di tepi gambar, membuang desimal sen `,00` / superscript `⁰⁰` (`- Rp 50.000⁰⁰ → Rp 50.000`), mengabaikan badge poin reward (`+ 1 poin`), dan mendeteksi top-up ke dompet e-wallet sendiri sebagai **Transfer**.
- **Pemilihan Dompet Aman (`[Keluarga]` vs `[Pribadi]`) + Deteksi Rekening Opsional:**
  - Pilih dompet tujuan secara eksplisit di awal (aman untuk screenshot m-banking polos tanpa nama bank/nomor rekening).
  - Tambahkan identitas opsional **Nama Bank & 4 Digit Terakhir Rekening** (terenkripsi lokal) di **Kelola Dompet** atau centang **"Ingat untuk mutasi berikutnya"** agar PDF bulan depan otomatis mengenali dompet yang cocok & memberi peringatan bila salah pilih dompet.
- **Anti-Duplikat 2 Lapis & Layar Review Massal:**
  - Otomatis menandai & menonaktifkan centang (*uncheck*) untuk transaksi yang overlap antar screenshot maupun yang sudah tercatat di SQLite.
  - Ringkasan **Total Masuk / Total Keluar / Transfer** untuk cek cepat sebelum klik **Simpan Semua Terpilih**, serta edit cepat kategori/nominal/tipe per baris.
  - Pintasan otomatis dari halaman **Scan Struk** apabila terdeteksi lebih dari 1 transaksi dalam gambar.

### File Unduhan
- **`Si-Hemat-v1.2.0-arm64-v8a.apk`** — Untuk HP Android 64-bit & emulator Apple Silicon (`arm64-v8a`).
- **`SHA256SUMS.txt`** — Checksum SHA-256 verifikasi file APK.
