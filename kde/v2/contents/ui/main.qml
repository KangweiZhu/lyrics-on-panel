import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import QtWebSockets

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents

/**
 * Lyrics on Panel for KDE Plasma 6 - v2.0.0
 *
 * This version uses a WebSocket connection to communicate with a Python backend
 * server that handles MPRIS2 interactions and lyrics fetching.
 *
 * Backend endpoints:
 *   ws://127.0.0.1:23560/poll    - Poll for player state and lyrics
 *   ws://127.0.0.1:23560/control - Send playback control commands
 */

PlasmoidItem {
    id: root

    width: 0
    height: lyricText.contentHeight

    preferredRepresentation: fullRepresentation
    Layout.preferredWidth: config_preferedWidgetWidth
    Layout.preferredHeight: lyricText.contentHeight

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    Plasmoid.status: hasActivePlayer || !config_hideItemWhenNoControlChecked
        ? PlasmaCore.Types.ActiveStatus
        : PlasmaCore.Types.HiddenStatus

    RowLayout {
        anchors.fill: parent
        spacing: config_mediaControllSpacing

        Item {
            id: lyricTextContainer
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                id: lyricText
                text: currentLyric || lrc_not_exists
                color: config_lyricTextColor
                font.pixelSize: config_lyricTextSize
                font.bold: config_lyricTextBold
                font.italic: config_lyricTextItalic
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: config_lyricTextVerticalOffset
            }
        }

        RowLayout {
            id: iconsContainer
            Layout.preferredWidth: 5 * config_mediaControllItemSize + 4 * config_mediaControllSpacing
            Layout.preferredHeight: config_mediaControllItemSize
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 1
            spacing: config_mediaControllSpacing

            Image {
                source: backwardIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: sendControl("previous")
                }
            }

            Image {
                source: (playbackStatus === "playing") ? pauseIcon : playIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: sendControl("play_pause")
                }
            }

            Image {
                source: forwardIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: sendControl("next")
                }
            }

            Image {
                source: liked ? likedIcon : likeIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: liked = !liked
                }
            }

            Image {
                id: mediaPlayerIcon
                source: config_yesPlayMusicChecked ? cloudMusicIcon : spotifyIcon
                sourceSize.width: config_mediaControllItemSize
                sourceSize.height: config_mediaControllItemSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (availablePlayers.length > 0) {
                            var pos = mediaPlayerIcon.mapToGlobal(0, mediaPlayerIcon.height)
                            playerPopup.x = pos.x - playerPopup.width + mediaPlayerIcon.width
                            playerPopup.y = pos.y + 5
                            playerPopup.visible = !playerPopup.visible
                        }
                    }
                }
            }
        }
    }

    PlasmaCore.Dialog {
        id: playerPopup
        location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.PopupMenu
        flags: Qt.WindowStaysOnTopHint
        hideOnWindowDeactivate: true

        mainItem: ListView {
            id: playerList
            width: 250
            height: Math.min(contentHeight, 300)
            model: availablePlayers
            spacing: 2
            clip: true

            delegate: Rectangle {
                width: playerList.width
                height: 36
                color: "transparent"
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: modelData === currentPlayerBusName ? "\u25CF" : "\u25CB"
                        color: modelData === currentPlayerBusName ? "#4CAF50" : "#888"
                        font.pixelSize: 10
                    }

                    Text {
                        text: modelData.replace("org.mpris.MediaPlayer2.", "")
                        color: "white"
                        font.pixelSize: config_lyricTextSize
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: delegateMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        selectedPlayer = modelData
                        playerPopup.visible = false
                    }
                }
            }
        }
    }

    property string backwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    property string pauseIcon: config_whiteMediaControlIconsChecked ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    property string forwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    property string likeIcon: config_whiteMediaControlIconsChecked ? "../assets/media-like-white.svg" : "../assets/media-like.svg"
    property string likedIcon: "../assets/media-liked.svg"
    property string cloudMusicIcon: config_whiteMediaControlIconsChecked ? "../assets/netease-cloud-music-white.svg" : "../assets/netease-cloud-music.svg"
    property string spotifyIcon: config_whiteMediaControlIconsChecked ? "../assets/spotify-white.svg" : "../assets/spotify.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"
    property bool liked: false

    property bool config_yesPlayMusicChecked: Plasmoid.configuration.yesPlayMusicChecked
    property bool config_lxMusicChecked: Plasmoid.configuration.lxMusicChecked
    property bool config_spotifyChecked: Plasmoid.configuration.spotifyChecked
    property bool config_compatibleModeChecked: Plasmoid.configuration.compatibleModeChecked

    property int config_lyricTextSize: Plasmoid.configuration.lyricTextSize
    property string config_lyricTextColor: Plasmoid.configuration.lyricTextColor
    property bool config_lyricTextBold: Plasmoid.configuration.lyricTextBold
    property bool config_lyricTextItalic: Plasmoid.configuration.lyricTextItalic
    property int config_lyricTextVerticalOffset: Plasmoid.configuration.lyricTextVerticalOffset

    property int config_mediaControllSpacing: Plasmoid.configuration.mediaControllSpacing
    property int config_mediaControllItemSize: Plasmoid.configuration.mediaControllItemSize
    property int config_mediaControllItemVerticalOffset: Plasmoid.configuration.mediaControllItemVerticalOffset

    property bool config_whiteMediaControlIconsChecked: Plasmoid.configuration.whiteMediaControlIconsChecked
    property int config_preferedWidgetWidth: Plasmoid.configuration.preferedWidgetWidth
    property bool config_hideItemWhenNoControlChecked: Plasmoid.configuration.hideItemWhenNoControlChecked

    property int config_lxMusicPort: Plasmoid.configuration.lxMusicPort

    readonly property string serverHost: "127.0.0.1"
    readonly property int serverPort: 23560

    property string playbackStatus: "stopped"
    property string currentLyric: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentAlbum: ""
    property string currentPlayerIdentity: ""
    property string currentPlayerBusName: ""
    property int positionMs: 0
    property bool hasActivePlayer: false
    property var availablePlayers: []
    property string selectedPlayer: ""

    property string requestedPlayer: {
        if (selectedPlayer) {
            return selectedPlayer
        } else if (config_yesPlayMusicChecked) {
            return "org.mpris.MediaPlayer2.yesplaymusic"
        } else if (config_spotifyChecked) {
            return "org.mpris.MediaPlayer2.spotify"
        } else if (config_lxMusicChecked) {
            return "org.mpris.MediaPlayer2.lx-music-desktop"
        } else {
            return ""
        }
    }

    property string lrc_not_exists: {
        if (currentTitle && currentArtist) {
            return currentTitle + " - " + currentArtist
        } else if (currentTitle) {
            return currentTitle
        } else {
            return " "
        }
    }

    WebSocket {
        id: pollSocket
        url: "ws://" + serverHost + ":" + serverPort + "/poll"
        active: true

        onStatusChanged: {
            if (pollSocket.status === WebSocket.Open) {
                console.log("Poll WebSocket connected")
                sendPollRequest()
            } else if (pollSocket.status === WebSocket.Closed) {
                console.log("Poll WebSocket closed, reconnecting...")
                hasActivePlayer = false
                currentLyric = ""
                reconnectTimer.start()
            } else if (pollSocket.status === WebSocket.Error) {
                console.log("Poll WebSocket error:", pollSocket.errorString)
                hasActivePlayer = false
                reconnectTimer.start()
            }
        }

        onTextMessageReceived: function(message) {
            try {
                var data = JSON.parse(message)
                handlePollResponse(data)
                sendPollRequest()
            } catch (e) {
                console.log("Error parsing poll response:", e)
            }
        }
    }

    WebSocket {
        id: controlSocket
        url: "ws://" + serverHost + ":" + serverPort + "/control"
        active: true

        onStatusChanged: {
            if (controlSocket.status === WebSocket.Open) {
                console.log("Control WebSocket connected")
            } else if (controlSocket.status === WebSocket.Error) {
                console.log("Control WebSocket error:", controlSocket.errorString)
            }
        }

        onTextMessageReceived: function(message) {
            try {
                var data = JSON.parse(message)
                if (!data.success) {
                    console.log("Control command failed")
                }
            } catch (e) {
                console.log("Error parsing control response:", e)
            }
        }
    }

    function sendPollRequest() {
        if (pollSocket.status === WebSocket.Open) {
            var request = { "player": requestedPlayer || null }
            pollSocket.sendTextMessage(JSON.stringify(request))
        }
    }

    Timer {
        id: reconnectTimer
        interval: 3000
        running: false
        repeat: false
        onTriggered: {
            if (pollSocket.status !== WebSocket.Open) {
                pollSocket.active = false
                pollSocket.active = true
            }
            if (controlSocket.status !== WebSocket.Open) {
                controlSocket.active = false
                controlSocket.active = true
            }
        }
    }

    function handlePollResponse(data) {
        if (!data || !data.player) {
            hasActivePlayer = false
            currentLyric = ""
            currentTitle = ""
            currentArtist = ""
            currentAlbum = ""
            playbackStatus = "stopped"
            return
        }

        hasActivePlayer = true
        playbackStatus = data.playback_status || "stopped"
        positionMs = data.position_ms || 0

        if (data.player) {
            currentPlayerIdentity = data.player.identity || ""
            currentPlayerBusName = data.player.bus_name || ""
        }

        if (data.track) {
            currentTitle = data.track.title || ""
            currentArtist = data.track.artist || ""
            currentAlbum = data.track.album || ""
        }

        if (data.lyrics && data.lyrics.current_lyric) {
            currentLyric = data.lyrics.current_lyric
        } else {
            currentLyric = ""
        }

        if (data.available_players) {
            availablePlayers = data.available_players
        }
    }

    function sendControl(action) {
        if (controlSocket.status !== WebSocket.Open) {
            console.log("Control socket not connected")
            return
        }
        var request = {
            "action": action,
            "player": requestedPlayer || currentPlayerBusName || null
        }
        controlSocket.sendTextMessage(JSON.stringify(request))
    }
}
