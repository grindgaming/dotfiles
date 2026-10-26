//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "WelcomeApp"
import "PowerApp"
import "SidebarApp"
import "CalendarApp"
import "WallpaperApp"
import "StatusbarApp"
import "DockApp"
import "CustomTheme"

ShellRoot {
    // Test IPC tools: qs ipc show

    IpcHandler {
        target: "theme-manager" 
        function reload(): void {
            Theme.reloadTheme()
        }
    }

    WelcomeWindow {}
    PowerWindow {}
    SidebarWindow {}
    CalendarWindow {}
    WallpaperWindow {}
    // One status bar per screen; the first screen's bar owns the IPC handlers.
    Variants {
        model: Quickshell.screens
        StatusbarWindow {
            required property var modelData
            screen: modelData
            primary: Quickshell.screens.indexOf(modelData) === 0
        }
    }
    // Creates the dock window only while the dock is enabled in dock.json.
    DockLoader {}
}