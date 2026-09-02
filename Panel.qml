import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Perfex Pulse detail popup: a hero with the LIVE/PAUSED/STALE pill and
// the querying switch, the outstanding total, the overdue invoices (click to
// open in the CRM), the optional "paid this month" feed, the display
// switches (the settings UI, since the shell renders none), and a footer.
// PerfexPulse.qml owns the bar label, the data and the network; this panel
// only reads its state and calls back into it. Opening the panel never
// fetches.
Panel {
  id: root
  moduleName: "karamble.perfex-pulse"
  ipcTarget: "karamble.perfex-pulse"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var hw: hostWidget

  readonly property var crm: hw ? hw.crm : null
  readonly property bool querying: hw ? hw.effectiveQuerying : false
  readonly property bool fetching: hw ? hw.fetching : false
  readonly property string error: hw ? hw.error : ""
  readonly property bool needsSetup: hw ? hw.needsSetup : false
  readonly property bool halted: hw ? hw.halted : false
  readonly property int lastUpdated: hw ? hw.lastUpdated : 0
  readonly property var headline: Model.headline(crm)
  readonly property var overdueList: crm && crm.overdue_invoices ? crm.overdue_invoices : []
  readonly property var paid: crm && crm.paid_month ? crm.paid_month : null
  readonly property bool showPaid: hw ? hw.paidThisMonth : false
  readonly property string crmUrl: hw ? hw.crmUrl : ""

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(contentForeground, 1.5)
  readonly property color faintForeground: Qt.darker(contentForeground, 2.0)
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent

  readonly property string metaText: {
    if (!hw) return ""
    if (halted) return "Key rejected - set up again"
    if (needsSetup) return "No working key - set up"
    if (!querying) return "Querying off" + (lastUpdated ? " · last data " + Model.fmtDayTime(lastUpdated) : "")
    if (error !== "" && crm) return Model.errorSentence(error, hw.errorDetail, hw.errorHttp, hw.host) + " · showing " + Model.fmtDayTime(lastUpdated) + " numbers"
    if (error !== "") return Model.errorSentence(error, hw.errorDetail, hw.errorHttp, hw.host)
    if (fetching) return "Fetching…"
    var parts = []
    if (lastUpdated) parts.push("Updated " + Model.fmtDayTime(lastUpdated))
    if (hw.nextPollAt > hw.now) parts.push("next poll in " + Model.fmtCountdown(hw.nextPollAt - hw.now))
    return parts.length ? parts.join(" · ") : "Waiting for first poll"
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function money(amount, symbol) {
    return Model.money(amount, symbol, true)
  }

  function openInvoice(id) {
    if (hw) hw.openInvoice(id)
    root.close()
  }

  function openCrm() {
    if (hw) hw.openCrm()
    root.close()
  }

  // Keeps the countdown honest while the panel is open; reads memory only.
  Timer {
    interval: 1000
    running: root.opened && root.querying
    repeat: true
    onTriggered: if (root.hw) root.hw.now = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.hw) return
        if (text === "r") root.hw.refresh(true)
        else if (text === "q") root.hw.setQuerying(!root.hw.effectiveQuerying)
        else if (text === "o") root.openCrm()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: parent.width
          spacing: Style.space(10)

          // ---- hero: pill, meta, the switch
          PanelHero {
            id: hero
            width: parent.width
            iconComponent: Component {
              PerfexIcon {
                iconSize: Style.font.display
                monochrome: false
              }
            }
            title: "Perfex CRM"
            detail: root.hw ? Model.pill(root.hw.viewState) : ""
            meta: root.metaText
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            trailingControl: Component {
              ToggleSwitch {
                id: querySwitch
                checked: root.querying
                foreground: root.contentForeground
                onToggled: if (root.hw) root.hw.setQuerying(!root.hw.effectiveQuerying)

                PanelToolTip {
                  visible: querySwitch.containsMouse
                  text: root.querying ? "Pause CRM polling - zero requests while off" : "Resume polling"
                }
              }
            }
          }

          Text {
            visible: root.error !== "" && root.error !== "off" && root.crm !== null && root.querying
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.hw ? Model.errorSentence(root.error, root.hw.errorDetail, root.hw.errorHttp, root.hw.host) : ""
            color: root.urgentColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.crm !== null && root.crm.approx === true
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Some balances are approximate - " + (root.crm ? Model.num(root.crm.skipped_gets) : 0) + " invoice lookups skipped"
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { width: parent.width; foreground: root.contentForeground }

          // ---- outstanding
          Column {
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader { text: "OUTSTANDING"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.headline ? root.money(root.headline.outstanding, root.headline.symbol) : "—"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: 44
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: 22
              font.weight: Font.DemiBold
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.lastUpdated > 0
              text: "as of " + Model.fmtDayTime(root.lastUpdated)
              color: root.faintForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: !root.headline
              text: root.querying ? "waiting for first poll" : "paused before first poll"
              color: root.faintForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.crm && root.crm.currencies && root.crm.currencies.length > 1 ? root.crm.currencies.slice(1) : []

              Text {
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                text: "also " + root.money(modelData.outstanding, modelData.symbol) + " " + (modelData.name || "")
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Repeater {
              model: root.headline ? [
                { label: "Overdue", bucket: root.headline.overdue, urgent: true },
                { label: "Unpaid", bucket: root.headline.unpaid, urgent: false },
                { label: "Partially paid", bucket: root.headline.partial, urgent: false }
              ] : []

              Item {
                id: bucketRow
                required property var modelData
                width: content.width
                height: Style.space(20)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: bucketRow.modelData.label
                  color: root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.num(bucketRow.modelData.bucket.count) + " · " + root.money(bucketRow.modelData.bucket.total, root.headline.symbol)
                  color: bucketRow.modelData.urgent && Model.num(bucketRow.modelData.bucket.count) > 0 ? root.urgentColor : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.contentForeground; visible: !root.needsSetup }

          // ---- overdue invoices
          Column {
            visible: !root.needsSetup
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "OVERDUE" + (root.overdueList.length > 0 ? " · " + root.overdueList.length : "")
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Text {
              visible: root.overdueList.length === 0
              text: root.crm ? "Nothing overdue" : "—"
              color: root.faintForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.overdueList

              Item {
                id: overdueRow
                required property var modelData
                width: content.width
                height: Style.space(22)

                CursorSurface {
                  anchors.fill: parent
                  anchors.leftMargin: -Style.space(4)
                  anchors.rightMargin: -Style.space(4)
                  hasCursor: rowMouse.containsMouse
                  foreground: root.contentForeground
                }

                Text {
                  id: overdueNumber
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(overdueRow.modelData.number || "")
                  textFormat: Text.PlainText
                  color: root.faintForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: overdueDays
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.num(overdueRow.modelData.days_overdue) + "d"
                  color: root.urgentColor
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: overdueBalance
                  anchors.right: overdueDays.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.money(overdueRow.modelData.balance, overdueRow.modelData.symbol)
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.left: overdueNumber.right
                  anchors.right: overdueBalance.left
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(overdueRow.modelData.client || "")
                  // Remote-controlled strings: never let AutoText read markup.
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openInvoice(overdueRow.modelData.id)
                }
              }
            }
          }

          // ---- paid this month (optional)
          PanelSeparator { width: parent.width; foreground: root.contentForeground; visible: root.showPaid && !root.needsSetup }

          Column {
            visible: root.showPaid && !root.needsSetup
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader { text: "PAID THIS MONTH"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }

            Text {
              text: root.paid ? root.money(root.paid.total, root.paid.symbol) + " · " + Model.num(root.paid.count) + " payment" + (Model.num(root.paid.count) === 1 ? "" : "s") : "—"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.paid && root.paid.rows ? root.paid.rows : []

              Item {
                id: paidRow
                required property var modelData
                width: content.width
                height: Style.space(20)

                Text {
                  id: paidDate
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(paidRow.modelData.date || "")
                  color: root.faintForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: paidAmount
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.money(paidRow.modelData.amount, root.paid ? root.paid.symbol : "")
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.left: paidDate.right
                  anchors.right: paidAmount.left
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "invoice #" + Model.num(paidRow.modelData.invoiceid) + (paidRow.modelData.mode ? " · " + paidRow.modelData.mode : "")
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.dimForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openInvoice(paidRow.modelData.invoiceid)
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.contentForeground }

          // ---- display switches: the settings UI
          Column {
            width: parent.width
            spacing: Style.space(2)

            PanelSectionHeader { text: "DISPLAY"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }

            Toggle {
              width: parent.width
              label: "Query the CRM"
              description: root.querying ? "Polling every " + (root.hw ? Math.round(root.hw.pollSeconds / 60) : 10) + " min" : "Off - no requests are made"
              checked: root.querying
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.hw) root.hw.setQuerying(!root.hw.effectiveQuerying)
            }

            Toggle {
              width: parent.width
              label: "Show amount in bar"
              checked: root.hw ? root.hw.showAmount : true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.hw) root.hw.persistSettings({ showAmount: !root.hw.showAmount })
            }

            Toggle {
              width: parent.width
              label: "Show cents in bar"
              checked: root.hw ? root.hw.showCents : false
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.hw) root.hw.persistSettings({ showCents: !root.hw.showCents })
            }

            Toggle {
              width: parent.width
              label: "Paid this month"
              description: "+1 request per poll"
              checked: root.showPaid
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.hw) root.hw.persistSettings({ paidThisMonth: !root.hw.paidThisMonth })
            }

            Toggle {
              width: parent.width
              label: "Notify on new overdue"
              checked: root.hw ? root.hw.notifyOverdue : false
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.hw) root.hw.persistSettings({ notifyOverdue: !root.hw.notifyOverdue })
            }
          }

          // ---- footer
          Item {
            width: parent.width
            height: Style.space(28)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Open CRM ↗"
              color: crmMouse.containsMouse ? Style.hoverStateColor(root.contentForeground, Color.accent) : root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                id: crmMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCrm()
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.crm !== null && root.crm.meta !== undefined
                text: root.crm && root.crm.meta ? "last run: " + Model.num(root.crm.meta.calls) + " calls, " + (Model.num(root.crm.meta.ms) / 1000).toFixed(1) + " s" : ""
                color: root.faintForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh now (r)"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: root.querying && !root.fetching
                onClicked: if (root.hw) root.hw.refresh(true)
              }

              PanelActionButton {
                iconText: "󰌆"
                tooltipText: "Set up / rotate the API key"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: { if (root.hw) root.hw.runSetup(); root.close() }
              }
            }
          }
        }
      }
    }
  }
}

