## Si-Hemat v1.1.3 — Dukungan Berbagi Konfigurasi AI 9Router & Gemini via QR Undangan Keluarga

Revisi halaman **Undang Keluarga (QR)** agar mendukung berbagi konfigurasi BYOK **9Router** maupun **Gemini** secara otomatis ke HP anggota keluarga saat bergabung. Dapat langsung di-install di atas versi sebelumnya tanpa kehilangan data.

### Yang Diperbarui
- **Berbagi Konfigurasi BYOK 9Router via QR Undangan:** Saat Admin menggunakan **9Router** dan mengaktifkan toggle **Sertakan Konfigurasi AI (9Router) dalam QR**, QR undangan otomatis menyertakan provider aktif, Base URL, API Key (jika ada), serta model/Combo 9Router sehingga HP pasangan langsung siap pakai tanpa setting ulang.
- **Dukungan Gemini & Kompatibilitas QR Lama:** Jika Admin menggunakan **Gemini**, QR ikut menyertakan API Key dan model Gemini aktif. QR undangan dari versi lama (`v1.0.0–v1.1.2`) tetap terbaca penuh.
- **Peringatan Otomatis `localhost` / `127.0.0.1`:** Halaman Undang Keluarga otomatis memberi peringatan jika Base URL 9Router memakai `localhost` atau `127.0.0.1` agar pengguna menggantinya ke IP LAN (mis. `http://192.168.x.x:20128`) atau domain publik sebelum dibagikan ke HP pasangan.
- **Badge Status AI pada Kartu QR:** Menampilkan ringkasan konfigurasi AI yang disertakan pada QR saat toggle diaktifkan.

### File Unduhan
- **`Si-Hemat-v1.1.3-arm64-v8a.apk`** — Untuk HP Android 64-bit & emulator Apple Silicon (`arm64-v8a`).
- **`SHA256SUMS.txt`** — Checksum SHA-256 verifikasi file APK.
