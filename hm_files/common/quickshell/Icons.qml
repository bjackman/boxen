pragma Singleton

import Quickshell

// Font Awesome codepoints. Named here so the glyphs never have to appear
// literally in source.
Singleton {
    readonly property string cpu: "\uf2db"
    readonly property string memory: "\uf0c9"
    readonly property string temperature: "\uf2c9"
    readonly property string backlight: "\uf185"

    readonly property string charging: "\uf5e7"
    readonly property string plugged: "\uf1e6"
    readonly property list<string> battery: ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"]

    readonly property string performance: "\uf0e7"
    readonly property string balanced: "\uf24e"
    readonly property string powerSaver: "\uf06c"

    readonly property string muted: "\uf6a9"
    readonly property string headphone: "\uf025"
    readonly property string headset: "\uf590"
    readonly property string phone: "\uf095"
    readonly property string car: "\uf1b9"
    readonly property list<string> volume: ["\uf026", "\uf027", "\uf028"]

    readonly property string microphone: "\uf130"
    readonly property string microphoneMuted: "\uf131"
}
