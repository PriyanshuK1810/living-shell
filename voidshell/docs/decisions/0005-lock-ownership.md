# ADR 0005 — Locker ownership and handoff contract

- Date: 2026-10-21 · Status: accepted · Supersedes: decorative-first lock flow
- PRD: LS-LOCK-01a–f · Evidence: `docs/r0-current-state-audit.md` §2

## Context

The lock surface (`modules/LockScreen/LockScreen.qml`) historically opened
first and started the trusted locker only when the user pressed Enter, while
`PopupManager.locked` was already true — an unbounded window in which the
session was *not* locked but the shell refused Escape/IPC and showed a
password-style field. Audit F-LOCK-1/2 (2026-10-20) also established from
hyprlock v0.9.6 source that **exit code 0 does not uniquely mean
"authenticated"**.

## Decision

1. **The locker owns the lock, from the first frame.** Opening the lock
   surface in a real (non-QA) context starts the discovered locker
   immediately (`LockScreen.qml` `onVisibleChanged` → `startAuth()`). The
   decorative QML layer is a backdrop only. A missing locker refuses the
   surface with a toast — the shell never presents itself as locked without
   a locker running (LS-LOCK-01b).
2. **Exit-code contract (per backend, verified where installed):**

   | hyprlock 0.9.6 (installed) | exit |
   |---|---|
   | Successful unlock → `releaseSessionLock()` → loop ends | 0 |
   | Compositor revokes lock after acquisition (`finished`) — **no PAM** | 0 |
   | `SIGUSR1` remote unlock — **no PAM** | 0 |
   | Config error, no `ext-session-lock-v1`, lock denied/already locked | 1 |
   | Crash / killed | signal code (≠ 0) |

   Policy: exit 0 → dismiss (either PAM passed, or another locker/compositor
   owns the lock — both safe). Exit ≠ 0 → **fail honest**: surface stays,
   message states "the session is NOT locked", Enter retries
   (LS-LOCK-01e). Grace (`--grace N`) is CLI-only and default 0; the shell
   never passes it.
   swaylock/gtklock: not installed on the target — contracts unverified; do
   not generalize hyprlock behavior to them (documented untested per PRD
   §0.5).
3. **QA isolation (LS-LOCK-01d):** any `VOID_POPUP` value marks the instance
   as a QA rig → locker never auto-starts (hardening-check N opens this
   surface via IPC on a `VOID_POPUP=overview` instance; auto-start there
   would lock the developer's session). Escape dismiss requires
   `VOID_POPUP=lock` **and** explicit `VOID_QA=1`; no gate sends synthetic
   Escape, so no gate depends on the old single-flag behavior.
4. **Deceptive affordance (LS-LOCK-01c):** the field's idle hint now says
   "Press Enter to start <locker>" — it is a start-lock control, not a
   password prompt; the real prompt is the locker's.
5. **Destructive actions** on the surface keep two-step arming; QA scripts
   must never execute real power actions (LS-LOCK-01f; grep-verified 2026-10-20).

## Consequences

- `ipc call lock toggle` / PowerMenu lock now locks the session for real,
  immediately; the pre-lock exposure window (audit F-LOCK-1) is gone.
- Locker crashes are reported as "NOT locked" instead of a generic error.
- The real lock/unlock round-trip, crash, and simultaneous-request tests
  (`scripts/lock-check.sh`, planned) must run on a disposable test session,
  never on the developer's live session.
