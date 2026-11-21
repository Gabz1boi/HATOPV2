# Laporan validasi HATOP Cloud Demo

## Diuji di mesin pembuatan paket

- `node --check` pada modul baru: lulus.
- `npm test`: 14/14 lulus, termasuk tes pooling yang hanya merekomendasikan pesanan sesuai area dan jadwal, serta rumus DP=50% ongkir.
- `npm run build` offline: lulus.
- ZIP dicek konsistensi menggunakan unzip test.

## Belum diuji di Supabase Cloud HATOP-DEV

- Eksekusi SQL migrasi dan seed di PostgreSQL Supabase nyata.
- Google OAuth redirects dan callback di domain Vercel pengguna.
- RLS policy terhadap login akun yang berbeda.
- Uji bersamaan dua pickup menerima tugas.
- Full end-to-end pembayaran simulasi, pooling, dan pengantaran lintas akun.

Jangan menyebut cloud backend sudah lolos pengujian tersebut sebelum benar-benar dijalankan. Jika SQL gagal saat dijalankan, hentikan dan periksa error sebelum melanjutkan.

Note: Browser automation localhost blocked by environment administrator. No real Supabase SQL/OAuth tests yet.
