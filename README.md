# Dynamic Island for macOS

Dynamic Island melayang di bawah notch: pill kecil saat idle, membesar saat di-hover, dan
bisa digeser horizontal untuk berpindah fitur.

Empat fitur saat ini:

| Fitur | Isi |
| --- | --- |
| **Now Playing** | Artwork, judul, artis, album, progress, tombol previous / play-pause / next. Tombol skip otomatis di-dim kalau pemutar tidak mengiklankan Next/Previous (mis. Spotify Web Player di Arc) |
| **Monitor** | CPU, GPU, RAM, network (↓/↑) dan disk usage, sampling tiap detik |
| **Stopwatch** | Stopwatch, Timer (preset 1–30 menit), Pomodoro 25/5 dengan auto-lanjut fase dan bunyi saat selesai |
| **Prayer Times** | Tanggal hari ini, Fajr, Dhuhr, Asr, Maghrib, Isha untuk lokasi device, highlight sholat berikutnya |
| **Drop Zone** | Tahan file & folder di sini, lihat ukurannya, drag keluar lagi, buka di Finder, hapus |

## Kebutuhan

- macOS 14 Sonoma atau lebih baru (memakai `scrollTargetBehavior` dan `scrollPosition`).
- Tanpa Xcode. Hanya Command Line Tools (`xcode-select --install`).

## Build & jalankan

```bash
make run        # build + launch
make dmg        # build + package installer DMG
make install    # copy ke /Applications lalu launch
make clean
```

## Install via DMG

```bash
make dmg
open "build/Dynamic Island.dmg"
```

Drag **Dynamic Island.app** ke folder **Applications**, lalu buka. DMG berisi app + shortcut
Applications, dibuat dengan `hdiutil`. Karena app di-ad-hoc sign dan belum dinotarize, saat
pertama dibuka mungkin perlu klik kanan → **Open**. Untuk distribusi publik diperlukan
Developer ID + notarization dari Apple.

Atau manual:

```bash
./build.sh
open "build/Dynamic Island.app"
```

App ini `LSUIElement` (tanpa ikon Dock). Ikon kapsul muncul di menu bar kanan sebagai
kontrol cadangan: Expand Island, Keep Expanded, Quit.

Kalau macOS memblokir saat pertama dibuka (app di-ad-hoc sign, bukan notarized):
klik kanan app → **Open**, atau jalankan lewat `make run`.

## Cara pakai

- **Hover** notch / lidah kecil di bawahnya → island membesar.
- **Geser dua jari horizontal** di trackpad untuk pindah fitur (halaman ditandai page dots di bawah).
- **Gear** (kanan atas) → *Keep expanded* dan *Quit*.
- **Drag file/folder** mendekati island → panel langsung membesar dan pindah ke halaman
  Drop Zone (mendeteksi drag dari app lain lewat mouse monitor + `NSPasteboard.drag`),
  sebelum kursor masuk ke window. Lepas untuk menambah.
- Di Drop Zone: **drag baris terpilih** → langsung memindahkan file (satu atau grup) lewat
  native `NSDraggingSession`. **Drag baris belum terpilih di dalam shelf** → marquee-select.
  **⇧/⌘-klik** menambah/mengurangi pilihan, klik baris memilih satu. Drag keluar island juga
  memindahkan file. Tombol folder = reveal di Finder, trash = kosongkan. Saat island ditutup,
  halaman kembali ke Now Playing sehingga hover berikutnya membuka music.

## Batasan

- Now Playing membaca `MediaRemote`, framework privat Apple. Tidak ada entitlement khusus,
  tapi ini bukan API publik — bisa berubah di macOS mendatang. Data yang dibaca sama dengan
  yang tampil di Control Center, jadi pemutar harus terdaftar di sana.
- Drop Zone menyimpan **referensi** file, bukan salinan. Isi daftar hilang saat app ditutup.
- App tidak di-sandbox dan tidak dinotarize; cocok untuk pemakaian sendiri.
- Tidak ada auto-launch saat login. Tambahkan manual: System Settings → General →
  Login Items → **+** → pilih `Dynamic Island.app`.
- Layar tanpa notch tetap dapat pill kecil (200×30) di tengah atas.
- **Prayer Times** butuh izin Location (sekali). Lokasi diambil saat launch, di-cache, dan
  diperbarui tiap 30 menit. Perhitungan dilakukan offline (tanpa API): metode **Kemenag**
  (Fajr 20°, Isha 18°) untuk timezone Indonesia, **MWL** (18°/17°) untuk lainnya. Selisih
  terhadap referensi ±1 menit; Asr memakai madzhab Syafi'i.
- Tombol next/previous hanya berfungsi kalau aplikasi pemutar mengiklankan command
  Next/Previous ke sistem. Spotify desktop dan Music mendukung; Spotify Web Player di Arc
  hanya mengiklankan Play/Pause/Stop/Seek, jadi tombolnya di-dim (bukan bug tombolnya).
  Cek `MRMediaRemoteGetSupportedCommands` lewat log kalau ragu.

## Struktur

```
Sources/
  main.swift              entry point AppKit (tanpa SwiftUI App/Scene)
  AppDelegate.swift       panel, hover tracking, animasi frame, status item
  IslandPanel.swift       NSPanel borderless non-activating + hosting view
  IslandGeometry.swift    hitung frame collapsed/expanded dari notch (NSScreen.safeAreaInsets)
  IslandShape.swift       siluet: tepi atas rata, sudut bawah membulat
  IslandRootView.swift    background + state collapsed/expanded + drop target global
  ExpandedIslandView.swift pager horizontal, gear, page dots
  SettingsOverlay.swift   panel setting di dalam island
  MusicPlayer.swift       MediaRemote (dlopen) + polling 0.75 s + transport command
  PrayerTimes.swift       kalkulasi waktu sholat offline (Kemenag / MWL)
  LocationService.swift   CoreLocation, izin, reverse geocode, cache lokasi
  PrayerModel.swift       jadwal hari ini + besok, refresh harian/lokasi
  PrayerPage.swift        timeline 5 waktu sholat + tanggal hari ini
  MonitorPage.swift       strip CPU/GPU/RAM/network/disk
  SystemMonitor.swift     sampler host_statistics/IOKit/network/volume (1 dtk)
  Stopwatch.swift         model stopwatch berbasis Date
  ClockTools.swift        mode clock, CountdownTimer (preset), Pomodoro 25/5
  DropStore.swift         daftar item, ekstraksi URL dari NSItemProvider
  DragHandle.swift        overlay baris: seleksi + NSDraggingSession untuk file terpilih
  MusicPage.swift / MonitorPage.swift / ClockPage.swift / DropPage.swift / PrayerPage.swift
  UIComponents.swift      tombol, format waktu
```

Catatan teknis:

- Panel memakai level `statusBar + 1`, `canJoinAllSpaces`, `fullScreenAuxiliary`, jadi tetap
  terlihat di atas menu bar dan di semua Space. Ekspansi dipicu polling posisi mouse 80 ms,
  bukan `onHover`, supaya tetap andal saat frame window ikut beranimasi.
- Tinggi panel saat expanded = 144 pt + tinggi notch (`NSScreen.safeAreaInsets.top`), dan
  konten diberi inset atas sebesar notch. Jadi judul, artwork, dan gear selalu berada di
  bawah notch, tidak terpotong. Di layar tanpa notch inset = 0.
- Now Playing di-poll, bukan memakai notifikasi, agar simbol notifikasi MediaRemote yang
  berubah antar versi tidak mematikan fitur.
- Shelf terbuka otomatis saat drag file mendekat: global monitor `leftMouseDragged` membaca
  `NSPasteboard(name: .drag)` lalu `NSEvent.mouseLocation`, karena target drop SwiftUI baru
  aktif setelah kursor masuk window. Pager memakai `ScrollViewReader` untuk menerapkan
  halaman awal yang dipilih sebelum panel expand.
- `build.sh` membuat *shim resource dir*. Di sebagian instalasi Command Line Tools ada dua
  module map (`module.modulemap` dan `bridging.modulemap`) yang sama-sama mendefinisikan
  `SwiftBridging`, sehingga setiap compile gagal dengan *redefinition of module
  'SwiftBridging'*. Shim itu hanya menyisakan satu module map.
