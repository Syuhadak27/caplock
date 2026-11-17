# CapLock

[![macOS](https://img.shields.io/badge/macOS-13%2B%20Ventura-blue.svg)](https://developer.apple.com/macos/)
[![Architecture](https://img.shields.io/badge/arch-Intel%20x86__64-orange.svg)](https://en.wikipedia.org/wiki/X86-64)
[![Built with](https://img.shields.io/badge/built%20with-Swift%205.8-red.svg)](https://swift.org/)
[![Accessibility](https://img.shields.io/badge/permissions-accessibility%20opsional-blue.svg)](#izin-accessibility)

Indikator **Caps Lock** untuk macOS Ventura ke atas yang tinggal duduk di menu bar dan
menampilkan badge kecil **tepat di atas text box yang sedang fokus** saat Caps Lock aktif.
Cocok untuk keyboard yang tidak punya lampu Caps Lock, atau kalau Anda sering mengetik dalam
huruf besar tanpa sadar.

<img width="420" alt="Ilustrasi ikon menu bar dan indikator di atas text box" src="docs/preview.svg">

> Ikon default: tombol Caps Lock klasik dengan huruf **A**. Warna, gaya, dan ukuran bisa
> diubah lewat Settings.

## Fitur

- **Status real-time di menu bar** — ikon berubah warna saat Caps Lock aktif.
- **Indikator menempel di atas text box** — badge `CAPS LOCK AKTIF` terkunci di atas field teks yang sedang fokus.
- **Tidak mengikuti kursor** — setelah menempel pada sebuah text box, badge tidak bergeser saat mouse digerakkan.
- **Tanpa Input Monitoring** — status dibaca dari HID system, bukan dari keystroke yang Anda ketik.
- **Settings lengkap**:
  - 3 gaya ikon: tombol klasik, huruf A saja, atau lingkaran
  - warna bebas untuk kondisi aktif dan nonaktif
  - ukuran ikon 14–24 pt
  - indikator selalu di atas text box yang fokus (tanpa opsi mengikuti kursor)
  - suara on/off saat status berubah
  - status izin Accessibility + tombol untuk memintanya
  - jalankan otomatis saat login (macOS 13+)
- **Menu bar only** — tidak muncul di Dock, tidak memunculkan jendela saat start.
- Ringan: polling 120 ms, tanpa event tap, tanpa network.

## Install

### Cara cepat (prebuilt)

1. Download **[CapLock.zip](CapLock.zip)** dari repo ini, lalu unzip.
2. Tarik `CapLock.app` ke folder **Applications**.
3. Buka dari Applications / Launchpad.
4. Klik ikon di menu bar → **Settings…** → **Indikator Caps Lock aktif**, lalu klik
   **Minta Izin** atau **Buka Pengaturan** untuk mengizinkan Accessibility. Izin ini dipakai
   supaya badge bisa menempel tepat di atas text box.
5. Ubah warna, gaya ikon, dan opsi lainnya di Settings sesuai selera.

Atau clone repo lalu pakai `CapLock.app` yang sudah ada di root:

```bash
git clone git@github.com:Syuhadak27/caplock.git
cp -R caplock/CapLock.app /Applications/
open /Applications/CapLock.app
```

Jika macOS menolak membuka aplikasi (karena di-build lokal, bukan dari App Store):

```bash
xattr -d com.apple.quarantine /Applications/CapLock.app
```

Atau klik kanan `CapLock.app` → **Open** → **Open** lagi.

### Build dari source

Butuh macOS 13+ dengan **Command Line Tools** (tidak perlu Xcode penuh):

```bash
xcode-select --install    # kalau belum ada
git clone git@github.com:Syuhadak27/caplock.git
cd caplock/CapLock
./build.sh                # hasil: CapLock/CapLock.app
```

Script `build.sh` melakukan kompilasi dengan `swiftc`, membuat bundle, menanam ikon, dan
memberi tanda tangan ad-hoc (`codesign --sign -`).

## Pakai

Klik ikon di menu bar untuk membuka menu:

```
Caps Lock: nonaktif
─────────────────────
Pratinjau indikator
Settings…
─────────────────────
Keluar CapLock
```

Saat Caps Lock aktif, badge `CAPS LOCK AKTIF` muncul tepat di atas text field yang sedang
Anda pakai. Badge tetap tampil selama Caps Lock aktif dan otomatis berpindah hanya saat Anda
berpindah ke field lain — menggerakkan mouse tidak memindahkannya. Saat Caps Lock dimatikan,
badge langsung hilang.

## Izin Accessibility

Status Caps Lock sendiri **tidak butuh izin apa pun** — dibaca dari HID system via IOKit.
Yang butuh izin hanyalah kemampuan mencari koordinat text field:

1. Buka **Settings… → Indikator Caps Lock aktif**.
2. Klik **Minta Izin** (atau **Buka Pengaturan** jika belum muncul prompt).
3. Di **System Settings → Privacy & Security → Accessibility**, centang **CapLock**.
4. Klik **Perbarui** di Settings untuk memastikan status berubah jadi “akses aktif”.

Tanpa izin ini, CapLock tetap bekerja, tetapi badge tidak tahu posisi text box dan akan diam
di posisi tetap tengah atas layar — ia tidak akan mengikuti kursor.
CapLock **tidak meminta Input Monitoring** dan tidak merekam apa pun yang Anda ketik.

> Catatan: untuk keyboard dengan fitur “Caps Lock untuk ganti bahasa input”, macOS
> kadang melaporkan status sesaat saat tombol ditekan. CapLock memakai dua pembacaan
> berurutan (≈240 ms) supaya tidak berkedip.

## Struktur repo

```
.
├── CapLock.app          # aplikasi siap pakai (prebuilt)
├── CapLock.zip          # versi zip untuk download
├── CapLock/
│   ├── Sources/main.swift   # seluruh source aplikasi
│   ├── Resources/AppIcon.icns
│   └── build.sh             # build + bundle + codesign
└── README.md
```

## Kompatibilitas

| Item | Keterangan |
|---|---|
| macOS | 13.0 Ventura ke atas (diuji di 13.7.8) |
| CPU | Intel x86_64 (di Apple Silicon bisa jalan via Rosetta 2) |
| Swift | 5.8+ |
| Izin | Accessibility (opsional, untuk posisi text box); Input Monitoring tidak dipakai |

## Uninstall

1. Klik ikon menu bar → **Keluar CapLock**.
2. Hapus `CapLock.app` dari Applications.
3. Kalau auto-start aktif, hapus dari **System Settings → General → Login Items & Extensions**.

## Troubleshooting

| Masalah | Solusi |
|---|---|
| Ikon tidak muncul | Pastikan app berjalan (`pgrep -fl CapLock`); keluar lalu buka lagi |
| “App cannot be opened” | `xattr -d com.apple.quarantine /Applications/CapLock.app` |
| Auto-start gagal aktif | Pindahkan app ke `/Applications` dulu, lalu aktifkan lagi di Settings |
| Badge tidak muncul di atas text box | Cek status Accessibility di Settings; centang CapLock lalu klik **Perbarui** |
| Badge tidak tepat di atas text box | Izin Accessibility belum aktif; aktifkan di Settings lalu klik **Perbarui** |
| Badge diam di tengah atas | Belum ada text field yang terdeteksi fokus; klik sebuah text box untuk memindahkannya |
| Status terasa telat | Durasi debounce ≈240 ms sengaja dipakai untuk menghindari kedip |

---

Dibuat dengan Swift + AppKit + SwiftUI + IOKit.
