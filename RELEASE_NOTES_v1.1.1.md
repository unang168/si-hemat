## Si-Hemat v1.1.1 — Perbaikan Notifikasi Android pada Release Build

Perbaikan cepat untuk bug notifikasi tidak muncul pada build release `v1.1.0`. Dapat langsung di-install di atas `v1.0.0` / `v1.1.0` tanpa kehilangan data.

### Yang Diperbaiki
- **Perbaikan Notifikasi Tidak Muncul di Release APK:** Menambahkan `android/app/src/main/res/raw/keep.xml` agar Android R8 Resource Shrinker tidak menghapus ikon notifikasi (`ic_stat_sihemat`), menambahkan fallback otomatis ke `@mipmap/ic_launcher`, serta mendaftarkan Notification Channel Android secara eksplisit dengan prioritas tinggi (suara + getar).
- **Opsi Izin Alarm Tepat Waktu (Android 14+):** Menambahkan pintasan **Izinkan Alarm Tepat Waktu** di **Pengaturan & Keamanan → Notifikasi Pengingat Tagihan** agar pengingat H-2 & Hari-H muncul tepat pada jam yang dipilih walau aplikasi tertutup.
- **Pesan Status Tes Notifikasi Lebih Jelas:** Tombol **Kirim Notifikasi Tes Sekarang** kini menampilkan pesan error yang jelas apabila izin notifikasi HP belum diaktifkan.

### File Unduhan
- **`Si-Hemat-v1.1.1-arm64-v8a.apk`** — Untuk HP Android 64-bit & emulator Apple Silicon (`arm64-v8a`).
- **`SHA256SUMS.txt`** — Checksum SHA-256 verifikasi file APK.
