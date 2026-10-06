# VOID SHELL — Performance

PRD §36 acceptance: document idle CPU, idle memory, CPU with dashboard
open, CPU with the audio visualizer enabled, and active child
processes. No numeric ceiling is prescribed; the engineering goal is
the elimination of runaway polling and unnecessary background work.

## 1. Test environment

| Item | Value |
|---|---|
| CPU | Intel Core i5-6300U, 2 cores / 4 threads (2015 mobile part) |
| RAM | 7.5 GiB total |
| Display | eDP-1 1920×1080 @ 60 Hz, scale 1.5 (logical 1280×720) |
| OS / compositor | Arch Linux (rolling), Hyprland 0.56.2 |
| Shell | Quickshell 0.3.1, Qt 6.11.2, daemonized (`qs -d -c voidshell --no-duplicate`) |
| Ambient load | desktop session in normal use; measured while the legacy `myshell` bar still ran alongside — removed 2026-10-02, so current ambient is this shell alone |

**Method.** CPU = Δ(utime+stime) from `/proc/<pid>/stat` over fixed
windows (`CLK_TCK` 100), cross-checked with `top -b` on the exact
PID. Each figure below is the printed value for its window; idle was
sampled in three consecutive 30 s windows. RSS from
`/proc/<pid>/status`. Child processes sampled at 10 Hz.

## 2. Measured results

| Scenario | CPU | RSS |
|---|---|---|
| **Idle** (no popup, overlay `off`) | **0.67 – 0.77 %** (3× 30 s windows) | **≈ 417 MB** |
| Dashboard open (5 tabs, stats sampling at 2 s) | 1.85 % | ≈ 420 MB |
| Task manager open (gauges + process table, 3 s `ps`) | 3.65 % | ≈ 431 MB |
| **Visualizer overlay enabled, silent** (sink muted, no MPRIS player) | **1.98 %** (band 1.7 – 2.0 %) | ≈ 424 MB |
| Visualizer enabled while the wake tap is armed (sink *un*muted, silent) | +2.8 pp over the above | — |
| Reference: legacy `myshell` bar (no stats, no services) | 0.04 % | 338 MB |

### Active child processes (PRD §36 acceptance)

| State | Children |
|---|---|
| Idle (any state above, 60 s @ 10 Hz sampling) | **none — zero spawns** |
| Task manager visible | `sh -c ps -eo …` every 3 s (parsed in-process, stops on close) |
| Disk / updates widgets | `df` every 60 s; package check every 15 min (floor is 60 s, “preferably longer”) |
| Visualizer audio-active | `ffmpeg` (sink monitor) + `base64` pipeline — short-lived by design (silence-stop after 4.2 s) |
| Screenshot / recording / wallpaper apply | `grim`(+`slurp`) / `wf-recorder` / `awww`, only on user action |
| Launcher `@git`, `@containers`, app index | `find`/`git`/`docker` scans, **cached** (one-shot waits, never per-frame) |

## 3. Work eliminated during the audit

Three regressions were found by measuring, A/B-ing, and fixing — each
verified with the same method:

1. **Always-on stats sampling — idle 2.11 % → 0.67 %.**
   `SystemStats` polled five `/proc` files every 2 s forever, feeding
   ~30 bound widgets even with no stats view on screen. Now the
   sampler runs **only while the task manager or dashboard is open**
   (`statsFast`), takes one immediate sample on open so gauges are
   fresh on frame one, and stops on close. Graph history fills at the
   full 2 s rate (60 points = 2 min) while visible — matching PRD §36’s
   “~2 s polling” where it is actually consumed.

2. **Visualizer frame loop never ended — enabled 5.93 % → 4.53 %.**
   After the silence-stop, `frame()` kept allocating and re-notifying
   a fresh zero array at 33 ms forever (30 fps full-scene churn with
   no audio at all). The loop now runs only while the capture is
   audio-active, decays the bars to flat exactly once, and stops
   itself — a silent overlay renders statically.

3. **Pipewire wake tap through digital silence — 4.53 % → 1.98 %.**
   The peak monitor (wake source, PRD’s no-polling rule) ran while the
   sink was **muted**, pushing ~47 Hz zero-level events through
   pipewire and QML where they could never cross the wake threshold
   (A/B measured: 4.53 % vs 1.73 % with it disabled). It is now gated
   on `active && !running && !AudioService.muted`: armed only when a
   sound *could* actually wake the pipeline; MPRIS play remains the
   second wake source.

Design rules now enforced in code (all `repeat: true` timers audited):

- every recurring timer is bound to the state that consumes it
  (stats → popup open, processes → drawer open, brightness → slider
  active, lyrics tick → lyrics available, visualizer loop →
  audio-active, recording tick → recording active);
- capability probes and scans are one-shot at startup or cached;
- no subprocess per frame, no network in the shell’s steady state.

## 4. Interpretation

- Idle ~0.7 % on a 2015 dual-core, with a live notification server,
  DBus/pipewire listeners, three bar surfaces and per-minute clock —
  versus 0.04 % for a bare status bar that keeps no services.
- The overlay window (fullscreen, bottom layer, click-through) adds
  ~1 pp while enabled; the visualizer pipeline adds nothing while
  silent.
- RSS ≈ 417 MB is QML/JS engine + item trees for ten popups and five
  dashboard tabs + image caches; acceptable at 7.5 GiB, and constant
  across states (no leak over the multi-hour QA session).

## 5. Caveats / reproduction notes

- **Audio-active CPU could not be sustained-measured**: the machine’s
  sink is muted (deliberately — audible test tones are not played
  during QA) and no MPRIS player is installed, so the pipeline
  correctly refuses to start. To reproduce: unmute, set `overlay:
  visualizer` in `~/.local/share/voidshell/wallpaper.json`, restart
  the shell, play audio; `ffmpeg` + 512-pt FFT at 30 fps is the
  active cost (it stops itself 4.2 s after silence).
- The “+2.8 pp armed tap” figure applies only while the sink is
  unmuted *and* silent; as soon as audio flows the tap disables
  itself (`enabled: active && !running`).
- Figures are for this hardware; relative deltas (the three fixes)
  generalize.

## 6. Health of a restart

Fresh `qs -d -c voidshell` comes up with configuration loaded, **zero
warnings/errors** in the log, all ten IPC targets registered, bar
layer surfaces present, overlay absent when `overlay: off`, and no
child processes — verified after every change (see `docs/testing.md`).
