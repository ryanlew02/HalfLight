-- Bound the avatar column.
--
-- Avatars are stored inline as base64 in profiles.avatar (there is no storage
-- bucket), and that column was the one profile field the 20260730120000 length
-- caps missed. RLS confines a dreamer to their own row, so an oversized avatar
-- is not a data breach — but `text` accepts up to 1GB, so any signed-in account
-- could PATCH megabytes into its own profile and make everyone who loads that
-- profile pay for it in egress. Same shape as the unbounded AI `entry` field.
--
-- 200 KB of base64 ≈ a 150 KB image, comfortably above what the app's cropper
-- produces (the largest avatar in the wild when this was written was 136 KB)
-- and far below the point where it costs anything to serve.

alter table public.profiles
    drop constraint if exists profiles_avatar_length;

alter table public.profiles
    add constraint profiles_avatar_length
    check (avatar is null or char_length(avatar) <= 200000);
