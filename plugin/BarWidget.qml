import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// The ego of the current workspace, and a panel to act on all of them.
//
// There is deliberately no "active ego": an ego is an identity that has windows
// on a workspace, not a mode the system is in. The label therefore reports the
// workspace, and turns urgent when a workspace holds more than one ego.
//
// Text entry goes through walker (`omaego app pick`, `omaego rule new`) rather
// than QML dialogs: the picker already exists, is themed, and keeps this file
// small enough to survive a shell API change.
// NOTE: this file must be called BarWidget.qml. A third-party bar widget loaded
// under any other name fails with Qt's "File name case mismatch", which points
// nowhere near the real cause. First-party widgets (dropbox, clock) use other
// names because they live inside the shell's own qs module tree.
Panel {
  id: root
  moduleName: "io.github.lcorneliussen.omaego"
  ipcTarget: "io.github.lcorneliussen.omaego"

  readonly property string omaego: setting("command", "omaego")
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true
  readonly property int pollSeconds: Math.max(1, setting("pollSeconds", 3))

  property var model: ({ egos: [], rules: [] })
  readonly property var egos: model.egos || []
  readonly property var rules: model.rules || []
  readonly property var hereEgos: egos.filter(function (e) { return e.here })
  readonly property bool mixed: hereEgos.length > 1
  readonly property string label: hereEgos.map(function (e) { return e.name }).join(" · ")
  readonly property real iconPx: Math.max(10, Math.round(barSize * 0.52))
  readonly property real ringPx: Math.max(1, Math.round(iconPx * 0.1))
  // nf-md-account (U+F0004), outside the BMP so it needs a surrogate pair
  readonly property string faceGlyph: "\udb80\udc04"
  readonly property string iconFont: setting("iconFont", "JetBrainsMono Nerd Font")

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Always visible by default: the widget is the only way into the panel, and
  // an empty workspace is exactly when you want it (to start an ego here).
  // Hiding it then made the widget look broken.
  visible: hereEgos.length > 0 || !hideWhenEmpty
  implicitWidth: vertical ? barSize : content.implicitWidth + Style.space(14)
  implicitHeight: vertical ? content.implicitHeight + Style.space(14) : barSize
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function refresh() { if (!probe.running) probe.running = true }
  function run(args) { runner.command = args; runner.running = true }
  function later() { reloadTimer.restart() }

  Process {
    id: probe
    command: [root.omaego, "panel"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.model = JSON.parse(String(text || "{}")) } catch (e) {}
      }
    }
  }
  Process { id: runner }
  Timer { id: reloadTimer; interval: 1200; onTriggered: root.refresh() }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.refresh() }
  }
  Timer {
    interval: root.pollSeconds * 1000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.label === "" ? 0 : Style.space(5)

    // Two-faced mark: half light, half dark, drawn rather than taken from a
    // glyph because no Nerd Font carries one. The ring keeps the dark half
    // readable on a dark bar, where a literal black fill would disappear.
    // Jekyll and Hyde: one person, split straight down the middle. No circle.
    // The dark half is a dimmed foreground rather than literal black - black has
    // no edge against a dark bar and the half simply disappears.
    Item {
      id: mark
      width: root.iconPx
      height: root.iconPx
      anchors.verticalCenter: parent.verticalCenter
      opacity: root.hereEgos.length ? 1.0 : 0.55

      Item {
        width: parent.width / 2
        height: parent.height
        clip: true
        Text {
          width: mark.width
          height: mark.height
          text: root.faceGlyph
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: root.iconPx
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
      Item {
        x: parent.width / 2
        width: parent.width / 2
        height: parent.height
        clip: true
        Text {
          x: -mark.width / 2
          width: mark.width
          height: mark.height
          text: root.faceGlyph
          color: Qt.darker(root.fg, 2.6)
          font.family: root.iconFont
          font.pixelSize: root.iconPx
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Text {
      id: labelText
      visible: root.label !== "" && !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: root.mixed && root.bar ? root.bar.urgent : root.fg
    }
  }
  MouseArea {
    id: button
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.toggle()
  }

  KeyboardPanel {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(420)
    contentHeight: Math.min(column.implicitHeight + Style.space(24), Style.space(620))

    Column {
      id: column
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader { text: "Egos"; foreground: root.fg; fontFamily: root.fontFamily }

      Repeater {
        model: root.egos
        Column {
          width: column.width
          spacing: Style.space(2)

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              text: modelData.name + (modelData.default ? "  (fallback)" : "")
              color: root.fg; font.family: root.fontFamily
              font.bold: modelData.here
              width: parent.width - Style.space(150)
              elide: Text.ElideRight
              MouseArea {
                anchors.fill: parent
                // Opens this ego's browser on the workspace you are on.
                onClicked: { root.run([root.omaego, "launch", modelData.slug]); root.close() }
              }
            }
            Text {
              text: modelData.here ? "on this desktop" : "elsewhere"
              color: root.dim; font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "  +app"
              color: root.dim; font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              MouseArea {
                anchors.fill: parent
                onClicked: { root.run([root.omaego, "app", "pick", modelData.slug])
                             root.close(); root.later() }
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            leftPadding: Style.space(12)
            Repeater {
              model: modelData.apps
              Text {
                text: "· " + modelData.name
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  anchors.fill: parent
                  // The stored Exec already names the ego, so launching it here
                  // cannot land the app in the wrong identity.
                  onClicked: { root.run(["sh", "-c", modelData.exec]); root.close() }
                }
              }
            }
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "Rules"; foreground: root.fg; fontFamily: root.fontFamily }

      Repeater {
        model: root.rules
        Row {
          width: column.width
          spacing: Style.space(8)
          Text {
            text: modelData.pattern
            color: root.fg; font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width - Style.space(130)
            elide: Text.ElideMiddle
          }
          Text {
            text: (modelData.profile || "this desktop") + (modelData.app ? " · app" : "")
            color: root.dim; font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            text: " ✕"
            color: root.dim; font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              onClicked: { root.run([root.omaego, "rule", "rm", modelData.pattern]); root.later() }
            }
          }
        }
      }

      Text {
        text: "+ add rule"
        color: root.dim; font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        MouseArea {
          anchors.fill: parent
          onClicked: { root.run([root.omaego, "rule", "new"]); root.close(); root.later() }
        }
      }
    }
  }
}
