# FRAME — Camera Rental & Finance

Akses Link: https://kinantibtr.github.io/Cam-Book/

Aplikasi manajemen penyewaan kamera + akuntansi sederhana (pelanggan, inventaris, booking, buku transaksi, laporan laba rugi & arus kas).
Frontend HTML/CSS/JS murni, data tersimpan di **Supabase (PostgreSQL)**.

## Struktur

```
backend/
  schema.sql     → tabel, trigger, view, RLS
  seed.sql       → data contoh
frontend/
  index.html     → halaman aplikasi
  style.css      → tampilan
  app.js         → logika + koneksi Supabase
index.html       → redirect ke frontend/index.html
README.md
```

## Setup

1. Buka **Supabase Dashboard → SQL Editor → New query**.
2. Paste isi `backend/schema.sql` → **Run**.
3. Paste isi `backend/seed.sql` → **Run** (cukup sekali).
4. Buka `frontend/index.html` lewat web server lokal (mis. ekstensi **Live Server** di VS Code, atau `npx serve .`).
   Indikator di sidebar akan berubah menjadi **SUPABASE TERHUBUNG**.

URL dan publishable key sudah diisi di bagian atas `frontend/app.js`.

## Logika yang ditangani database (trigger)

| Aksi | Efek otomatis |
|------|---------------|
| Booking dibuat | `total` = tarif kamera × durasi; transaksi pemasukan dibuat; kamera → *Disewa* |
| Status booking → *Dibatalkan* | Transaksi otomatis dihapus; kamera → *Tersedia* |
| Status booking → *Selesai* | Kamera → *Tersedia* |
| Booking dibatalkan lalu diaktifkan lagi | Transaksi pemasukan dibuat ulang |
| Booking dihapus | Transaksi otomatis dihapus; kamera dibebaskan |

Kamera berstatus *Perawatan* tidak pernah diubah otomatis.

## Tabel

`customers` · `cameras` · `bookings` · `transactions`, plus view `v_monthly_cashflow` dan `v_customer_summary` untuk laporan.

## ⚠ Keamanan

Aplikasi ini belum memiliki login, sehingga policy RLS di `schema.sql` mengizinkan role `anon` membaca **dan menulis** semua tabel.
Siapa pun yang membuka situs dan punya key bisa mengubah data. Cocok untuk pengembangan/demo, **bukan untuk produksi**.

Untuk mengamankan:

1. Aktifkan **Authentication** di Supabase (mis. email + password) dan tambahkan form login di frontend.
2. Ganti policy:

```sql
drop policy "frame_open_access" on customers;
create policy "auth_only" on customers for all to authenticated using (true) with check (true);
-- ulangi untuk cameras, bookings, transactions
revoke all on customers, cameras, bookings, transactions from anon;
```

> Publishable key (`sb_publishable_...`) memang boleh ada di frontend. Jangan pernah menaruh **secret key / service_role** di kode frontend.
