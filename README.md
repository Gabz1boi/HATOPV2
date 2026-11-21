# HATOP Cloud Marketplace

Marketplace multipihak HATOP: pembeli/petani, toko, pickup, administrator. Supabase Cloud/PostgreSQL/Auth/Storage dan Vercel Static Frontend. Pembuatan QRIS dinamis Midtrans menggunakan Supabase Edge Functions (Server Key hanya di backend). Tidak memerlukan Docker.

**Langkah pemasangan:** `PANDUAN_DEPLOY_HATOP_FINAL.md`. **Foto & lisensi:** `FOTO_ASSETS_DAN_LISENSI.md`.

**Penting:** QRIS otomatis belum dapat menerima pembayaran nyata tanpa akun merchant aktif, Server Key produksi, deployment Edge Functions, registrasi webhook dan uji end-to-end di lingkungan produksi. Jangan menerima transfer sebelum semua selesai.

Perintah pengujian: `npm test` dan `npm run build`.
