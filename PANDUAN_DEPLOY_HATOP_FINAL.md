# HATOP | Panduan Pembaruan Cloud dan QRIS Otomatis
Tanggal paket: 21 November 2026.

## Status yang sebenarnya
Paket ini berisi **kode frontend + SQL migrasi + dua Supabase Edge Functions** untuk QRIS dinamis Midtrans. Kode tidak diunggah otomatis ke GitHub/Vercel/Supabase dan belum terhubung ke akun merchant. Pembayaran nyata **BELUM AKTIF** sampai seluruh langkah aktivasi dan pengujian berhasil. Jangan meminta pelanggan melakukan transfer sebelum itu.

Rumus HATOP sesuai proposal: **DP = pembulatan ke bawah (50% dari ongkir final)**; **COD = total barang + ongkir final + biaya layanan - DP**. Contoh barang Rp52.000, ongkir Rp400.000, layanan Rp20.000: total Rp472.000; QRIS Rp200.000; COD Rp272.000.

## Bagian yang diperbarui
- Cloud-only; tidak dapat kembali ke etalase localStorage jika environment Vercel hilang.
- Halaman depan mengutamakan peran Pembeli, Toko Mitra, dan Pickup; admin terpisah.
- Detail produk, galeri 1–5 foto toko, rating dari transaksi selesai.
- Variasi foto kategori menggunakan materi CC0/public-domain terverifikasi; **bukan foto produk milik toko tertentu**. Foto unggahan toko mengambil prioritas. Sumber dicatat di `FOTO_ASSETS_DAN_LISENSI.md`.
- Penawaran toko contoh dan produk katalog yang belum diverifikasi **tidak muncul** di katalog publik. Karena itu katalog bisa kosong sampai toko nyata dan harga/stok terverifikasi.
- Hapus tombol pembayaran manual. Pembuatan QRIS hanya setelah toko memastikan stok dan admin menetapkan ongkir akhir (gabungan pooling atau pengiriman tunggal).
- Notifikasi ber-tanda tangan dari Midtrans mengubah status DP menjadi terverifikasi; penanda pembayaran langsung oleh pelanggan tidak lagi tersedia pada RPC baru.

## Cara mengganti kode pada repository HATOPV2
1. **Cadangkan dulu** repository dan database Supabase. Jangan hapus project Vercel atau Supabase.
2. Unduh ZIP paket HATOP dan **ekstrak**; jangan mengunggah ZIP sebagai satu file ke repo GitHub.
3. Di GitHub Desktop, masuk dengan akun GitHub, pilih **File > Clone Repository > Gabz1boi/HATOPV2**. Pilih lokasi folder yang mudah ditemukan.
4. Salin **isi folder hasil ekstrak**, bukan folder pembungkusnya, ke dalam folder HATOPV2 hasil clone. Pilih Replace/Overwrite untuk file bernama sama.
5. Di GitHub Desktop tulis Summary `Update HATOP UI and Midtrans QRIS integration`; klik **Commit to main**, lalu **Push origin**.
6. Buka **Vercel > Project hatopv-2 > Deployments** dan pastikan build baru dari commit terakhir **Ready**. Jika GitHub auto-deployment aktif, tidak perlu menekan Redeploy manual. Bila tidak muncul, pilih **Redeploy** dari deployment terbaru.
7. Pengaturan Vercel tetap: Framework Preset **Other**; Build Command `npm run build`; Output Directory `dist`; Root Directory root repository (`./`). Environment Variables frontend tetap `VITE_SUPABASE_URL` dan `VITE_SUPABASE_PUBLISHABLE_KEY`.

**PENTING**: Lakukan migrasi SQL + deploy Edge Function **sebelum** mempublikasikan frontend QRIS kepada pelanggan. Gunakan project pengujian/DEV terlebih dahulu.

## Pembaruan Supabase (JANGAN RESET database)
1. Masuk ke Supabase Dashboard dan pastikan sedang di project HATOP yang benar. Buat backup/export data lebih dahulu.
2. **Jangan jalankan ulang** `001_hatop_core.sql` atau skrip data contoh lama karena itu setup awal, bukan upgrade.
3. Periksa **Table Editor**. Jika tabel `listing_images` dan `product_reviews` belum ada, jalankan `supabase/upgrades/04_product_media_and_reviews.sql` melalui SQL Editor. Jika sudah ada, lewati 04 untuk menghindari konflik policy.
4. Jalankan **sekali** `supabase/upgrades/05_qris_midtrans_secure.sql` di project pengujian. Ini membuat tabel `hatop_qris_sessions`, tiga RPC yang dibatasi service_role, dan mengunci ulang perintah pembayaran manual lama.
5. Periksa bahwa tabel `hatop_qris_sessions` ada, dan pengguna biasa tidak bisa melakukan INSERT/UPDATE langsung. Login dengan dua akun dan uji akses RLS.
6. Di **Edge Functions**, buat dua fungsi `hatop-qris` dan `hatop-qris-webhook`. Salin isi masing-masing `supabase/functions/<nama>/index.ts` dari paket ke editor, lalu deploy. **Disable Verify JWT** pada keduanya karena kode `hatop-qris` memeriksa JWT pengguna melalui Auth API, sedangkan fungsi webhook memeriksa SHA-512 Midtrans. Pengaturan yang sama disimpan di `supabase/config.toml` jika nanti memakai CLI. Jangan membuka fungsi yang lain tanpa otorisasi.
7. Supabase > Edge Functions > Secrets: pastikan `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (server only), `MIDTRANS_SERVER_KEY`, `MIDTRANS_ENV`, dan `HATOP_ALLOWED_ORIGIN` tersedia. Gunakan `HATOP_ALLOWED_ORIGIN=https://hatopv-2.vercel.app` atau domain produksi yang benar. Set `MIDTRANS_ENV=sandbox` dulu. `MIDTRANS_MERCHANT_ID` opsional untuk memverifikasi merchant webhook.
8. Di dashboard Midtrans daftarkan **Payment Notification URL** menjadi `https://PROJECT_REF.supabase.co/functions/v1/hatop-qris-webhook`. PROJECT_REF adalah bagian depan alamat Supabase milik projectmu. Pastikan pengaturan webhook dibaca oleh lingkungan Midtrans yang benar.
9. Untuk pembayaran **sungguhan**, merchant yang berwenang harus menyelesaikan registrasi/verifikasi akun merchant, mendapatkan **Server Key produksi**, mengaktifkan QRIS, serta menyetel `MIDTRANS_ENV=production`. Jangan memalsukan umur, identitas, dan dokumen merchant. Jangan mengirim kunci rahasia lewat chat, GitHub, atau Vercel frontend.
10. Uji lengkap di sandbox: checkout → toko terima → admin set ongkir → customer buka QRIS → status pending → transaksi sandbox diselesaikan → webhook tervalidasi → status `dp_verified` → barang siap pickup → COD → pesanan selesai. Ulangi callback untuk memastikan pembayaran tidak digandakan.

## Poin keamanan dan operasional sebelum transaksi nyata
- Kelola rekening merchant, aliran dana ke toko dan pickup, potongan platform, refund/pembatalan, stok habis, dan barang tidak sesuai. HATOP adalah marketplace banyak pihak: uang tidak otomatis terbagi ke mitra hanya dengan membuat QRIS.
- Jika Midtrans berhasil membuat charge tetapi respons jaringan gagal, sistem sengaja tidak menerbitkan tagihan duplikat. Admin harus mencocokkan transaksi di dashboard Midtrans.
- Permintaan yang sudah dikirim sebelum pembaruan mungkin berasal dari toko contoh. Pesanan historis tetap disimpan, tetapi QRIS baru ditolak jika melibatkan mitra atau produk yang belum diverifikasi.
- Ongkir Rp400.000 adalah nilai pengaturan default historis, bukan tarif berdasarkan jarak secara otomatis. Admin menetapkan tarif sebelum QRIS; untuk harga berbasis kilometer perlu fitur tambahan.
- Versi ini **belum** memiliki refund otomatis, pencairan dana ke mitra, inventory multi-varian, penghitungan jumlah views, pengiriman WhatsApp otomatis, atau payment reconciliation dashboard produksi. Jangan menjual fitur tersebut sebagai sudah tersedia.

## Mengaktifkan toko nyata secara benar
- Empat nama yang pernah ditelusuri: Ondolife, UD. SaiTio, Sinur Napinahan, dan Toko Sejahtera. Keberadaan di peta bukan izin kemitraan.
- Toko mengajukan akun lalu admin meninjau; hanya toko dengan pemilik nyata dan `approved=true,demo=false` yang boleh menjual.
- Produk perlu `catalog_products.local_verified=true`, harga dan stok aktual dalam `store_listings`, serta 1–5 foto aktual dari pemilik toko. Gunakan data setelah meminta persetujuan mitra.
- Jangan sekadar mengganti nama toko contoh menjadi nama toko sungguhan, karena bisa menyatakan kemitraan yang belum ada.

## Verifikasi singkat di browser
1. Beranda memiliki tiga pintu: belanja, toko, pickup.
2. Kategori bergambar tampil, tetapi produk belum terverifikasi tidak bisa dibeli.
3. Halaman detail produk mempunyai galeri dan ulasan.
4. Di pesanan baru yang sudah terkonfirmasi, customer tidak perlu menyetujui invoice untuk kedua kalinya. QRIS muncul **setelah admin menetapkan ongkir final**.
5. Logout/login tidak mengubah nominal DP. Semua angka dihitung dari database.
6. Jika error, lihat Supabase Edge Function Logs dan Vercel Runtime/Deployment Logs. Rahasiakan access token dan Server Key.

## Pengujian lokal tanpa Docker
Pada folder proyek (jika Node.js sudah terpasang): `npm test` dan `npm run build`. Untuk build mode Cloud, Vercel mengisi dua Environment Variables frontend. Jangan menyimpan MIDTRANS_SERVER_KEY atau SUPABASE_SERVICE_ROLE_KEY di project frontend.

## Sumber teknis resmi
- Midtrans QRIS Charge: https://docs.midtrans.com/reference/qris
- Midtrans HTTP Notification: https://docs.midtrans.com/docs/https-notification-webhooks
- Supabase Deploy Edge Functions: https://supabase.com/docs/guides/functions/quickstart-dashboard
- Supabase Secrets: https://supabase.com/docs/guides/functions/secrets
