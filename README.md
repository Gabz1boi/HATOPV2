# HATOP Cloud Demo | Paket ZIP konfigurasi Supabase + Vercel

**Paket pengembangan berbasis source MVP HATOP asli**, menjaga logo resmi, 23 produk referensi, CSS/halaman MVP lama dan semua fitur offline-nya. Versi cloud tersedia ketika dua variabel publik Supabase diatur di Vercel.

## Apa yang telah dibuat

| Kemampuan | Mode demo offline | Mode Supabase Cloud |
| --- | --- | --- |
| Desain MVP dan logo | Ada | Dipertahankan gaya visual |
| Katalog 23 produk & sumber web | Ada | Ada: 23 referensi, 21 listing toko demo yang bisa diorder |
| Login Google | Tidak | Implementasi OAuth PKCE, perlu konfigurasi Google + Supabase |
| Akun farmer, store, pickup, admin | Simulasi role | Role Supabase dan approval admin |
| Multi-toko dalam 1 checkout | Lama: simulasi gabungan | Ada: Parent Order + Child Order |
| Konfirmasi stok tiap toko | Simulasi | Transaksi SQL terproteksi |
| DP 50% ongkir + QRIS DEMO | Simulasi lokal | Simulasi tercatat di database, verifikasi admin |
| Pelunasan COD | Simulasi lokal | Tercatat driver + dikonfirmasi customer |
| Pooling otomatis + admin approval | Simulasi | Rekomendasi tujuan/tanggal, admin menyetujui |
| Penugasan pickup hybrid | Simulasi | Admin assign / driver claim, atomic di database |
| Update status | localStorage | Supabase database, polling 15 detik |
| Keamanan RLS | Tidak ada | Script RLS, role checks, RPC keamanan |

**QRIS dan COD hanya simulasi.** Tidak ada QR yang bisa dipakai untuk membayar dan tidak ada pencatatan uang nyata. Toko, harga dan stok dalam seed adalah **DEMO**, bukan konfirmasi dari toko Balige.

## MULAI DI SINI

Baca **`PANDUAN_MULAI_TANPA_DOCKER.md`** secara berurutan, khususnya instruksi tiga SQL dan dua Environment Variables Vercel.

### Build lokal (tidak wajib untuk konfigurasi cloud)

```bash
npm test
npm run build
npm run dev
```

Tanpa env: demo MVP lama berjalan di `http://localhost:4173`. Jika env `VITE_SUPABASE_URL` dan `VITE_SUPABASE_PUBLISHABLE_KEY` tersedia **saat `npm run build`**, versi Cloud aktif. Tidak ada package eksternal yang perlu diunduh untuk build.

### Data dan modul

- `supabase/migrations/001_hatop_core.sql`: PostgreSQL, tabel, RLS, RPC transaksi, trigger auth.
- `supabase/setup/02_demo_catalog.sql`: seed katalog, tiga toko DEMO dan listing simulasi.
- `supabase/setup/03_admin_after_google_login.sql`: petunjuk manual bootstrap satu admin.
- `src/cloud-auth.mjs`: OAuth Google PKCE dan sesi Supabase (tidak memerlukan JS SDK).
- `src/cloud-app.mjs`: antarmuka dan alur cloud multi-role.
- `src/cloud-domain.mjs`: logika murni pooling dan kalkulasi.
- `src/main.mjs`: source UI prototype asli tetap dipertahankan sebagai demo offline.
- `src/data.mjs` dan `CATALOG_SOURCES.md`: katalog dan sumber web MVP asli.
- `build.mjs`: membuat file konfigurasi publishable dalam `dist/hatop-config.js` saat deployment; hanya variabel publik.

## Validasi dan batasan

- `npm test` dan `npm run build` diuji pada lingkungan pembuatan ZIP. Detail lihat `LAPORAN_PENGUJIAN.md`.
- SQL belum dijalankan ke proyek Supabase HATOP-DEV karena proyek itu belum dikonfigurasi. Karena itu, **jangan mengklaim integrasi cloud sudah lolos end-to-end**.
- Login Google memerlukan Google Cloud OAuth Client ID dan Client Secret yang dikonfigurasi **di dashboard Supabase**, bukan dimasukkan ke GitHub/Vercel.
- Realtime menggunakan polling 15 detik untuk demo, bukan WebSocket atau peta GPS asli.
- Kandidat pooling menggunakan lokasi wilayah + tanggal saja; kapasitas kendaraan dan rute harus diperiksa admin secara manual.
- Admin diperbolehkan tepat satu akun, ditetapkan manual setelah login Google pertama.
- Nominal referensi nasional bukan harga lokal; katalog seed selalu tertulis DEMO.

## Jangan dilakukan

Jangan menjalankan `supabase/schema.sql` lama pada project yang sama dengan migrasi baru. Itu hanya dokumen starter arsip. Jangan masukkan Supabase secret key/service-role ke variabel `VITE_*`, GitHub atau browser.
