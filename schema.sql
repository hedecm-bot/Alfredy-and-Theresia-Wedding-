-- Alfred F. Mhina & Theresia P. Marcel wedding admission system
-- Run in Supabase SQL Editor. Then create staff users in Supabase Auth and assign roles below.
create extension if not exists pgcrypto;

create table if not exists public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('admin','gate')) default 'gate',
  created_at timestamptz not null default now()
);

create table if not exists public.wedding_events (
  id uuid primary key default gen_random_uuid(),
  event_name text not null default 'Alfred F. Mhina & Theresia P. Marcel',
  event_date date not null default date '2026-12-05',
  venue text not null default 'Ngome Hall, Africa Sana, Mwenge, Dar es Salaam',
  event_slug text not null unique default 'alfred-theresia-2026',
  physical_qr_code text not null unique default encode(gen_random_bytes(18),'hex'),
  created_at timestamptz not null default now()
);

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.wedding_events(id) on delete cascade,
  invitation_code text not null unique,
  invitation_type text not null check (invitation_type in ('single','couple')),
  delivery_type text not null check (delivery_type in ('physical','electronic')),
  created_at timestamptz not null default now()
);

create table if not exists public.invitees (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.invitations(id) on delete cascade,
  full_name text not null,
  normalized_name text generated always as (lower(regexp_replace(trim(full_name), '\s+', ' ', 'g'))) stored,
  created_at timestamptz not null default now()
);

create table if not exists public.admissions (
  id uuid primary key default gen_random_uuid(),
  invitee_id uuid not null unique references public.invitees(id) on delete restrict,
  admitted_by uuid not null references auth.users(id),
  admitted_at timestamptz not null default now(),
  device_label text
);

create index if not exists invitees_normalized_name_idx on public.invitees(normalized_name);
create index if not exists invitations_event_idx on public.invitations(event_id);

insert into public.wedding_events(event_name,event_date,venue,event_slug)
values ('Alfred F. Mhina & Theresia P. Marcel', date '2026-12-05', 'Ngome Hall, Africa Sana, Mwenge, Dar es Salaam', 'alfred-theresia-2026')
on conflict (event_slug) do nothing;

alter table public.staff_profiles enable row level security;
alter table public.wedding_events enable row level security;
alter table public.invitations enable row level security;
alter table public.invitees enable row level security;
alter table public.admissions enable row level security;

-- Helper: only authenticated staff can use the operational tables.
create or replace function public.current_staff_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.staff_profiles where user_id = auth.uid() $$;

-- Staff can read event information. Admins can change it.
drop policy if exists "staff read event" on public.wedding_events;
create policy "staff read event" on public.wedding_events for select to authenticated using (public.current_staff_role() in ('admin','gate'));
drop policy if exists "admin manage event" on public.wedding_events;
create policy "admin manage event" on public.wedding_events for all to authenticated using (public.current_staff_role()='admin') with check (public.current_staff_role()='admin');

-- Admin manages records; gate staff can read the guest list needed for lookup.
drop policy if exists "staff read invitations" on public.invitations;
create policy "staff read invitations" on public.invitations for select to authenticated using (public.current_staff_role() in ('admin','gate'));
drop policy if exists "admin manage invitations" on public.invitations;
create policy "admin manage invitations" on public.invitations for all to authenticated using (public.current_staff_role()='admin') with check (public.current_staff_role()='admin');
drop policy if exists "staff read invitees" on public.invitees;
create policy "staff read invitees" on public.invitees for select to authenticated using (public.current_staff_role() in ('admin','gate'));
drop policy if exists "admin manage invitees" on public.invitees;
create policy "admin manage invitees" on public.invitees for all to authenticated using (public.current_staff_role()='admin') with check (public.current_staff_role()='admin');
drop policy if exists "staff read admissions" on public.admissions;
create policy "staff read admissions" on public.admissions for select to authenticated using (public.current_staff_role() in ('admin','gate'));

-- Staff can read their own profile; admins can manage staff roles.
drop policy if exists "read own profile" on public.staff_profiles;
create policy "read own profile" on public.staff_profiles for select to authenticated using (user_id=auth.uid() or public.current_staff_role()='admin');
drop policy if exists "admin manage staff" on public.staff_profiles;
create policy "admin manage staff" on public.staff_profiles for all to authenticated using (public.current_staff_role()='admin') with check (public.current_staff_role()='admin');

-- Atomic admission: simultaneous scans cannot admit the same person twice.
create or replace function public.admit_guest(p_invitee_id uuid, p_device_label text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_role text;
  v_name text;
  v_invitation uuid;
  v_admission public.admissions%rowtype;
begin
  v_role := public.current_staff_role();
  if auth.uid() is null or v_role not in ('admin','gate') then
    return jsonb_build_object('status','unauthorised','message','Staff sign-in required');
  end if;
  select i.full_name, i.invitation_id into v_name, v_invitation
  from public.invitees i where i.id=p_invitee_id;
  if v_name is null then
    return jsonb_build_object('status','invalid','message','Guest not found');
  end if;
  insert into public.admissions(invitee_id,admitted_by,device_label)
  values (p_invitee_id,auth.uid(),left(p_device_label,100))
  on conflict (invitee_id) do nothing
  returning * into v_admission;
  if found then
    return jsonb_build_object('status','admitted','guest_name',v_name,'admitted_at',v_admission.admitted_at);
  end if;
  select * into v_admission from public.admissions where invitee_id=p_invitee_id;
  return jsonb_build_object('status','already_admitted','guest_name',v_name,'admitted_at',v_admission.admitted_at);
end; $$;
revoke all on function public.admit_guest(uuid,text) from public;
grant execute on function public.admit_guest(uuid,text) to authenticated;

-- Least-privilege table grants; row access remains controlled by RLS.
grant usage on schema public to authenticated;
grant select on public.staff_profiles, public.wedding_events, public.invitations, public.invitees, public.admissions to authenticated;
grant insert, update, delete on public.staff_profiles, public.wedding_events, public.invitations, public.invitees to authenticated;

-- AFTER creating the first Auth user, replace USER_UUID and run this as project owner:
-- insert into public.staff_profiles(user_id,full_name,role) values ('USER_UUID','Wedding Administrator','admin');
-- Add gate operators similarly with role='gate'.
