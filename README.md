# zStats

<img src="assets/brand/zStats%20Exports/zStats-iOS-Default-1024@1x.png" alt="zStats app icon" width="112" height="112">

A native macOS system monitor inspired by [VitalsMac](https://vitalsmac.com/) and [Stats](https://github.com/exelban/stats).

Keep CPU, GPU, memory, disk, network, battery and temperatures in view with a customizable menu bar and a detailed dashboard. Explore your Mac's hardware, see which apps are busy, and track local activity over time.

Built with SwiftUI, AppKit, Darwin and IOKit, with no external package dependencies. Requires macOS 26 (Tahoe) or later.

## Build and run

Building requires macOS 26 or later and Xcode 26 or later (Swift 6.2 or later), with full Xcode selected as the active developer directory. The app icon is compiled directly from `assets/brand/zStats.icon` using Apple's asset compiler.

```sh
bash scripts/build-app.sh
open dist/zStats.app
```

Open `Package.swift` in Xcode to develop. Run `swift test --disable-sandbox` for core tests. Run `dist/zStats.app/Contents/MacOS/zStats --diagnose` to print a live sampling summary without opening a window. `--diagnose-sensors` reports live thermal readings, fan speeds and polling time. `--render-previews /tmp/zstats-previews` renders the dashboard views, menu panels, My Machine and Settings into PNGs without capturing the desktop.

## Features

- My Machine opens by default: model, macOS, processor/core types, installed RAM, graphics, startup disk, displays, model year, serial number and uptime. Hardware details come from macOS; model years are reported only for known models.
- Overview with configurable live metric cards and memory breakdowns.
- CPU, Memory, Disk, Network, GPU, Battery, Sensors and Projects screens. Sensors shows CPU/GPU averages, individual component temperatures and fan RPM.
- Grouped app processes, filtering, process inspection and confirmed termination.
- Development servers grouped by working directory, with listening ports.
- Rounded menu-bar panel and keyboard navigation (⌘1–⌘8 for monitors, ⌘9 for My Machine, ⌘0 for Sensors).
- Left- or right-click a menu-bar widget to open its panel. Escape closes Settings or the dashboard; monitoring continues when those windows close.
- Settings (⌘,): General, Menu Bar, Monitors, Appearance and About. Saved preferences control menu-bar metric/style, opening tabs, refresh interval, Dock visibility, number precision and system-owned process visibility.
- Light, Dark and System appearance, with a custom app icon created in Apple's Icon Composer.
- Disable individual monitors in Settings to hide their tabs and overview cards. Network/GPU app collectors and project discovery pause when those monitors are disabled; shared system sampling and history continue.
- Menu-bar customization supports up to eight ordered widgets, including multiple views of one metric. Choose Icon, Figure, Stacked, Graph, History bars, Usage bar, or Vertical gauge; customize text/icon labels, colors, widths, spacing and units. Minimal, Usage meters and Detailed presets provide starting layouts. The live preview uses the same renderer as the actual status item.
- Widgets stay together as a group; ⌘-drag the group to position it, and reorder its contents in Settings. General settings can remember its position and select System/Celsius/Fahrenheit temperature units. CPU, GPU and Battery widgets support a Temperature reading. Disabling Sensors pauses SMC polling and makes CPU/GPU temperature widgets unavailable.
- Launch at login uses macOS Login Items, is off by default, and may require approval in System Settings.
- Local system history: Live, 12 h, 24 h, 7 d and 30 d.
- Developer → Reference Data provides labeled simulated readings for comparison with the reference. Launch with `--reference` or `--reference --tab cpu` for the same view. Demo process actions are disabled.

## Measurement details

System CPU is normalized across logical cores. Process CPU uses one core as 100%, and can exceed 100%. App memory sums process physical footprints (resident memory is the fallback when access is restricted); it need not equal system memory because accounting and shared memory differ. Processes are grouped by the outer .app bundle, then by their app ancestor. Background services remain separate groups.

Disk I/O covers accessible physical disks; capacity is for the startup filesystem. Network rates include active `en` interfaces, excluding loopback, VPN and bridge interfaces to avoid double counting. Session traffic starts when zStats opens. Project discovery runs every 20 seconds and detects listening processes for the current user with a recognized runtime or project folder. No low-CPU process is automatically declared abandoned.

Thermal and fan readings use a read-only AppleSMC connection on the background sampling task. CPU/GPU figures average the available mapped component sensors; they do not represent case/surface temperature. Sensor labels identify thermal zones and do not necessarily correspond one-to-one with physical cores. Unidentified temperature keys are kept in a collapsed Additional sensors section. Sensor availability and labels depend on hardware; live validation was performed on an M5 Max. No fan-control commands or privileged helper are used. Protocol references and sensor mappings are attributed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Thermal readings are live only and are not included in stored history.

History begins when zStats runs, records one system sample per minute to `~/Library/Application Support/zStats/history.json`, and retains 30 days. It is saved every minute; the last minute can be lost on exit. History does not collect while the app is closed. Reference readings never enter the history file. No analytics, license server or network service is used.

## Current limits

GPU/battery values depend on hardware and available OS counters. Missing readings show “—”. Live app rankings collect external-network byte counters with Apple's `nettop`, GPU execution time from the Apple Silicon driver's `AppUsage` counters, and CPU energy through `proc_pid_rusage` V6. Helpers are grouped into their application. CPU power is energy per second, in watts; it excludes GPU, display, network and other device power and is labeled separately from total battery draw. GPU queue times may overlap, so per-app percentages need not sum to device utilization. These counters are hardware/OS-dependent; unavailable values stay unknown. Network sampling can miss traffic from sockets that open and close between samples. Only process byte totals are requested—no remote addresses or payloads.

Automatic update checks need a release feed and signed distribution setup and are not yet offered. Total per-app power, audio control, per-app historical attribution and background alerts remain unimplemented. The app uses no privileged helper and cannot stop protected processes. Stop actions recheck PID/start time, but macOS's PID-based signal API cannot eliminate the final check-to-signal race entirely.

The build is locally ad-hoc signed; distribution notarization is not configured.

## Inspiration and acknowledgments

- [VitalsMac](https://vitalsmac.com/) inspired the dashboard, metric cards and compact menu-bar panels.
- [Stats](https://github.com/exelban/stats), by [Serhiy Mytrovtsiy (exelban)](https://github.com/exelban), inspired the configurable monitors, hardware overview and settings. Its open-source AppleSMC implementation and sensor mappings also informed zStats' thermal monitoring.

Thank you to both projects for the ideas and work behind them. The Stats-derived protocol definitions and sensor mappings retain their MIT attribution in [Third-party notices](THIRD_PARTY_NOTICES.md).
