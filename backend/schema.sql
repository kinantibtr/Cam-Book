-- =====================================================================
-- FRAME — Camera Rental & Finance
-- backend/schema.sql  (PostgreSQL / Supabase)
--
-- Cara pakai: Supabase Dashboard → SQL Editor → New query →
-- paste seluruh isi file ini → Run. Setelah itu jalankan seed.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. RESET (opsional) — hapus komentar HANYA jika ingin mulai dari nol.
--    Ini akan menghapus semua data!
-- ---------------------------------------------------------------------
-- drop view  if exists v_monthly_cashflow, v_customer_summary;
-- drop table if exists transactions, bookings, cameras, customers cascade;
-- drop sequence if exists customer_seq, camera_seq, booking_seq, transaction_seq;

-- ---------------------------------------------------------------------
-- 1. SEQUENCE untuk kode yang mudah dibaca (CUS-001, CAM-001, ...)
-- ---------------------------------------------------------------------
create sequence if not exists customer_seq    start 1;
create sequence if not exists camera_seq      start 1;
create sequence if not exists booking_seq     start 1;
create sequence if not exists transaction_seq start 1;

-- ---------------------------------------------------------------------
-- 2. TABEL
-- ---------------------------------------------------------------------

-- 2.1 Pelanggan
create table if not exists customers (
  id          text primary key default ('CUS-' || lpad(nextval('customer_seq')::text, 3, '0')),
  name        text not null check (length(trim(name)) > 0),
  phone       text not null,
  email       text,
  address     text,
  created_at  timestamptz not null default now()
);

-- 2.2 Inventaris kamera
create table if not exists cameras (
  id            text primary key default ('CAM-' || lpad(nextval('camera_seq')::text, 3, '0')),
  name          text not null,
  brand         text not null,
  price_per_day numeric(12,0) not null check (price_per_day >= 0),
  status        text not null default 'Tersedia'
                check (status in ('Tersedia', 'Disewa', 'Perawatan')),
  condition     text not null default 'Baik'
                check (condition in ('Baik', 'Perlu pengecekan', 'Rusak ringan', 'Rusak berat')),
  emoji         text not null default '📷',
  created_at    timestamptz not null default now()
);

-- 2.3 Booking & penyewaan
create table if not exists bookings (
  id            text primary key default ('BKG-' || lpad(nextval('booking_seq')::text, 3, '0')),
  customer_id   text not null references customers(id) on delete restrict,
  camera_id     text not null references cameras(id)   on delete restrict,
  start_date    date not null default current_date,
  duration_days integer not null default 1 check (duration_days >= 1),
  total         numeric(14,0) not null default 0,       -- dihitung otomatis oleh trigger
  status        text not null default 'Menunggu'
                check (status in ('Menunggu', 'Berlangsung', 'Selesai', 'Dibatalkan')),
  note          text,
  created_at    timestamptz not null default now()
);

-- 2.4 Transaksi (buku kas)
create table if not exists transactions (
  id          text primary key default ('TRX-' || lpad(nextval('transaction_seq')::text, 4, '0')),
  trx_date    date not null default current_date,
  type        text not null check (type in ('Pemasukan', 'Pengeluaran')),
  category    text not null default 'Lainnya'
              check (category in ('Pendapatan sewa', 'Perawatan', 'Perlengkapan', 'Transportasi',
                                  'Utilitas', 'Gaji', 'Penyusutan', 'Lainnya')),
  account     text not null default 'Kas',
  amount      numeric(14,0) not null check (amount > 0),
  description text,
  booking_id  text references bookings(id) on delete set null,
  is_auto     boolean not null default false,            -- true = dibuat otomatis dari booking
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. INDEX
-- ---------------------------------------------------------------------
create index if not exists idx_bookings_customer     on bookings(customer_id);
create index if not exists idx_bookings_camera       on bookings(camera_id);
create index if not exists idx_bookings_status       on bookings(status);
create index if not exists idx_transactions_date     on transactions(trx_date);
create index if not exists idx_transactions_booking  on transactions(booking_id);
create index if not exists idx_transactions_type     on transactions(type);

-- ---------------------------------------------------------------------
-- 4. TRIGGER — logika bisnis dipindah ke database
-- ---------------------------------------------------------------------

-- 4.1 Hitung total booking = tarif kamera × durasi (tidak bisa dimanipulasi dari client)
create or replace function trg_booking_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_price numeric;
begin
  select price_per_day into v_price from cameras where id = new.camera_id;
  if v_price is null then
    raise exception 'Kamera % tidak ditemukan', new.camera_id;
  end if;
  new.total := v_price * new.duration_days;
  return new;
end $$;

drop trigger if exists booking_before_insert on bookings;
create trigger booking_before_insert
  before insert on bookings
  for each row execute function trg_booking_before_insert();

-- 4.2 Setelah booking dibuat: buat transaksi pemasukan otomatis + update status kamera
create or replace function trg_booking_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status <> 'Dibatalkan' then
    insert into transactions (trx_date, type, category, account, amount, description, booking_id, is_auto)
    select new.start_date, 'Pemasukan', 'Pendapatan sewa', 'Kas', new.total,
           'Pembayaran booking ' || new.id || ' — ' || c.name, new.id, true
    from customers c where c.id = new.customer_id;
  end if;

  update cameras
     set status = case when new.status in ('Menunggu', 'Berlangsung') then 'Disewa' else 'Tersedia' end
   where id = new.camera_id and status <> 'Perawatan';
  return new;
end $$;

drop trigger if exists booking_after_insert on bookings;
create trigger booking_after_insert
  after insert on bookings
  for each row execute function trg_booking_after_insert();

-- 4.3 Saat status booking berubah: sinkronkan transaksi otomatis & status kamera
create or replace function trg_booking_after_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'Dibatalkan' then
      delete from transactions where booking_id = new.id and is_auto;
    elsif not exists (select 1 from transactions where booking_id = new.id and is_auto) then
      -- booking diaktifkan kembali dari status Dibatalkan
      insert into transactions (trx_date, type, category, account, amount, description, booking_id, is_auto)
      select new.start_date, 'Pemasukan', 'Pendapatan sewa', 'Kas', new.total,
             'Pembayaran booking ' || new.id || ' — ' || c.name, new.id, true
      from customers c where c.id = new.customer_id;
    end if;

    update cameras
       set status = case when new.status in ('Menunggu', 'Berlangsung') then 'Disewa' else 'Tersedia' end
     where id = new.camera_id and status <> 'Perawatan';
  end if;
  return new;
end $$;

drop trigger if exists booking_after_update on bookings;
create trigger booking_after_update
  after update on bookings
  for each row execute function trg_booking_after_update();

-- 4.4 Sebelum booking dihapus: hapus transaksi otomatis, bebaskan kamera
create or replace function trg_booking_before_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from transactions where booking_id = old.id and is_auto;
  update cameras set status = 'Tersedia'
   where id = old.camera_id and status = 'Disewa'
     and old.status in ('Menunggu', 'Berlangsung');
  return old;
end $$;

drop trigger if exists booking_before_delete on bookings;
create trigger booking_before_delete
  before delete on bookings
  for each row execute function trg_booking_before_delete();

-- ---------------------------------------------------------------------
-- 5. VIEW laporan (opsional, bisa dipakai dari dashboard/BI)
-- ---------------------------------------------------------------------
create or replace view v_monthly_cashflow with (security_invoker = true) as
select date_trunc('month', trx_date)::date                          as bulan,
       coalesce(sum(amount) filter (where type = 'Pemasukan'), 0)    as pemasukan,
       coalesce(sum(amount) filter (where type = 'Pengeluaran'), 0)  as pengeluaran,
       coalesce(sum(amount) filter (where type = 'Pemasukan'), 0)
     - coalesce(sum(amount) filter (where type = 'Pengeluaran'), 0)  as laba_bersih
from transactions
group by 1
order by 1;

create or replace view v_customer_summary with (security_invoker = true) as
select c.id, c.name, c.phone, c.email, c.address,
       count(b.id)                  as total_booking,
       coalesce(sum(b.total), 0)    as total_transaksi
from customers c
left join bookings b on b.customer_id = c.id and b.status <> 'Dibatalkan'
group by c.id;

-- ---------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY
--    Aplikasi ini belum memakai login, jadi policy di bawah mengizinkan
--    role "anon" (publishable key) membaca & menulis semua tabel.
--    ⚠ Artinya SIAPA PUN yang punya URL + key bisa mengubah data.
--    Untuk produksi: aktifkan Supabase Auth, lalu ganti "anon, authenticated"
--    menjadi "authenticated" saja (lihat README).
-- ---------------------------------------------------------------------
alter table customers    enable row level security;
alter table cameras      enable row level security;
alter table bookings     enable row level security;
alter table transactions enable row level security;

do $$
declare t text;
begin
  foreach t in array array['customers', 'cameras', 'bookings', 'transactions'] loop
    execute format('drop policy if exists "frame_open_access" on %I', t);
    execute format(
      'create policy "frame_open_access" on %I for all to anon, authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- Hak akses tabel & sequence untuk API Supabase
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on customers, cameras, bookings, transactions to anon, authenticated;
grant select on v_monthly_cashflow, v_customer_summary to anon, authenticated;
grant usage, select on sequence customer_seq, camera_seq, booking_seq, transaction_seq to anon, authenticated;
