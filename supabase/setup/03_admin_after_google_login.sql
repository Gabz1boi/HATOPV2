-- JALANKAN HANYA SETELAH ADMIN LOGIN GOOGLE SEKALI.
-- Ganti email di bawah dengan email Google admin resmi (jangan share email di chat).
-- Periksa hasil SELECT dulu. Jika 0, login Google dahulu. Jangan lanjut INSERT.
select id,email,created_at from auth.users where lower(email)=lower('GANTI_EMAIL_ADMIN@gmail.com');
-- Setelah SELECT menunjukkan tepat 1 pengguna yang sesuai, jalankan baris berikut secara terpisah:
-- insert into public.user_roles(user_id,role)
-- select id,'admin' from auth.users where lower(email)=lower('GANTI_EMAIL_ADMIN@gmail.com')
-- on conflict do nothing;
-- Verifikasi admin:
-- select ur.user_id,ur.role from public.user_roles ur where ur.role='admin';
