import QtQuick
import QtQuick.Controls as Controls
import org.kde.kwin
import org.kde.kirigami as Kirigami
import "../code/FuzzyMatcher.js" as FuzzyMatcher

SceneEffect {
    id: effect

    // A normal interaction should take only a few seconds;
    // if the effect is still open after 30s, dismiss it so a suspend/lock/focus
    // glitch cannot strand the full-screen SceneEffect on screen.
    readonly property int autoDismissInterval: 30000

    property point invocationPos: Qt.point(0, 0)
    property var invocationWindow: null
    property var invocationScreen: null
    property var pendingPointerWindow: null

    // candidates: MRU order, with the window that was active on invocation
    // appended at the end.
    property var candidates: []
    property var filteredCandidates: []
    property var mruWindows: []
    property string query: ""
    property int selectedIndex: -1

    function resetTimer() {
        if (visible) {
            autoDismissTimer.restart();
        }
    }

    function trackable(window) {
        return window
            && window.managed
            && !window.deleted
            && !window.specialWindow
            && !window.skipSwitcher
            && window.wantsInput;
    }

    function moveToMruFront(window) {
        if (!trackable(window)) {
            return;
        }

        const next = [window];
        for (let i = 0; i < mruWindows.length; ++i) {
            const previous = mruWindows[i];
            if (previous && previous !== window) {
                next.push(previous);
            }
        }
        mruWindows = next;
    }

    function removeFromMru(window) {
        const next = [];
        for (let i = 0; i < mruWindows.length; ++i) {
            const previous = mruWindows[i];
            if (previous && previous !== window) {
                next.push(previous);
            }
        }
        mruWindows = next;
    }

    function seedMru() {
        const initial = [];
        const active = Workspace.activeWindow;

        if (trackable(active)) {
            initial.push(active);
        }

        // Initial fallback only. Once activation events have been observed,
        // mruWindows contains genuine recency information.
        const stack = Workspace.stackingOrder;
        for (let i = stack.length - 1; i >= 0; --i) {
            const window = stack[i];
            if (trackable(window) && initial.indexOf(window) < 0) {
                initial.push(window);
            }
        }

        mruWindows = initial;
    }

    function reconcileMru() {
        // Keep the genuine MRU order for known windows, discard stale entries,
        // then append newly discovered background windows in topmost-first order.
        const next = [];

        for (let i = 0; i < mruWindows.length; ++i) {
            const window = mruWindows[i];
            if (trackable(window) && next.indexOf(window) < 0) {
                next.push(window);
            }
        }

        const stack = Workspace.stackingOrder;
        for (let i = stack.length - 1; i >= 0; --i) {
            const window = stack[i];
            if (trackable(window) && next.indexOf(window) < 0) {
                next.push(window);
            }
        }

        mruWindows = next;
    }

    function onCurrentDesktop(window) {
        if (window.onAllDesktops) {
            return true;
        }

        for (let i = 0; i < window.desktops.length; ++i) {
            if (window.desktops[i] === Workspace.currentDesktop) {
                return true;
            }
        }
        return false;
    }

    function onCurrentActivity(window) {
        if (window.activities.length === 0) {
            return true;
        }

        for (let i = 0; i < window.activities.length; ++i) {
            if (window.activities[i] === Workspace.currentActivity) {
                return true;
            }
        }
        return false;
    }

    function snapshotWindows() {
        reconcileMru();

        const result = [];
        const active = invocationWindow;
        const includeActive = trackable(active);

        // Everything except the invocation window stays in MRU order.
        for (let i = 0; i < mruWindows.length; ++i) {
            const window = mruWindows[i];
            if (!trackable(window) || window === active) {
                continue;
            }
            result.push(window);
        }

        // The currently active window is deliberately last (mimic the Alt-Tab behaviour)
        if (includeActive) {
            result.push(active);
        }

        candidates = result;
        updateFilter();
    }

    function partialMatchScore(searchString, text) {
        if (!text || !searchString) {
            return -1;
        }

        const value = String(text);
        const needle = String(searchString).trim();

        const queryTokens = needle
            .split(/[\s._\-:/\\]+/)
            .filter(token => token.length > 0);

        const valueTokens = value
            .split(/[\s._\-:/\\]+/)
            .filter(token => token.length > 0);

        if (queryTokens.length === 0 || valueTokens.length === 0) {
            return -1;
        }

        // use the whole-string comparison as the baseline
        let best = FuzzyMatcher.score(needle, value, true);

        const windowSize = queryTokens.length;

        if (windowSize <= valueTokens.length) {
            for (let start = 0;
             start + windowSize <= valueTokens.length;
             ++start) {
                 const fragment = valueTokens.slice(start, start + windowSize).join(" ");
                 best = Math.max(best, FuzzyMatcher.score(needle, fragment, true));
             }
        }

        return best;        
    }

    function windowMatchScore(window, searchString) {
        const caption = window.caption ? String(window.caption) : "";

        const resourceClass = window.resourceClass ? String(window.resourceClass) : "";

        const resourceName = window.resourceName ? String(window.resourceName) : "";

        return Math.max(
            partialMatchScore(searchString, caption),
            partialMatchScore(searchString, resourceClass),
            partialMatchScore(searchString, resourceName)
        );

    }

    function updateFilter() {
        const needle = query.trim();

        if (needle.length === 0) {
            filteredCandidates = candidates.slice();
            selectedIndex = filteredCandidates.length > 0 ? 0 : -1;
            return;
        }

        let minimumScore = 0;
        if (needle.length >= 3) {
           minimumScore = 50;
        }
        const matches = [];

        for (let i = 0; i < candidates.length; ++i) {
            const window = candidates[i];
            const score = windowMatchScore(window, needle);

            if (score >= minimumScore) {
                matches.push({
                    window: window,
                    score: score,
                    mruIndex: i
                });
            }
        }

        matches.sort(function(a, b) {
            if (a.score !== b.score) {
                return b.score - a.score;
            }

            // Equal-quality matches retain MRU ordering.
            return a.mruIndex - b.mruIndex;
        });

        filteredCandidates = matches.map(function(match) {
            return match.window;
        });

        selectedIndex = filteredCandidates.length > 0 ? 0 : -1;
    }

    function openSwitcher() {
        pendingPointerWindow = null;
        invocationPos = Workspace.cursorPos;
        invocationScreen = Workspace.screenAt(invocationPos);
        invocationWindow = Workspace.activeWindow;
        query = "";
        selectedIndex = -1;
        snapshotWindows();

        if (candidates.length > 0) {
            visible = true;
            autoDismissTimer.restart();
        }
    }

    function cancel() {
        autoDismissTimer.stop();
        selectedIndex = -1;
        visible = false;
    }

    function matchesActivation(window, target) {
        while (window) {
            if (window === target) {
                return true;
            }
            window = window.modal ? window.transientFor : null;
        }
        return false;
    }
    
    function activateFilteredIndex(index) {
        if (index < 0 || index >= filteredCandidates.length) {
            return;
        }

        const window = filteredCandidates[index];
        autoDismissTimer.stop();
        visible = false;
        pendingPointerWindow = matchesActivation(Workspace.activeWindow, window) ? null : window;        
        Workspace.activeWindow = window;
    }

    function cycle(delta) {
        const count = filteredCandidates.length;
        if (count === 0) {
            selectedIndex = -1;
            return;
        }

        if (selectedIndex < 0) {
            selectedIndex = delta > 0 ? 0 : count - 1;
            return;
        }

        // Deliberate wrap-around in both directions.
        selectedIndex = (selectedIndex + delta + count) % count;
    }

    function shortcutIndexForKey(key) {
        switch (key) {
        case Qt.Key_1: return 0;
        case Qt.Key_2: return 1;
        case Qt.Key_3: return 2;
        case Qt.Key_4: return 3;
        case Qt.Key_5: return 4;
        case Qt.Key_6: return 5;
        case Qt.Key_7: return 6;
        case Qt.Key_8: return 7;
        case Qt.Key_9: return 8;
        case Qt.Key_0: return 9;
        default: return -1;
        }
    }

    function shortcutLabel(index) {
        if (index < 0 || index > 9) {
            return "";
        }
        return index === 9 ? "Ctrl+0" : "Ctrl+" + String(index + 1);
    }

    
    Component.onCompleted: seedMru()

    Connections {
        target: Workspace

        function onWindowActivated(window) {
            effect.moveToMruFront(window);
            if (!window) {
                return;
            }
            const target = effect.pendingPointerWindow;
            effect.pendingPointerWindow = null;
            if (target && effect.matchesActivation(window, target)) {
                if (effect.configuration.TeleportCursor) {
                    moveMouseToFocus.call();
                }
            }            
        }

        function onWindowAdded(window) {
            if (!effect.trackable(window) || effect.mruWindows.indexOf(window) >= 0) {
                return;
            }
            const next = effect.mruWindows.slice();
            next.push(window);
            effect.mruWindows = next;
        }

        function onWindowRemoved(window) {
            effect.removeFromMru(window);
        }
    }

    Timer {
        id: autoDismissTimer
        interval: effect.autoDismissInterval
        repeat: false
        onTriggered: effect.cancel()
    }


    DBusCall {
        id: moveMouseToFocus

        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        dbusInterface: "org.kde.kglobalaccel.Component"
        method: "invokeShortcut"
        arguments: ["MoveMouseToFocus"]

        onFailed: console.warn("Failed to move cursor to focused window")
    }    

    ShortcutHandler {
        name: "Search Window Switcher"
        text: "Show Search Window Switcher"
        sequence: "Meta+Alt+Space"
        onActivated: effect.openSwitcher()
    }

    delegate: Item {
        id: scene

        readonly property var screen: SceneView.screen
        readonly property rect screenGeometry: screen.geometry
        readonly property bool invocationView: effect.invocationScreen === screen

        focus: invocationView
        onInvocationViewChanged: focusSearchField()

        function focusSearchField() {
            if (!effect.visible || !scene.invocationView) {
                return;
            }

            Qt.callLater(function() {
                switcherUi.forceActiveFocus();
                searchField.forceActiveFocus(Qt.ShortcutFocusReason);
            });
        }

        // SceneEffect replaces KWin's normal scene while active, so reconstruct
        // the current desktop and visible windows underneath the switcher.
        DesktopBackground {
            anchors.fill: parent
            output: scene.screen
            desktop: Workspace.currentDesktop
            activity: Workspace.currentActivity
        }

        Repeater {
            model: Workspace.stackingOrder

            delegate: WindowThumbnail {
                required property var modelData

                client: modelData
                x: client.x - scene.screenGeometry.x
                y: client.y - scene.screenGeometry.y
                width: client.width
                height: client.height

                visible: !client.deleted
                      && (!client.specialWindow || client.dock)
                      && !client.minimized
                      && !client.hidden
                      && effect.onCurrentDesktop(client)
                      && effect.onCurrentActivity(client)
                      && x < scene.width
                      && y < scene.height
                      && x + width > 0
                      && y + height > 0
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#66000000"
        }

        FocusScope {
            id: switcherUi
            anchors.fill: parent
            focus: visible
            visible: scene.invocationView

            // reset timer on mouse movement
            PointHandler {
                acceptedButtons: Qt.NoButton
                onPointChanged: effect.resetTimer()
            }

            // Click outside the panel to cancel.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => effect.cancel()
            }

            Rectangle {
                id: panel

                width: Math.min(760, scene.width - 48)
                height: Math.min(620, scene.height - 48)
                anchors.centerIn: parent
                radius: 12
                color: "#f225272a"
                border.width: 1
                border.color: "#70ffffff"

                // Prevent clicks inside the panel from reaching the outside
                // cancellation MouseArea.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onClicked: mouse => mouse.accepted = true
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Controls.TextField {
                        id: searchField

                        width: parent.width
                        placeholderText: "Search windows…"
                        selectByMouse: true
                        focus: true

                        onTextChanged: {
                            effect.query = text;
                            effect.updateFilter();
                        }

                        Keys.onPressed: event => {
                            effect.resetTimer();
                            let handled = true;
                            const emacsNavigation = effect.configuration.EmacsStyleNavigation
                                && event.modifiers === Qt.ControlModifier;

                            if (event.key === Qt.Key_Escape) {
                                effect.cancel();
                            } else if (event.key === Qt.Key_Down) {
                                effect.cycle(1);
                            } else if (event.key === Qt.Key_Up) {
                                effect.cycle(-1);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                effect.activateFilteredIndex(effect.selectedIndex);
                            } else if (emacsNavigation
                                    && event.key === Qt.Key_A) {
                                searchField.cursorPosition = 0;
                            } else if (emacsNavigation
                                    && event.key === Qt.Key_E) {
                                searchField.cursorPosition = searchField.length;
                            } else if (emacsNavigation
                                    && event.key === Qt.Key_D) {
                                if (searchField.selectedText.length > 0) {
                                    searchField.remove(searchField.selectionStart, searchField.selectionEnd);
                                } else {
                                    const pos = searchField.cursorPosition;
                                    const size = searchField.text.codePointAt(pos) > 0xffff ? 2 : 1;
                                    searchField.remove(pos, Math.min(pos + size, searchField.length));
                                }
                            } else if (emacsNavigation
                                    && event.key === Qt.Key_N) {
                                effect.cycle(1);
                            } else if (emacsNavigation
                                    && event.key === Qt.Key_P) {
                                effect.cycle(-1);
                            } else if ((event.modifiers & Qt.ControlModifier) !== 0) {
                                const shortcutIndex = effect.shortcutIndexForKey(event.key);
                                if (shortcutIndex >= 0
                                        && shortcutIndex < effect.filteredCandidates.length) {
                                    effect.activateFilteredIndex(shortcutIndex);
                                } else {
                                    handled = false;
                                }
                            } else {
                                handled = false;
                            }

                            if (handled) {
                                event.accepted = true;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: "#38ffffff"
                    }

                    ListView {
                        id: windowList

                        width: parent.width
                        height: parent.height - searchField.height - 11
                        clip: true
                        spacing: 2
                        model: effect.filteredCandidates
                        currentIndex: effect.selectedIndex

                        Controls.ScrollBar.vertical: Controls.ScrollBar { }

                        delegate: Rectangle {
                            id: row
                            required property int index
                            required property var modelData

                            readonly property bool selected: index === effect.selectedIndex

                            width: ListView.view.width
                            height: 58
                            radius: 7
                            color: row.selected
                                 ? Kirigami.Theme.highlightColor
                                 : "transparent"

                            Kirigami.Icon {
                                id: windowIcon
                                anchors {
                                    left: parent.left
                                    leftMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 38
                                height: 38
                                source: row.modelData.icon
                                fallback: "application-x-executable"
                            }

                            Column {
                                anchors {
                                    left: windowIcon.right
                                    leftMargin: 10
                                    right: shortcutText.left
                                    rightMargin: 12
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: row.modelData.caption
                                    font: Kirigami.Theme.defaultFont
                                    elide: Text.ElideRight
                                    color: row.selected
                                         ? Kirigami.Theme.highlightedTextColor
                                         : "white"
                                }

                                Text {
                                    width: parent.width
                                    text: row.modelData === effect.invocationWindow
                                        ? String(row.modelData.resourceClass) + "  ·  current window"
                                        : String(row.modelData.resourceClass)
                                    font: Kirigami.Theme.smallFont
                                    elide: Text.ElideRight
                                    color: row.selected
                                         ? Kirigami.Theme.highlightedTextColor
                                         : "white"
                                }
                            }

                            Text {
                                id: shortcutText
                                anchors {
                                    right: parent.right
                                    rightMargin: 12
                                    verticalCenter: parent.verticalCenter
                                }
                                text: row.index < 10
                                    ? effect.shortcutLabel(row.index)
                                    : ""
                                color: row.selected
                                    ? Kirigami.Theme.highlightedTextColor
                                    : "white"
                                font: Kirigami.Theme.smallFont
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                onEntered: effect.selectedIndex = row.index
                                onClicked: effect.activateFilteredIndex(row.index)
                            }
                        }

                        footer: Item {
                            width: windowList.width
                            height: effect.filteredCandidates.length === 0 ? 70 : 0

                            Text {
                                anchors.centerIn: parent
                                visible: effect.filteredCandidates.length === 0
                                text: "No matching windows"
                                color: "#aaffffff"
                                font: Kirigami.Theme.defaultFont
                            }
                        }
                    }
                }
            }
        }

        Connections {
            target: effect

            function onVisibleChanged() {
                if (effect.visible && scene.invocationView) {
                    scene.focusSearchField();
                    searchField.text = "";
                }
            }

            function onSelectedIndexChanged() {
                if (scene.invocationView && effect.selectedIndex >= 0) {
                    windowList.positionViewAtIndex(effect.selectedIndex, ListView.Contain);
                }
            }
        }
    }
}
