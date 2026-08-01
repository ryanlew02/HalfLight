-- `follows` is keyed by `followee_username`, a mutable text handle, and nothing
-- rewrote it when a dreamer changed their username. Two consequences, both bad
-- for a social app:
--
--   • The renamed dreamer silently loses every follower — the rows still point at
--     a handle nobody owns, so `followers_of` (which joins on lower(username))
--     returns nothing and their follower count drops to zero.
--   • Whoever claims the abandoned handle next inherits those followers. Handles
--     free up as soon as they're changed, so this is reachable on purpose:
--     rename yourself to a handle a popular account just left and their
--     followers are now yours.
--
-- Identity elsewhere is keyed by uuid with a denormalized snapshot for display
-- (see `notifications.actor_id`, `feed_posts.author_id`), which is the right
-- shape. Repointing follows to `profiles.id` would be the thorough fix, but it
-- changes the primary key and every RPC that reads the graph; keeping the
-- handle in step is the small, safe change and closes both holes.

create or replace function public.rename_follow_targets()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.username is distinct from old.username then
        -- The primary key is (follower_id, followee_username), so a follower who
        -- already follows the *new* handle would collide. That needs a previous
        -- owner of this handle to have renamed away while the follow stayed put —
        -- exactly the stale rows this migration exists to prevent — so drop the
        -- stale duplicate and keep the live one.
        delete from public.follows f
         where lower(f.followee_username) = lower(old.username)
           and exists (
               select 1 from public.follows g
                where g.follower_id = f.follower_id
                  and lower(g.followee_username) = lower(new.username)
           );

        update public.follows
           set followee_username = new.username
         where lower(followee_username) = lower(old.username);
    end if;
    return new;
end;
$$;

revoke execute on function public.rename_follow_targets() from public, anon, authenticated;

drop trigger if exists rename_follow_targets on public.profiles;
create trigger rename_follow_targets
    after update of username on public.profiles
    for each row execute function public.rename_follow_targets();
