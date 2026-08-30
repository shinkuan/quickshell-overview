import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/functions"
import "../../services"

Item { // Window
    id: root
    property var toplevel
    property var windowData
    property var monitorData
    property var scale
    property var availableWorkspaceWidth
    property var availableWorkspaceHeight
    property bool restrictToWorkspace: true
    // Geometry of the monitor this window actually lives on (windowData.monitor
    // comes from `hyprctl clients`, so it is correct even when the window sits on
    // a different monitor than the overview widget).
    property var monitorGeometry: HyprlandData.monitorGeometries.find(m => m.id == (windowData?.monitor ?? -1))
    property real monitorX: monitorGeometry?.x ?? 0
    property real monitorY: monitorGeometry?.y ?? 0

    // Window position relative to its own monitor's origin, in logical pixels.
    // The workspace cell represents the whole monitor, so no reserved-area offset.
    // Fullscreen windows sit exactly at the monitor origin (`at` == monitor pos),
    // so this can be 0 or slightly negative — clamp, never wrap.
    property real relX: (windowData?.at?.[0] ?? 0) - monitorX
    property real relY: (windowData?.at?.[1] ?? 0) - monitorY

    property real xOffset: 0
    property real yOffset: 0
    property int widgetMonitorId: 0
    
    property var targetWindowWidth: (windowData?.size?.[0] ?? 100) * scale
    property var targetWindowHeight: (windowData?.size?.[1] ?? 100) * scale
    property real clampedWidth: Math.min(targetWindowWidth, availableWorkspaceWidth)
    property real clampedHeight: Math.min(targetWindowHeight, availableWorkspaceHeight)

    // Keep the preview inside its workspace cell.
    property real initX: Math.max(Math.min(relX * root.scale, availableWorkspaceWidth - clampedWidth), 0) + xOffset
    property real initY: Math.max(Math.min(relY * root.scale, availableWorkspaceHeight - clampedHeight), 0) + yOffset
    property bool hovered: false
    property bool pressed: false

    property var iconToWindowRatio: 0.25
    property var xwaylandIndicatorToIconRatio: 0.35
    property var iconToWindowRatioCompact: 0.45
    property var entry: DesktopEntries.heuristicLookup(windowData?.class)
    property var iconPath: Quickshell.iconPath(entry?.icon ?? windowData?.class ?? "application-x-executable", "image-missing")
    property bool compactMode: Appearance.font.pixelSize.smaller * 4 > targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > targetWindowWidth

    property bool indicateXWayland: windowData?.xwayland ?? false
    
    x: initX
    y: initY
    width: clampedWidth
    height: clampedHeight
    opacity: 1

    Behavior on x {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding * root.scale
        clip: true
        color: "transparent"

        ScreencopyView {
            id: windowPreview
            anchors.fill: parent
            captureSource: (GlobalStates.overviewOpen && root.toplevel) ? root.toplevel : null
            live: true
        }

        MultiEffect {
            anchors.fill: windowPreview
            source: windowPreview
            blurEnabled: Config.options.overview.blur_strength > 0
            blurMax: Config.options.overview.blur_strength
            blur: 1.0
            visible: Config.options.overview.blur_strength > 0
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding * root.scale
            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) : 
                hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) : 
                ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.color : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
            border.width : 1
        }

        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Appearance.font.pixelSize.smaller * 0.5

            Image {
                id: windowIcon
                property var iconSize: {
                    return Math.min(targetWindowWidth, targetWindowHeight) * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio) / (root.monitorData?.scale ?? 1);
                }
                Layout.alignment: Qt.AlignHCenter
                source: root.iconPath
                width: iconSize
                height: iconSize
                sourceSize: Qt.size(iconSize, iconSize)

                Behavior on width {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }
}
