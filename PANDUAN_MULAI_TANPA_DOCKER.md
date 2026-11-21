# PANDUAN HATOP FINAL, TANPA DOCKER (langkah demi langkah)

**Ikuti nomor secara berurutan.** Kalau sebuah tahap gagal, berhenti dan catat pesan error. Tidak perlu instalasi Docker/PowerShell untuk setup Supabase Cloud dan Vercel.

## 0. Hal yang perlu disiapkan

- Akun Supabase yang kamu kendalikan.
- Repository GitHub HATOP, misalnya `HATOPV1`.
- Akun Vercel yang terhubung ke GitHub.
- Akun Google Cloud untuk OAuth, dan Google Account untuk akun admin.
- Satu atau lebih Google Account terpisah untuk role toko, pickup, customer saat menguji alur (bisa menggunakan beberapa akun yang kamu kendalikan).

Semua uang dan pembayaran pada website **hanya simulasi**. QRIS Demo adalah tulisan simulasi, **bukan QRIS merchant**.

## 1. Buat Supabase Cloud HATOP-DEV

1. Buka `https://supabase.com/dashboard` dan login.
2. Klik **New project**.
3. Pilih organisasi milikmu sendiri, cek apakah kuota paket gratis masih tersedia. Jangan menyetujui biaya berbayar tanpa meninjaunya.
4. Nama project: `HATOP-DEV`.
5. Database password: buat dan simpan sendiri secara aman (jangan kirim ke chat).
6. Region: pilih **Southeast Asia (Singapore)** jika tersedia.
7. Klik Create new project dan pastikan statusnya aktif/healthy.
8. Jangan mengubah project Supabase milik aplikasi lain.

## 2. Buat struktur database dan katalog

1. Di project HATOP-DEV, buka menu kiri **SQL Editor**.
2. Klik **New query**.
3. Buka file `supabase/migrations/001_hatop_core.sql` dari ZIP dengan editor teks (misalnya Notepad).
4. **Salin seluruh isi SQL**, tempel ke SQL Editor. Pastikan database target benar-benar HATOP-DEV.
5. Klik **Run** sekali. Jika sukses, buka Table Editor dan periksa tabel `profiles`, `orders`, `store_orders`, `payments`, `shipments`, dll.
6. Buat query baru; tempel semua isi `supabase/setup/02_demo_catalog.sql`.
7. Jalankan sekali. Katalog seharusnya berisi 7 kategori, 23 produk referensi, 3 toko berlabel DEMO, dan 21 listing dengan harga simulasi.
8. **Jangan jalankan** `supabase/schema.sql` starter lama. Jangan ulang seluruh SQL ketika ada error tanpa memeriksa dulu apakah sebagian tabel sudah tercipta.

SQL ini dioptimalkan untuk **project kosong**. Bukan untuk database Supabase yang sudah berisi aplikasi lain.

## 3. Buat Google OAuth (login Google)

1. Buka `https://console.cloud.google.com/` dengan akun milikmu.
2. Buat/select project Google Cloud khusus HATOP.
3. Buka Google Auth Platform / OAuth consent screen, selesaikan informasi nama aplikasi dan kontak.
4. Pada tahap Testing, masukkan alamat Google Account penguji ke daftar **Test users**, bila diminta.
5. Buka menu **Clients** / Credentials > **Create OAuth Client ID** > **Web application**.
6. Pada **Authorized redirect URIs**, isi URL ini, dengan `PROJECT_REF` diganti id project Supabase HATOP-DEV:
   `https://PROJECT_REF.supabase.co/auth/v1/callback`
7. Simpan Google Client ID dan Client Secret.
8. Kembali ke Supabase > **Authentication** > **Providers** > **Google** > Enable.
9. Masukkan Google Client ID dan Google Client Secret ke Supabase, lalu Save.
10. Client Secret **TIDAK** dimasukkan ke Vercel, ZIP, GitHub, atau chat.

## 4. Konfigurasikan URL Login di Supabase

1. Supabase > Authentication > **URL Configuration**.
2. Site URL: gunakan URL utama Vercel yang akan kamu deploy, misalnya `https://hatopv-1.vercel.app` (ini hanya contoh, sesuaikan URL sebenarnya).
3. Redirect URLs: tambahkan URL yang sama, jika login diarahkan ke homepage dengan root `/` gunakan `https://NAMA-SITUS.vercel.app/`.
4. Jika ingin uji localhost, tambah `http://localhost:4173/**`.
5. Jangan menambahkan wildcard luas untuk domain produksi tanpa alasan.

**Ingat:** Google Cloud callback adalah domain `supabase.co/auth/v1/callback`, sedangkan Supabase Redirect URL adalah domain `vercel.app` milikmu.

## 5. Environment Variables di Vercel

1. Buka `https://vercel.com/dashboard`, masuk ke project HATOP.
2. Buka **Settings > Environment Variables**.
3. Buat **dua variabel** berikut (huruf kapital dan underscore harus persis):

| Name | Value dari Supabase |
| --- | --- |
| `VITE_SUPABASE_URL` | `https://PROJECT_REF.supabase.co` |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_...` |

4. Nilai diambil dari Supabase > Project Settings > API Keys / Connect (pilih **Publishable key**, BUKAN Secret key).
5. Tambahkan untuk Environment **Production** (dan Preview bila digunakan).
6. Pastikan tidak ada `VITE_SUPABASE_ANON_KEY` lama yang dipakai sebagai pengganti publishable key; file baru memerlukan key yang namanya `VITE_SUPABASE_PUBLISHABLE_KEY`.
7. Klik Save.
8. Deploy ulang karena env baru diproses pada saat build.

**JANGAN** masukkan `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEY`, `GOOGLE_CLIENT_SECRET` atau password database ke Vercel frontend. File `dist/hatop-config.js` hasil build sengaja hanya menyimpan public URL dan Publishable Key.

## 6. Upload ZIP project ke GitHub dan deploy Vercel

1. Ekstrak ZIP di komputer.
2. Masuk ke repository GitHub HATOP (misalnya HATOPV1).
3. Unggah **seluruh isi folder `hatop-mvp`** ke root repository. Folder `src`, `public`, `supabase`, serta file `package.json`, `build.mjs`, `index.html`, `vercel.json` harus terlihat di root.
4. Perhatikan file `.gitignore`; **jangan upload file `.env.local`**.
5. Vercel > Import repository HATOP.
6. Framework Preset: `Other` (karena build ini tanpa paket Vite).
7. Root Directory: `./` jika `package.json` berada di root.
8. Build Command: `npm run build`.
9. Output Directory: `dist`.
10. Install Command: otomatis.
11. Deploy. Buka domain Vercel dan lihat katalog.
12. **Jika katalog tampil kosong**, periksa tab Network/Console browser dan pastikan dua env di Vercel benar, kedua SQL sukses, dan deploy dilakukan setelah env disimpan.

## 7. Aktivasi satu akun admin

1. Buka website HATOP setelah online.
2. Klik **Masuk Google** dengan akun yang akan menjadi admin.
3. Setelah berhasil kembali ke website, buka Supabase > Authentication > Users. Email admin seharusnya sudah muncul.
4. Buka file `supabase/setup/03_admin_after_google_login.sql`.
5. Ganti `GANTI_EMAIL_ADMIN@gmail.com` dengan email **akunmu sendiri** pada query SELECT. Jalankan SELECT; pastikan hanya ada **satu** baris pengguna.
6. Baru kemudian salin **satu perintah INSERT yang dikomentari** (hapus `--` pada dua baris INSERT/SELECT/ON CONFLICT) dan jalankan sebagai query terpisah setelah mengganti email. Jangan mengaktifkan sembarang email.
7. Periksa tabel `user_roles` dan pastikan hanya ada satu user dengan role `admin`.
8. Refresh website dan masuk ke Dashboard. Tab **Admin** seharusnya terlihat.

Ini tidak memungkinkan pengguna umum membuat admin sendiri; user biasa otomatis mendapat role farmer lewat trigger auth.

## 8. Aktivasi minimal 2 toko dan 1 driver

1. Login dengan Google Account toko A (bukan akun admin).
2. Dashboard > **Ajukan Toko**. Pilih `Toko DEMO Balige A`, isi data dan kirim.
3. Login akun Admin, buka Dashboard > Admin > Pengajuan mitra, klik **Aktifkan**.
4. Lakukan ulang dengan akun toko B untuk `Toko DEMO Laguboti B`.
5. Login akun driver, Dashboard > **Ajukan Pickup**, kirim; admin aktifkan.
6. Admin boleh mengelola pengajuan; role toko dan pickup tidak boleh dipilih langsung oleh user tanpa approval.

**Catatan:** Ini seluruhnya akun dan toko demo. Nama toko dalam seed bukan nama bisnis Balige yang sudah diverifikasi.

## 9. Coba pemesanan ujung-ke-ujung

1. Login akun petani/customer.
2. Tambahkan produk dari 2 toko berbeda ke keranjang, klik Checkout.
3. Lengkapi alamat, wilayah dan jadwal, lalu klik Buat Pesanan.
4. Toko A dan B masing-masing login, terima pesanan stok dan klik Barang Siap Dijemput.
5. Customer buka Pesanan Saya dan melihat status **Invoice perlu disetujui**. Bila ingin pooling, jangan menyetujui invoice sebelum admin meninjau rekomendasi.
6. Untuk uji pooling: buat **dua pesanan customer** dengan wilayah dan tanggal yang sama. Setelah kedua toko siap menerima, Admin > Rekomendasi Pooling > Setujui pooling (cek kapasitas/rute manual).
7. Customer setujui invoice final dan klik **Saya sudah bayar DP (DEMO)**. Tidak ada transaksi uang sungguhan.
8. Admin > Verifikasi DP > Setujui.
9. Admin > Pengiriman > Buka tugas pickup, kemudian pilih salah satu: admin menugaskan driver atau driver mengambil dari tugas terbuka.
10. Driver > Pickup > Semua barang diambil > Tiba di lokasi customer.
11. Customer klik Barang sesuai hasil pemeriksaan.
12. Driver klik Catat COD DEMO, lalu customer konfirmasi diterima.
13. Status berubah selesai, riwayat di Supabase tersimpan.

## 10. Jika terjadi error

- **Login Google error redirect_uri_mismatch**: URL callback di Google Cloud salah. Gunakan URL Supabase `/auth/v1/callback`, bukan Vercel.
- **Login sukses tapi tidak masuk akun**: cek Supabase Auth URL Configuration dan aplikasi masih di URL redirect terdaftar.
- **403, 42501 permission denied**: jangan buka RLS tanpa batas; cek SQL telah dijalankan utuh dan role yang digunakan.
- **Gagal mengambil produk, katalog kosong**: cek seed SQL dan publishable key serta devtools Network.
- **Belum ada tab Admin**: jalankan bootstrap admin setelah akun tersebut login sekali.
- **Toko tidak menerima pesanan**: pastikan ia telah mengajukan dan disetujui sebagai pemilik toko DEMO yang dipilih.
- **Tidak bisa Dispatch**: DP harus verified dan seluruh toko yang diterima harus menandai barang siap.
- **Gagal pooling**: wilayah/tanggal harus sama, status semua `ready_for_quote`, maksimal 3 anggota default.
- **Vercel tetap tampil mode lama**: variabel publik belum diset saat build, setelah menambah env wajib redeploy.
- **Build gagal karena invalid Supabase key**: gunakan `sb_publishable_...` modern, bukan anon JWT lama; pastikan dua variabel lengkap.

Bila error muncul, catat **pesan error** dan langkah yang dilakukan. Jangan kirim password atau secret key.

## 11. Batas validasi paket

- Tes Node JS dan build bisa dilakukan sebelum Supabase Cloud dibuat.
- Migrasi SQL/RLS, OAuth Google, multi-akun, transaksi nyata tersimpan di Supabase harus diuji **setelah** project aktif.
- Tidak ada jaminan 0 bug pada cloud yang belum di-deploy dan diuji. Paket sengaja mendokumentasikan hal yang belum diuji.
- Sistem ini hanya cocok untuk **presentasi/demonstrasi**, bukan menerima uang, pembayaran QRIS asli, atau order nyata.
