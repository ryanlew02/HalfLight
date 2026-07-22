-- Server-side content moderation backstop.
--
-- The app already filters client-side (ContentFilter.swift), which gives instant
-- inline feedback. But the anon key ships in the binary and RLS lets any
-- authenticated user insert/update their own profile row and their own
-- feed_posts, so a direct PostgREST call could still write a slur handle or a
-- hateful post the app would never send. This enforces the same two-tier policy
-- in the database, mirroring the existing feed integrity / rate-limit triggers:
--
--   • profiles (username, first_name, last_name) — blocks slurs AND profanity.
--   • feed_posts (title, dream_description, tags) — blocks slurs ONLY. Swearing
--     is allowed in posts, matching the app.
--
-- Matching mirrors the Swift filter: leetspeak folding, whole-word matching
-- (digits/punctuation/underscore act as boundaries), plus a compact separator-
-- stripped substring pass for 4+ letter terms, with an allow-list sparing
-- innocuous words that merely contain a banned substring (the Scunthorpe
-- problem). Profile violations raise SQLSTATE 'P0403' with a "MODERATION" marker
-- so the app can show a friendly message, like the 'P0429'/'RATE_LIMIT' pattern.
--
-- The word lists are kept only here (and in the app's bundled data files); they
-- are not exposed to clients — RLS locks the table and the check runs inside
-- SECURITY DEFINER functions.

-- ─────────────────────────────────────────────────────────────────────────────
-- Term storage. category: 'hate' (blocked everywhere) | 'profanity' (names only)
-- | 'allow' (Scunthorpe exemptions). Terms are stored lowercase + leetspeak-
-- folded, the same normal form the check folds input into.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.moderation_terms (
    term     text not null,
    category text not null check (category in ('hate', 'profanity', 'allow')),
    primary key (term, category)
);

-- Locked down: no client ever needs to read the list. SECURITY DEFINER triggers
-- bypass RLS, so enforcement still works; direct API reads get nothing.
alter table public.moderation_terms enable row level security;
revoke all on public.moderation_terms from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Normalize: lowercase + fold common leetspeak. Mirrors ContentFilter.fold so a
-- list authored in plain spelling matches obfuscated input (sh1t, f4ggot, n0b).
-- Only letter-ish substitutions; '2'/'6' are left alone, as in the app.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.moderation_normalize(p text)
returns text
language sql
immutable
as $$
    select translate(lower(coalesce(p, '')), '0134578@$|!9', 'oieastbasiig');
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- The core check. Returns the offending category ('hate' | 'profanity') or null.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.moderation_offense(p_text text, p_include_profanity boolean)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    folded  text := public.moderation_normalize(p_text);
    compact text := regexp_replace(folded, '[^a-z]', '', 'g');
    words   text[] := regexp_split_to_array(folded, '[^a-z]+');
    rec     record;
begin
    if folded = '' then
        return null;
    end if;

    for rec in
        select term, category from public.moderation_terms
        where category = 'hate'
           or (p_include_profanity and category = 'profanity')
    loop
        -- 1) Whole-word match. A non-letter (space, digit, punctuation, or the
        --    underscore/start/end of string) must border the term on both sides,
        --    matching the app's `(?<![a-z])term(?![a-z])`.
        if folded ~ ('(^|[^a-z])' || rec.term || '([^a-z]|$)') then
            return rec.category;
        end if;

        -- 2) Compact substring for 4+ letter terms — catches spaced/punctuated
        --    evasion ("f a g"). Skipped when an allow-listed word actually present
        --    in the text explains the hit (e.g. "assassin" contains "ass").
        if length(rec.term) >= 4 and position(rec.term in compact) > 0 then
            if not exists (
                select 1 from public.moderation_terms a
                where a.category = 'allow'
                  and a.term = any(words)
                  and position(rec.term in a.term) > 0
            ) then
                return rec.category;
            end if;
        end if;
    end loop;

    return null;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles: strict gate (slurs + profanity) on the username and both name parts.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.moderate_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if public.moderation_offense(new.username, true) is not null
       or public.moderation_offense(coalesce(new.first_name, ''), true) is not null
       or public.moderation_offense(coalesce(new.last_name, ''), true) is not null then
        raise exception 'MODERATION: profile contains disallowed language'
            using errcode = 'P0403'; -- reuse-friendly custom code
    end if;
    return new;
end;
$$;

drop trigger if exists moderate_profile_t on public.profiles;
create trigger moderate_profile_t
    before insert or update of username, first_name, last_name on public.profiles
    for each row execute function public.moderate_profile();

-- ─────────────────────────────────────────────────────────────────────────────
-- feed_posts: lenient gate (slurs only) on title, description, and tags.
-- Scoped to the content columns so the engagement-count triggers (which update
-- like/view/comment counts with no JWT) never re-run moderation.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.moderate_feed_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if public.moderation_offense(coalesce(new.title, ''), false) is not null
       or public.moderation_offense(coalesce(new.dream_description, ''), false) is not null
       or (new.tags is not null
           and public.moderation_offense(array_to_string(new.tags, ' '), false) is not null) then
        raise exception 'MODERATION: post contains hateful language'
            using errcode = 'P0403';
    end if;
    return new;
end;
$$;

drop trigger if exists moderate_feed_post_t on public.feed_posts;
create trigger moderate_feed_post_t
    before insert or update of title, dream_description, tags on public.feed_posts
    for each row execute function public.moderate_feed_post();

-- ─────────────────────────────────────────────────────────────────────────────
-- The sign-up trigger inserts a profile from auth metadata. A raise there would
-- abort the auth user creation itself, so — exactly like the invalid-username
-- case in 20260716130000 — it now SKIPS inserting a profile whose metadata
-- fails moderation. The user still gets an account and lands on the in-app
-- username-setup screen, where the client filter and the table trigger apply.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_handle text := lower(new.raw_user_meta_data ->> 'username');
    v_first  text := coalesce(new.raw_user_meta_data ->> 'first_name', '');
    v_last   text := coalesce(new.raw_user_meta_data ->> 'last_name', '');
begin
    if v_handle ~ '^[a-z0-9_]{3,20}$'
       and public.moderation_offense(v_handle, true) is null
       and public.moderation_offense(v_first, true) is null
       and public.moderation_offense(v_last, true) is null then
        insert into public.profiles (id, username, first_name, last_name)
        values (new.id, v_handle, v_first, v_last)
        on conflict do nothing;
    end if;
    return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed the term lists. Kept in sync with HalfLight/Moderation/*.txt. Terms are
-- stored already lowercase + leetspeak-folded (they contain only letters, so
-- folding is a no-op here, but the column is the folded normal form by contract).
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.moderation_terms (term, category)
select term, 'hate' from unnest(array[
    -- Racial / ethnic slurs
    'nigger','nigga','niger','coon','spic','spick','wetback','chink','gook',
    'kike','kyke','beaner','wop','dago','greaser','raghead','towelhead',
    'sandnigger','sandnigga','paki','pakis','gyppo','gypo','abo','boong',
    'coolie','darkie','darky','negro','jigaboo','jiggaboo','porchmonkey',
    'tarbaby','zipperhead','slanteye','redskin','injun','squaw','halfbreed',
    'mulatto','quadroon','mudslime','cameljockey','junglebunny','spearchucker',
    'moolie','hymie','shylock','heeb','cracker','honky','gringo','cholo','gyp',
    'wigger','wigga',
    -- Anti-LGBTQ slurs
    'faggot','faggit','fagot','fag','fags','dyke','dike','tranny','trannie',
    'shemale','heshe','ladyboy','queer','homo','poofter','poof','fairy',
    'fudgepacker','carpetmuncher','buttpirate','sodomite',
    -- Ableist / other targeted slurs
    'retard','retarded','retards','tard','spastic','spaz','cripple','mongoloid',
    'midget',
    -- Nazi / hate ideology signals
    'hitler','nazi','heilhitler','whitepower','kkk','klux'
]) as term
on conflict do nothing;

insert into public.moderation_terms (term, category)
select term, 'profanity' from unnest(array[
    'fuck','fucker','fucking','fuk','fuc','motherfucker','mofo','shit','shite',
    'shitty','bullshit','dipshit','bitch','biatch','bastard','asshole',
    'arsehole','ass','arse','jackass','dumbass','dick','dickhead','cock',
    'cocksucker','prick','wanker','wank','pussy','cunt','twat','slut','whore',
    'hoe','skank','boob','boobs','tits','titties','titty','penis','vagina',
    'cum','cumming','jizz','jerkoff','handjob','blowjob','rimjob','anal','anus',
    'porn','porno','pornhub','damn','goddamn','crap','bollocks','bugger','piss',
    'pissed','nutsack','ballsack','scrotum','dildo','butthole','asshat',
    'shithead','fckface','fuckface','clit','smegma','queef','felch','fap'
]) as term
on conflict do nothing;

insert into public.moderation_terms (term, category)
select term, 'allow' from unnest(array[
    'assassin','assassinate','assassination','class','classic','glass','grass',
    'brass','bass','pass','password','passage','compass','mass','massive',
    'assist','assistant','assess','assessment','asset','assemble','assembly',
    'assign','assignment','associate','assume','assumption','assure','embarrass',
    'harass','lass','molasses','cassette','cassidy','cocktail','cockpit',
    'cockroach','peacock','shuttlecock','hancock','analysis','analyst','analyze',
    'analytical','canal','banal','analog','analogy','scunthorpe','penistone',
    'sussex','essex','middlesex','niggardly','niggard','cockburn','babcock',
    'leacock','hitchcock','woodcock','therapist','therapists','shiitake',
    'dickens','dickinson','clithero','clitheroe','matisse','narcissist',
    'specialist','cummings','cumberland','cumulative','circumstance','document',
    'accumulate','titan','titanic','title','titration','constitution',
    'competition','buttress','button','buttermilk','butter','wankel'
]) as term
on conflict do nothing;
