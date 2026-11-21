# Luak Explorer

Flutter app for sharing and discovering travel information in Payakumbuh and
Lima Puluh Kota, backed by Supabase.

## Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor** and run [`supabase/schema.sql`](./supabase/schema.sql),
   then run [`supabase/role_workflows.sql`](./supabase/role_workflows.sql).
   The workflow migration adds reports, curator applications, notifications,
   admin statistics, verification notes, and their role-based policies.
3. Project URL and publishable key are configured as client defaults in
   `lib/main.dart`. Run the app:

   ```powershell
   flutter run
   ```

   To override them, pass `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` through
   `--dart-define`. The publishable key is intended for client apps and does
   not bypass RLS. Never put a `service_role` key in a Flutter app.
4. Register or sign in through the app. A database profile is created
   automatically when an account is registered.

The app reads only verified spots. New spot suggestions are saved with
verification status **Menunggu** and do not appear in public browsing until an
administrator verifies them in Supabase. Categories and kecamatan are seeded
by the SQL file.

`Users.password` is intentionally not stored in the public profile table.
Supabase Auth owns password storage and verification; the `users.id` field
references `auth.users.id`.

The app currently stores media URLs in `media_spot.url_media`; configure
Supabase Storage and its bucket policies separately if contributors should
upload files directly.

## Implemented data flows

- Supabase Auth sign-up/sign-in and profile creation.
- Read verified spots, active stories, categories, and kecamatan.
- Submit a spot for verification.
- Persist bookmarks and log activity atomically.
- Read and submit tips, and vote tips as helpful.
- Create public/private collections and add spots to collections through the
  repository.
- Admin dashboard statistics, spot verification, report handling, and curator
  application review.
- User notifications and curator applications backed by Supabase.
