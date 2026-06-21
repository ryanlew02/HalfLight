-- Anchor the username cooldown for users who existed before the column was
-- added: treat their account creation as the last "change". Rows created after
-- the cooldown window can change immediately; very recent accounts wait out the
-- remainder of their first 30 days.
update public.profiles
set username_changed_at = created_at
where username_changed_at is null;
