-- Remove calendar_id from events. Events are scoped by user_id only.
-- Run in Supabase SQL Editor after events have user_id (from previous migration).

drop index if exists public.idx_events_calendar_id;
alter table public.events drop column if exists calendar_id;
