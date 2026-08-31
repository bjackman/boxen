pragma Singleton

import Quickshell

// The quickshell module rewrites these to absolute store paths when it
// assembles the config directory. The bare names are what the config uses when
// run straight out of a checkout, where they come from PATH.
Singleton {
    readonly property string capslockWatch: "capslock-watch"
}
