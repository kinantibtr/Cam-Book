-- =====================================================================
-- FRAME — Camera Rental & Finance
-- backend/seed.sql — data awal / contoh
--
-- Jalankan SETELAH schema.sql, cukup SEKALI di SQL Editor.
-- Tanggal dibuat relatif terhadap hari ini supaya grafik 6 bulan terisi.
-- =====================================================================

-- 1. Pelanggan ---------------------------------------------------------
insert into customers (id, name, phone, email, address) values
  ('CUS-001', 'Nadia Putri',    '081234567890', 'nadia@email.com',      'Semarang'),
  ('CUS-002', 'Raka Mahendra',  '082112223333', 'raka@email.com',       'Ungaran'),
  ('CUS-003', 'Studio Senja',   '085677889900', 'halo@studiosenja.id',  'Semarang')
on conflict (id) do nothing;

-- 2. Kamera ------------------------------------------------------------
insert into cameras (id, name, brand, price_per_day, status, condition, emoji) values
  ('CAM-001', 'Sony A7 III',    'Sony',     350000, 'Tersedia',  'Baik',             '📷'),
  ('CAM-002', 'Canon EOS R6',   'Canon',    400000, 'Tersedia',  'Baik',             '📸'),
  ('CAM-003', 'Fujifilm X-T5',  'Fujifilm', 300000, 'Tersedia',  'Baik',             '🎞️'),
  ('CAM-004', 'Sony A6400',     'Sony',     200000, 'Perawatan', 'Perlu pengecekan', '📷')
on conflict (id) do nothing;

-- 3. Booking (urut dari yang paling lama) ------------------------------
--    Trigger otomatis: menghitung total, membuat transaksi pemasukan,
--    dan mengatur status kamera.
insert into bookings (id, customer_id, camera_id, start_date, duration_days, status, note) values
  ('BKG-001', 'CUS-001', 'CAM-001', current_date - 70, 1, 'Selesai',     'Prewedding outdoor'),
  ('BKG-002', 'CUS-002', 'CAM-002', current_date - 40, 2, 'Selesai',     null),
  ('BKG-003', 'CUS-001', 'CAM-001', current_date - 25, 3, 'Selesai',     'Wisuda'),
  ('BKG-004', 'CUS-002', 'CAM-002', current_date - 10, 2, 'Dibatalkan',  'Dibatalkan pelanggan'),
  ('BKG-005', 'CUS-003', 'CAM-003', current_date - 2,  3, 'Berlangsung', 'Produksi konten produk')
on conflict (id) do nothing;

-- 4. Transaksi manual (pengeluaran & pemasukan lain) -------------------
insert into transactions (trx_date, type, category, account, amount, description) values
  (current_date - 65, 'Pengeluaran', 'Perlengkapan', 'Kas', 450000, 'Beli memory card & baterai cadangan'),
  (current_date - 45, 'Pengeluaran', 'Utilitas',     'Kas', 300000, 'Internet & listrik studio'),
  (current_date - 30, 'Pengeluaran', 'Perawatan',    'Kas', 275000, 'Service sensor Sony A6400'),
  (current_date - 20, 'Pengeluaran', 'Transportasi', 'Kas', 120000, 'Antar jemput kamera'),
  (current_date - 12, 'Pemasukan',   'Lainnya',      'Kas', 150000, 'Denda keterlambatan pengembalian'),
  (current_date - 5,  'Pengeluaran', 'Perlengkapan', 'Kas', 380000, 'Tas kamera & lens cleaning kit');

-- 5. Samakan sequence agar data baru tidak bentrok dengan ID seed ----------
select setval('customer_seq', (select count(*) from customers));
select setval('camera_seq',   (select count(*) from cameras));
select setval('booking_seq',  (select count(*) from bookings));
select setval('transaction_seq', (select count(*) from transactions));
