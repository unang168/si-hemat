## Si-Hemat v1.1.2 — Alarm Pengingat Tagihan Tepat Waktu (`USE_EXACT_ALARM`)

Perbaikan lanjutan agar pengingat tagihan H-2 & Hari-H selalu muncul **tepat pada jam yang dipilih (menit `:00`)** di Android 13/14/15/16 meski aplikasi ditutup, tanpa perlu mengatur izin khusus secara manual. Dapat langsung di-install di atas versi sebelumnya tanpa kehilangan data.

### Yang Diperbaiki & Ditambahkan
- **Izin `USE_EXACT_ALARM` Otomatis di Android 13–16+:** Sebelumnya pada Android 14+, izin `SCHEDULE_EXACT_ALARM` berstatus nonaktif secara bawaan sehingga Android menunda alarm hingga rentang `+1 jam` (`inexactAllowWhileIdle`). Dengan `USE_EXACT_ALARM`, alarm `RTC_WAKEUP` kini langsung berstatus tepat waktu (`window=0`) sejak aplikasi terpasang.
- **Aturan ProGuard / R8 Khusus (`proguard-rules.pro`):** Menjaga kelas `com.dexterous.flutterlocalnotifications.**` serta metadata generik Gson `TypeToken` agar `ScheduledNotificationReceiver` tetap stabil 100% di APK release.
- **Status Jadwal Aktif & Tes Alarm Background 15 Detik:** Di **Pengaturan & Keamanan → Notifikasi Pengingat Tagihan**, kini tampil status alarm tepat waktu, tanggal/jam jadwal pengingat berikutnya, serta tombol **Tes Alarm Background (15 Detik)** untuk menguji langsung notifikasi terjadwal saat aplikasi ditutup tanpa perlu mengubah jam HP.

### File Unduhan
- **`Si-Hemat-v1.1.2-arm64-v8a.apk`** — Untuk HP Android 64-bit & emulator Apple Silicon (`arm64-v8a`).
- **`SHA256SUMS.txt`** — Checksum SHA-256 verifikasi file APK.
