import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Which ego owns the workspace you are looking at.
//
// There is deliberately no "active ego" here. An ego is not a mode you switch
// the system into - it is an identity that happens to have windows on a given
// workspace. Links always resolve on the workspace they were clicked from, so
// the workspace is the only unit worth displaying. A workspace showing two egos
// is worth noticing, which is why `mixed` is drawn in the urgent colour.
BarWidget {
  id: root
  moduleName: "io.github.lcorneliussen.omaego"

  readonly property string omaego: setting("command", "omaego")
  readonly property bool showWhenEmpty: setting("showWhenEmpty", false) === true
  readonly property int pollSeconds: Math.max(1, setting("pollSeconds", 3))

  property string state: "empty"      // empty | single | mixed
  property var egos: []
  property var withBrowser: []
  property string fallback: ""

  readonly property string label: state === "empty" ? "—" : egos.join(" | ")
  readonly property bool webappOnly: state !== "empty" && withBrowser.length === 0

  visible: state !== "empty" || showWhenEmpty
  implicitWidth: vertical ? barSize : text.implicitWidth + 14
  implicitHeight: vertical ? text.implicitHeight + 14 : barSize

  function refresh() { if (!probe.running) probe.running = true }

  Process {
    id: probe
    command: [root.omaego, "space", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "{}"))
          root.state = d.state || "empty"
          root.egos = d.egos || []
          root.withBrowser = d.withBrowser || []
          root.fallback = d.fallback || ""
        } catch (e) {
          root.state = "empty"; root.egos = []
        }
      }
    }
  }

  // Workspace changes are the event that actually matters; the timer only
  // catches windows opening and closing on the workspace already shown.
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.refresh() }
  }

  Timer {
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    font.family: root.bar ? root.bar.fontFamily : ""
    font.pixelSize: Style.bar.fontSize !== undefined ? Style.bar.fontSize : 13
    color: root.state === "mixed" && root.bar ? root.bar.urgent
         : root.bar ? root.bar.foreground : "white"
    opacity: root.state === "empty" ? 0.45 : (root.webappOnly ? 0.75 : 1.0)
    rotation: root.vertical ? 90 : 0
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onEntered: if (root.bar) root.bar.showTooltip(root, tooltip())
    onExited: if (root.bar) root.bar.hideTooltip(root)
    // Opening a browser here is the useful action: on an empty workspace it
    // raises the ego picker, on a populated one it reuses what is already here.
    onClicked: opener.running = true
  }

  Process { id: opener; command: [root.omaego] }

  function tooltip() {
    if (state === "empty")
      return "No ego on this workspace.\nA link would ask; fallback is " + fallback + "."
    if (state === "mixed")
      return "This workspace has more than one ego:\n  " + egos.join("\n  ")
           + "\nA link opens in whichever one it matches."
    if (webappOnly)
      return egos[0] + " — web app only.\nA link opens a new browser window here."
    return egos[0] + " owns this workspace."
  }
}
