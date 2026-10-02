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
  readonly property bool showWhenEmpty: setting("showWhenEmpty", false) === true
  readonly property int pollSeconds: Math.max(1, setting("pollSeconds", 3))

  property var model: ({ egos: [], rules: [] })
  readonly property var egos: model.egos || []
  readonly property var rules: model.rules || []
  readonly property var hereEgos: egos.filter(function (e) { return e.here })
  readonly property bool mixed: hereEgos.length > 1
  readonly property string label: hereEgos.length
    ? hereEgos.map(function (e) { return e.name }).join(" | ") : "—"

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  visible: hereEgos.length > 0 || showWhenEmpty
  implicitWidth: vertical ? barSize : labelText.implicitWidth + Style.space(14)
  implicitHeight: vertical ? labelText.implicitHeight + Style.space(14) : barSize
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

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    font.family: root.fontFamily
    color: root.mixed && root.bar ? root.bar.urgent : root.fg
    opacity: root.hereEgos.length ? 1.0 : 0.45
    rotation: root.vertical ? 90 : 0
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
