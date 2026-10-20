# R0 current-state audit — source-of-truth evidence

- Document: LS-R0-AUDIT-001 (evidence for PRD LS-PRD-IMPROVEMENTS-001 §0.1, §15, G0)
- Date: 2026-10-20 · Mode: read-only inspection; no source files modified
- Author: OpenCode agent session · Status: findings for LS-001/LS-002 inputs

## 0. Environment measured (revalidated vs PRD "Target")

| Item | PRD target doc | Actual installed | Note |
|---|---|---|---|
| Quickshell | 0.3.1 | **0.3.2** (Arch) | deviation; revalidation done per PRD |
| Qt | 6.11.x | **6.12.0** (qt6-base) | deviation |
| kitty | 0.49.x | 0.49.2 | matches |
| Hyprland | — | 0.56.2 | live session (wayland-1) |
| hyprlock | one of 3 | **0.9.6 only** | swaylock/gtklock **not installed** |
| cliphist | — | 1:0.7.0-2 | watcher live: `wl-paste --watch cliphist store` (PID 678), single instance |
| shellcheck | required by CI plan | **missing** | install before G0 static gate |
| python3 | — | 3.14.8 | qmllint/qmlformat present |

Display: eDP-1 1920×1080 @ scale 1.5 → **logical 1280×720** (only monitor).
Live shell: `qs -c voidshell --no-duplicate` PID 680, started 2026-10-20 18:39; **no deployed *.qml newer than process start** → running code == deployed working tree.

## 1. CRITICAL process finding — two divergent trees (not anticipated by the PRD)

The PRD treats `PriyanshuK1810/living-shell` (target checkout) as the baseline, but the **running shell is a different tree**:

| | Repo (target checkout) | Deployed (runtime) |
|---|---|---|
| Path | `/home/Priyanshu/living-shell/voidshell` | `~/.config/quickshell/voidshell` |
| git | 1 commit `2c39b4d`, remote=origin (GitHub), clean | own repo, **no remote**, **disjoint history** (`2c39b4d` not an object here), HEAD `8ad0244` |
| QML files | 120 | **134** |
| Working state | clean | **20 modified + 28 untracked files** (incl. whole `modules/Island/`, `ClipboardService.qml`, `JobBridge.qml`, `modules/Workbench/`, `services/RofiBridge.qml`, …) |
| IPC targets | 13 | **16 live** (adds `workbench`, `gesture`, `void`) |

- Deployed is a **content superset** of the repo (no file exists only in repo); repo copies of 10 shared files differ from deployed working copies (Launcher +188 diff lines, LauncherModel +202, BluetoothService +125, DeviceList, DeviceMenu, AppDetail, shell.qml, plus docs).
- `hyprland.lua` binds `Super+Shift+Space → qs -c voidshell ipc call workbench keyboard` — a **keybind depends on deployed-only code**; installing the repo tree as-is would break it.
- Deployed carries **uncommitted user work** (WIP) and untracked new features. PRD invariant "don't destroy user files" applies before any sync.

**Implication for R0 (LS-002):** decide and document which tree is authoritative, commit/preserve deployed WIP, then reconcile. The PRD's §0.1 evidence (taken from GitHub URLs) describes the repo, **not** the runtime. All §0.1 bullets below were re-verified against both.

## 2. Lock handoff (LS-LOCK-01) — findings

Evidence: `voidshell/modules/LockScreen/LockScreen.qml` (identical in both trees), `services/PowerService.qml`, `modules/PowerMenu/PowerMenu.qml:36-41`, `services/PopupManager.qml:20-28,116-129,144-155,230-235`, `~/.config/hypr/hypridle.conf`, hyprlock v0.9.6 source (upstream `main.cpp`, `core/hyprlock.cpp`).

Flow as implemented:
1. Entry points: PowerMenu "Lock Screen" → `PopupManager.open("lock")`; IPC `qs -c voidshell ipc call lock toggle` → `toggle("lock")`. **Nothing starts the locker at this point.**
2. `PopupManager.locked === true` the moment the decorative surface opens (`activePopup === "lock"`). It blocks all other popups, blocks Escape, blocks IPC toggle-close.
3. The locker (`PowerService.commandFor("lock")` → discovered `hyprlock`) starts **only when the user presses Enter** in the decorative password field (`LockScreen.qml:344-345` → `startAuth()` at `:64-79`).
4. Locker exit 0 → `PopupManager.closeAll()` ("unlock"); exit ≠ 0 → error text, surface stays (`:51-61`).

Findings:

- **F-LOCK-1 (P0, violates LS-LOCK-01b):** an *unsecured* session is presented as locked: between step 2 and a successful hyprlock start — an **unbounded** window (user may never press Enter; hyprlock may be missing/failing) — `PopupManager.locked` is true, Escape/IPC are refused, yet the session is not locked at all (no `ext-session-lock` held; VT switch, ssh, DBus, second seat remain available). The decorative QML layer alone defines "locked".
- **F-LOCK-2 (P0, violates LS-LOCK-01a):** **exit 0 ≠ authenticated.** hyprlock `main()` returns 0 whenever `run()` returns normally. Normal-return paths besides successful unlock: (a) `onLockFinished()` — compositor sends `finished` (e.g. another locker already holds the lock) → `m_bTerminate = true` → exit 0 **with no authentication**; (b) `SIGUSR1` remote-unlock (no PAM); (c) `--grace N` window: *any* keypress during grace → `fadeOutAndUnlock()` → exit 0 (grace is CLI-only, default 0; PowerService passes no args → not active here, but any arg change silently weakens it). `exit(1)` covers config errors, `ext-session-lock-v1` missing, and `acquireSessionLock()` failure (incl. "already locked"). **Conclusion: exit-code alone cannot distinguish unlock from lock-denied; per-backend contract must be per-path, and 0 must not be reported as "authenticated".**
- **F-LOCK-3 (P1, LS-LOCK-01c):** **no keyboard lock bind exists.** `hyprland.lua` has no `ipc call lock` binding; only mouse (PowerMenu) and automatic paths (hypridle `lock_cmd = pidof hyprlock || hyprlock`; `before_sleep_cmd`/`on-timeout = loginctl lock-session` → hypridle → direct hyprlock). Note `Super+L` is bound to `loginctl terminate-user $USER` ("Log out to SDDM") — intentional per comment, but it is the conventional lock chord and it is *destructive* (two-step confirm does not exist for keybinds; out of shell scope, flag to user).
- **F-LOCK-4 (P1, LS-LOCK-01d):** QA bypass = `VOID_POPUP=lock` env (`LockScreen.qml:26`) makes Escape dismiss the surface. The flag is the generic popup-QA hook, not an isolated test flag; in a normal user session `VOID_POPUP=lock` yields a dismissible "lock". Low risk today (that surface never held a real lock), but it does not meet "impossible in normal runtime" without an extra test-only condition.
- **F-LOCK-5 (P1, LS-LOCK-01e):** locker crash/kill (exit ≠ 0) → decorative surface stays with error text while the compositor has already released the session lock (client death ends `ext-session-lock`) → **sensitive UI (media controls, power actions, username/host) exposed over an unlocked session**, and the shell still reports "locked". Missing-locker is handled honestly (`canDo("lock")` false → explanatory text) ✓.
- **F-LOCK-6 (positive):** destructive actions gated: reboot/poweroff require two-step armed confirm within 4 s in both PowerMenu (`:29-35`) and LockScreen (`:85-92`); `PowerService.execute` uses fixed argv arrays, `startDetached` so shell restarts can't kill an in-flight action (`:164-177`). QA scripts contain **no** systemctl/reboot/logout invocations (grep-verified). Real-lock/unlock round-trip and "simultaneous lock" acceptance tests **not yet executed** (require live session — G0 item, needs user consent because they lock the machine).
- Locker availability fallback: probe `command -v hyprlock || swaylock || gtklock || swaylock-effects` (`PowerService.qml:87`); on this machine only hyprlock resolves. swaylock/gtklock contracts: **cannot be verified here (not installed)** — document as untested per PRD, do not generalize.

## 3. IPC baseline (invariant 2) — live inventory

`qs -c voidshell ipc show` (runtime, 16 targets) vs source grep in repo (13):

| Target | Functions | In repo? |
|---|---|---|
| launcher, calendar, media, quickSettings, notifications, power, dashboard, taskManager, overview, lock | toggle | yes (calendar → routes to dashboard) |
| island | toggle, stack, section, context, close, diagnostics | yes |
| job | publish, update, finish, announce, pin, invoke | yes (matches LS-IS-03 list) |
| shelf | toggle | yes |
| **workbench** | toggle, show, hide, menu, keyboard, state, preview, ping | **deployed only** |
| **gesture** | state, commit, config, ping | **deployed only** |
| **void** | rows, run | **deployed only** (RofiBridge) |

No `controlCenter` target exists (expected pre-R1). Keybinds in `hyprland.lua` reference launcher, notifications, quickSettings, media, dashboard, taskManager, overview, shelf, island, workbench — all present at runtime. **Preservation baseline must be the live 16**, not the repo's 13.

## 4. Dashboard tab truth (§0.1 item resolved)

Runtime model (both trees identical): `Dashboard.qml:45-66` → **exactly 4 tabs: overview, media, alerts, productivity.** Documentation is three-way inconsistent:

| Claim | Where |
|---|---|
| 4 tabs | `voidshell/docs/features.md:53`; `Dashboard.qml:7` header comment |
| 5 tabs | root `README.md:5,96`; `features.md:884`; `voidshell/docs/testing.md:40` |
| 6 tabs | `shell.qml:93` entry-point comment |
| `tab-check.sh` expects **5 incl. `weather`** | `scripts/tab-check.sh:5` (`TABS="overview media weather alerts productivity"`) — no weather tab exists → that gate's "5/5" expectation is stale (behavior: `VOID_TAB=weather` sets an unknown `activeTab`; log stays clean → **gate passes vacuously**) |

`popup-check.sh:5` expects 10 popups incl. `calendar`, but `PopupManager.popups` has 9 names and no `calendar` (`VOID_POPUP=calendar` is silently ignored) → docs claim "10/10" is also stale/vacuous.

## 5. PopupManager / invariant 3 — confirmed

- `popups` = 9 names, **no controlCenter** (`PopupManager.qml:20`) ✓ PRD §0.1.
- One-primary-popup enforced: `open()` closes Island, refuses while locked; `toggle()` refuses to close lock; `handleEscape()` no-ops while locked (`:70-155`). Island surface owns its namespace (shell.qml:121-125) → announcement rendering independent of popup geometry ✓.
- QA hook `VOID_POPUP` → `PopupManager.open(wanted)` at startup (`shell.qml:135-140`), invalid names ignored ✓.

## 6. Launcher (R2 inputs)

- **Search:** synchronous, in `LauncherModel.qml` reactive bindings; case-insensitive **substring** match (`:168-198`); apps ranked by 2-tier comparator prefix-first then `localeCompare` (`:186-196`); commands keep declaration order, **no ranking** (`:300-320`); no debounce, no async providers → LS-SR-03's "score function in a pure helper" would formalize current behavior. Empty query = all apps in current section (default `all`) + persistent Recent strip (`Launcher.qml:718-729`) — *not* favorites/recent-default as PRD §5.1 wording suggests.
- **Modes/Escape:** plugin → (clearPlugin keeps `@prefix`) → close; **command list is not an Escape stage** (`Launcher.qml:53-59`) vs PRD LS-SR-06 "plugin → search mode → close". Enter dispatch: app launch / command activate / re-dispatch typed command in plugin mode (`:72-80,119-127`).
- **Injection:** no unquoted query reaches a shell. `@web` is `encodeURIComponent` + `shQuote` (`LauncherModel.qml:430`); all exec paths pass values through `HyprlandService.shQuote` (`HyprlandService.qml:668-670`); fixed-argv Process used for probes. LS-SR-05's allowlisted ActionRegistry does **not** exist yet — dispatch is hardcoded `commands[]` + `runAction` if/else (`:411-450`).
- **Bug (both trees):** `@containers` resolves to `plugins/ContainerPlugin.qml` (`Launcher.qml:28`) but the file is `ContainersPlugin.qml` → plugin renders blank; silent (never exercised by QA gates).
- **Rendering:** all `Text` default `PlainText`; no `textFormat` anywhere in launcher → LS-SR-07 already satisfied.
- **Keyboard:** `Keys.onPressed` only, no `isAutoRepeat`/`inputMethodComposing` guard (`Launcher.qml:336,477`) → IME candidate navigation/Enter/Escape are consumed by `handleKey` (LS-SR-06 gap); focus return after close is compositor-side only.
- **Size/monitors:** fixed `panelW 1160 × panelH 600` + 28 shadow pad → window 1216×656, top offset 48 (`Launcher.qml:35-37,210-223`); **no screen-fit clamp** — on this machine logical 1280×720 it fits with ~32 px side / ~16 px bottom slack; any logical screen < 1216 wide or < 704 tall overflows (§15 multi-monitor item: risk confirmed, ticket deferred per PRD).
- **Idle cost:** no Timer/Process in `Launcher.qml`; probes one-shot at startup; `servicesWarmed` (shell.qml:33) has **no consumers** and in the repo asserts `=== 26` while listing 28 entries (always false; deployed corrected to an honest 33).

## 7. Clipboard (R3 inputs)

- Service is an adapter over cliphist ✓ (PRD §6.1 correct); single watcher live; API `probe/refresh/copyId/deleteId/clear` matches PRD; announcement carries only the *fact*, never content (`ClipboardService.qml:121-130,183-192`) ✓ invariant 4/privacy.
- **Ordering empirically resolved (LS-CB-02):** installed cliphist 0.7.0 `cliphist list` is **newest-first** (observed IDs 322…2 descending; 198 entries). The code comment claims "oldest-first" (`:104`) and then `reverse()`s (`:105`) → the Island displays **oldest-first**, opposite of the comment's stated intent. Truncation to `limit` happens *before* reverse, so the newest N are kept (correct set, wrong display order). Normalize explicitly per PRD.
- Command construction: numeric-ID validated (`/^[0-9]+$/`) then interpolated into `sh -c` (`:147-148,171`) — safe today, but LS-CB-03's "stdin/argv instead of strings" is a fair hardening target.
- Failure taxonomy (LS-CB-07) partially present: `available`, `lastError` from stderr; missing watcher / decode-failure / concurrent-delete not distinguished yet.

## 8. Theme & kitty (R4 inputs)

- ThemeService: **6 presets** ✓ (`ThemeService.qml:38-75`), dark/light + wallpaper `dynTone`, tolerant parse of missing/malformed `theme.json` (`:109-132`) ✓ invariant 6. Unknown preset falls back to default. **No** custom accent/opacity/font/motion controls exist (to be added by LS-TH-01).
- Persistence: `FileView.setText` → `~/.local/share/voidshell/theme.json`. **Atomicity of `FileView.setText` is unverified** (needs quickshell source/doc check) — open item for LS config-schema tests (invariant 6).
- Kitty sync: **does not exist** anywhere in either tree (grep-verified) → PRD proposal accurate. Deployed tree already has `RofiThemeSync.qml` (palette export to rofi) — a precedent for LS-KT-01's mapping approach, and evidence that "eager singleton referenced from shell.qml or it never runs" is a real constraint.
- Kitty include slot: user `kitty.conf:33` has `globinclude conf.d/*.conf`; conf.d currently `10-fonts…95-tools` (no `25-*`, no `20` beyond colors) → a generated `25-living-shell-generated.conf` **is auto-included and sorts after `20-colors.conf`** (later include wins in kitty) without touching any existing file ✓ LS-KT-02 feasible as proposed.

## 9. Storage / XDG (invariant 6, §10)

- `StorageService.qml:14-23` hardcodes `$HOME/.local/share/voidshell` — **ignores `XDG_DATA_HOME`**. All stores (theme, island, launcher, tasks, …) route through it (`StorageService.path()`), so one future migration point exists. kitty-side scripts *do* honor `XDG_CONFIG_HOME` (`kitty/shell/void-kitty.sh:9`, `kitty.conf` uses `${XDG_RUNTIME_DIR}`). No TCP services; no `XDG_RUNTIME_DIR` misuse found.
- PRD §10.1's "`${XDG_DATA_HOME:-…}` for compatibility with existing theme.json" matches actual paths **only when XDG_DATA_HOME is unset** — document the delta or add env fallback in one place.

## 10. Docs vs runtime claim matrix (LS-002 input)

| Claim | Status |
|---|---|
| Dashboard 5 tabs (root README) / 5 (testing.md gates) / 6 (shell.qml) vs actual **4** | wrong — fix all three |
| `tab-check` "5/5" incl. weather; `popup-check` "10/10" incl. calendar | stale expectations; gates pass vacuously |
| `features.md` internally says 4 (line 53) *and* 5 (line 884) | self-contradictory |
| Placeholder clone cmds `git clone <this-repo>` (README.md:42, voidshell/README.md:58) | still placeholders |
| `performance.md` env: qs 0.3.1 / Qt 6.11.2 / "Dashboard open (5 tabs)" | stale versions + wrong tab count; historic 417 MB / 0.67–0.77 % remain *unverified historic* claims |
| docs "eight QA scripts" | true for repo; deployed has a 9th (`workbench-check.sh`) |
| `docs/decisions/` ADRs | absent (proposed in PRD, not created) |
| IPC docs list 10 popup targets + island/job/shelf | misses deployed `workbench`/`gesture`/`void` |

## 11. QA gate status (G0 prep)

- `scripts/check.sh` (qmllint + qmldir) → **CHECK-PASS on repo tree** and **CHECK-PASS on deployed tree** (both run today).
- `smoke-test.sh` and the 6 UI-driving scripts **not run** in this audit: popup/tab/coord/shelf/hardening/island checks open popups or spawn isolated instances → will disturb the live session; run at G0 with user consent. Expected friction: `tab-check` (weather) and `popup-check` (calendar) expectations are stale (§4).
- shellcheck absent → install before ShellCheck gate.

## 12. §15 verification-decision register (audit verdicts)

| §15 decision | Verdict |
|---|---|
| Lock process semantics | **Resolved for hyprlock 0.9.6 (source-level):** exit 0 = "run loop ended", reachable *without* auth (`finished`, SIGUSR1, grace); exit 1 = config/lock-acquire failure. Decorative-first flow violates LS-LOCK-01b → redesign required (start locker at lock initiation; treat exit code as "locker ended", not "authenticated"). swaylock/gtklock: not installed → untestable here. |
| Actual dashboard routes | **Resolved: 4 tabs** (overview/media/alerts/productivity); all docs corrected-by-finding; deep links use these IDs only. |
| Theme persistence | **Partially resolved:** theme.json via StorageService, tolerant parse confirmed; `FileView.setText` atomicity still open. Deployed RofiThemeSync shows the eager-singleton requirement. |
| Launcher internals | **Resolved:** sync substring+prefix ordering in LauncherModel; no provider/registry abstraction; hardcoded command table = starting point for ActionRegistry; @containers path bug found. |
| Clipboard ordering/format | **Resolved empirically:** cliphist 0.7.0 list = newest-first; code reverses to oldest-first against its own comment; fix + fixture test. |
| Config-file ownership | **Partially resolved:** single StorageService authority, but XDG_DATA_HOME ignored; new settings should extend StorageService (or documented new file) — one ADR pending. |
| Multi-monitor scaling | **Risk confirmed** (no screen-fit clamp; fits 1280×720 logical by 16 px); separate usability ticket per PRD. |
| Packaging | Not started (R6); source-deploy first per PRD. |

## 13. Recommended next actions (ordered)

1. **Reconcile trees first (new, blocking):** commit/tag deployed WIP, decide authority, re-run this audit's IPC/dashboard checks after sync — every later gate depends on which tree ships.
2. LS-001 lock redesign note using §2 findings (start locker immediately; per-path exit semantics; add keyboard lock bind decision; fix QA flag isolation).
3. LS-002 doc corrections from §10 table (after tree decision).
4. LS-003 benchmark harness (baseline informal sample today: RSS 326 308 KB, lifetime avg CPU 2.1 % — *not* a benchmark).
5. G0 with user consent: run remaining 7 QA scripts; fix stale tab/popup expectations; install shellcheck.
