-- Luak Explorer - pemeriksaan status verifikasi email
-- Jalankan bagian SELECT untuk melihat akun yang sudah/belum terverifikasi.

select
  id,
  email,
  created_at,
  email_confirmed_at,
  case
    when email_confirmed_at is null then 'Belum terverifikasi'
    else 'Sudah terverifikasi'
  end as status_verifikasi
from auth.users
order by created_at desc;

-- Untuk mengaktifkan SATU akun lama secara manual, ganti email di bawah
-- lalu hapus tanda komentar pada query UPDATE.
-- Catatan: ini melewati verifikasi email dan hanya boleh digunakan untuk
-- akun uji coba/admin yang memang sudah Anda pastikan kepemilikannya.

-- update auth.users
-- set email_confirmed_at = coalesce(email_confirmed_at, now())
-- where lower(email) = lower('email-uji@example.com');

-- Verifikasi hasilnya:
-- select email, email_confirmed_at
-- from auth.users
-- where lower(email) = lower('email-uji@example.com');

-- OTP tidak diaktifkan melalui SQL. Aktifkan dari:
-- Authentication > Providers > Email > Confirm email = ON
-- lalu atur Email Templates > Confirm signup agar menggunakan {{ .Token }}.
