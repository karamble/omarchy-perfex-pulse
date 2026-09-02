import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Outstanding receivables from a Perfex CRM as a bar label. Left click opens
// the panel (or the setup terminal while no key works), right click refreshes
// now, middle click flips the querying switch.
//
// The numbers come from the bundled perfex-pulse-fetch script, which reads
// the bearer key from ~/.config/perfex-pulse/api_key - the key never enters
// the shell process, shell.json or argv. Exactly one object here can open a
// socket (fetchProcess) and every path to it goes through refresh(), which
// refuses while the "querying" setting is off; the script re-checks the same
// setting in shell.json before it touches the key, so a paused widget makes
// zero requests even if this file regresses.
BarWidget {
  id: root
  moduleName: "karamble.perfex-pulse"

  // ---- settings (inline on the shell.json entry; these fallbacks ARE the defaults)
  readonly property bool querying: Style.boolToken(setting("querying", false), false)
  readonly property int pollSeconds: clampInt(setting("pollSeconds", 600), 120, 3600, 600)
  readonly property bool showAmount: Style.boolToken(setting("showAmount", true), true)
  readonly property bool showCents: Style.boolToken(setting("showCents", false), false)
  readonly property int overdueRows: clampInt(setting("overdueRows", 5), 0, 15, 5)
  readonly property bool paidThisMonth: Style.boolToken(setting("paidThisMonth", false), false)
  readonly property bool notifyOverdue: Style.boolToken(setting("notifyOverdue", false), false)
  readonly property string crmUrl: String(setting("crmUrl", "https://crm.example.com"))

  // ---- state
  property var crm: null
  property string error: ""
  property string errorDetail: ""
  property int errorHttp: 0
  property int errorSince: 0
  property int lastUpdated: 0
  property int failures: 0
  property int authFailures: 0
  property bool halted: false
  property double rateLimitedUntil: 0
  property bool cancelling: false
  property bool watchdogFired: false
  property int offRetries: 0
  property var pendingQuerying: null
  property double lastRunStarted: 0
  property double nextPollAt: 0
  property var notified: ({})
  property double now: Date.now()

  readonly property bool effectiveQuerying: pendingQuerying !== null ? pendingQuerying === true : querying
  readonly property bool fetching: fetchProcess.running
  readonly property bool needsSetup: error === "no_key" || error === "key_perms" || error === "bad_endpoint" || halted
  readonly property bool stale: error !== "" && crm !== null
  readonly property int effectiveIntervalMs: Math.min(3600000, pollSeconds * 1000 * Math.pow(2, Math.min(failures, 3)))
  readonly property string host: Model.hostOf(crmUrl)

  readonly property string fetchScript: Qt.resolvedUrl("perfex-pulse-fetch").toString().replace(/^file:\/\//, "")
  readonly property string setupScript: Qt.resolvedUrl("perfex-pulse-setup").toString().replace(/^file:\/\//, "")

  readonly property var viewState: ({
    querying: effectiveQuerying, halted: halted, error: error, errorDetail: errorDetail, errorHttp: errorHttp,
    errorSince: errorSince, data: crm, lastUpdated: lastUpdated, host: host,
    nextPollAt: nextPollAt, now: now, showAmount: showAmount, showCents: showCents
  })
  readonly property var barSegments: Model.barSegments(viewState)
  readonly property var verticalLines: Model.verticalLines(viewState)
  // NetBird's bar rule: the bar foreground while active, a darker shade of it
  // while inactive. Never the urgent colour - overdue is the panel's job.
  readonly property bool inactive: !effectiveQuerying && !needsSetup
  readonly property color barInactiveColor: Qt.darker(button.foreground, 1.55)
  readonly property color barColor: inactive ? barInactiveColor : button.foreground
  readonly property string tooltip: Model.tooltip(viewState)
  readonly property int overdueCount: Model.overdueCount(crm)

  function clampInt(value, min, max, fallback) {
    var n = parseInt(value, 10)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  // ---- the single choke point for network activity
  function refresh(force) {
    if (!effectiveQuerying) {
      if (force && root.bar) root.bar.showTooltip(button, "Querying is off - switch it on to refresh")
      return
    }
    if (needsSetup && !force) return
    if (fetchProcess.running) return
    var t = Date.now()
    if (t < rateLimitedUntil && !force) return
    if (!force && t - lastRunStarted < 30000) return
    if (force) { failures = 0; authFailures = 0 }
    lastRunStarted = t
    nextPollAt = t + effectiveIntervalMs
    now = t
    var cmd = [fetchScript, String(overdueRows)]
    if (paidThisMonth) cmd.push("--payments")
    if (force) cmd.push("--force")
    fetchProcess.command = cmd
    cancelling = false
    watchdogFired = false
    fetchProcess.running = true
    if (force) halted = false
  }

  function refreshForced() { refresh(true) }

  function setError(code, detail, http) {
    if (error !== code) errorSince = Math.floor(Date.now() / 1000)
    error = code
    errorDetail = String(detail || "")
    errorHttp = Number(http) || 0
  }

  function applyResult(text, fromCache) {
    var parsed
    try {
      parsed = JSON.parse(text)
    } catch (problem) {
      if (!fromCache) { setError("parse_failed", "", 0); failures = Math.min(failures + 1, 3) }
      return
    }
    if (!parsed || typeof parsed !== "object") {
      if (!fromCache) { setError("parse_failed", "", 0); failures = Math.min(failures + 1, 3) }
      return
    }
    if (parsed.error) {
      if (fromCache) return
      var code = String(parsed.error)
      if (code === "off") {
        // shell.json lagged behind the in-memory flip; retry a few times.
        if (effectiveQuerying && offRetries < 3) { offRetries++; offRetry.restart() }
        else pendingQuerying = null
        return
      }
      if (code === "no_key" || code === "key_perms" || code === "bad_endpoint") {
        error = code; errorDetail = String(parsed.detail || ""); errorHttp = 0
        return
      }
      if (code === "auth") {
        authFailures++
        if (authFailures >= 2) halted = true
        setError(code, parsed.detail, parsed.http)
        return
      }
      if (code === "forbidden") {
        failures = Math.max(failures, 2)
        setError(code, parsed.detail, parsed.http)
        return
      }
      if (code === "rate_limited") {
        rateLimitedUntil = Date.now() + 60000
        setError(code, parsed.detail, parsed.http)
        return
      }
      failures = Math.min(failures + 1, 3)
      setError(code, parsed.detail, parsed.http)
      return
    }
    if (parsed.ok) {
      var previous = crm
      crm = parsed
      lastUpdated = Number(parsed.updated) || lastUpdated
      offRetries = 0
      if (!fromCache) {
        error = ""; errorDetail = ""; errorHttp = 0; errorSince = 0
        failures = 0; authFailures = 0; halted = false
        if (notifyOverdue) notifyNewOverdue(previous, parsed)
      }
    }
  }

  // ---- the switch: every path converges here
  function setQuerying(value) {
    var v = value === true
    pendingQuerying = v
    offRetries = 0
    if (!v && fetchProcess.running) { cancelling = true; fetchProcess.running = false }
    if (v) { halted = false; failures = 0; authFailures = 0; lastRunStarted = 0 }
    persistSettings({ querying: v })
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    } else if (root.bar) {
      for (var k in values) root.bar.run("omarchy bar set " + root.moduleName + " " + k + " " + JSON.stringify(values[k]) + " --json")
    }
  }

  onSettingsChanged: {
    injectPanel()
    if (pendingQuerying !== null && querying === pendingQuerying) pendingQuerying = null
  }

  function runSetup() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation \"" + root.setupScript + "\"")
  }

  function openCrm() {
    Quickshell.execDetached(["omarchy", "launch", "browser", Model.adminUrl(crmUrl)])
  }

  function openInvoice(id) {
    Quickshell.execDetached(["omarchy", "launch", "browser", Model.invoiceUrl(crmUrl, id)])
  }

  // ---- notifications
  function notify(message, openPanel) {
    if (notifyProc.running) return
    var cmd = ["omarchy-notification-send", "--app-name", "Perfex Pulse", "-t", "6000", message]
    if (openPanel) cmd = cmd.concat(["--exec", "omarchy-shell", "shell", "toggle", "karamble.perfex-pulse"])
    notifyProc.command = cmd
    notifyProc.running = true
  }

  function notifyToggle(v) {
    notify("Perfex polling: " + (v ? "on" : "off"), false)
  }

  function notifyNewOverdue(previous, current) {
    var list = current.overdue_invoices || []
    var seen = {}
    for (var k in notified) seen[k] = true
    var fire = null
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i].id)
      if (seen[id]) continue
      seen[id] = true
      // First load marks what is already overdue without shouting about it.
      if (previous !== null && fire === null) fire = list[i]
    }
    notified = seen
    if (fire !== null) notify(fire.number + " is overdue · " + fire.client + " · " + Model.money(fire.balance, fire.symbol, true), true)
  }

  // ---- processes and timers
  Process {
    id: fetchProcess
    running: false
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (root.watchdogFired) {
        root.watchdogFired = false
        root.setError("watchdog", "", 0)
        root.failures = Math.min(root.failures + 1, 3)
      } else if (root.cancelling) {
        root.cancelling = false
        return
      } else {
        root.applyResult(String(fetchStdout.text || ""), false)
      }
      root.now = Date.now()
      root.nextPollAt = root.now + root.effectiveIntervalMs
    }
  }

  Process {
    id: notifyProc
  }

  // The poll. No triggeredOnStart: the first run is the explicit
  // onRunningChanged, so a settings edit while on never sneaks in a fetch.
  Timer {
    id: poll
    interval: root.effectiveIntervalMs
    running: root.effectiveQuerying && !root.needsSetup
    repeat: true
    onRunningChanged: if (running) root.refresh(false)
    onTriggered: root.refresh(false)
  }

  Timer {
    id: offRetry
    interval: 3000
    repeat: false
    onTriggered: if (root.effectiveQuerying) root.refresh(true)
  }

  Timer {
    id: watchdog
    interval: 120000
    running: fetchProcess.running
    repeat: false
    onTriggered: {
      root.watchdogFired = true
      fetchProcess.running = false
    }
  }

  Timer {
    interval: 30000
    running: root.effectiveQuerying
    repeat: true
    onTriggered: root.now = Date.now()
  }

  // Last successful result, from local disk, so the bar shows the greyed
  // last number after a restart while paused - nothing is spawned for it.
  FileView {
    id: lastFile
    path: Quickshell.env("HOME") + "/.cache/perfex-pulse/last.json"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyResult(text(), true)
  }

  Component.onCompleted: lastFile.reload()

  IpcHandler {
    target: "karamble.perfex-pulse"

    function refresh(): void { root.broadcast("refreshForced") }
    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function toggle(): void { root.togglePanel() }
    function queryingOn(): void { root.setQuerying(true); root.notifyToggle(true) }
    function queryingOff(): void { root.setQuerying(false); root.notifyToggle(false) }
    function toggleQuerying(): void { var v = !root.effectiveQuerying; root.setQuerying(v); root.notifyToggle(v) }
    function querying(): string { return root.effectiveQuerying ? "on" : "off" }
    function setup(): void { root.runSetup() }
    function state(): string {
      return JSON.stringify({
        querying: root.querying, effective: root.effectiveQuerying, pending: root.pendingQuerying,
        settings: root.settings, error: root.error, halted: root.halted, fetching: root.fetching,
        hasData: root.crm !== null, lastUpdated: root.lastUpdated, panelLoaded: panelLoader.item !== null,
        opened: root.opened, nextPollAt: root.nextPollAt
      })
    }
  }

  // ---- bar label
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    // The visible text is the overlay below; WidgetButton sizes its slot from
    // the hidden label, so the slot is sized from the overlay instead.
    fixedWidth: root.vertical ? -1 : labelsRow.implicitWidth + button.scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? (1 + root.verticalLines.length) * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh(true)
      else if (b === Qt.MiddleButton) root.setQuerying(!root.effectiveQuerying)
      else if (root.needsSetup) root.runSetup()
      else root.togglePanel()
    }

    // The Perfex mark leads; while polling is off it stands alone, greyed.
    Row {
      id: labelsRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.spaceReal(6)

      PerfexIcon {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Style.font.icon
        color: root.barColor
      }

      Repeater {
        model: root.barSegments

        Text {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.text
          color: modelData.dim ? root.barInactiveColor : root.barColor
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          font.weight: Font.Medium
          renderType: Text.NativeRendering
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Item {
        width: button.width
        height: Style.bar.iconSlot

        PerfexIcon {
          anchors.centerIn: parent
          iconSize: Style.font.icon
          color: root.barColor
        }
      }

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 2 ? button.fontSize * 0.9 : button.fontSize
          color: root.barColor
        }
      }
    }
  }

  // ---- detail panel (shape contract for the bar's popout routing)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { openPanel() }
  function close() { closePanel() }
  function toggle() { togglePanel() }

  function openPanel() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function closePanel() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  onBarChanged: injectPanel()
}
