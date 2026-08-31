pragma Singleton

import Quickshell

// Tracks the one open top level menu, so clicking elsewhere can dismiss it.
Singleton {
    id: root

    property PopupWindow current: null

    function open(menu: PopupWindow): void {
        if (current && current !== menu)
            current.visible = false;
        current = menu;
        menu.visible = true;
    }

    function close(): void {
        if (!current)
            return;
        current.visible = false;
        current = null;
    }

    function toggle(menu: PopupWindow): void {
        if (menu.visible)
            close();
        else
            open(menu);
    }
}
