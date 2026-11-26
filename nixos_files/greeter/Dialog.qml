import Quickshell.Io
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Layouts

Bevel {
    id: root

    property bool shutDownMode: false
    property bool restart: false

    property string errorText: Greetd.available ? "" : "Can't connect to greetd."
    property string infoText: ""
    // A prompt beyond the password, e.g. for a second factor.
    property string prompt: ""
    property bool responsePending: false
    // The password is collected before the session exists, then sent when
    // greetd asks for it.
    property string queuedPassword: ""
    property bool hasQueuedPassword: false

    readonly property bool busy: Greetd.state !== GreetdState.Inactive && !responsePending
    readonly property int buttonWidth: 130

    implicitWidth: content.implicitWidth + 2 * (bevelWidth + 2)
    implicitHeight: content.implicitHeight + 2 * (bevelWidth + 2)

    function submit() {
        if (busy || !Greetd.available)
            return;
        errorText = "";
        infoText = "";
        if (responsePending) {
            responsePending = false;
            Greetd.respond(password.text);
        } else {
            queuedPassword = password.text;
            hasQueuedPassword = true;
            Greetd.createSession(user.text);
        }
        password.text = "";
    }

    function resetPrompt() {
        responsePending = false;
        hasQueuedPassword = false;
        queuedPassword = "";
        prompt = "";
        password.echoMode = TextInput.Password;
    }

    function cancel() {
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        resetPrompt();
        password.text = "";
        errorText = "";
        infoText = "";
        password.input.forceActiveFocus();
    }

    function powerOff() {
        power.command = restart ? GreeterSettings.rebootCommand : GreeterSettings.powerOffCommand;
        power.running = true;
    }

    Component.onCompleted: password.input.forceActiveFocus()
    onBusyChanged: {
        if (!busy)
            password.input.forceActiveFocus();
    }

    Keys.onEscapePressed: {
        if (shutDownMode) {
            shutDownMode = false;
            password.input.forceActiveFocus();
        } else {
            cancel();
        }
    }

    Process {
        id: power
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (!responseRequired) {
                if (error)
                    root.errorText = message;
                else
                    root.infoText = message;
                return;
            }
            if (root.hasQueuedPassword && !echoResponse) {
                const response = root.queuedPassword;
                root.hasQueuedPassword = false;
                root.queuedPassword = "";
                Greetd.respond(response);
                return;
            }
            root.hasQueuedPassword = false;
            root.queuedPassword = "";
            root.prompt = message.trim();
            password.echoMode = echoResponse ? TextInput.Normal : TextInput.Password;
            root.responsePending = true;
            password.input.forceActiveFocus();
        }

        function onAuthFailure(message) {
            console.warn("greetd auth failure:", message);
            root.resetPrompt();
            root.errorText = "The password you typed is incorrect.";
        }

        function onError(error) {
            root.resetPrompt();
            root.errorText = error;
        }

        function onReadyToLaunch() {
            Greetd.launch(GreeterSettings.sessionCommand, ["XDG_SESSION_TYPE=wayland"]);
        }
    }

    ColumnLayout {
        id: content

        anchors {
            fill: parent
            margins: root.bevelWidth + 2
        }
        spacing: 0

        TitleBar {
            Layout.fillWidth: true
            text: root.shutDownMode ? "Shut Down " + GreeterSettings.hostName : "Welcome to " + GreeterSettings.hostName
        }

        RowLayout {
            visible: !root.shutDownMode
            Layout.margins: 14
            spacing: 14

            BarText {
                Layout.alignment: Qt.AlignTop
                icon: true
                text: Icons.key
                color: "#b08800"
                font.pixelSize: 36
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 10

                BarText {
                    text: "Type your password to log on to " + GreeterSettings.hostName + "."
                }

                GridLayout {
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 8

                    BarText {
                        text: "User name:"
                    }

                    Field {
                        id: user

                        Layout.fillWidth: true
                        enabled: !root.busy && !root.responsePending
                        text: GreeterSettings.userName
                        onAccepted: password.input.forceActiveFocus()
                    }

                    BarText {
                        text: root.prompt !== "" ? root.prompt : "Password:"
                    }

                    Field {
                        id: password

                        Layout.fillWidth: true
                        enabled: !root.busy
                        echoMode: TextInput.Password
                        onAccepted: root.submit()
                    }
                }

                BarText {
                    visible: text !== ""
                    Layout.maximumWidth: 420
                    wrapMode: Text.Wrap
                    text: root.errorText !== "" ? root.errorText : root.infoText
                    color: root.errorText !== "" ? Theme.critical : Theme.text
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 8

                PushButton {
                    Layout.preferredWidth: root.buttonWidth
                    text: "OK"
                    enabled: !root.busy
                    onClicked: root.submit()
                }

                PushButton {
                    Layout.preferredWidth: root.buttonWidth
                    text: "Cancel"
                    onClicked: root.cancel()
                }

                PushButton {
                    Layout.preferredWidth: root.buttonWidth
                    text: "Shut Down..."
                    onClicked: {
                        root.cancel();
                        root.restart = false;
                        root.shutDownMode = true;
                        root.forceActiveFocus();
                    }
                }
            }
        }

        RowLayout {
            visible: root.shutDownMode
            Layout.margins: 14
            spacing: 14

            BarText {
                Layout.alignment: Qt.AlignTop
                icon: true
                text: Icons.power
                font.pixelSize: 36
            }

            ColumnLayout {
                spacing: 10

                BarText {
                    text: "Are you sure you want to:"
                }

                RadioOption {
                    text: "Shut down the computer?"
                    checked: !root.restart
                    onClicked: root.restart = false
                }

                RadioOption {
                    text: "Restart the computer?"
                    checked: root.restart
                    onClicked: root.restart = true
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 6
                    spacing: 8

                    PushButton {
                        Layout.preferredWidth: root.buttonWidth
                        text: "Yes"
                        onClicked: root.powerOff()
                    }

                    PushButton {
                        Layout.preferredWidth: root.buttonWidth
                        text: "No"
                        onClicked: {
                            root.shutDownMode = false;
                            password.input.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }
}
