# Panduan & Aset Publikasi Google Play Store — Si-Hemat

Seluruh konfigurasi rilis teknis (`targetSdk = 36`, upload keystore, `.aab` signed release, ikon `512×512`, feature graphic `1024×500`, dan `privacy-policy.html`) sudah disiapkan di proyek ini.

---

## 1. Keamanan Keystore (WAJIB BACKUP!)
- File keystore: `android/keystore/sihemat-upload-keystore.jks`
- File konfigurasi password: `android/key.properties`
- Keduanya sudah ditambahkan ke `.gitignore` agar **tidak pernah ter-commit ke Git**.
- **Wajib salin cadangan** kedua file tersebut ke Google Drive terenkripsi / Password Manager Anda. Jika keystore hilang, Anda harus meminta reset upload key di Google Play Console sebelum bisa merilis update aplikasi.

---

## 2. Hosting Gratis `privacy-policy.html` (2 Menit via GitHub Pages)
1. Buka `play_store/privacy-policy.html` dan ganti `[email-pengembang@domain.com]` dengan email aktif Anda.
2. Buat repository publik baru di GitHub (misal `si-hemat-privacy`), upload `privacy-policy.html` sebagai `index.html`.
3. Buka **Settings → Pages → Source: Deploy from a branch (`main` / `root`) → Save**.
4. Salin URL publiknya (misal `https://<username>.github.io/si-hemat-privacy/`) dan tempel di Google Play Console → **App Content → Privacy Policy**.

---

## 3. Teks Store Listing (Siap Copy-Paste)

### Bahasa Indonesia (Default)
- **App Name (maks 30 karakter):**
  `Si-Hemat: Keuangan Keluarga AI`
- **Short Description (maks 80 karakter):**
  `Catat keuangan keluarga 100% offline, sync Wi-Fi terenkripsi & asisten AI.`
- **Full Description:**
  ```text
  Si-Hemat adalah asisten pencatatan & laporan keuangan pribadi dan keluarga yang 100% offline-first, cepat, privat, dan dilengkapi asisten AI opsional.

  FITUR UTAMA:
  • 100% Offline & Privat: Seluruh data tersimpan lokal di HP Anda tanpa server cloud dan tanpa wajib login.
  • Mode Keluarga & Pribadi: Pisahkan dompet/transaksi bersama keluarga dengan dompet pribadi Anda dalam satu aplikasi.
  • Multi-Dompet & Transfer Akurat: Kelola Kas, Rekening Bank, E-Wallet, dan Kartu Kredit tanpa hitungan ganda saat transfer.
  • Safe-to-Spend Harian: Hitung batas belanja aman harian menuju tanggal gajian berikutnya (mendukung tanggal 1–31/akhir bulan & otomatis maju ke Jumat bila akhir pekan).
  • Anggaran Bulanan & Tagihan Rutin: Pantau realisasi anggaran per kategori, pengingat tagihan H-3, serta dukungan tenor cicilan dengan riwayat lunas yang aman.
  • Laporan Grafik Interaktif & Export: Grafik donut pengeluaran, tren arus kas 6 bulan, rincian transaksi per kategori, serta export PDF & CSV.
  • Sinkronisasi Wi-Fi Keluarga (Terenkripsi): Gabungkan catatan keluarga antar HP pasangan/keluarga lewat Wi-Fi rumah dengan enkripsi AES-256-GCM (data Pribadi tetap lokal).
  • Asisten Gemini AI Opsional (BYOK Gratis): Catat transaksi lewat chat santai, scan struk/screenshot QRIS, dan tanya evaluasi laporan keuangan memakai API Key Google AI Studio gratis Anda sendiri.
  • Keamanan & Backup Terenkripsi: Kunci aplikasi dengan PIN 6 digit + Biometrik (sidik jari) serta backup/restore penuh file terenkripsi (.sihemat).
  ```

### English (Opsional)
- **App Name:** `Si-Hemat: Offline Family Budget`
- **Short Description:** `100% offline-first family finance tracker with encrypted Wi-Fi sync & AI.`

---

## 4. Jawaban Formulir Kepatuhan (*App Content* di Play Console)

| Menu di Play Console | Pengaturan yang Disarankan |
|---|---|
| **Privacy Policy** | Masukkan URL `privacy-policy.html` dari GitHub Pages |
| **App Access** | *All functionality is available without special access* (tambahkan catatan bahwa fitur AI opsional memakai Google AI Studio API Key pengguna) |
| **Ads** | *No, my app does not contain ads* |
| **Content Rating (IARC)** | Kategori *Utility / Productivity / Finance* — jawab *No* untuk kekerasan, judi, konten dewasa → rating **Everyone / 3+** |
| **Target Audience** | Pilih **18 and over** (atau **13–15, 16–17, 18+**) agar tidak masuk *Families Policy* khusus anak |
| **Data Safety** | *Does your app collect or share any of the required user data types?* → **No** (tidak ada server pengembang; fitur AI opsional langsung ke Google Gemini API memakai API Key pengguna sendiri) |
| **Financial Features** | Pilih **My app doesn't provide any financial features** *(catatan: Google Play Financial Features hanya untuk layanan bank, pinjaman/BNPL, transfer uang riil, kripto, asuransi, atau broker investasi — aplikasi pencatatan manual/budgeting offline tidak termasuk layanan keuangan berizin)* |
| **Government Apps** | **No** |

---

## 5. Daftar File Aset Siap Unggah
- **App Bundle (`.aab`):** `build/app/outputs/bundle/release/app-release.aab`
- **Hi-Res App Icon (`512×512`):** `play_store/icon_512x512.png`
- **Feature Graphic (`1024×500`):** `play_store/feature_graphic_1024x500.png`
- **Screenshot HP (2–8 gambar):** Ambil screenshot layar Beranda, Catat Transaksi, Anggaran/Tagihan, Laporan Grafik, dan Sync Wi-Fi dari HP Anda (Samsung A35) atau emulator.

---

## 6. Alur Rilis & Syarat Akun Pribadi (12 Tester / 14 Hari)
1. Daftar di https://play.google.com/console (biaya pendaftaran **sekali bayar $25 USD**).
2. Buat aplikasi → unggah `app-release.aab` ke jalur **Closed Testing**.
3. Undang minimal **12 tester** (email Gmail keluarga/teman) untuk opt-in & meng-install selama **14 hari berturut-turut**.
4. Setelah 14 hari selesai, klik **Apply for Production** → tunggu persetujuan Google (1–7 hari) → aplikasi resmi tayang di Google Play Store!
5. Untuk setiap update berikutnya, naikkan `version:` di `pubspec.yaml` (mis. `1.0.0+1` → `1.0.1+2`) lalu jalankan:
   ```bash
   docker compose exec -T -w /workspace/si_hemat flutter \
     flutter build appbundle --release
   ```
