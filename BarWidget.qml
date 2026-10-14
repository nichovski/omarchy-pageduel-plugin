import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Total current visitors across every PageDuel site the configured API key
// can read, refreshed on a timer via fetch.sh -> GET /api/v1/live. Click
// opens a popup with the per-site breakdown.
BarWidget {
  id: root
  moduleName: "nichovski.pageduel-live-visitors"

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") || "") + "/.config") + "/omarchy"
  readonly property string credentialsFile: configDir + "/pageduel/credentials.env"
  readonly property string outputFile: configDir + "/pageduel/live_visitors.json"
  readonly property string fetchScript: configDir + "/plugins/nichovski.pageduel-live-visitors/fetch.sh"

  // 60s default keeps a poller inside the Starter plan's daily API budget
  // (docs/api-v1.md: 30s exceeds it, 60s+ fits both plans).
  readonly property int pollIntervalSeconds: Math.max(30, setting("pollIntervalSeconds", 60))

  property bool hasCredentials: false
  property bool hasData: false
  property int totalVisitors: 0
  property var sites: []
  property string errorMessage: ""
  property real retryAt: 0

  readonly property real pollInterval: {
    var now = Date.now() / 1000
    if (root.retryAt > now)
      return Math.max(5000, Math.min((root.retryAt - now) * 1000, 3600000))
    return root.pollIntervalSeconds * 1000
  }

  property bool popupOpen: false
  function close() { popupOpen = false }

  visible: hasCredentials
  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  FileView {
    id: credFile
    path: root.credentialsFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.hasCredentials = String(text() || "").length > 0
      if (root.hasCredentials) fetchTimer.restart()
    }
    onLoadFailed: root.hasCredentials = false
    onFileChanged: reload()
  }

  function parseLiveVisitors(content) {
    if (!content || content.length === 0) return
    try {
      var data = JSON.parse(content)
      root.errorMessage = data.error || ""
      root.retryAt = Number(data.retry_at || 0)
      if (data.visitors !== undefined) {
        root.totalVisitors = data.visitors || 0
        root.sites = data.sites || []
        root.hasData = true
      }
    } catch (e) {
      // Ignore parse errors — keep showing the last good state.
    }
  }

  FileView {
    id: outputFile
    path: root.outputFile
    watchChanges: true
    printErrors: false
    onLoaded: root.parseLiveVisitors(String(text() || ""))
    onFileChanged: reload()
  }

  Timer {
    id: fetchTimer
    interval: 100
    repeat: false
    onTriggered: fetchProcess.running = true
  }

  Timer {
    id: pollTimer
    interval: root.pollInterval
    repeat: true
    running: root.hasCredentials
    // NOTE: intentionally NOT triggeredOnStart, matching the Spotify widget —
    // the initial fetch is done by fetchTimer when credentials load.
    // restart() after each fetch must only re-arm the interval.
    onTriggered: fetchProcess.running = true
  }

  Process {
    id: fetchProcess
    command: ["bash", root.fetchScript]
    running: false
    onRunningChanged: if (!running) pollTimer.restart()
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{f0c0}"
      color: root.errorMessage !== "" ? Color.urgent : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical
      text: root.hasData ? String(root.totalVisitors) : "…"
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, root.errorMessage !== "" ? root.errorMessage : "PageDuel — live visitors")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: root.hasData ? (root.totalVisitors + " visitor" + (root.totalVisitors === 1 ? "" : "s") + " right now") : "PageDuel Live Visitors"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.hasData && root.sites.length > 0

        Repeater {
          model: root.sites

          Row {
            required property var modelData
            width: column.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: modelData.domain || modelData.name || ""
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width - countLabel.implicitWidth - Style.space(8)
            }

            Text {
              id: countLabel
              textFormat: Text.PlainText
              text: String(modelData.visitors || 0)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: root.hasData && root.sites.length === 0 ? "No sites on this API key" : ""
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        visible: text !== ""
      }

      Text {
        textFormat: Text.PlainText
        text: root.errorMessage
        color: Color.urgent
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        width: parent.width
        wrapMode: Text.WordWrap
        visible: text !== ""
      }
    }
  }
}
