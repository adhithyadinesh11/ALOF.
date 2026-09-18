-- ALOF V28: cloud saving + coach access
-- Run this ONCE in Supabase SQL Editor before using V28.

-- Expected data table used by the app.
create table if not exists public.alof_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  data jsonb not null default '{"workouts":[],"events":[]}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.alof_data enable row level security;

-- Authenticated athletes can read only their own row.
-- Coaches can read every athlete row when their email is listed in coach_access.
drop policy if exists "Users and coaches can read ALOF data" on public.alof_data;
create policy "Users and coaches can read ALOF data"
on public.alof_data for select
to authenticated
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.coach_access c
    where lower(c.email) = lower(coalesce(auth.jwt()->>'email',''))
  )
);

-- Athletes may create only their own row.
drop policy if exists "Users can insert their own ALOF data" on public.alof_data;
create policy "Users can insert their own ALOF data"
on public.alof_data for insert
to authenticated
with check (auth.uid() = user_id);

-- Athletes may update only their own row. Coaches remain read-only.
drop policy if exists "Users can update their own ALOF data" on public.alof_data;
create policy "Users can update their own ALOF data"
on public.alof_data for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select, insert, update on public.alof_data to authenticated;

-- Coach access list. Add coach emails here.
create table if not exists public.coach_access (
  email text primary key,
  created_at timestamptz not null default now()
);

alter table public.coach_access enable row level security;

drop policy if exists "Coaches can read their own access row" on public.coach_access;
create policy "Coaches can read their own access row"
on public.coach_access for select
to authenticated
using (lower(email) = lower(coalesce(auth.jwt()->>'email','')));

grant select on public.coach_access to authenticated;

-- Keep the email column on existing installations populated.
update public.alof_data d
set email = u.email
from auth.users u
where u.id = d.user_id
  and (d.email is null or d.email = '');

-- Add coaches with their exact login email, for example:
-- insert into public.coach_access (email) values ('coach@example.com')
-- on conflict (email) do nothing;
