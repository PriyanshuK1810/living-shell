import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/components/" as Comp
import "../../services"

// VOID SHELL — workspace overview (PRD 24) in its Shadow Spaces form
// (plan §5): a label-free card strip of real window previews, plus an
// expanded view for one workspace.
//
// Layout follows the Neon Purple concept: everything lives on one thin,
// highly translucent panel over the ink art — a row of wide ~2:1 cards
// (focused card full size behind a bright accent border and a violet
// halo, the rest set back a little and dimmer) with the indicator pills
// centred under it. No rail, no badges, no chips: the reference card is
// preview only. The panel sizes itself from its content, so one
// workspace and fifteen both fit the output.
//
// Cards carry live or last-still captures through ScreencopyView — no
// fake previews, nothing written to disk, no polling and no processes:
// capture is a Wayland protocol request budgeted by PreviewController
// (live slots → single captured still → neutral plate). The idle top
// bar is never altered: this is a separate overlay window.
//
// Escape closes the topmost layer first (expanded view, then the
// overview itself), matching the one-primary-popup rule.
Scope {
    id: root

    // Workspace open in the expanded view (null → card strip).
    property var expandedWs: null

    // Drop the expanded view if its workspace disappears underneath it.
    readonly property var expanded: {
        const want = root.expandedWs;
        if (want === null || want === undefined) {
            return null;
        }
        return HyprlandService.workspaceById(want.id) !== null ? want : null;
    }

    // Fullscreen policy (§3): under `explicit-only` this overlay may
    // cover a fullscreen window only when it was invoked deliberately.
    // Every opener today (Super+W, pill right-click, launcher action)
    // invokes explicitly, so the gate is open; the dwell-reveal opener
    // planned for a later phase must pass PopupManager "reveal" and is
    // refused here while the policy stays `explicit-only`.
    readonly property bool mayOverlay: ManagerSettings.fullscreenPolicy === "follow-focus" || PopupManager.openReason !== "reveal"

    function openExpanded(ws) {
        if (ws !== null && ws !== undefined) {
            root.expandedWs = ws;
        }
    }

    function closeExpanded() {
        root.expandedWs = null;
    }

    // Focus a window from a preview, then dismiss the overview. The
    // dispatch is the *validated* one: it re-checks the window exists
    // first (a stale preview can never retarget focus at a dead
    // address) and the compositor's confirmation is what marks it done.
    function focusWindow(toplevel) {
        if (toplevel !== null && toplevel !== undefined) {
            HyprlandService.activateWindow(toplevel.address);
        }
        PopupManager.closeAll();
    }

    // A card click: activate exactly this workspace, then dismiss.
    // Bounded and silent when correct — same helper the dash pill uses.
    function switchToWorkspace(ws) {
        if (ws !== null && ws !== undefined) {
            HyprlandService.goToWorkspace(String(ws.name));
        }
        PopupManager.closeAll();
    }

    // Escape: expanded view first, overview second (never both at once).
    function handleEscape() {
        if (root.expanded !== null) {
            root.closeExpanded();
            return;
        }
        PopupManager.closeAll();
    }

    // Arrow-key entry point (window scope, like Escape): the strip
    // walks only while it is on screen and collapsed — with the
    // expanded view up there is no strip to walk, so the keys rest.
    function browseStrip(dir) {
        if (body.item !== null && body.item !== undefined) {
            body.item.navigate(dir);
        }
    }

    // --- drag-to-move (Phase D) ------------------------------------------
    // A preview carried off its card and released over another card
    // moves that one window to that one workspace — silently
    // (`follow:false`): neither the current workspace nor focus changes
    // as a side effect of relocating a window (plan §8). The overview
    // stays open, because you may be moving several windows; the strip
    // resolves the drop target from live geometry, never from focus or
    // from a cached position. The QA token `move:<address>:<workspace>`
    // runs exactly this function.
    function moveWindowTo(address, ws) {
        if (address === null || address === undefined || ws === null || ws === undefined) {
            return;
        }
        HyprlandService.moveWindow(String(address), ws.id, false);
    }

    // --- QA hooks ---------------------------------------------------------
    // This environment has no input-injection tool (no wtype/ydotool,
    // /dev/input is not writable), so hover and clicks cannot be driven
    // live. `VOID_OVERVIEW` therefore runs the *same* functions those
    // clicks call, so the code path is still exercised end to end:
    //
    //   expand:<workspace>   open the strip on that workspace's expanded view
    //   switch:<workspace>   run the card-click path (exact workspace focus)
    //   focus:<address>      run the preview-click path (exact window focus)
    //   move:<address>:<ws>  run the drop path (silent move; current
    //                        workspace and focus must not change)
    //   create               run the rail's "+" path (jump to the next
    //                        free workspace id, which the compositor
    //                        creates on focus)
    //
    // Tokens may be comma-separated. Inert unless the variable is set —
    // nothing in the running shell sets it.
    readonly property string qaSpec: String(Quickshell.env("VOID_OVERVIEW") || "")
    readonly property var qaTokens: root.qaSpec === "" ? [] : root.qaSpec.split(",").map(t => t.trim()).filter(t => t !== "")

    function qaToken(prefix) {
        const list = root.qaTokens;
        for (let i = 0; i < list.length; i++) {
            if (list[i].indexOf(prefix) === 0) {
                return list[i].slice(prefix.length);
            }
        }
        return "";
    }

    readonly property string qaExpand: root.qaToken("expand:")
    readonly property string qaSwitch: root.qaToken("switch:")
    readonly property string qaFocus: root.qaToken("focus:")
    readonly property string qaMove: root.qaToken("move:")

    readonly property var qaExpandWs: root.qaExpand !== "" ? HyprlandService.workspaceByName(root.qaExpand) : null
    readonly property var qaFocusWindow: root.qaFocus !== "" ? HyprlandService.windowByAddress(root.qaFocus) : null
    // `move:<address>:<workspace>` — an address never contains a colon,
    // so the first split is the whole parse.
    readonly property var qaMoveParts: root.qaMove !== "" ? root.qaMove.split(":") : []
    readonly property string qaMoveAddress: root.qaMoveParts.length > 0 ? root.qaMoveParts[0] : ""
    readonly property var qaMoveWs: root.qaMoveParts.length > 1 ? HyprlandService.workspaceByName(root.qaMoveParts[1]) : null
    readonly property bool qaHit: root.qaTokens.indexOf("hit") >= 0
    readonly property bool qaScroll: root.qaTokens.indexOf("scroll") >= 0

    property bool qaSwitchDone: false
    property bool qaFocusDone: false
    property bool qaMoveDone: false

    // One-shot actions, re-checked on every Hyprland event until their
    // target exists — event-driven, never a timer.
    function runQa() {
        if (root.qaTokens.length === 0) {
            return;
        }
        if (!root.qaSwitchDone && root.qaSwitch !== "" && HyprlandService.workspaceByName(root.qaSwitch) !== null) {
            root.qaSwitchDone = true;
            console.log("[voidshell] overview QA: card-click path → workspace " + root.qaSwitch);
            root.switchToWorkspace(HyprlandService.workspaceByName(root.qaSwitch));
        }
        if (!root.qaFocusDone && root.qaFocus !== "" && root.qaFocusWindow !== null) {
            root.qaFocusDone = true;
            console.log("[voidshell] overview QA: preview-click path → window " + root.qaFocus);
            root.focusWindow(root.qaFocusWindow);
        }
        if (!root.qaMoveDone && root.qaMoveAddress !== "" && root.qaMoveWs !== null && HyprlandService.windowByAddress(root.qaMoveAddress) !== null) {
            root.qaMoveDone = true;
            console.log("[voidshell] overview QA: drop path → move " + root.qaMoveAddress + " to workspace " + root.qaMoveWs.name);
            root.moveWindowTo(root.qaMoveAddress, root.qaMoveWs);
        }
    }

    Connections {
        target: HyprlandService
        enabled: root.qaTokens.length > 0
        function onEventSerialChanged() {
            root.runQa();
        }
    }

    Component.onCompleted: {
        if (root.qaSpec !== "") {
            console.log("[voidshell] overview QA hook: spec=[" + root.qaSpec + "]");
            PopupManager.open("overview");
            root.runQa();
        }
    }

    // The expanded workspace may only appear after the IPC stream is up.
    onQaExpandWsChanged: {
        if (root.qaExpand !== "" && root.qaExpandWs !== null && PopupManager.isOpen("overview") && root.expandedWs === null) {
            root.expandedWs = root.qaExpandWs;
        }
    }

    PanelWindow {
        id: win

        visible: PopupManager.isOpen("overview") && root.mayOverlay
        screen: PopupManager.activeScreen !== null ? PopupManager.activeScreen : PopupManager.fallbackScreen
        // Blur-exempt + ignores other surfaces' zones (design-system §2).
        WlrLayershell.namespace: "voidshell-overview"
        // Keyboard while open so Escape reaches the overview (default None).
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        exclusiveZone: -1

        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }

        // Escape closes the overview (it is not a lock surface). The
        // window-scope shortcut mirrors PopupShell: a clicked preview
        // holding focus must not swallow the key.
        Shortcut {
            enabled: win.visible
            context: Qt.ApplicationShortcut
            sequences: ["Escape"]
            onActivated: root.handleEscape()
        }

        // Arrow keys walk the strip exactly as the wheel does — one
        // card per press while the row overflows the frame, a focus
        // step when every card fits (nothing to scroll then). Same
        // application scope as Escape, and at rest while the expanded
        // view covers the strip.
        Shortcut {
            enabled: win.visible && root.expanded === null
            context: Qt.ApplicationShortcut
            sequences: ["Left", "Up"]
            onActivated: root.browseStrip(-1)
        }
        Shortcut {
            enabled: win.visible && root.expanded === null
            context: Qt.ApplicationShortcut
            sequences: ["Right", "Down"]
            onActivated: root.browseStrip(1)
        }

        Item {
            id: escGrab
            anchors.fill: parent
            focus: win.visible
            Keys.enabled: win.visible
            Keys.onEscapePressed: root.handleEscape()
        }

        onVisibleChanged: {
            if (visible) {
                // Fresh layer on every open; the QA hook (if any) pins it
                // to the expanded view instead.
                root.expandedWs = root.qaExpandWs !== null ? root.qaExpandWs : null;
                escGrab.forceActiveFocus();
            }
        }

        // Transparent backdrop: like the reference, the desktop stays
        // as it is — no dim and no full-screen art; the ink wash lives
        // on the panel itself. Clicking empty space still dismisses.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.expanded !== null) {
                    root.closeExpanded();
                } else {
                    PopupManager.closeAll();
                }
            }
        }

        // The whole body (cards, previews, expanded view) exists only
        // while the overview is open: closing it destroys every
        // ScreencopyView, releasing its capture session and its live
        // slot. Nothing keeps capturing behind a closed overlay.
        Loader {
            id: body
            anchors.fill: parent
            active: win.visible
            sourceComponent: bodyComponent
            // Fades up on open (created dark, then shown), so the
            // reduced mode keeps a fade while `off` never animates.
            property bool shown: false
            opacity: shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: ManagerSettings.durationOverview
                    easing.type: Easing.OutCubic
                }
            }

            onLoaded: shown = true

            onActiveChanged: {
                if (!active) {
                    shown = false;
                    root.expandedWs = null;
                    PreviewController.clear();
                }
            }
        }

        Component {
            id: bodyComponent

            Item {
                id: strip
                anchors.fill: parent

                // ---- slider geometry (derived, fixed frame) ---------------
                // The frame is a slider window: it holds one row's worth
                // of slots on this output and never grows with the
                // workspace count — additions scroll in sideways instead
                // of wrapping or stretching the panel. slotW/slotH mirror
                // WorkspaceCard's slot — keep both in sync.
                readonly property int slotW: 340
                readonly property int slotH: 176
                readonly property int cardGap: 24
                readonly property int panelPad: 36
                readonly property int indGap: 16
                readonly property int indBlock: 16

                readonly property int cardCount: Math.max(1, cardRepeater.count)
                readonly property int viewportCap: Math.max(1, Math.floor((win.width - 32 - panelPad * 2 + cardGap) / (slotW + cardGap)))
                readonly property int viewportW: viewportCap * slotW + Math.max(0, viewportCap - 1) * cardGap
                // Content width grows with the workspaces; the viewport
                // (and therefore the panel) does not.
                readonly property int cardsW: cardCount * slotW + Math.max(0, cardCount - 1) * cardGap
                readonly property int contentH: slotH + indGap + indBlock
                readonly property int panelW: Math.min(win.width - 32, viewportW + panelPad * 2)
                readonly property int panelH: Math.min(win.height - 48, contentH + panelPad * 2)

                // ---- slider scroll state ----------------------------------
                // While the row fits, the strip locks to the centre and
                // the wheel is inert; past the fit it scrolls between
                // [viewport − content, 0] like a carousel. scrollX is the
                // row's x inside the viewport — its Behaviour is the
                // movement duration (§12), so reduced/off snap.
                readonly property bool scrollFits: cardsW <= viewportW
                readonly property real scrollHome: (viewportW - cardsW) / 2
                readonly property real scrollMin: scrollFits ? scrollHome : viewportW - cardsW
                readonly property real scrollMax: scrollFits ? scrollHome : 0
                property real scrollX: 0

                Behavior on scrollX {
                    NumberAnimation {
                        duration: ManagerSettings.durationCard
                        easing.type: Easing.OutCubic
                    }
                }

                function clampScroll(x) {
                    return Math.max(strip.scrollMin, Math.min(strip.scrollMax, x));
                }

                // +1 slides to the next card (content moves left); the
                // QA token drives the same clamp the wheel does.
                function scrollBy(dir) {
                    if (strip.scrollFits) {
                        return;
                    }
                    strip.scrollX = strip.clampScroll(strip.scrollX - dir * (strip.slotW + strip.cardGap));
                }

                function scrollTo(x) {
                    strip.scrollX = strip.clampScroll(x);
                }

                // One navigation unit for every input (wheel, touchpad,
                // arrows): a card step while the row overflows the
                // frame; when every card fits there is nothing to
                // scroll, so the same gesture walks focus instead (the
                // dash pill's rule) — no input is ever inert.
                function navigate(dir) {
                    if (strip.scrollFits) {
                        HyprlandService.goToRelativeWorkspace(dir);
                        return;
                    }
                    strip.scrollBy(dir);
                }

                // Wheel/touchpad entry: devices disagree on units —
                // mice turn in notches (angle 120), Wayland touchpads
                // swipe in pixels and often report a zero angle stream
                // (which is why the old angle-only handler was dead
                // under two fingers) — so both are folded into detents:
                // 120 units, or half a card of finger travel, is one
                // step. A trackpad's stream of tiny deltas can then
                // never blast through the row the way a per-event step
                // would. Returns the steps it took (QA reads it).
                property real navAcc: 0

                function wheelStep(d, isPixel) {
                    if (d === 0) {
                        return 0;
                    }
                    const unit = isPixel ? (strip.slotW + strip.cardGap) / 2 : 120;
                    strip.navAcc += d / unit;
                    let steps = 0;
                    while (Math.abs(strip.navAcc) >= 1 && steps < 6) {
                        const back = strip.navAcc > 0;
                        strip.navAcc += back ? -1 : 1;
                        // Positive delta is "back" — the direction the
                        // old wheel code took for a rising angle.
                        strip.navigate(back ? -1 : 1);
                        steps++;
                    }
                    return steps;
                }

                // Keep the focused card in the viewport: centred when the
                // body opens (force), and otherwise only moved when the
                // focused card has scrolled out of sight — a visible card
                // never fights the user's position.
                function ensureFocusVisible(force) {
                    if (root.qaScroll) {
                        return;
                    }
                    const focused = HyprlandService.focusedWorkspace;
                    if (focused === null || cardRepeater.count === 0) {
                        return;
                    }
                    let idx = -1;
                    for (let i = 0; i < cardRepeater.count; i++) {
                        const c = cardRepeater.itemAt(i);
                        if (c !== null && c.ws !== null && c.ws.id === focused.id) {
                            idx = i;
                            break;
                        }
                    }
                    if (idx < 0) {
                        return;
                    }
                    const left = idx * (strip.slotW + strip.cardGap);
                    const right = left + strip.slotW;
                    const viewL = -strip.scrollX;
                    const viewR = viewL + strip.viewportW;
                    if (!force && left >= viewL && right <= viewR) {
                        return;
                    }
                    strip.scrollTo(-(left - (strip.viewportW - strip.slotW) / 2));
                }

                // The scroll range is derived, so it re-clamps whenever a
                // workspace is added or removed (event-driven, no timer).
                onScrollMinChanged: strip.scrollX = strip.clampScroll(strip.scrollX)
                onScrollMaxChanged: strip.scrollX = strip.clampScroll(strip.scrollX)

                // ---- drag-to-move (Phase D) ----------------------------
                // The drop target is picked from live geometry: each
                // card's scene rectangle is tested against the pointer's
                // scene position (the same space the preview reports),
                // so a drop lands on the card that is visibly there —
                // never on focus order, never on a cached position.
                function cardAt(x, y) {
                    // A card scrolled out of the slider viewport is clipped
                    // away, so the drop must not see it either: the point
                    // has to be inside the viewport before any card counts.
                    const vp = viewport.mapToItem(null, 0, 0);
                    if (x < vp.x || x >= vp.x + viewport.width || y < vp.y || y >= vp.y + viewport.height) {
                        return null;
                    }
                    for (let i = 0; i < cardRepeater.count; i++) {
                        const card = cardRepeater.itemAt(i);
                        if (card === null || card === undefined) {
                            continue;
                        }
                        // The pointer sees the *painted* card, which is the
                        // surface centred in the slot at whatever scale the
                        // carousel gave it — so the drop lands on the
                        // rectangle that is visibly there, not on the slot.
                        const surf = card.surfaceItem;
                        const sp = card.mapToItem(null, 0, 0);
                        const w = surf.width * surf.scale;
                        const h = surf.height * surf.scale;
                        const x0 = sp.x + (card.width - w) / 2;
                        const y0 = sp.y + (card.height - h) / 2;
                        if (x >= x0 && x < x0 + w && y >= y0 && y < y0 + h) {
                            return card;
                        }
                    }
                    return null;
                }

                // ---- QA: hit-test probe (`VOID_OVERVIEW=hit`) ---------
                // The drop path is pointer-driven and this machine has no
                // pointer injector (no wtype/ydotool), so the probe answers
                // cardAt directly instead of pretending to drag: the centre
                // of the painted card must hit it, two pixels inside the
                // painted left edge must hit it, and a point that sits
                // inside the *slot* but outside the painted surface —
                // exactly the rectangle the old slot-based test claimed —
                // must miss.
                property bool qaHitDone: false

                // Focus is computed here instead of reading `card.activeWs`:
                // the probe runs inside the very signal emission that changed
                // focus, where a property binding can still be read from its
                // previous activation — the same expression evaluated in JS
                // always sees the current value.
                function focusedCard() {
                    const focused = HyprlandService.focusedWorkspace;
                    if (focused === null) {
                        return null;
                    }
                    for (let i = 0; i < cardRepeater.count; i++) {
                        const c = cardRepeater.itemAt(i);
                        if (c !== null && c.ws !== null && c.ws.id === focused.id) {
                            return c;
                        }
                    }
                    return null;
                }

                function tryProbe() {
                    if (!root.qaHit || strip.qaHitDone) {
                        return;
                    }
                    // Readiness = the startup model sync has landed *and*
                    // the layer surface has been configured: right after a
                    // remap win.width is still 0, which would fake a
                    // one-slot viewport and a wrong clip half. Deferred
                    // through Qt.callLater so it never measures a
                    // mid-emission binding state; wait for the next event
                    // (never a timer) if it is not ready yet.
                    if (win.width <= 0
                        || cardRepeater.count === 0
                        || HyprlandService.focusedWorkspace === null
                        || cardRepeater.itemAt(0) === null
                        || cardRepeater.itemAt(0).width <= 0) {
                        return;
                    }
                    const fc = strip.focusedCard();
                    if (fc === null) {
                        return;
                    }
                    strip.qaHitDone = true;
                    let fIdx = 0;
                    for (let i = 0; i < cardRepeater.count; i++) {
                        if (cardRepeater.itemAt(i) === fc) {
                            fIdx = i;
                            break;
                        }
                    }
                    // The focused card (scale 1 — its painted surface sits
                    // only 6px inside the slot, the tightest margin), card0,
                    // and the last card: with the slider, the first and
                    // last are the ones a scroll can push out of the
                    // viewport — in view they take the full hit half, out
                    // of view they take the clip half (every point must
                    // miss, or a clipped card would still swallow drops).
                    const idxs = [];
                    for (const k of [fIdx, 0, cardRepeater.count - 1]) {
                        if (k >= 0 && idxs.indexOf(k) < 0) {
                            idxs.push(k);
                        }
                    }
                    const vpos = viewport.mapToItem(null, 0, 0);
                    const out = [];
                    for (let n = 0; n < idxs.length; n++) {
                        const i = idxs[n];
                        const card = cardRepeater.itemAt(i);
                        if (card === null || card === undefined) {
                            continue;
                        }
                        const surf = card.surfaceItem;
                        const sp = card.mapToItem(null, 0, 0);
                        const w = surf.width * surf.scale;
                        const h = surf.height * surf.scale;
                        const cx = sp.x + card.width / 2;
                        const cy = sp.y + card.height / 2;
                        // Branch on the probe point, not the card: a card
                        // half-scrolled past the frame still owns the
                        // points the viewport shows (centre hits), while
                        // the points the clip cut off must miss.
                        const full = sp.x >= vpos.x - 0.5 && sp.x + card.width <= vpos.x + viewport.width + 0.5;
                        const centreIn = cx >= vpos.x && cx < vpos.x + viewport.width;
                        if (!centreIn) {
                            const clipped = cardAt(cx, cy) === null;
                            out.push("card" + i + "(clipped) centre=" + (clipped ? "miss" : "HIT-BUG"));
                            continue;
                        }
                        const centre = cardAt(cx, cy) === card;
                        out.push("card" + i + (card === fc ? "(focused)" : "(idle)") + (full ? "" : "(partial)")
                            + " centre=" + (centre ? "hit" : "MISS"));
                        if (!full) {
                            continue;
                        }
                        const margin = cardAt(sp.x + 2, sp.y + 2) === null;
                        const edge = cardAt(sp.x + (card.width - w) / 2 + 2, cy) === card;
                        out[out.length - 1] += " painted-edge=" + (edge ? "hit" : "MISS")
                            + " slot-margin=" + (margin ? "miss" : "HIT")
                            + " painted=" + Math.round(w) + "x" + Math.round(h);
                    }
                    console.log("[voidshell] overview QA: hit " + out.join(" | ")
                        + " || focused=" + HyprlandService.focusedWorkspace.id
                        + " cards=" + cardRepeater.count);
                }

                // `VOID_OVERVIEW=scroll` — the wheel cannot be injected
                // on this machine, so the probe first feeds one synthetic
                // half-card pixel delta through the very function the
                // touchpad path calls (proof a pixel stream is accepted
                // and folded to exactly one detent), then drives the
                // slider to its far end through the same clamp the wheel
                // uses and prints the geometry; the QA screenshot then
                // shows workspaces that only exist by scrolling.
                property bool qaScrollDone: false

                function tryScroll() {
                    if (!root.qaScroll || strip.qaScrollDone) {
                        return;
                    }
                    // Same readiness bar as tryProbe: right after a remap
                    // win.width is still 0, which would fake a one-slot
                    // viewport (340) and a wrong far end in the log.
                    if (win.width <= 0
                        || cardRepeater.count === 0
                        || cardRepeater.itemAt(0) === null
                        || cardRepeater.itemAt(0).width <= 0) {
                        return;
                    }
                    strip.qaScrollDone = true;
                    const step = strip.slotW + strip.cardGap;
                    let wheelSteps = 0;
                    if (!strip.scrollFits) {
                        wheelSteps = strip.wheelStep(step / 2, true);
                    }
                    const target = strip.clampScroll(strip.scrollMin);
                    strip.scrollTo(strip.scrollMin);
                    console.log("[voidshell] overview QA: scroll cards=" + cardRepeater.count
                        + " viewport=" + strip.viewportW + " content=" + strip.cardsW
                        + " range=[" + Math.round(strip.scrollMin) + "," + Math.round(strip.scrollMax) + "]"
                        + " x=" + Math.round(target)
                        + " cards-visible=" + Math.floor(-target / step) + ".."
                        + Math.ceil((-target + strip.viewportW) / step));
                    console.log("[voidshell] overview QA: wheel pixels=" + (step / 2)
                        + " steps=" + wheelSteps + " acc=" + strip.navAcc
                        + (strip.scrollFits ? " (fits: wheel walks focus)" : ""));
                }

                // The probes need laid-out cards: one loop turn later the
                // repeater has run and QML has resolved the geometry.
                // Focus-follow queues first, so a drop probe never measures
                // a focused card the slider has scrolled out of view.
                Component.onCompleted: {
                    Qt.callLater(() => strip.ensureFocusVisible(true));
                    if (root.qaHit || root.qaScroll) {
                        Qt.callLater(strip.runQaProbes);
                    }
                }

                // The slider follows real state: centred on the focused
                // workspace when it opens, nudged only when focus moves or
                // a workspace is added and the focused card has left the
                // viewport — event-driven, never a timer.
                Connections {
                    target: HyprlandService
                    function onFocusedWorkspaceChanged() { Qt.callLater(() => strip.ensureFocusVisible(false)); }
                    function onEligibleWorkspacesChanged() { Qt.callLater(() => strip.ensureFocusVisible(false)); }
                }

                // Re-checked on Hyprland events, never on a timer: the
                // workspace and focus models may sync after the body is
                // built. Every trigger defers through callLater so the probe
                // reads settled bindings, not the emission that woke it.
                Connections {
                    target: HyprlandService
                    enabled: (root.qaHit && !strip.qaHitDone) || (root.qaScroll && !strip.qaScrollDone)
                    function onEventSerialChanged() { Qt.callLater(strip.runQaProbes); }
                    function onEligibleWorkspacesChanged() { Qt.callLater(strip.runQaProbes); }
                    function onFocusedWorkspaceChanged() { Qt.callLater(strip.runQaProbes); }
                }

                function runQaProbes() {
                    strip.tryProbe();
                    strip.tryScroll();
                }

                function clearDropTargets() {
                    for (let i = 0; i < cardRepeater.count; i++) {
                        const card = cardRepeater.itemAt(i);
                        if (card !== null && card !== undefined) {
                            card.dropHover = false;
                        }
                    }
                }

                // Live highlight while a preview is carried.
                function trackDrop(x, y) {
                    const target = strip.cardAt(x, y);
                    strip.clearDropTargets();
                    if (target !== null) {
                        target.dropHover = true;
                    }
                }

                // The release: one window, one workspace, silent move.
                function dropPreview(toplevel, x, y) {
                    const target = strip.cardAt(x, y);
                    strip.clearDropTargets();
                    if (target === null || toplevel === null || toplevel === undefined) {
                        return;
                    }
                    root.moveWindowTo(String(toplevel.address), target.ws);
                }

                // ---- the glass panel ---------------------------------------
                // One fixed slider frame carrying the ink wash: the card
                // row with the pills centred under it. Clicking the frame
                // itself does nothing — only the backdrop *outside* it
                // dismisses.
                Item {
                    id: panel
                    width: strip.panelW
                    height: strip.panelH
                    anchors.centerIn: parent

                    // Grounding base: the ink used to composite over the
                    // dim backdrop; now that the backdrop is transparent
                    // the same violet sits under the art, so the frame
                    // reads identically over any desktop behind it.
                    Rectangle {
                        anchors.fill: parent
                        radius: 36
                        color: Qt.rgba(16 / 255, 12 / 255, 26 / 255, 0.42)
                    }

                    // The ink wash lives here, not behind the whole
                    // screen: the same session artwork (InkArt), masked to
                    // the frame, its veil keeping the card glass readable
                    // over bright wallpapers.
                    Comp.InkTexture {
                        anchors.fill: parent
                        radius: 36
                        source: InkArt.sourceFor("overview")
                    }

                    // Hairline edge, over the art.
                    Rectangle {
                        anchors.fill: parent
                        radius: 36
                        color: "transparent"
                        border.width: 1.5
                        border.color: Qt.rgba(240 / 255, 236 / 255, 255 / 255, 0.30)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {}
                    }

                    // Wheel and touchpad drive the strip from anywhere on
                    // the frame — cards, pills, padding: the dominant
                    // axis is taken from `pixelDelta` first (Wayland
                    // touchpads report pixels with a zero angle stream)
                    // and falls back to `angleDelta` (mouse notches), so
                    // a vertical two-finger swipe scrolls the row
                    // sideways too. Its pan target is an invisible pad,
                    // so a pan can never shift the strip itself — only
                    // navigate() moves the row.
                    WheelHandler {
                        target: wheelPad
                        acceptedModifiers: Qt.NoModifier
                        onWheel: event => {
                            const pd = event.pixelDelta;
                            const ad = event.angleDelta;
                            const dpx = Math.abs(pd.x) >= Math.abs(pd.y) ? pd.x : pd.y;
                            const dan = Math.abs(ad.x) >= Math.abs(ad.y) ? ad.x : ad.y;
                            if (dpx !== 0) {
                                strip.wheelStep(dpx, true);
                            } else if (dan !== 0) {
                                strip.wheelStep(dan, false);
                            }
                        }
                    }

                    // ---- slider viewport: one row, scrolled sideways ----
                    Item {
                        id: viewport
                        x: strip.panelPad
                        y: strip.panelPad
                        width: strip.viewportW
                        height: strip.slotH
                        // Cards past the frame are gone, not painted over —
                        // clip is what keeps the drop test agreeing with
                        // the eye (cardAt tests this rect too).
                        clip: true

                        Item {
                            id: wheelPad
                            // Deliberately un-anchored: the WheelHandler's
                            // inertial pan writes x/y, which anchors would
                            // reject. It is empty and clipped away, so it
                            // only exists to absorb that pan.
                            width: viewport.width
                            height: viewport.height
                        }

                        Row {
                            id: cards
                            // The slider: the row's offset inside the fixed
                            // viewport, animated by durationCard (§12).
                            x: strip.scrollX
                            spacing: strip.cardGap

                            Repeater {
                                id: cardRepeater
                                model: HyprlandService.eligibleWorkspaces

                                WorkspaceCard {
                                    required property var modelData

                                    ws: modelData
                                    covered: root.expanded !== null && root.expanded.id === modelData.id
                                    onExpandRequested: ws => root.openExpanded(ws)
                                    onSwitchRequested: ws => root.switchToWorkspace(ws)
                                    onWindowFocused: tl => root.focusWindow(tl)
                                    onDragPosition: (x, y) => strip.trackDrop(x, y)
                                    onDragReleased: (tl, x, y) => strip.dropPreview(tl, x, y)
                                    onDragAborted: strip.clearDropTargets()
                                }
                            }
                        }
                    }

                    // ---- indicator pills (shape, no labels) -------------------
                    // One pill per workspace, the focused one wider and lit
                    // violet — the same switch path as a card click.
                    Row {
                        id: indicators
                        x: strip.panelPad + (strip.viewportW - width) / 2
                        y: strip.panelPad + strip.slotH + strip.indGap
                        height: strip.indBlock
                        spacing: 8

                        Repeater {
                            model: HyprlandService.eligibleWorkspaces

                            Item {
                                required property var modelData

                                readonly property bool activePill: HyprlandService.focusedWorkspace !== null && modelData.id === HyprlandService.focusedWorkspace.id
                                width: activePill ? 26 : 16
                                height: strip.indBlock

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 9
                                    radius: height / 2
                                    color: parent.activePill ? Colors.accentStrong : Colors.glassPressed
                                    border.width: parent.activePill ? 0 : 1
                                    border.color: Colors.borderSubtle
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.switchToWorkspace(modelData)
                                }
                            }
                        }
                    }

                }

                // ---- expanded view (over the cards) ---------------------
                ExpandedView {
                    anchors.fill: parent
                    ws: root.expanded
                    onCloseRequested: root.closeExpanded()
                    onWindowFocused: tl => root.focusWindow(tl)
                }
            }
        }
    }
}
