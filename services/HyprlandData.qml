pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 *
 * The 2D-grid model (monitors -> activities -> workspaces[rows][cols] -> windows)
 * used to come from `hyprkool info monitors-all-info`. hyprkool has been removed;
 * the grid is now defined entirely by the KGrid Lua engine in the Hyprland config
 * (workspaces are plain numeric ids named "activity:(x y)"). We rebuild the same
 * structure here purely from `hyprctl` so the rest of the overview is unchanged.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var monitorGeometries: []
    property var layers: ({})

    // Grid definition — must match hyprland/kgrid.lua
    readonly property var kgridActivities: ["default", "Z", "X", "C", "A", "S", "D", "Q", "W", "E"]
    readonly property int kgridW: 5
    readonly property int kgridH: 5

    property var _rawHyprkoolData: null
    property var _rawClientsData: null
    property var _rawMonitorsData: null
    property var _rawWorkspacesData: null

    function updateClients() { getClients.running = true; }
    function updateMonitorGeometries() { getMonitorGeometries.running = true; }
    function updateWorkspaces() { getWorkspaces.running = true; }
    function updateLayers() { getLayers.running = true; }

    function updateAll() {
        updateClients();
        updateMonitorGeometries();
        updateWorkspaces();
        updateLayers();
    }

    // Build the hyprkool-shaped grid model from raw hyprctl data.
    function buildModel() {
        if (!_rawClientsData || !_rawMonitorsData || !_rawWorkspacesData) return;

        const W = root.kgridW, H = root.kgridH;
        const activities = root.kgridActivities;

        // Map "activity:(x y)" -> [window objects]
        const winsByWs = {};
        _rawClientsData.forEach(c => {
            const wsName = c.workspace ? c.workspace.name : "";
            if (!wsName) return;
            (winsByWs[wsName] = winsByWs[wsName] || []).push({
                address: c.address,
                title: c.title,
                "class": c.class,
                initial_title: c.initialTitle,
                focusHistoryID: c.focusHistoryID,
            });
        });

        const out = _rawMonitorsData.map(mon => {
            const activeWsName = mon.activeWorkspace ? mon.activeWorkspace.name : "";
            const am = activeWsName.match(/^(.+):\((\d+) (\d+)\)$/);
            const focusedActivity = am ? am[1] : activities[0];

            const acts = activities.map(act => {
                const rows = [];
                for (let y = 1; y <= H; y++) {
                    const row = [];
                    for (let x = 1; x <= W; x++) {
                        const name = `${act}:(${x} ${y})`;
                        row.push({
                            name: name,
                            focused: (name === activeWsName),
                            named_focus: [],
                            windows: winsByWs[name] || [],
                        });
                    }
                    rows.push(row);
                }
                return { name: act, focused: (act === focusedActivity), workspaces: rows };
            });

            return {
                id: mon.id,
                name: mon.name,
                focused: mon.focused,
                transform: mon.transform,
                activities: acts,
            };
        });

        root._rawHyprkoolData = out;
        root.rebuildData();
    }

    function rebuildData() {
        if (!_rawHyprkoolData || !_rawClientsData) return;

        // Create a map of clients for fast lookup
        var clientsMap = {};
        _rawClientsData.forEach(c => {
            clientsMap[c.address] = c;
        });

        var data = _rawHyprkoolData;
        root.monitors = data;

        var wins = [];
        var winByAddr = {};
        var addrs = [];
        var activeWs = null;

        data.forEach(monitor => {
            monitor.activities.forEach(activity => {
                activity.workspaces.forEach(row => {
                    row.forEach(workspace => {
                        if (monitor.focused && activity.focused && workspace.focused) {
                            activeWs = workspace;
                        }
                        workspace.windows.forEach(win => {
                            // Merge with client data
                            var clientData = clientsMap[win.address];
                            if (clientData) {
                                win.at = clientData.at;
                                win.size = clientData.size;
                                win.xwayland = clientData.xwayland;
                                win.pinned = clientData.pinned;
                                win.floating = clientData.floating;
                                // win.monitor is set below from the structure
                            }

                            win.workspace = workspace;
                            win.monitor = monitor.id;
                            wins.push(win);
                            winByAddr[win.address] = win;
                            addrs.push(win.address);
                        });
                    });
                });
            });
        });

        root.windowList = wins;
        root.windowByAddress = winByAddr;
        root.addresses = addrs;
        root.activeWorkspace = activeWs;
    }


    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            updateAll()
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root._rawClientsData = JSON.parse(clientsCollector.text);
                root.buildModel();
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                root._rawWorkspacesData = JSON.parse(workspacesCollector.text);
                root.buildModel();
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    Process {
        id: getMonitorGeometries
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorGeometriesCollector
            onStreamFinished: {
                root.monitorGeometries = JSON.parse(monitorGeometriesCollector.text);
                root._rawMonitorsData = root.monitorGeometries;
                root.buildModel();
            }
        }
    }


}
