import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// omaplay in the Omarchy bar: a bar button with the title, and a keyboard-operable mini player.
//
// It talks to omaplay only through MPRIS (the player whose DesktopEntry is "omaplay"). It never
// decodes or renders anything and never touches other players, including the official VLC.
Panel {
  id: root
  moduleName: "io.github.t3-venture-labs-limited.omaplay"
  ipcTarget: "omaplay"
  // The stock open/close/toggle IPC is replaced by the actions below.
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ------------------------------------------------------------------ the player
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    for (var i = 0; i < players.length; i++)
      if (players[i] && String(players[i].desktopEntry) === "omaplay") return players[i]
    return null
  }
  readonly property bool present: player !== null
  readonly property bool playing: present && !!player.isPlaying

  // Titles and URLs come from files and streams: untrusted. Everything below is shown as plain text.
  // Untagged files have no title over MPRIS, only a URL: show the file name then.
  function fileName(url) {
    var path = String(url || "").split("?")[0]
    var name = path.substring(path.lastIndexOf("/") + 1)
    try { return decodeURIComponent(name) } catch (e) { return name }
  }
  readonly property string title: {
    if (!present) return ""
    var t = String(player.trackTitle || "")
    if (t !== "") return t
    return player.metadata ? fileName(player.metadata["xesam:url"]) : ""
  }
  readonly property string artist: present ? String(player.trackArtist || "") : ""
  readonly property string heading: title !== "" ? title : (present ? strings.t("panel.nothingPlaying") : strings.t("panel.notRunning"))

  // Artwork only from local files; a remote URL would make the shell fetch it.
  readonly property string artUrl: {
    var u = present ? String(player.trackArtUrl || "") : ""
    return u.indexOf("file://") === 0 ? u : ""
  }

  readonly property real length: present && player.lengthSupported ? Math.max(0, player.length) : 0
  readonly property real position: present && player.positionSupported ? Math.max(0, player.position) : 0
  readonly property real volume: present && player.volumeSupported ? Math.max(0, Math.min(1, player.volume)) : 0

  function formatTime(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
    var two = function(n) { return (n < 10 ? "0" : "") + n }
    return h > 0 ? h + ":" + two(m) + ":" + two(r) : m + ":" + two(r)
  }

  // ------------------------------------------------------------------ actions
  function launch() { Quickshell.execDetached(["omaplay"]) }
  function playPause() { if (present && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (present && player.canGoNext) player.next() }
  function previous() { if (present && player.canGoPrevious) player.previous() }
  function toggleFullscreen() { if (present && player.canSetFullscreen) player.fullscreen = !player.fullscreen }
  function showPlayer() { if (present && player.canRaise) player.raise(); else if (!present) launch() }
  function setVolume(v) { if (present && player.volumeSupported) player.volume = Math.max(0, Math.min(1, v)) }
  // A step is 5%, the same as the keybinding targets and the arrow keys in the panel.
  function stepVolume(direction) { setVolume(volume + direction * 0.05) }
  function seekTo(seconds) {
    if (present && player.canSeek && length > 0) player.position = Math.max(0, Math.min(length, seconds))
  }
  // Relative seeks use MPRIS Seek, which the player measures from its real position. Reading `position`
  // here would be stale (it is only refreshed while the panel is open) and make jumps over- or undershoot.
  function seekBy(delta) {
    if (!present || !player.canSeek)
      return
    player.seek(delta)
    player.positionChanged()
  }

  // The position is not pushed by MPRIS; ask for it while the panel is open.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.present
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // ------------------------------------------------------------------ keybinding targets
  // omarchy-shell omaplay <action>   (add -q in a keybinding to keep it silent)
  ShellIpc {
    target: root.ipcTarget
    function togglePanel(): void { root.toggle() }
    // One line of plain text: what the widget currently shows. Useful for scripts and tests.
    function status(): string {
      if (!root.present) return "not running"
      return (root.playing ? "playing" : "paused") + ": " + root.heading
        + (root.artist !== "" ? " - " + root.artist : "")
        + " [" + root.formatTime(root.position) + "/" + root.formatTime(root.length) + "]"
    }
    function playPause(): string { if (!root.present) return "unavailable"; root.playPause(); return "ok" }
    function next(): string { if (!root.present) return "unavailable"; root.next(); return "ok" }
    function previous(): string { if (!root.present) return "unavailable"; root.previous(); return "ok" }
    function volumeUp(): string { if (!root.present) return "unavailable"; root.stepVolume(1); return "ok" }
    function panelState(): string { return root.opened ? "open" : "closed" }
    // Relative seek in seconds, e.g. `omarchy-shell omaplay seek -10`.
    function seek(seconds: int): string { if (!root.present) return "unavailable"; root.seekBy(seconds); return "ok" }
    function volumeDown(): string { if (!root.present) return "unavailable"; root.stepVolume(-1); return "ok" }
  }

  // ------------------------------------------------------------------ the bar button
  readonly property int maxTitleWidth: Number(setting("maxTitleWidth", 180))
  readonly property bool hideWhenNotRunning: String(setting("hideWhenNotRunning", "Off")) === "On"
  // Elide to the configured width so a long title never pushes other widgets around.
  TextMetrics {
    id: titleMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    elideWidth: Math.max(1, root.maxTitleWidth)
    text: root.title
  }
  readonly property string barLabel: maxTitleWidth > 0 && title !== "" ? titleMetrics.elidedText : ""

  visible: present || !hideWhenNotRunning
  readonly property bool showLabel: barLabel !== "" && !(bar && bar.vertical)
  implicitWidth: visible ? button.implicitWidth + (showLabel ? titleLabel.implicitWidth + Style.space(4) : 0) : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    bar: root.bar
    // 󰐊 play, 󰏤 pause, 󰐍 idle (a play mark in a ring, like the omaplay icon)
    text: root.playing ? "󰏤" : (root.present ? "󰐊" : "󰐍")
    tooltipText: root.present ? root.heading + (root.artist !== "" ? " — " + root.artist : "") : strings.t("widget.tooltip.idle")
    foreground: root.playing ? root.barForeground : Qt.darker(root.barForeground, 1.5)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.playPause()
      else root.toggle()
    }
  }

  // The title sits beside the icon. It is drawn here rather than through the button so the
  // widget's width includes it and it never overlaps its neighbours.
  Text {
    id: titleLabel
    anchors.left: button.right
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showLabel
    textFormat: Text.PlainText
    text: root.barLabel
    color: root.playing ? root.barForeground : Qt.darker(root.barForeground, 1.5)
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) root.playPause()
        else root.toggle()
      }
    }
  }

  // ------------------------------------------------------------------ the mini player
  // Rows the keyboard cursor can sit on.
  property int row: 1
  readonly property var rows: ["seek", "transport", "volume", "actions"]
  property int transportColumn: 1
  property bool cursorActive: false

  function moveCursor(dx, dy) {
    if (dy !== 0) {
      row = Math.max(0, Math.min(rows.length - 1, row + dy))
      return
    }
    var r = rows[row]
    if (r === "seek") seekBy(dx * 5)
    else if (r === "volume") stepVolume(dx)
    else if (r === "transport") transportColumn = Math.max(0, Math.min(3, transportColumn + dx))
  }

  function activateCursor() {
    var r = rows[row]
    if (r === "transport") {
      if (transportColumn === 0) previous()
      else if (transportColumn === 1) playPause()
      else if (transportColumn === 2) next()
      else toggleFullscreen()
    } else if (r === "actions") {
      showPlayer()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(420))

    content: PanelKeyCatcher {
      id: keys
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: { root.cursorActive = false; root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === " " || t === "k") root.playPause()
        else if (t === "n" || t === "N") root.next()
        else if (t === "p" || t === "P") root.previous()
        else if (t === "o" || t === "O") root.showPlayer()
        else if (t === "f" || t === "F") root.toggleFullscreen()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---- title block
        Row {
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(64)
            height: Style.space(64)
            radius: Style.spacing.labelGap
            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.08)
            visible: root.artUrl !== ""
            Image {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              source: root.artUrl
              sourceSize: Qt.size(Style.space(128), Style.space(128))
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
            }
          }

          Column {
            width: parent.width - (root.artUrl !== "" ? Style.space(74) : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.heading
              elide: Text.ElideRight
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.artist
              visible: text !== ""
              elide: Text.ElideRight
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---- not running
        Button {
          visible: !root.present
          width: parent.width
          foreground: root.barForeground
          text: strings.t("panel.open")
          bordered: true
          onClicked: { root.launch(); root.close() }
        }

        // ---- seek
        Column {
          visible: root.present
          width: parent.width
          spacing: Style.space(2)
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: Math.max(1, root.length)
            value: root.position
            enabled: root.present && root.length > 0
            opacity: root.cursorActive && root.rows[root.row] === "seek" ? 1 : 0.9
            onReleased: function(v) { root.seekTo(v) }
          }
          Row {
            width: parent.width
            Text {
              width: parent.width / 2
              textFormat: Text.PlainText
              text: root.formatTime(root.position)
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width / 2
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: root.length > 0 ? root.formatTime(root.length) : ""
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---- transport
        Row {
          visible: root.present
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)
          Button {
            foreground: root.barForeground
            iconText: "󰒮"
            tooltipText: strings.t("panel.previous")
            enabled: root.present && root.player.canGoPrevious
            hasCursor: root.cursorActive && root.rows[root.row] === "transport" && root.transportColumn === 0
            onClicked: root.previous()
          }
          Button {
            foreground: root.barForeground
            iconText: root.playing ? "󰏤" : "󰐊"
            tooltipText: root.playing ? strings.t("panel.pause") : strings.t("panel.play")
            enabled: root.present && root.player.canTogglePlaying
            hasCursor: root.cursorActive && root.rows[root.row] === "transport" && root.transportColumn === 1
            onClicked: root.playPause()
          }
          Button {
            foreground: root.barForeground
            iconText: "󰒭"
            tooltipText: strings.t("panel.next")
            enabled: root.present && root.player.canGoNext
            hasCursor: root.cursorActive && root.rows[root.row] === "transport" && root.transportColumn === 2
            onClicked: root.next()
          }
          Button {
            foreground: root.barForeground
            iconText: "󰊓"
            tooltipText: strings.t("panel.fullscreen")
            enabled: root.present && root.player.canSetFullscreen
            hasCursor: root.cursorActive && root.rows[root.row] === "transport" && root.transportColumn === 3
            onClicked: root.toggleFullscreen()
          }
        }

        // ---- volume
        Row {
          visible: root.present && root.player.volumeSupported
          width: parent.width
          spacing: Style.space(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰕾"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.icon
          }
          PanelSlider {
            width: parent.width - Style.space(34)
            anchors.verticalCenter: parent.verticalCenter
            bar: root.bar
            minimum: 0
            maximum: 1
            step: 0.05
            value: root.volume
            onMoved: function(v) { root.setVolume(v) }
          }
        }

        // ---- loop / shuffle summary and the show-player action
        Text {
          visible: root.present
          width: parent.width
          textFormat: Text.PlainText
          color: Qt.darker(root.barForeground, 1.4)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          text: {
            if (!root.present) return ""
            var loop = strings.t("panel.loopState." + String(root.player.loopState === MprisLoopState.Track ? "Track"
                                 : root.player.loopState === MprisLoopState.Playlist ? "Playlist" : "None"))
            var shuffle = root.player.shuffle ? strings.t("panel.shuffleOn") : strings.t("panel.shuffleOff")
            return strings.t("panel.loop") + ": " + loop + "   " + strings.t("panel.shuffle") + ": " + shuffle
          }
        }

        Button {
          visible: root.present
          width: parent.width
          foreground: root.barForeground
          text: strings.t("panel.show")
          bordered: true
          hasCursor: root.cursorActive && root.rows[root.row] === "actions"
          onClicked: { root.showPlayer(); root.close() }
        }
      }
    }
  }
}
