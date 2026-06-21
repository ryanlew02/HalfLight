-- The first username change after sign-up is free; only later changes wait 30
-- days. A never-changed profile must therefore have a null cooldown anchor — the
-- trigger sets it on the first real change. This undoes the earlier created_at
-- backfill: only those rows match (anchor == created_at); genuine changes set
-- the anchor to their change time and are left untouched.
update public.profiles
set username_changed_at = null
where username_changed_at = created_at;
