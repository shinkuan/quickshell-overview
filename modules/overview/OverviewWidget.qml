import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"
import "."

Item {
    id: root
    required property var panelWindow
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property var toplevels: ToplevelManager.toplevels
    readonly property int workspacesShown: Config.options.overview.rows * Config.options.overview.columns
    readonly property int workspaceGroup: Math.floor((monitor.activeWorkspace?.id - 1) / workspacesShown)
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor.name)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowAddresses: HyprlandData.addresses
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    property var activeActivity: monitorData?.activities?.find(a => a.focused) ?? monitorData?.activities?.[0]
    property var workspacesGrid: activeActivity?.workspaces ?? []
    property int gridRows: workspacesGrid.length
    property int gridCols: workspacesGrid[0]?.length ?? 0

    property real scale: Config.options.overview.scale
    property color activeBorderColor: ColorUtils.transparentize(Appearance.colors.colSecondary, 1.0 - Config.options.overview.opacity)

    property real workspaceImplicitWidth: (monitorData?.transform % 2 === 1) ? 
        ((monitor.height / monitor.scale) * root.scale) :
        ((monitor.width / monitor.scale) * root.scale)
    property real workspaceImplicitHeight: (monitorData?.transform % 2 === 1) ? 
        ((monitor.width / monitor.scale) * root.scale) :
        ((monitor.height / monitor.scale) * root.scale)

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: 250 * monitor.scale
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 5

    property string draggingFromWorkspace: ""
    property string draggingTargetWorkspace: ""

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    property Component windowComponent: OverviewWindow {}
    property list<OverviewWindow> windowWidgets: []

    StyledRectangularShadow {
        target: overviewBackground
        visible: Config.options.overview.shadow
    }
    Rectangle { // Background
        id: overviewBackground
        property real padding: 10
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2
        radius: Appearance.rounding.screenRounding * root.scale + padding
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 1.0 - Config.options.overview.opacity)
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 1.0 - Config.options.overview.opacity)

        ColumnLayout { // Workspaces
            id: workspaceColumnLayout

            z: root.workspaceZ
            anchors.centerIn: parent
            spacing: workspaceSpacing
            Repeater {
                model: root.gridRows
                delegate: RowLayout {
                    id: row
                    property int rowIndex: index
                    spacing: workspaceSpacing

                    Repeater { // Workspace repeater
                        model: root.gridCols
                        Rectangle { // Workspace
                            id: workspace
                            property int colIndex: index
                            property var workspaceData: root.workspacesGrid[rowIndex][colIndex]
                            property string workspaceName: workspaceData.name
                            property color defaultWorkspaceColor: ColorUtils.transparentize(Appearance.colors.colLayer1, 1.0 - Config.options.overview.opacity)
                            property color hoveredWorkspaceColor: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer1Hover, 0.1), 1.0 - Config.options.overview.opacity)
                            property color hoveredBorderColor: ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 1.0 - Config.options.overview.opacity)
                            property bool hoveredWhileDragging: false

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor
                            radius: Appearance.rounding.screenRounding * root.scale
                            border.width: 2
                            border.color: hoveredWhileDragging ? hoveredBorderColor : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: workspaceName
                                font {
                                    pixelSize: root.workspaceNumberSize * root.scale
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.expressive
                                }
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: workspaceArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    if (root.draggingTargetWorkspace === "") {
                                        GlobalStates.overviewOpen = false
                                        Hyprland.dispatch(`(function() KGrid.switch_name("${workspaceName}") return hl.dsp.no_op() end)()`)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = workspaceName
                                    if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                    hoveredWhileDragging = true
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (root.draggingTargetWorkspace == workspaceName) root.draggingTargetWorkspace = ""
                                }
                            }

                        }
                    }
                }
            }
        }

        Item { // Windows & focused workspace indicator
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            Repeater { // Window repeater
                model: ScriptModel {
                    values: {
                        if (!root.activeActivity) return [];
                        return ToplevelManager.toplevels.values.filter((toplevel) => {
                            const address = `0x${toplevel.HyprlandToplevel.address}`
                            var win = windowByAddress[address]
                            // Check if window is in one of the workspaces of the active activity
                            if (!win || !win.workspace) return false;
                            
                            // We can check if the workspace object exists in our grid
                            // Or check if the workspace name matches any in the grid
                            // Since we have the grid structure:
                            for (let r = 0; r < root.gridRows; r++) {
                                for (let c = 0; c < root.gridCols; c++) {
                                    if (root.workspacesGrid[r][c].name === win.workspace.name) {
                                        return true;
                                    }
                                }
                            }
                            return false;
                        }).sort((a, b) => {
                            // Proper stacking order based on Hyprland's window properties
                            const addrA = `0x${a.HyprlandToplevel.address}`
                            const addrB = `0x${b.HyprlandToplevel.address}`
                            const winA = windowByAddress[addrA]
                            const winB = windowByAddress[addrB]
                            
                            // 1. Pinned windows are always on top
                            if (winA?.pinned !== winB?.pinned) {
                                return winA?.pinned ? 1 : -1
                            }
                            
                            // 2. Floating windows above tiled windows
                            if (winA?.floating !== winB?.floating) {
                                return winA?.floating ? 1 : -1
                            }
                            
                            // 3. Within same category, sort by focus history
                            // Lower focusHistoryID = more recently focused = higher in stack
                            return (winB?.focusHistoryID ?? 0) - (winA?.focusHistoryID ?? 0)
                        })
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    required property int index

                    property string address: `0x${modelData.HyprlandToplevel.address}`
                    windowData: windowByAddress[address]
                    toplevel: modelData
                    monitorData: root.monitorData
                    
                    // Calculate scale relative to window's source monitor
                    property real sourceMonitorWidth: (monitorGeometry?.transform % 2 === 1) ? 
                        (monitorGeometry?.height ?? 1920) / (monitorGeometry?.scale ?? 1) :
                        (monitorGeometry?.width ?? 1920) / (monitorGeometry?.scale ?? 1)
                    property real sourceMonitorHeight: (monitorGeometry?.transform % 2 === 1) ?
                        (monitorGeometry?.width ?? 1080) / (monitorGeometry?.scale ?? 1) :
                        (monitorGeometry?.height ?? 1080) / (monitorGeometry?.scale ?? 1)
                    
                    // Scale windows to fit the workspace size, accounting for different monitor sizes
                    scale: Math.min(
                        root.workspaceImplicitWidth / sourceMonitorWidth,
                        root.workspaceImplicitHeight / sourceMonitorHeight
                    )
                    
                    availableWorkspaceWidth: root.workspaceImplicitWidth
                    availableWorkspaceHeight: root.workspaceImplicitHeight
                    widgetMonitorId: root.monitor.id

                    property bool atInitPosition: (initX == x && initY == y)

                    property int workspaceColIndex: {
                        const name = windowData?.workspace?.name ?? "";
                        const match = name.match(/\((\d+) (\d+)\)/);
                        if (match && match[1]) return parseInt(match[1]) - 1;
                        return 0;
                    }
                    property int workspaceRowIndex: {
                        const name = windowData?.workspace?.name ?? "";
                        const match = name.match(/\((\d+) (\d+)\)/);
                        if (match && match[2]) return parseInt(match[2]) - 1;
                        return 0;
                    }
                    xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex

                    Timer {
                        id: updateWindowPosition
                        interval: Config.options.hacks.arbitraryRaceConditionDelay
                        repeat: false
                        running: false
                        onTriggered: {
                            window.x = Math.round(Math.max((windowData?.at?.[0] ?? 0) * root.scale, 0) + xOffset)
                            window.y = Math.round(Math.max((windowData?.at?.[1] ?? 0) * root.scale, 0) + yOffset)
                        }
                    }

                    z: atInitPosition ? (root.windowZ + index) : root.windowDraggingZ
                    Drag.hotSpot.x: targetWindowWidth / 2
                    Drag.hotSpot.y: targetWindowHeight / 2
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true
                        onExited: hovered = false
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            root.draggingFromWorkspace = windowData?.workspace.name
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = mouse.x
                            window.Drag.hotSpot.y = mouse.y
                        }
                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace
                            window.pressed = false
                            window.Drag.active = false
                            root.draggingFromWorkspace = ""
                            if (targetWorkspace !== "" && targetWorkspace !== windowData?.workspace.name) {
                                Hyprland.dispatch(`hl.dsp.window.move({ workspace = "name:${targetWorkspace}", window = "address:${window.windowData?.address}", follow = false })`)
                                updateWindowPosition.restart()
                            }
                            else {
                                window.x = window.initX
                                window.y = window.initY
                            }
                        }
                        onClicked: (event) => {
                            if (!windowData) return;

                            if (event.button === Qt.LeftButton) {
                                GlobalStates.overviewOpen = false
                                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${windowData.address}" })`)
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                Hyprland.dispatch(`hl.dsp.window.close("address:${windowData.address}")`)
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                            text: `${windowData?.title ?? "Unknown"}\n[${windowData?.class ?? "unknown"}]`
                        }
                    }
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                property var activeWs: HyprlandData.activeWorkspace
                property int activeWorkspaceRowIndex: {
                    const name = activeWs?.name ?? "";
                    const match = name.match(/\((\d+) (\d+)\)/);
                    if (match) return parseInt(match[2]) - 1;
                    return 0;
                }
                property int activeWorkspaceColIndex: {
                    const name = activeWs?.name ?? "";
                    const match = name.match(/\((\d+) (\d+)\)/);
                    if (match) return parseInt(match[1]) - 1;
                    return 0;
                }
                x: (root.workspaceImplicitWidth + workspaceSpacing) * activeWorkspaceColIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * activeWorkspaceRowIndex
                z: root.windowDraggingZ + 1
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"
                radius: Appearance.rounding.screenRounding * root.scale
                border.width: 2
                border.color: root.activeBorderColor
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

}
