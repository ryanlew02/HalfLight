-- Store the dreamer's profile photo on their profile row so it follows them
-- across devices. The app uploads a small cropped JPEG (512×512, ~tens of KB)
-- as base64 text — simple and self-contained, no Storage bucket required.
--
-- Readable by signed-in users (for the profile screen and future social
-- surfaces); writable only by the owner, which the existing
-- "Users update their own profile" RLS policy already enforces per row.
alter table public.profiles
    add column if not exists avatar text;

grant select (avatar) on public.profiles to authenticated;
grant update (avatar) on public.profiles to authenticated;
