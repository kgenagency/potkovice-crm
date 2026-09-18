-- COMPLETE CRM · POTKOVICE modul (tabele p_*)
create table if not exists public.p_products (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,                -- VERONA
  category text,                     -- haljina
  buy_price numeric(10,2) not null default 0,
  sell_price numeric(10,2) not null default 0,
  compare_price numeric(10,2),       -- "bila" cena
  supplier text,
  material text,
  image_url text,
  shopify_product_id text unique,
  status text not null default 'active' check (status in ('draft','active','archived')),
  note text
);

create table if not exists public.p_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.p_products(id) on delete cascade,
  size text not null,                -- S / M / L / UNI
  color text,
  stock int not null default 0,
  shopify_variant_id text unique,
  unique (product_id, size, color)
);

create table if not exists public.p_orders (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  order_no text,                     -- #1001 ili IG-001
  channel text not null default 'instagram' check (channel in ('shopify','instagram','other')),
  customer_name text not null,
  phone text,
  email text,
  instagram text,
  address text,
  city text,
  postal_code text,
  status text not null default 'new'
    check (status in ('new','confirmed','packed','shipped','delivered','returned','cancelled')),
  payment text not null default 'cod' check (payment in ('cod','card','bank')),
  shipping_price numeric(10,2) not null default 0,   -- naplaćeno kupcu
  shipping_cost numeric(10,2) not null default 0,    -- plaćeno kuriru
  packaging_cost numeric(10,2) not null default 0,   -- kutija, papir, stiker, šnalica
  discount numeric(10,2) not null default 0,
  discount_code text,
  courier text,
  tracking_no text,
  courier_status text,
  shipped_at timestamptz,
  delivered_at timestamptz,
  shopify_order_id text unique,
  note text
);

create table if not exists public.p_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.p_orders(id) on delete cascade,
  product_id uuid references public.p_products(id) on delete set null,
  variant_id uuid references public.p_variants(id) on delete set null,
  name text not null,                -- snapshot imena
  size text,
  qty int not null default 1,
  unit_price numeric(10,2) not null default 0,  -- prodajna u trenutku porudžbine
  unit_cost numeric(10,2) not null default 0    -- nabavna u trenutku porudžbine
);

create table if not exists public.p_ad_spend (
  id uuid primary key default gen_random_uuid(),
  day date not null,
  campaign text not null default 'all',
  spend numeric(10,2) not null default 0,
  purchases int,
  revenue numeric(10,2),
  unique (day, campaign)
);

create table if not exists public.p_activities (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.p_orders(id) on delete cascade,
  product_id uuid references public.p_products(id) on delete cascade,
  type text not null check (type in ('comment','status','stock','screenshot','system')),
  author text not null,
  body text,
  attachment_url text,
  created_at timestamptz not null default now()
);

create index if not exists p_orders_created_idx on public.p_orders(created_at desc);
create index if not exists p_items_order_idx on public.p_order_items(order_id);
create index if not exists p_variants_product_idx on public.p_variants(product_id);
create index if not exists p_act_order_idx on public.p_activities(order_id, created_at);

-- zbirni pregled porudžbine: prihod, trošak robe, profit
create or replace view public.p_order_totals with (security_invoker = true) as
select o.id, o.created_at, o.status, o.channel,
  coalesce(sum(i.qty*i.unit_price),0) as items_total,
  coalesce(sum(i.qty*i.unit_cost),0)  as items_cost,
  coalesce(sum(i.qty*i.unit_price),0) + o.shipping_price - o.discount as revenue,
  coalesce(sum(i.qty*i.unit_price),0) - o.discount
    - coalesce(sum(i.qty*i.unit_cost),0) - o.packaging_cost
    - (o.shipping_cost - o.shipping_price) as gross_profit
from public.p_orders o left join public.p_order_items i on i.order_id = o.id
group by o.id;

-- RLS: samo ulogovan tim
do $$ declare t text; begin
  foreach t in array array['p_products','p_variants','p_orders','p_order_items','p_ad_spend','p_activities'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "team all" on public.%I', t);
    execute format('create policy "team all" on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;
-- v2: Objave, Sajt, Brand story, beleške
create table if not exists public.p_posts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  title text not null,
  concept text,
  hook text,
  caption text,
  format text not null default 'reel',          -- reel / carousel / story / post / tiktok
  status text not null default 'idea' check (status in ('idea','scripting','filming','editing','scheduled','published')),
  publish_at timestamptz,
  drive_link text,
  post_url text,
  product_id uuid references public.p_products(id) on delete set null,
  assignee text,
  created_by text,
  views int, likes int, saves int
);
create table if not exists public.p_site_ideas (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  title text not null,
  description text,
  category text not null default 'dizajn',       -- dizajn / tekst / funkcija / proizvod / ostalo
  priority text not null default 'medium' check (priority in ('low','medium','high')),
  status text not null default 'proposed' check (status in ('proposed','approved','in_progress','done','rejected')),
  link text,
  image_url text,
  created_by text,
  votes text[] not null default '{}'
);
create table if not exists public.p_story_sections (
  id uuid primary key default gen_random_uuid(),
  position int not null default 0,
  title text not null,
  body text not null default '',
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists public.p_notes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  area text not null default 'story',
  author text not null,
  body text not null,
  pinned boolean not null default false,
  done boolean not null default false
);
alter table public.p_activities add column if not exists post_id uuid references public.p_posts(id) on delete cascade;
alter table public.p_activities add column if not exists site_id uuid references public.p_site_ideas(id) on delete cascade;
alter table public.p_activities drop constraint if exists p_activities_type_check;
alter table public.p_activities add constraint p_activities_type_check check (type in ('comment','status','stock','screenshot','system','alert'));

do $$ declare t text; begin
  foreach t in array array['p_posts','p_site_ideas','p_story_sections','p_notes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "team all" on public.%I', t);
    execute format('create policy "team all" on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;
-- v3: Pakovanje
alter table public.p_site_ideas add column if not exists area text not null default 'site';
create table if not exists public.p_packaging (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  kind text not null default 'kutija',            -- kutija / papir / stiker / kartica / etiketa / poklon / ostalo
  supplier text,
  link text,
  unit_price numeric(10,2),
  stock int not null default 0,
  min_stock int not null default 10,
  per_order int not null default 0,               -- koliko ide u svaki paket (0 = ne ide automatski)
  image_url text,
  note text
);
alter table public.p_packaging enable row level security;
drop policy if exists "team all" on public.p_packaging;
create policy "team all" on public.p_packaging for all to authenticated using (true) with check (true);
alter table public.p_activities add column if not exists packaging_id uuid references public.p_packaging(id) on delete cascade;
-- v4: Povrati, reklamacije, feedback
create sequence if not exists public.p_returns_seq start 1;
create table if not exists public.p_returns (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  case_no text not null unique default ('P-' || lpad(nextval('public.p_returns_seq')::text, 4, '0')),
  type text not null check (type in ('return','exchange','complaint','feedback')),
  source text not null default 'form',
  status text not null default 'new' check (status in ('new','in_review','waiting_package','received','resolved','rejected')),
  order_no text,
  order_id uuid references public.p_orders(id) on delete set null,
  customer_name text not null,
  phone text, email text, instagram text,
  item text,
  size text,
  product_id uuid references public.p_products(id) on delete set null,
  reason text,
  description text,
  photos text[] not null default '{}',
  resolution_wanted text,
  exchange_details text,
  bank_account text,
  rating int check (rating between 1 and 5),
  delivered_on date,
  package_received_at timestamptz,
  refund_amount numeric(10,2),
  return_shipping_cost numeric(10,2),
  restocked boolean not null default false,
  resolution_note text,
  improve text,
  resolved_at timestamptz,
  assignee text,
  consent boolean not null default false
);
alter table public.p_returns enable row level security;
drop policy if exists "team all" on public.p_returns;
create policy "team all" on public.p_returns for all to authenticated using (true) with check (true);
alter table public.p_activities add column if not exists return_id uuid references public.p_returns(id) on delete cascade;
-- v5: podešavanja (link sajta i sl.)
create table if not exists public.p_settings (
  key text primary key,
  value text,
  updated_at timestamptz not null default now(),
  updated_by text
);
alter table public.p_settings enable row level security;
drop policy if exists "team all" on public.p_settings;
create policy "team all" on public.p_settings for all to authenticated using (true) with check (true);
-- v6: trajna istorija, promocije, prekretnice, dnevni presek, meko brisanje

-- 1) meko brisanje: ništa se fizički ne briše
do $$ declare t text; begin
  foreach t in array array['p_products','p_variants','p_orders','p_order_items','p_posts','p_site_ideas','p_returns','p_packaging','p_notes','p_story_sections','p_ad_spend'] loop
    execute format('alter table public.%I add column if not exists deleted_at timestamptz', t);
    execute format('alter table public.%I add column if not exists deleted_by text', t);
  end loop;
end $$;

-- 2) audit: svaka promena svakog reda, zauvek
create table if not exists public.p_audit (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor text,
  tbl text not null,
  row_id text,
  op text not null,
  old_row jsonb,
  new_row jsonb,
  changed jsonb
);
create index if not exists p_audit_at_idx on public.p_audit(at desc);
create index if not exists p_audit_row_idx on public.p_audit(tbl, row_id);
alter table public.p_audit enable row level security;
drop policy if exists "team read" on public.p_audit;
create policy "team read" on public.p_audit for select to authenticated using (true);

create or replace function public.p_audit_fn() returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor text; v_old jsonb; v_new jsonb; v_changed jsonb; k text;
begin
  v_actor := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'email', 'system');
  v_actor := split_part(v_actor, '@', 1);
  if tg_op = 'INSERT' then v_new := to_jsonb(new);
  elsif tg_op = 'UPDATE' then v_old := to_jsonb(old); v_new := to_jsonb(new);
    v_changed := '{}'::jsonb;
    for k in select jsonb_object_keys(v_new) loop
      if v_new->k is distinct from v_old->k then v_changed := v_changed || jsonb_build_object(k, jsonb_build_object('od', v_old->k, 'na', v_new->k)); end if;
    end loop;
    if v_changed = '{}'::jsonb then return new; end if;
  else v_old := to_jsonb(old); end if;
  insert into p_audit (actor, tbl, row_id, op, old_row, new_row, changed)
  values (v_actor, tg_table_name, coalesce(v_new->>'id', v_old->>'id', v_new->>'key', v_old->>'key'), tg_op, v_old, v_new, v_changed);
  return coalesce(new, old);
end $$;

do $$ declare t text; begin
  foreach t in array array['p_products','p_variants','p_orders','p_order_items','p_posts','p_site_ideas','p_returns','p_packaging','p_notes','p_story_sections','p_ad_spend','p_settings','p_activities'] loop
    execute format('drop trigger if exists p_audit_trg on public.%I', t);
    execute format('create trigger p_audit_trg after insert or update or delete on public.%I for each row execute function public.p_audit_fn()', t);
  end loop;
end $$;

-- 3) promocije
create table if not exists public.p_promotions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  type text not null default 'code' check (type in ('code','free_shipping','flash','bundle','giveaway','influencer','launch','other')),
  code text,
  discount_pct numeric(5,2),
  discount_rsd numeric(10,2),
  description text,
  channel text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  budget numeric(10,2),
  goal text,
  result_note text,
  created_by text,
  deleted_at timestamptz, deleted_by text
);
alter table public.p_promotions enable row level security;
drop policy if exists "team all" on public.p_promotions;
create policy "team all" on public.p_promotions for all to authenticated using (true) with check (true);
drop trigger if exists p_audit_trg on public.p_promotions;
create trigger p_audit_trg after insert or update or delete on public.p_promotions for each row execute function public.p_audit_fn();
alter table public.p_activities add column if not exists promo_id uuid references public.p_promotions(id) on delete set null;

-- 4) prekretnice (ručni zapisi u istoriji)
create table if not exists public.p_milestones (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  happened_at timestamptz not null default now(),
  kind text not null default 'event' check (kind in ('start','end','decision','milestone','event')),
  title text not null,
  body text,
  author text,
  deleted_at timestamptz, deleted_by text
);
alter table public.p_milestones enable row level security;
drop policy if exists "team all" on public.p_milestones;
create policy "team all" on public.p_milestones for all to authenticated using (true) with check (true);
drop trigger if exists p_audit_trg on public.p_milestones;
create trigger p_audit_trg after insert or update or delete on public.p_milestones for each row execute function public.p_audit_fn();

-- 5) dnevni presek stanja (da se zna kako je bilo tog dana)
create table if not exists public.p_daily_stats (
  day date primary key,
  orders int not null default 0,
  revenue numeric(12,2) not null default 0,
  profit numeric(12,2) not null default 0,
  stock_pcs int not null default 0,
  stock_value numeric(12,2) not null default 0,
  ad_spend numeric(12,2) not null default 0,
  open_returns int not null default 0,
  active_products int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.p_daily_stats enable row level security;
drop policy if exists "team all" on public.p_daily_stats;
create policy "team all" on public.p_daily_stats for all to authenticated using (true) with check (true);
-- v7: kupci, loyalty, popusti
create table if not exists public.p_customers (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  phone text, phone_norm text, email text, instagram text,
  city text, address text, postal_code text,
  tags text[] not null default '{}',
  vip boolean not null default false,
  points_adj int not null default 0,
  birthday date,
  source text,
  note text,
  first_order_at timestamptz,
  deleted_at timestamptz, deleted_by text
);
create index if not exists p_customers_phone_idx on public.p_customers(phone_norm);
alter table public.p_orders add column if not exists customer_id uuid references public.p_customers(id) on delete set null;
alter table public.p_returns add column if not exists customer_id uuid references public.p_customers(id) on delete set null;
alter table public.p_activities add column if not exists customer_id uuid references public.p_customers(id) on delete cascade;

create table if not exists public.p_loyalty_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  customer_id uuid not null references public.p_customers(id) on delete cascade,
  points int not null,
  reason text,
  author text,
  order_id uuid references public.p_orders(id) on delete set null,
  code_id uuid
);
create table if not exists public.p_discount_codes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  code text not null,
  kind text not null default 'general' check (kind in ('general','personal','loyalty','influencer')),
  customer_id uuid references public.p_customers(id) on delete set null,
  pct numeric(5,2), rsd numeric(10,2), min_order numeric(10,2),
  valid_from timestamptz not null default now(), valid_to timestamptz,
  max_uses int,
  note text, created_by text,
  active boolean not null default true,
  deleted_at timestamptz, deleted_by text
);
create unique index if not exists p_discount_codes_code_idx on public.p_discount_codes(upper(code)) where deleted_at is null;

do $$ declare t text; begin
  foreach t in array array['p_customers','p_loyalty_events','p_discount_codes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "team all" on public.%I', t);
    execute format('create policy "team all" on public.%I for all to authenticated using (true) with check (true)', t);
    execute format('drop trigger if exists p_audit_trg on public.%I', t);
    execute format('create trigger p_audit_trg after insert or update or delete on public.%I for each row execute function public.p_audit_fn()', t);
  end loop;
end $$;

create or replace function public.p_norm_phone(p text) returns text language sql immutable as $$
  select case when p is null then null else
    regexp_replace(regexp_replace(regexp_replace(p, '\D', '', 'g'), '^00381', '0'), '^381', '0') end $$;
create or replace function public.p_norm_ig(p text) returns text language sql immutable as $$
  select nullif(lower(regexp_replace(coalesce(p,''), '^@|\s|https?://(www\.)?instagram\.com/|/$', '', 'g')), '') $$;

-- nađi ili napravi kupca za porudžbinu
create or replace function public.p_find_or_create_customer(p_name text, p_phone text, p_email text, p_ig text, p_city text, p_address text, p_zip text, p_source text, p_at timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid; ph text := nullif(p_norm_phone(p_phone), ''); ig text := p_norm_ig(p_ig); em text := nullif(lower(trim(p_email)), '');
begin
  if ph is not null then select id into cid from p_customers where phone_norm = ph and deleted_at is null limit 1; end if;
  if cid is null and ig is not null then select id into cid from p_customers where p_norm_ig(instagram) = ig and deleted_at is null limit 1; end if;
  if cid is null and em is not null then select id into cid from p_customers where lower(email) = em and deleted_at is null limit 1; end if;
  if cid is null and ph is null and ig is null and em is null then
    select id into cid from p_customers where lower(name) = lower(trim(p_name)) and deleted_at is null limit 1; end if;
  if cid is null then
    insert into p_customers (name, phone, phone_norm, email, instagram, city, address, postal_code, source, first_order_at)
    values (trim(p_name), p_phone, ph, p_email, p_ig, p_city, p_address, p_zip, p_source, p_at) returning id into cid;
  else
    update p_customers set
      phone = coalesce(phone, p_phone), phone_norm = coalesce(phone_norm, ph), email = coalesce(email, p_email), instagram = coalesce(instagram, p_ig),
      city = coalesce(p_city, city), address = coalesce(p_address, address), postal_code = coalesce(p_zip, postal_code),
      first_order_at = least(coalesce(first_order_at, p_at), coalesce(p_at, first_order_at))
    where id = cid;
  end if;
  return cid;
end $$;

create or replace function public.p_order_link_customer() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.customer_id is null and new.customer_name is not null then
    new.customer_id := p_find_or_create_customer(new.customer_name, new.phone, new.email, new.instagram, new.city, new.address, new.postal_code, new.channel, new.created_at);
  end if;
  return new;
end $$;
drop trigger if exists p_order_link_trg on public.p_orders;
create trigger p_order_link_trg before insert or update of customer_name, phone, email, instagram on public.p_orders for each row execute function public.p_order_link_customer();

create or replace function public.p_return_link_customer() returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid; ph text := nullif(p_norm_phone(new.phone), ''); ig text := p_norm_ig(new.instagram); em text := nullif(lower(trim(new.email)), '');
begin
  if new.customer_id is null then
    if new.order_id is not null then select customer_id into cid from p_orders where id = new.order_id; end if;
    if cid is null and ph is not null then select id into cid from p_customers where phone_norm = ph and deleted_at is null limit 1; end if;
    if cid is null and ig is not null then select id into cid from p_customers where p_norm_ig(instagram) = ig and deleted_at is null limit 1; end if;
    if cid is null and em is not null then select id into cid from p_customers where lower(email) = em and deleted_at is null limit 1; end if;
    new.customer_id := cid;
  end if;
  return new;
end $$;
drop trigger if exists p_return_link_trg on public.p_returns;
create trigger p_return_link_trg before insert or update of phone, email, instagram, order_id on public.p_returns for each row execute function public.p_return_link_customer();
-- v8: obaveštenja
create table if not exists public.p_notif_state (
  username text primary key,
  cleared_before timestamptz,
  dismissed bigint[] not null default '{}',
  snooze_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.p_notif_state enable row level security;
drop policy if exists "team all" on public.p_notif_state;
create policy "team all" on public.p_notif_state for all to authenticated using (true) with check (true);
-- realtime na audit (živa obaveštenja)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='p_audit') then
    alter publication supabase_realtime add table public.p_audit;
  end if;
end $$;
-- v9: izmena beleški
alter table public.p_notes add column if not exists updated_at timestamptz;
alter table public.p_notes add column if not exists updated_by text;
alter table public.p_notes add column if not exists done_by text;
alter table public.p_notif_state add column if not exists seen_tabs jsonb not null default '{}'::jsonb;
-- v11: AI asistent, evidencija potrošnje
create table if not exists public.p_ai_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  username text not null,
  model text,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  cache_read int not null default 0,
  cache_write int not null default 0,
  cost_usd numeric(10,5) not null default 0
);
create index if not exists p_ai_log_user_at on public.p_ai_log(username, at);
alter table public.p_ai_log enable row level security;
drop policy if exists "team read" on public.p_ai_log;
create policy "team read" on public.p_ai_log for select to authenticated using (true);

-- ================= POTKOVICE: dodaci =================
alter table public.p_products add column if not exists maker text;                      -- proizvođač (Mustad, St. Croix…)
alter table public.p_products add column if not exists unit text not null default 'kom'; -- kom / par / kutija
alter table public.p_products add column if not exists pack_qty int not null default 1;  -- komada u pakovanju

-- nabavka i uvoz (ture)
create table if not exists public.p_imports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  code text,
  supplier text not null,
  country text,
  status text not null default 'planned' check (status in ('planned','ordered','paid','transit','customs','arrived','cancelled')),
  ordered_at date, paid_at date, eta date, arrived_at date,
  currency text not null default 'EUR',
  fx numeric(10,4),
  freight_cost numeric(12,2) not null default 0,
  duty_cost numeric(12,2) not null default 0,
  other_cost numeric(12,2) not null default 0,
  tracking text, note text, created_by text,
  received boolean not null default false,
  deleted_at timestamptz, deleted_by text
);
create table if not exists public.p_import_items (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.p_imports(id) on delete cascade,
  product_id uuid references public.p_products(id) on delete set null,
  variant_id uuid references public.p_variants(id) on delete set null,
  name text, size text,
  qty int not null default 1,
  unit_cost numeric(12,2) not null default 0,
  deleted_at timestamptz, deleted_by text
);
create index if not exists p_import_items_imp_idx on public.p_import_items(import_id);
alter table public.p_imports enable row level security;
alter table public.p_import_items enable row level security;
drop policy if exists "team all" on public.p_imports;
create policy "team all" on public.p_imports for all to authenticated using (true) with check (true);
drop policy if exists "team all" on public.p_import_items;
create policy "team all" on public.p_import_items for all to authenticated using (true) with check (true);
drop trigger if exists p_audit_trg on public.p_imports;
create trigger p_audit_trg after insert or update or delete on public.p_imports for each row execute function public.p_audit_fn();
drop trigger if exists p_audit_trg on public.p_import_items;
create trigger p_audit_trg after insert or update or delete on public.p_import_items for each row execute function public.p_audit_fn();
alter table public.p_activities add column if not exists import_id uuid references public.p_imports(id) on delete cascade;
alter table public.p_activities drop constraint if exists p_activities_type_check;
alter table public.p_activities add constraint p_activities_type_check check (type in ('comment','status','stock','screenshot','system','alert'));

insert into public.p_settings (key, value) values ('site_url', ''), ('site_pass', '')
on conflict (key) do nothing;
insert into public.p_milestones (happened_at, kind, title, body, author)
select now(), 'event', 'Pokrenut CRM za potkovice', 'Prva verzija: porudžbine, roba, kupci, nabavka i uvoz, reklamacije, objave, sajt, reklame, istorija.', 'Konstantin'
where not exists (select 1 from public.p_milestones);
-- ===== POTKOVICE: pravila pristupa po modulu (crm_user) =====
-- ko je prijavljen (korisničko ime iz mejla)
create or replace function public.crm_user() returns text language sql stable as $$
  select lower(split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1))
$$;
revoke all on function public.crm_user() from public;
grant execute on function public.crm_user() to authenticated, anon;

-- pravila pristupa po modulu
do $$
declare t record;
begin
  for t in select table_name from information_schema.tables
           where table_schema = 'public' and table_type = 'BASE TABLE' and (table_name like 'h\_%' or table_name like 'p\_%')
  loop
    execute format('alter table public.%I enable row level security', t.table_name);
    execute format('drop policy if exists "team all" on public.%I', t.table_name);
    execute format('drop policy if exists "team read" on public.%I', t.table_name);
    execute format('drop policy if exists "modul harizma" on public.%I', t.table_name);
    execute format('drop policy if exists "modul potkovice" on public.%I', t.table_name);
    if t.table_name like 'h\_%' then
      execute format($f$create policy "modul harizma" on public.%I for all to authenticated
        using (public.crm_user() in ('konstantin','stasa','marjan'))
        with check (public.crm_user() in ('konstantin','stasa','marjan'))$f$, t.table_name);
    else
      execute format($f$create policy "modul potkovice" on public.%I for all to authenticated
        using (public.crm_user() in ('konstantin','marjan','stefan'))
        with check (public.crm_user() in ('konstantin','marjan','stefan'))$f$, t.table_name);
    end if;
  end loop;
end $$;

-- slike: svaki modul svoje kante
insert into storage.buckets (id, name, public) values ('p-screenshots','p-screenshots', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('p-returns','p-returns', false, 10485760, array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

drop policy if exists "crm screenshots upload" on storage.objects;
drop policy if exists "crm screenshots read" on storage.objects;
drop policy if exists "returns team read" on storage.objects;
drop policy if exists "pk screenshots rw" on storage.objects;
drop policy if exists "pk returns rw" on storage.objects;

create policy "crm screenshots upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'screenshots' and public.crm_user() in ('konstantin','stasa','marjan'));
create policy "crm screenshots read" on storage.objects for select to authenticated
  using (bucket_id = 'screenshots' and public.crm_user() in ('konstantin','stasa','marjan'));
create policy "returns team read" on storage.objects for select to authenticated
  using (bucket_id = 'returns' and public.crm_user() in ('konstantin','stasa','marjan'));
create policy "pk screenshots rw" on storage.objects for all to authenticated
  using (bucket_id in ('p-screenshots','p-returns') and public.crm_user() in ('konstantin','marjan','stefan'))
  with check (bucket_id in ('p-screenshots','p-returns') and public.crm_user() in ('konstantin','marjan','stefan'));

-- POTKOVICE v2: šta treba biznisu koji uvozi i prodaje po Srbiji
alter table public.p_products add column if not exists wholesale_price numeric(10,2);   -- veleprodajna (potkivači)
alter table public.p_products add column if not exists profile text;                    -- presek, npr. 22x8
alter table public.p_products add column if not exists clips text;                      -- kapne: prednja 1 prstna, zadnja 2 bočne
alter table public.p_products add column if not exists moq int not null default 1000;   -- fabrički minimum po modelu
alter table public.p_products add column if not exists weight_g int;                    -- težina komada u gramima
alter table public.p_variants add column if not exists min_stock int;                   -- granica upozorenja po veličini (null = opšta)
alter table public.p_customers add column if not exists kind text;                      -- potkivac, ergela, klub, salas, prodavnica, veterinar, ostalo
alter table public.p_customers add column if not exists company text;
alter table public.p_customers add column if not exists pib text;
alter table public.p_customers add column if not exists price_tier text not null default 'retail';  -- retail / wholesale
alter table public.p_customers add column if not exists cycle_days int;                 -- očekivani razmak između porudžbina (ručno; inače se računa)
alter table public.p_orders add column if not exists paid_at timestamptz;
alter table public.p_orders add column if not exists due_date date;
alter table public.p_orders add column if not exists invoice_no text;
alter table public.p_orders add column if not exists delivery text;                     -- kurir / licno / preuzimanje
alter table public.p_imports add column if not exists duty_pct numeric(5,2);
alter table public.p_imports add column if not exists vat_cost numeric(12,2) not null default 0;
alter table public.p_imports add column if not exists vat_recoverable boolean not null default false;
alter table public.p_imports add column if not exists advance_pct int not null default 30;
alter table public.p_imports add column if not exists advance_paid_at date;
alter table public.p_imports add column if not exists qc jsonb not null default '{}'::jsonb;
alter table public.p_imports add column if not exists lead_days int;
alter table public.p_imports drop constraint if exists p_imports_status_check;
alter table public.p_imports add constraint p_imports_status_check check (status in ('planned','sample','ordered','paid','transit','customs','arrived','cancelled'));

insert into public.p_settings (key, value) values ('cover_months', '4'), ('vat_recoverable', '0'), ('moq_default', '1000'), ('site_url', 'https://w0bxjz-sm.myshopify.com')
on conflict (key) do update set value = excluded.value where public.p_settings.key = 'site_url' and (public.p_settings.value is null or public.p_settings.value = '');

-- Asortiman iz mozga (Đoletovi prioriteti + System Line reference), status Priprema dok ne stigne prva tura
insert into public.p_products (id, name, category, maker, material, unit, pack_qty, profile, clips, moq, buy_price, wholesale_price, sell_price, compare_price, supplier, status, note) values
 ('a0000000-0000-4000-8000-000000000001','RADNA 22x8','radna','naša (kovana, Kina)','čelik, kovano','kom',40,'22x8','prednja 1 prstna, zadnja 2 bočne',1000,190,340,450,460,'Jimo Qiangli / Jerlan','draft','PRIORITET 1. Referenca oblika: Kerckhaert DF 22x8 (System Line 460 RSD), Mustad LiBero. Fulerirana, 4+4 probijene rupe za E-head. Ekseri E3–E6. Nabavna je PROCENA do prve ture.'),
 ('a0000000-0000-4000-8000-000000000002','KASAČKA RAPID','kasačka','naša (kovana, Kina)','čelik, kovano','kom',40,'15x6','1 prstna',1000,170,300,400,400,'Jimo Qiangli / Jerlan','draft','PRIORITET 2. Referenca: Mustad Rapid (Clair 360–400), KW Fram 15x6 (System Line 400). Ravna i sa žlebom. Nabavna je PROCENA do prve ture.'),
 ('a0000000-0000-4000-8000-000000000003','KASAČKA HALF ROUND','kasačka','naša (kovana, Kina)','čelik, kovano','kom',40,'15x5 polukružni','1 prstna',1000,170,340,450,500,'Jimo Qiangli / Jerlan','draft','PRIORITET 2b. Referenca: KW Half Round 15x5 (System Line 500), Mustad Half Round (Clair od 400). Nabavna je PROCENA do prve ture.'),
 ('a0000000-0000-4000-8000-000000000004','ALU TROT FLAT','aluminijumska','naša (die forged, Kina)','aluminijum','kom',40,'alu','1 prstna',1000,280,990,1290,1400,'Thinkwell / Qiangli','draft','PRIORITET 3. Referenca: Cawe Trot Flat (System Line 1.400–1.800). Numeracija po širini u mm. Nabavna je PROCENA do prve ture.'),
 ('a0000000-0000-4000-8000-000000000005','GALOPSKA ALU','galopska','naša (die forged, Kina)','aluminijum','kom',40,'20x9 alu','1 prstna',1000,260,590,750,750,'Thinkwell / Qiangli','draft','PRIORITET 4. Referenca: Kerckhaert Kings Plate Extra Sound (System Line 750, poreklo Kina). Trkačka numeracija. Nabavna je PROCENA do prve ture.'),
 ('a0000000-0000-4000-8000-000000000006','EKSERI E-HEAD (kutija 250)','ekseri','naša (Kina)','čelik','kutija',1,'E-head','',100,350,1390,1800,1900,'Qiangli / Thinkwell','draft','Referenca: Liberty E-head (System Line 1.900–2.720 za 250). U Srbiji idu E3–E6 (45–54 mm). Fabrici zadati dužinu u mm, ne E broj. Nabavna je PROCENA do prve ture.')
on conflict (id) do nothing;

insert into public.p_variants (product_id, size, color, stock)
select p.id, v.size, v.color, 0 from (values
 ('a0000000-0000-4000-8000-000000000001','00','prednja'),('a0000000-0000-4000-8000-000000000001','00','zadnja'),
 ('a0000000-0000-4000-8000-000000000001','0','prednja'),('a0000000-0000-4000-8000-000000000001','0','zadnja'),
 ('a0000000-0000-4000-8000-000000000001','1','prednja'),('a0000000-0000-4000-8000-000000000001','1','zadnja'),
 ('a0000000-0000-4000-8000-000000000001','2','prednja'),('a0000000-0000-4000-8000-000000000001','2','zadnja'),
 ('a0000000-0000-4000-8000-000000000001','3','prednja'),('a0000000-0000-4000-8000-000000000001','3','zadnja'),
 ('a0000000-0000-4000-8000-000000000002','0','ravna'),('a0000000-0000-4000-8000-000000000002','0','žleb'),
 ('a0000000-0000-4000-8000-000000000002','1','ravna'),('a0000000-0000-4000-8000-000000000002','1','žleb'),
 ('a0000000-0000-4000-8000-000000000002','2','ravna'),('a0000000-0000-4000-8000-000000000002','2','žleb'),
 ('a0000000-0000-4000-8000-000000000002','3','ravna'),('a0000000-0000-4000-8000-000000000002','3','žleb'),
 ('a0000000-0000-4000-8000-000000000002','4','ravna'),('a0000000-0000-4000-8000-000000000002','4','žleb'),
 ('a0000000-0000-4000-8000-000000000003','1',''),('a0000000-0000-4000-8000-000000000003','3',''),('a0000000-0000-4000-8000-000000000003','4',''),('a0000000-0000-4000-8000-000000000003','5',''),
 ('a0000000-0000-4000-8000-000000000004','115','prednja'),('a0000000-0000-4000-8000-000000000004','115','zadnja'),
 ('a0000000-0000-4000-8000-000000000004','120','prednja'),('a0000000-0000-4000-8000-000000000004','120','zadnja'),
 ('a0000000-0000-4000-8000-000000000004','125','prednja'),('a0000000-0000-4000-8000-000000000004','125','zadnja'),
 ('a0000000-0000-4000-8000-000000000004','130','prednja'),('a0000000-0000-4000-8000-000000000004','130','zadnja'),
 ('a0000000-0000-4000-8000-000000000005','3-27','prednja'),('a0000000-0000-4000-8000-000000000005','3-27','zadnja'),
 ('a0000000-0000-4000-8000-000000000005','4-28','prednja'),('a0000000-0000-4000-8000-000000000005','4-28','zadnja'),
 ('a0000000-0000-4000-8000-000000000005','5-29','prednja'),('a0000000-0000-4000-8000-000000000005','5-29','zadnja'),
 ('a0000000-0000-4000-8000-000000000005','6-30','prednja'),('a0000000-0000-4000-8000-000000000005','6-30','zadnja'),
 ('a0000000-0000-4000-8000-000000000005','7-32','prednja'),('a0000000-0000-4000-8000-000000000005','7-32','zadnja'),
 ('a0000000-0000-4000-8000-000000000006','E3 (45 mm)',''),('a0000000-0000-4000-8000-000000000006','E4 (47,5 mm)',''),('a0000000-0000-4000-8000-000000000006','E5 (51 mm)',''),('a0000000-0000-4000-8000-000000000006','E6 (54 mm)','')
) as v(pid, size, color) join public.p_products p on p.id = v.pid::uuid
where not exists (select 1 from public.p_variants x where x.product_id = p.id and x.size = v.size and coalesce(x.color,'') = v.color);

-- Istorija projekta iz mozga
insert into public.p_milestones (happened_at, kind, title, body, author)
select * from (values
 ('2026-08-25'::timestamptz, 'decision', 'Đole potvrdio prioritete asortimana', 'Prioriteti: (1) 22x8 bilo kog proizvođača, (2) Rapid i Half Round kasačke, (3) Alu Trot Flat, (4) galopske. Ortopedske ne. Ekseri po Đoletu 0–2, po System Line-u u Srbiji idu E3–E6.', 'Konstantin'),
 ('2026-08-27'::timestamptz, 'event', 'Proverene domaće cene i poslat RFQ v1', 'Clair i System Line kao referentni retail (22x8 od 450–460, kasačke 360–500, alu trot 1.400–1.800, Kings Plate 750, ekseri 1.900–2.720/250). RFQ v1: 2.000 potkovica + 25.000 eksera, 6 stavki, 43 artikla.', 'Konstantin'),
 ('2026-09-02'::timestamptz, 'event', 'Demo sajt potkovica.rs gotov', 'Shopify w0bxjz-sm, 6 proizvoda, intro animacija, srpski prevod. Čeka Publish teme i domen potkovica.rs.', 'Konstantin'),
 ('2026-09-08'::timestamptz, 'event', 'Qiangli poslao spec-liste', 'Jimo Qiangli Forging (od 1996, izvoz u UK i Irsku): FLAT 8 mm sa kapnama je kandidat za 22x8. Fale cene, presek i potvrda drop forged. Thinkwell verovatno preprodaje Qiangli robu.', 'Konstantin')
) as m(happened_at, kind, title, body, author)
where not exists (select 1 from public.p_milestones where title = m.title);

-- Pravila koja se znaju napamet (zakačene beleške)
insert into public.p_notes (area, author, body, pinned)
select 'general', 'konstantin', b, true from (values
 ('PRAVILO: u svakoj porudžbini fabrici mora da stoji DROP FORGED, nikad samo „steel horseshoe“. Livena puca kod kapne. Test na uzorku: stegni u mengele i savij.'),
 ('PRAVILO: 22x8 je PROFIL (širina × debljina), veličina je nešto drugo (00–3 po Kerckhaertu = 122–152 mm). Sa fabrikom uvek crteži u milimetrima, nikad brojevi.'),
 ('PRAVILO: kapne se ne podrazumevaju. Prednja 1 prstna kapna (toe clip), zadnja 2 bočne (side clips). Kineske fabrike prave bez kapni ako se ne traži.'),
 ('PRAVILO: MOQ je 1.000 komada po modelu. Ispod toga cena skače 40–80% ili odbijaju. Prvi test: 2 modela × 1.000+, ne 6 modela.'),
 ('PRAVILO: uvozni PDV 20% je nepovratan trošak dok firma nije u sistemu PDV-a (oko 80.000 RSD na test turi). U turi štikliraj „PDV se odbija“ tek kad uđemo u sistem.'),
 ('PRAVILO: nikad avans pre nego što uzorak prođe kontrolu kod potkivača (kovano, probijene rupe, ekser se ne klati, ista debljina, kapna izvučena, prednja ≠ zadnja).')
) as t(b)
where not exists (select 1 from public.p_notes where body like 'PRAVILO:%');

-- kanali i plaćanja
alter table public.p_orders drop constraint if exists p_orders_channel_check;
alter table public.p_orders add constraint p_orders_channel_check check (channel in ('shopify','instagram','phone','person','other'));
alter table public.p_orders drop constraint if exists p_orders_payment_check;
alter table public.p_orders add constraint p_orders_payment_check check (payment in ('cod','cash','bank','invoice','card'));
alter table public.p_orders alter column channel set default 'phone';
-- telefon se normalizuje i kad se kupac unese ručno
create or replace function public.p_customer_norm() returns trigger language plpgsql as $$
begin new.phone_norm := nullif(p_norm_phone(new.phone), ''); return new; end $$;
drop trigger if exists p_customer_norm_trg on public.p_customers;
create trigger p_customer_norm_trg before insert or update of phone on public.p_customers for each row execute function public.p_customer_norm();
