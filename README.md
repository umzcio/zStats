<p align="center">
  <img src="assets/brand/zStats%20Exports/zStats-iOS-Default-1024@1x.png" alt="zStats app icon" width="112" height="112">
</p>

<h1 align="center">zStats</h1>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1.0-5B9CF6?style=flat" alt="Version 0.1.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/code_license-MIT-5B9CF6?style=flat" alt="Code license: MIT"></a>
  <a href="#build-and-run"><img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?style=flat&amp;logo=swift&amp;logoColor=white" alt="Swift toolchain 6.2 or later"></a>
  <img src="https://img.shields.io/badge/UI-SwiftUI_%7C_AppKit-5B9CF6?style=flat" alt="UI: SwiftUI and AppKit">
  <a href="#build-and-run"><img src="https://img.shields.io/badge/platform-macOS_26%2B_(Tahoe)-333333?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 26 Tahoe or later"></a>
</p>

A native macOS system monitor inspired by [VitalsMac](https://vitalsmac.com/) and [Stats](https://github.com/exelban/stats).

Keep CPU, GPU, memory, disk, network, battery and temperatures in view with a customizable menu bar and a detailed dashboard. Explore your Mac's hardware, see which apps are busy, and track local activity over time.

Built with SwiftUI, AppKit, Darwin and IOKit, with [Sparkle](https://sparkle-project.org/) for signed app updates. Requires macOS 26 (Tahoe) or later.

## Install

Download the signed and notarized DMG from [GitHub Releases](https://github.com/umzcio/zStats/releases/latest), open it, and drag zStats into Applications. Open Settings → About to check for updates.

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
- Settings → About includes Check for Updates and optional automatic checks. Installation always requires your choice. Before the release feed is published, the button explains that updates are not yet available and automatic checks remain disabled.
- Developer → Reference Data provides labeled simulated readings for comparison with the reference. Launch with `--reference` or `--reference --tab cpu` for the same view. Demo process actions are disabled.

## Measurement details

System CPU is normalized across logical cores. Process CPU uses one core as 100%, and can exceed 100%. App memory sums process physical footprints (resident memory is the fallback when access is restricted); it need not equal system memory because accounting and shared memory differ. Processes are grouped by the outer .app bundle, then by their app ancestor. Background services remain separate groups.

Disk I/O covers accessible physical disks; capacity is for the startup filesystem. Network rates include active `en` interfaces, excluding loopback, VPN and bridge interfaces to avoid double counting. Session traffic starts when zStats opens. Project discovery runs every 20 seconds and detects listening processes for the current user with a recognized runtime or project folder. No low-CPU process is automatically declared abandoned.

Thermal and fan readings use a read-only AppleSMC connection on the background sampling task. CPU/GPU figures average the available mapped component sensors; they do not represent case/surface temperature. Sensor labels identify thermal zones and do not necessarily correspond one-to-one with physical cores. Unidentified temperature keys are kept in a collapsed Additional sensors section. Sensor availability and labels depend on hardware; live validation was performed on an M5 Max. No fan-control commands or privileged helper are used. Protocol references and sensor mappings are attributed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Thermal readings are live only and are not included in stored history.

History begins when zStats runs, records one system sample per minute to `~/Library/Application Support/zStats/history.json`, and retains 30 days. It is saved every minute; the last minute can be lost on exit. History does not collect while the app is closed. Reference readings never enter the history file. There is no analytics or license server. Configured release builds contact the update host when you check for updates or enable automatic checks; system profiling is disabled and monitoring data is not sent.

## Signed and notarized DMG

The release script builds a Developer ID-signed app and a branded drag-to-Applications DMG, submits both to Apple for notarization, staples both tickets, and checks Gatekeeper acceptance. It does not publish a GitHub release.

Install the packaging tool with `brew install create-dmg` (verified with create-dmg 1.3.0). Packaging uses Finder to save the window layout, so run it from a logged-in macOS desktop session and allow Finder automation if prompted. The background is generated by `scripts/render-dmg-background.swift`; the DMG uses the official app icon, positioned app/Applications icons, and a fixed window size. Light backplates keep Finder’s native filename labels readable against the dark artwork.

Copy `scripts/notary-config.example` to `scripts/.notary-config.local`, restrict that file with `chmod 600`, and fill in your Developer ID Application identity and App Store Connect API key references. Keep the private `.p8` key outside the repository. The local config, signing keys, and all generated artifacts are ignored by Git.

```sh
bash scripts/release.sh
```

Version and build number come from `config/release.json`. The final installer is `dist/zStats-VERSION-BUILD.dmg`; Apple submission results are saved under `dist/notarization/`. Existing DMGs are not overwritten. The app's ticket is stapled before the DMG is built so the app inside also carries its notarization ticket.

For individual steps, use `scripts/build-app.sh`, `scripts/notarize.sh`, and `scripts/make-dmg.sh`. The build and DMG scripts use `ZSTATS_SIGNING_IDENTITY` from the environment; `release.sh` loads and exports it from the local config. Notarization reads the local config directly. A signed DMG can be prepared before Sparkle hosting is configured.

## Preparing app updates

Sparkle is pinned in `Package.resolved` and embedded by the build script. `config/release.json` contains the future public GitHub Releases feed URL and the public signing key. `updatesEnabled` stays `false` while the repository is private: the network updater remains inactive, but Check for Updates stays visible in About and the app menu and explains that the feed is not published yet. The private signing key stays in Keychain.

For the first public release, make the repository public, set `updatesEnabled` to `true`, and build a new signed release. Publish its ZIP and signed `appcast.xml` as assets on the same GitHub release; the configured feed uses the latest release's `appcast.xml` asset. Automatic checking remains opt-in. Existing private builds need that first public build installed manually.

Before the first public release:

1. Resolve dependencies with `swift package resolve`. Create a dedicated Sparkle signing key in your login Keychain:

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.zach.zStats
   ```

2. Confirm `feedURL` is the permanent HTTPS location of `appcast.xml` and `publicEDKey` matches the printed **public** key in `config/release.json`. Keep the private key in Keychain, with a secure backup outside the repository. Set `updatesEnabled` to `true` for public releases. Partial or malformed configuration fails the build, and enabling updates requires both fields.
3. Set `version` and a monotonically increasing integer `build` in that file. Environment overrides are available as `ZSTATS_VERSION`, `ZSTATS_BUILD_NUMBER`, `ZSTATS_UPDATE_FEED_URL`, and `ZSTATS_UPDATE_PUBLIC_KEY`.
4. Configure the local signing/notarization credentials as described above, then build the signed, notarized app and DMG. The build signs Sparkle's nested helpers, framework, and host app in order:

   ```sh
   bash scripts/release.sh
   ```

5. Prepare the signed ZIP archive and appcast, supplying the immutable HTTPS directory for this release tag:

   ```sh
   bash scripts/prepare-update.sh https://github.com/OWNER/zStats/releases/download/vVERSION/
   ```

   This checks the embedded public key against Keychain, verifies the signed/notarized app, and creates `dist/updates/zStats-VERSION-BUILD.zip` and a signed `dist/updates/appcast.xml`. It never uploads anything. Use `ZSTATS_SPARKLE_KEY_ACCOUNT` if your key has a different Keychain account. Existing archives are not overwritten. Keep this staging directory between releases. Sparkle verifies the prior feed and retained archives, the generator processes only the new archive and preserves every older feed item unchanged, then Sparkle signs and verifies the new archive and final feed after the new item is added.

   Preparation holds an exclusive lock and builds both artifacts in a unique workspace on the updates filesystem. It promotes the ZIP only after every check passes and replaces the feed last. The two renames are not a single atomic operation; transaction metadata lets the same command recover an interrupted promotion. An ordinary failure removes its incomplete workspace and leaves no final ZIP, so retry with the same version and build. A successfully prepared archive still refuses a duplicate run.

   Every new `CFBundleVersion` must be a positive integer greater than all builds in the retained feed. The check reads the candidate app and every retained ZIP rather than trusting filenames alone. Keep or restore the complete `dist/updates` history before preparing another release; if both the prior feed and archives are absent, this local guard cannot discover an already published build, and it does not fetch release history from GitHub.

Upload each archive to the matching GitHub release tag used in that preparation command, and upload the appcast to the exact `feedURL` embedded in the app. Do not replace an older archive or move its URL to a newer tag: published enclosure URLs, lengths, and signatures remain immutable across later appcast generations. The appcast itself needs a stable HTTPS URL. A private repository's release assets and raw files require authentication, so they cannot serve as an anonymous update feed; use separate public hosting or an authenticated update service. Do not embed GitHub access tokens in the app. Do not edit a generated signed appcast without regenerating its signature. Before publishing the first update, test discovery, download, installation, and relaunch from an older signed build. Increment the build number for every update, even when the display version stays the same.

The feed, update archive, and release notes are signed following [Sparkle's setup instructions](https://sparkle-project.org/documentation/). No production feed, signing identity, Sparkle private key, or Apple API credentials are supplied by the repository.

## Current limits

GPU/battery values depend on hardware and available OS counters. Missing readings show “—”. Live app rankings collect external-network byte counters with Apple's `nettop`, GPU execution time from the Apple Silicon driver's `AppUsage` counters, and CPU energy through `proc_pid_rusage` V6. Helpers are grouped into their application. CPU power is energy per second, in watts; it excludes GPU, display, network and other device power and is labeled separately from total battery draw. GPU queue times may overlap, so per-app percentages need not sum to device utilization. These counters are hardware/OS-dependent; unavailable values stay unknown. Network sampling can miss traffic from sockets that open and close between samples. Only process byte totals are requested—no remote addresses or payloads.

Total per-app power, audio control, per-app historical attribution and background alerts remain unimplemented. Monitoring uses no privileged helper and cannot stop protected processes. Sparkle includes its own update installation tools. Stop actions recheck PID/start time, but macOS's PID-based signal API cannot eliminate the final check-to-signal race entirely.

Local builds are ad-hoc signed by default. Public distribution requires your Developer ID identity, notarization, and update hosting as described above.

## Inspiration and acknowledgments

- [VitalsMac](https://vitalsmac.com/) inspired the dashboard, metric cards and compact menu-bar panels.
- [Stats](https://github.com/exelban/stats), by [Serhiy Mytrovtsiy (exelban)](https://github.com/exelban), inspired the configurable monitors, hardware overview and settings. Its open-source AppleSMC implementation and sensor mappings also informed zStats' thermal monitoring.

Thank you to both projects for the ideas and work behind them. The Stats-derived protocol definitions and sensor mappings retain their MIT attribution in [Third-party notices](THIRD_PARTY_NOTICES.md).

## License

The original zStats code and documentation are licensed under [MIT](LICENSE). Original logo and app-icon artwork in `assets/brand/` is covered separately by the [artwork terms](assets/brand/LICENSE); forks should use their own branding or obtain permission to reuse it. Third-party code and components retain their existing licenses and attribution in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
