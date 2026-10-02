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
  readonly property real iconPx: Math.max(10, Math.round(barSize * 0.78))
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

    // One item per ego so each name can be hovered on its own. Hovering
    // outlines that ego's windows - the quickest way to see which tiles on a
    // mixed workspace belong to whom.
    Row {
      id: labelRow
      visible: !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Repeater {
        model: root.hereEgos
        Row {
          spacing: 0
          Text {
            text: index === 0 ? "" : "·"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          // The hit area is the whole card - full bar height and padded either
          // side. The glyph box alone is a few pixels tall and nearly
          // impossible to hit while looking away at the windows.
          Text {
            text: modelData.name
            color: hover.containsMouse && root.bar ? root.bar.urgent : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            height: root.barSize
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(2)
            rightPadding: Style.space(2)
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.run([root.omaego, "highlight", modelData.slug])
              onExited: root.run([root.omaego, "highlight", "off"])
              onClicked: root.toggle()
            }
          }
        }
      }
    }
  }
  MouseArea {
    id: button
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.toggle()
  }

  // One column per ego, side by side: its browser, its web apps, the hosts
  // that always open in it. The last column makes a new ego. Rules that name
  // no ego (Zoom rewrites and the like) sit underneath, across the panel.
  //
  // Hover is one root property rather than per-row containsMouse, the same
  // contract the first-party panels keep: exactly one highlight on screen.
  property string hoverKey: ""
  readonly property real colWidth: Style.space(220)
  readonly property real colGap: Style.space(10)
  readonly property var looseRules: model.looseRules || []

  function act(args) { run(args); close(); later() }
  function bare(pattern) { return String(pattern).replace(/^https?:\/\//, "") }

  // A hoverable, clickable row. `key` must be unique across the panel.
  component Hit: CursorSurface {
    id: hit
    property string key: ""
    signal activated()
    signal entered()
    signal exited()
    foreground: root.fg
    hasCursor: root.hoverKey === key
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.hoverKey = hit.key; hit.entered() }
      onExited: { if (root.hoverKey === hit.key) root.hoverKey = ""; hit.exited() }
      onClicked: hit.activated()
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  // "+ Add app" and friends: quiet until hovered.
  component AddRow: Hit {
    id: add
    property string label: ""
    width: parent ? parent.width : 0
    implicitHeight: addText.implicitHeight + Style.space(8)
    Caption {
      id: addText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "+  " + add.label
      color: add.hasCursor ? root.fg : root.dim
    }
  }

  component RuleRow: Hit {
    id: rr
    property var rule
    width: parent ? parent.width : 0
    implicitHeight: Math.max(ruleText.implicitHeight, rmBtn.height) + Style.space(4)
    Caption {
      id: ruleText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: rmBtn.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: root.bare(rr.rule.pattern) + (rr.rule.app ? "  · app" : "")
      color: rr.hasCursor ? root.fg : root.dim
      elide: Text.ElideMiddle
    }
    // Shown on hover only, and only the ✕ deletes: a stray click on the
    // row must not lose a rule.
    Caption {
      id: rmBtn
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: "✕"
      opacity: rr.hasCursor ? 1 : 0
      color: root.bar ? root.bar.urgent : root.fg
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.act([root.omaego, "rule", "rm", rr.rule.pattern])
      }
    }
  }

  KeyboardPanel {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(body.implicitWidth + padding * 2)
    contentHeight: fittedContentHeight(body.implicitHeight)

    Column {
      id: body
      spacing: Style.space(10)

      // RowLayout so every column stretches to the tallest one.
      RowLayout {
        id: columns
        spacing: root.colGap

        Repeater {
          model: root.egos

          BorderSurface {
            id: egoCard
            readonly property var ego: modelData
            Layout.preferredWidth: root.colWidth
            Layout.fillHeight: true
            implicitHeight: egoCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            // Egos on this desktop get the selected tint: the "selected" border
            // token alone draws nothing in most themes.
            color: ego.here ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
            borderSpec: Border.controlSpec("normal", root.fg, Color.accent)

            Column {
              id: egoCol
              x: Style.space(8); y: Style.space(8)
              width: parent.width - Style.space(16)
              spacing: Style.space(2)

              // The ego itself: click opens its browser on this desktop.
              Hit {
                key: "ego:" + egoCard.ego.slug
                width: parent.width
                implicitHeight: head.implicitHeight + Style.space(10)
                onActivated: root.act([root.omaego, "launch", egoCard.ego.slug])
                onEntered: if (egoCard.ego.here) root.run([root.omaego, "highlight", egoCard.ego.slug])
                onExited: if (egoCard.ego.here) root.run([root.omaego, "highlight", "off"])

                Column {
                  id: head
                  x: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(12)
                  spacing: Style.space(1)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: egoCard.ego.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Row {
                    spacing: Style.space(5)
                    Rectangle {
                      width: Style.space(6); height: width; radius: width / 2
                      anchors.verticalCenter: parent.verticalCenter
                      color: egoCard.ego.here ? Color.accent : "transparent"
                      border.width: egoCard.ego.here ? 0 : 1
                      border.color: root.dim
                    }
                    Caption {
                      text: (egoCard.ego.here ? "on this desktop" : "open here")
                            + (egoCard.ego.default ? "  ·  fallback" : "")
                    }
                  }
                }
              }

              Item { width: 1; height: Style.space(4) }
              PanelSectionHeader {
                x: Style.space(6)
                text: "APPS"; foreground: root.fg; fontFamily: root.fontFamily
              }

              Repeater {
                model: egoCard.ego.apps
                Hit {
                  key: "app:" + egoCard.ego.slug + ":" + modelData.desktop
                  width: egoCol.width
                  implicitHeight: Math.max(appIcon.height, appName.implicitHeight) + Style.space(8)
                  // The stored Exec already names the ego, so launching it
                  // here cannot land the app in the wrong identity.
                  onActivated: root.act(["sh", "-c", modelData.exec])
                  Image {
                    id: appIcon
                    x: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.font.iconLarge; height: width
                    sourceSize.width: width * 2; sourceSize.height: height * 2
                    source: modelData.iconPath ? "file://" + modelData.iconPath : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                  }
                  Text {
                    id: appName
                    anchors.left: appIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.short || modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                }
              }
              AddRow {
                key: "addapp:" + egoCard.ego.slug
                label: "Add app"
                onActivated: root.act([root.omaego, "app", "pick", egoCard.ego.slug])
              }

              Item { width: 1; height: Style.space(4) }
              PanelSectionHeader {
                x: Style.space(6)
                text: "ALWAYS OPENS HERE"; foreground: root.fg; fontFamily: root.fontFamily
              }
              Repeater {
                model: egoCard.ego.rules
                RuleRow { key: "rule:" + modelData.pattern; rule: modelData }
              }
              AddRow {
                key: "addrule:" + egoCard.ego.slug
                label: "Add rule"
                onActivated: root.act([root.omaego, "rule", "new", egoCard.ego.slug])
              }
            }
          }
        }

        // New ego: a hollow column, so it reads as a slot rather than an ego.
        Hit {
          id: newCard
          key: "newego"
          Layout.preferredWidth: root.colWidth * 0.6
          Layout.fillHeight: true
          implicitHeight: newCol.implicitHeight + Style.space(16)
          bordered: true
          onActivated: root.act([root.omaego, "new"])
          Column {
            id: newCol
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "+"
              color: newCard.hasCursor ? root.fg : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            Caption {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "New ego"
              color: newCard.hasCursor ? root.fg : root.dim
            }
          }
        }
      }

      Column {
        visible: root.looseRules.length > 0
        width: columns.width
        spacing: Style.space(2)
        PanelSeparator { width: parent.width }
        PanelSectionHeader {
          x: Style.space(6)
          text: "ANY EGO · REWRITES"; foreground: root.fg; fontFamily: root.fontFamily
        }
        Repeater {
          model: root.looseRules
          RuleRow { key: "rule:" + modelData.pattern; rule: modelData; width: Math.min(columns.width, Style.space(420)) }
        }
      }
    }
  }
}
