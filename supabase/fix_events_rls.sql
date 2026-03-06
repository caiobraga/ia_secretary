-- =============================================================================
-- Fix RLS for table "events" (Authorization failed - new row violates RLS)
-- Run this in Supabase SQL Editor.
-- =============================================================================
-- Cause: Inserts are allowed only when the row's calendar_id belongs to the
-- current user (auth.uid()). The error usually means:
--   1. Request has no user JWT (auth.uid() is null), e.g. from n8n/cron without
--      passing the user's token, or
--   2. The calendar_id you're inserting doesn't exist or belongs to another user.
-- =============================================================================

-- 1) Remove existing policy so we can recreate it cleanly
drop policy if exists "Users can manage their events" on public.events;

-- 2) Recreate policy: user can only see/insert/update/delete events whose
--    calendar belongs to them
create policy "Users can manage their events"
on public.events
for all
using (
  exists (
    select 1 from public.calendars c
    where c.id = events.calendar_id
      and c.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.calendars c
    where c.id = events.calendar_id
      and c.user_id = auth.uid()
  )
);

-- 3) Optional: if you insert from a backend/n8n that does NOT send a user JWT,
--    you have two options:
--    A) Use the service_role key for that request (bypasses RLS), or
--    B) Pass the user's JWT in the request so auth.uid() is set.
--
--    If you must allow inserts without a user (e.g. system-created events),
--    you can add a second policy that allows insert when calendar exists
--    and is owned by a specific user (e.g. from a trigger). Example that
--    allows any authenticated user to insert only into their own calendar:
--    (already satisfied by the policy above; no extra policy needed.)
--
-- 4) Quick check: ensure the inserting user has a calendar and you're using it.
--    Run as the user (e.g. in a request that sends their JWT):
--
--    select id, name from public.calendars where user_id = auth.uid();
--
--    Then use one of those ids as calendar_id when inserting into events.
