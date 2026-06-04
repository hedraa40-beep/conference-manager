create extension if not exists pgcrypto;

-- Conference Manager Pro V1
-- Real tables + JSON state compatibility + audit log + role users.

create table if not exists public.conference_rooms (
  room_id text primary key,
  secret_hash text not null,
  data jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  updated_at timestamptz not null default now()
);

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  username text not null,
  full_name text not null,
  role text not null check (role in ('admin','finance','committees','viewer')),
  pin_hash text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(room_id, username)
);

create table if not exists public.members (
  id text primary key,
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  name text not null default '',
  phone text default '',
  paid numeric not null default 0,
  notes text default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id text primary key,
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  expense_date date,
  category text not null default 'أخرى',
  member_id text,
  meal_type text default '',
  count numeric not null default 1,
  unit_price numeric not null default 0,
  amount numeric not null default 0,
  description text default '',
  notes text default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.revenues (
  id text primary key,
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  revenue_date date,
  type text default 'أخرى',
  source text default '',
  amount numeric not null default 0,
  notes text default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.committees (
  id text primary key,
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  name text not null default '',
  leader text default '',
  tasks text default '',
  member_ids jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.activities (
  id text primary key,
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  name text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.attendance (
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  activity_id text not null,
  member_id text not null,
  attended_at timestamptz not null default now(),
  primary key(room_id, activity_id, member_id)
);

create table if not exists public.audit_logs (
  id text primary key,
  room_id text not null references public.conference_rooms(room_id) on delete cascade,
  user_name text default '',
  role text default '',
  action text not null,
  details text default '',
  before_value text default '',
  after_value text default '',
  created_at timestamptz not null default now()
);

alter table public.conference_rooms enable row level security;
alter table public.app_users enable row level security;
alter table public.members enable row level security;
alter table public.expenses enable row level security;
alter table public.revenues enable row level security;
alter table public.committees enable row level security;
alter table public.activities enable row level security;
alter table public.attendance enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists no_direct_room_access on public.conference_rooms;
create policy no_direct_room_access on public.conference_rooms for all using (false) with check (false);

create or replace function public.sync_normalized_tables(p_room_id text, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare item jsonb; act text; mem text;
begin
  delete from public.members where room_id=p_room_id;
  for item in select * from jsonb_array_elements(coalesce(p_data->'members','[]'::jsonb)) loop
    insert into public.members(id,room_id,name,phone,paid,notes)
    values(item->>'id',p_room_id,item->>'name',item->>'phone',coalesce((item->>'paid')::numeric,0),item->>'notes')
    on conflict(id) do update set name=excluded.name,phone=excluded.phone,paid=excluded.paid,notes=excluded.notes,updated_at=now();
  end loop;

  delete from public.expenses where room_id=p_room_id;
  for item in select * from jsonb_array_elements(coalesce(p_data->'expenses','[]'::jsonb)) loop
    insert into public.expenses(id,room_id,expense_date,category,member_id,meal_type,count,unit_price,amount,description,notes)
    values(item->>'id',p_room_id,nullif(item->>'date','')::date,item->>'category',item->>'memberId',item->>'mealType',coalesce((item->>'count')::numeric,1),coalesce((item->>'unitPrice')::numeric,0),coalesce((item->>'amount')::numeric,0),item->>'desc',item->>'notes')
    on conflict(id) do update set expense_date=excluded.expense_date,category=excluded.category,member_id=excluded.member_id,meal_type=excluded.meal_type,count=excluded.count,unit_price=excluded.unit_price,amount=excluded.amount,description=excluded.description,notes=excluded.notes,updated_at=now();
  end loop;

  delete from public.revenues where room_id=p_room_id;
  for item in select * from jsonb_array_elements(coalesce(p_data->'revenues','[]'::jsonb)) loop
    insert into public.revenues(id,room_id,revenue_date,type,source,amount,notes)
    values(item->>'id',p_room_id,nullif(item->>'date','')::date,item->>'type',item->>'source',coalesce((item->>'amount')::numeric,0),item->>'notes')
    on conflict(id) do update set revenue_date=excluded.revenue_date,type=excluded.type,source=excluded.source,amount=excluded.amount,notes=excluded.notes,updated_at=now();
  end loop;

  delete from public.committees where room_id=p_room_id;
  for item in select * from jsonb_array_elements(coalesce(p_data->'committees','[]'::jsonb)) loop
    insert into public.committees(id,room_id,name,leader,tasks,member_ids)
    values(item->>'id',p_room_id,item->>'name',item->>'leader',item->>'tasks',coalesce(item->'members','[]'::jsonb))
    on conflict(id) do update set name=excluded.name,leader=excluded.leader,tasks=excluded.tasks,member_ids=excluded.member_ids,updated_at=now();
  end loop;

  delete from public.activities where room_id=p_room_id;
  for item in select * from jsonb_array_elements(coalesce(p_data->'activities','[]'::jsonb)) loop
    insert into public.activities(id,room_id,name) values(item->>'id',p_room_id,item->>'name')
    on conflict(id) do update set name=excluded.name,updated_at=now();
  end loop;

  delete from public.attendance where room_id=p_room_id;
  for act, item in select key, value from jsonb_each(coalesce(p_data->'arrivals','{}'::jsonb)) loop
    for mem in select key from jsonb_each(item) loop
      insert into public.attendance(room_id,activity_id,member_id,attended_at)
      values(p_room_id,act,mem,to_timestamp(coalesce((item->>mem)::numeric,0)/1000.0))
      on conflict(room_id,activity_id,member_id) do update set attended_at=excluded.attended_at;
    end loop;
  end loop;

  delete from public.audit_logs where room_id=p_room_id;
  for item in select * from jsonb_array_elements(coalesce(p_data->'auditLogs','[]'::jsonb)) loop
    insert into public.audit_logs(id,room_id,user_name,role,action,details,before_value,after_value,created_at)
    values(coalesce(item->>'id',gen_random_uuid()::text),p_room_id,item->>'userName',item->>'role',coalesce(item->>'action','update'),item->>'details',item->>'before',item->>'after',coalesce(nullif(item->>'at','')::timestamptz,now()))
    on conflict(id) do nothing;
  end loop;
end;
$$;

create or replace function public.init_conference_room(p_room_id text,p_secret text,p_data jsonb default '{}'::jsonb)
returns table(data jsonb, version integer, updated_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if p_room_id is null or length(trim(p_room_id)) < 3 then raise exception 'room_id is required'; end if;
  if p_secret is null or length(p_secret) < 6 then raise exception 'secret must be at least 6 characters'; end if;
  insert into public.conference_rooms(room_id, secret_hash, data, version, updated_at)
  values (trim(p_room_id), crypt(p_secret, gen_salt('bf')), coalesce(p_data, '{}'::jsonb), 1, now()) on conflict(room_id) do nothing;
  if not exists(select 1 from public.conference_rooms r where r.room_id=trim(p_room_id) and r.secret_hash=crypt(p_secret,r.secret_hash)) then raise exception 'wrong room secret'; end if;
  insert into public.app_users(room_id,username,full_name,role,pin_hash)
  values(trim(p_room_id),'admin','مدير النظام','admin',crypt('1234',gen_salt('bf'))) on conflict(room_id,username) do nothing;
  perform public.sync_normalized_tables(trim(p_room_id),coalesce(p_data,'{}'::jsonb));
  return query select r.data,r.version,r.updated_at from public.conference_rooms r where r.room_id=trim(p_room_id);
end; $$;

create or replace function public.app_login(p_room_id text,p_username text,p_pin text)
returns table(ok boolean, user_id uuid, full_name text, role text, message text)
language plpgsql security definer set search_path = public as $$
begin
  return query select true,u.id,u.full_name,u.role,'ok'::text from public.app_users u
  where u.room_id=trim(p_room_id) and u.username=trim(p_username) and u.active=true and u.pin_hash=crypt(p_pin,u.pin_hash) limit 1;
  if not found then return query select false,null::uuid,''::text,''::text,'invalid login'::text; end if;
end; $$;

create or replace function public.get_conference_state(p_room_id text,p_secret text)
returns table(data jsonb, version integer, updated_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.conference_rooms r where r.room_id=trim(p_room_id) and r.secret_hash=crypt(p_secret,r.secret_hash)) then raise exception 'wrong room secret'; end if;
  return query select r.data,r.version,r.updated_at from public.conference_rooms r where r.room_id=trim(p_room_id);
end; $$;

create or replace function public.save_conference_state(p_room_id text,p_secret text,p_expected_version integer,p_data jsonb)
returns table(ok boolean, conflict boolean, data jsonb, version integer, updated_at timestamptz, message text)
language plpgsql security definer set search_path = public as $$
declare current_version integer;
begin
  if not exists(select 1 from public.conference_rooms r where r.room_id=trim(p_room_id) and r.secret_hash=crypt(p_secret,r.secret_hash)) then raise exception 'wrong room secret'; end if;
  select r.version into current_version from public.conference_rooms r where r.room_id=trim(p_room_id) for update;
  if current_version <> coalesce(p_expected_version,0) then
    return query select false,true,r.data,r.version,r.updated_at,'version conflict'::text from public.conference_rooms r where r.room_id=trim(p_room_id); return;
  end if;
  update public.conference_rooms r set data=coalesce(p_data,'{}'::jsonb),version=r.version+1,updated_at=now() where r.room_id=trim(p_room_id);
  perform public.sync_normalized_tables(trim(p_room_id),coalesce(p_data,'{}'::jsonb));
  return query select true,false,r.data,r.version,r.updated_at,'saved'::text from public.conference_rooms r where r.room_id=trim(p_room_id);
end; $$;

grant execute on function public.init_conference_room(text,text,jsonb) to anon, authenticated;
grant execute on function public.app_login(text,text,text) to anon, authenticated;
grant execute on function public.get_conference_state(text,text) to anon, authenticated;
grant execute on function public.save_conference_state(text,text,integer,jsonb) to anon, authenticated;
