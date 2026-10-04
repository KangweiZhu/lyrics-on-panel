import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import QtQuick.Window 2.15

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.workspace.dbus as DBus
import "DbusValues.js" as DbusValues
import "LyricDisplay.js" as LyricDisplay


/**
Below are some documents that I found useful when writing this widget.

https://specifications.freedesktop.org/mpris-spec/latest/Player_Interface.html

https://app.readthedocs.org/projects/mpris2/downloads/pdf/latest/
*/

PlasmoidItem {
    id: root

    Mpris.Mpris2Model {
        id: mpris2Model
    }

    // Plasma's MPRIS model does not expose the raw track ID to QML.
    readonly property string openOrpheusService: config_openOrpheusChecked
        ? config_openOrpheusService
        : ""

    DBus.DBusServiceWatcher {
        id: openOrpheusWatcher
        busType: DBus.BusType.Session
        watchedService: openOrpheusService
        onRegisteredChanged: {
            if (registered) openOrpheusProperties.updateAll();
        }
    }

    DBus.Properties {
        id: openOrpheusProperties
        busType: DBus.BusType.Session
        service: openOrpheusService
        path: "/org/mpris/MediaPlayer2"
        iface: "org.mpris.MediaPlayer2.Player"
    }

    readonly property var openOrpheusMetadata: openOrpheusWatcher.registered
        ? DbusValues.dictionary(openOrpheusProperties.properties.Metadata) : ({})
    readonly property string openOrpheusSongId: {
        var metadata = openOrpheusMetadata;
        var trackId = metadata ? String(metadata["mpris:trackid"] || "") : "";
        var match = /^\/com\/163\/music\/([0-9]+)$/.exec(trackId);
        return match && /[1-9]/.test(match[1]) ? match[1] : "";
    }
    property string previousOpenOrpheusSongId: ""
    property var compatibleRequest: null
    property double compatibleRetryAt: 0
    property var openOrpheusRequest: null
    property int openOrpheusGeneration: 0
    property bool openOrpheusLyricsLoaded: false
    property double openOrpheusRetryAt: 0
    property string previousOpenOrpheusService: ""

    // Seems obsolete by KDE Plasma 6.
    Mpris.MultiplexerModel {
        id: multiplexerModel
    }
    
    width: 0;
    height: lyricText.contentHeight;

    // Need to set it full representation. Otherwise it will only display the applet icon declared in the metadata.json file on the panel.
    preferredRepresentation: fullRepresentation 
    Layout.preferredWidth: config_preferedWidgetWidth;
    Layout.preferredHeight: lyricText.contentHeight;
    
    /**
        Set the background of this widget to be 'configurable' transparent or non transparent.
        https://develop.kde.org/docs/plasma/widget/properties/#x-plasma-api-x-plasma-mainscript
    */    
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    // Should ask uiYzzi if problem occurs.
    Plasmoid.status: (config_openOrpheusChecked ? openOrpheusWatcher.registered : mpris2Model.currentPlayer?.canControl)
        || !config_hideItemWhenNoControlChecked ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus;

    Text {
        id: lyricText
        text: ""
        color: config_lyricTextColor
        font.pixelSize: config_lyricTextSize
        font.bold: config_lyricTextBold
        font.italic: config_lyricTextItalic
        anchors.right: parent.right
        anchors.rightMargin: 6 * (config_mediaControllItemSize + config_mediaControllSpacing)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: config_lyricTextVerticalOffset
    }

    Item {
        id: iconsContainer
        anchors.right: parent.right
        anchors.rightMargin: 1 
        anchors.verticalCenter: parent.verticalCenter
        width: 5 * config_mediaControllItemSize + 4 * config_mediaControllSpacing
        height: config_mediaControllItemSize
        anchors.verticalCenterOffset: config_mediaControllItemVerticalOffset

        Image {
            source: backwardIcon
            sourceSize.width: config_mediaControllItemSize 
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    previous();
                }
            }
        }

        Image {
            source: (playbackStatus == 2 && !isWrongPlayer()) ? pauseIcon : playIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: config_mediaControllItemSize + config_mediaControllSpacing
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (playbackStatus == 2) {
                        pause();
                    } else {
                        play();
                    }
                }
            }
        }

        Image {
            source: forwardIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: 2 * (config_mediaControllItemSize + config_mediaControllSpacing)
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    next();
                }
            }
        }

        Image {
            source: liked ? likedIcon : likeIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: 3 * (config_mediaControllItemSize + config_mediaControllSpacing)
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (liked) {
                        liked = false;
                    } else {
                        liked = true;
                    }
                }
            }
        }

        Image {
            id: mediaPlayerIcon
            source: {
                if (config_yesPlayMusicChecked || config_openOrpheusChecked) {
                    return cloudMusicIcon;
                } else if (config_splayerChecked) {
                    return splayerIcon;
                } else {
                    return spotifyIcon;
                }
            }
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: 4 * (config_mediaControllItemSize + config_mediaControllSpacing)
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (config_yesPlayMusicChecked) {
                        menuDialog.x = globalPos.x;
                        menuDialog.y = globalPos.y * 3.5;
                        if (!dialogShowed) { 
                            menuDialog.show(); 
                            dialogShowed = true;
                        } else {
                            dialogShowed = false;
                            menuDialog.close();
                        }
                    } 
                }
            }
        }
    }

    // UI-Resources related configurations
    property string backwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    property string pauseIcon: config_whiteMediaControlIconsChecked ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    property string forwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    property string likeIcon: config_whiteMediaControlIconsChecked ? "../assets/media-like-white.svg" : "../assets/media-like.svg"
    property string likedIcon: "../assets/media-liked.svg"
    property string splayerIcon: "../assets/splayer.svg"
    property string cloudMusicIcon: config_whiteMediaControlIconsChecked ? "../assets/netease-cloud-music-white.svg" : "../assets/netease-cloud-music.svg"
    property string spotifyIcon: config_whiteMediaControlIconsChecked ? "../assets/spotify-white.svg" : "../assets/spotify.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"
    property bool liked: false;

    // Applet UI behavior configuration
    property bool config_yesPlayMusicChecked: Plasmoid.configuration.yesPlayMusicChecked;
    property bool config_lxMusicChecked: Plasmoid.configuration.lxMusicChecked;
    property bool config_splayerChecked: Plasmoid.configuration.splayerChecked;
    property bool config_spotifyChecked: Plasmoid.configuration.spotifyChecked;
    readonly property string config_openOrpheusService: Plasmoid.configuration.openOrpheusInstallation === 1
        ? "org.mpris.MediaPlayer2.io.github.yucling.open-orpheus"
        : "org.mpris.MediaPlayer2.open-orpheus"
    property bool config_openOrpheusChecked: Plasmoid.configuration.openOrpheusChecked
    property bool config_compatibleModeChecked: Plasmoid.configuration.compatibleModeChecked;

    property int config_lyricTextSize: Plasmoid.configuration.lyricTextSize;
    property string config_lyricTextColor: Plasmoid.configuration.lyricTextColor;
    property bool config_lyricTextBold: Plasmoid.configuration.lyricTextBold;
    property bool config_lyricTextItalic: Plasmoid.configuration.lyricTextItalic;
    property int config_lyricTextVerticalOffset: Plasmoid.configuration.lyricTextVerticalOffset

    property int config_mediaControllSpacing: Plasmoid.configuration.mediaControllSpacing
    property int config_mediaControllItemSize: Plasmoid.configuration.mediaControllItemSize
    property int config_mediaControllItemVerticalOffset: Plasmoid.configuration.mediaControllItemVerticalOffset;

    property int config_whiteMediaControlIconsChecked: Plasmoid.configuration.whiteMediaControlIconsChecked;
    property int config_preferedWidgetWidth: Plasmoid.configuration.preferedWidgetWidth;
    property bool config_hideItemWhenNoControlChecked: Plasmoid.configuration.hideItemWhenNoControlChecked;

    property int config_lxMusicPort: Plasmoid.configuration.lxMusicPort;

    /**
    ===============================================================================================================================================================================
    Above are the UI related code. 

    I am planning to disassemble them. 

    Below are backend logic related code.
    ===============================================================================================================================================================================
    */

    /**
        Some music player doesn't actively pushing the position to mpris2 datasource. 
        So have to send mpris2 datasource a signal to let'em pull the current position of the song from the player.
    */
    Timer {
        id: positionTimer
        interval: 1
        running: !config_openOrpheusChecked
        repeat: true
        onTriggered: {
            mpris2Model.currentPlayer?.updatePosition();
        }
    }

    Timer {
        interval: 250
        running: config_openOrpheusChecked && openOrpheusWatcher.registered
        repeat: true
        onTriggered: openOrpheusProperties.update("Position")
    }

    // A transient empty Metadata notification must not leave us waiting for
    // another track change. Re-read it while the selected service is present.
    Timer {
        interval: 1000
        running: openOrpheusWatcher.registered && !openOrpheusSongId
        repeat: true
        onTriggered: openOrpheusProperties.updateAll()
    }

    Timer {
        id: schedulerTimer
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            //log();
            /**
                Use translator if you don't understand the comment... Too lazy to rewrite it in English.

                如果 
                    1. 元数据变化时重置；持续为空时不反复重置。
                    2. mpris 里面，当前播放器和之前的播放器不一样，就重置。
                    3. 设置 里面， 当前播放器和之前设置的播放器不一样(即更新了当前追踪的播放器),就重置。
                    4. 前后歌名，前后歌手不一样，重置。
                
                重置后，重新判断当前预期的播放器是哪个。并且开启对应的timer（线程）
            */ 
            if (
                mpris2PreviousPlayerIdentity != mpris2CurrentPlayerIdentity ||
                prevExpectedPlayerIdentity != currExpectedPlayerIdentity ||
                currentMediaTitle != previousMediaTitle || 
                currentMediaArtists != previousMediaArtists ||
                (config_openOrpheusChecked
                    && (openOrpheusSongId !== previousOpenOrpheusSongId
                        || openOrpheusService !== previousOpenOrpheusService))
            ){
                reset();
                if (currExpectedPlayerIdentity === "compatible" || currExpectedPlayerIdentity === "Spotify") {
                    compatibleModeTimer.start()
                } else if (currExpectedPlayerIdentity === "YesPlayMusic") {
                    if (mpris2CurrentPlayerIdentity === "YesPlayMusic") {
                        yesPlayMusicTimer.start();
                    }
                } else if (currExpectedPlayerIdentity === "lx-music-desktop") {
                    if (mpris2CurrentPlayerIdentity === "lx-music-desktop") {
                        lxMusicTimer.start();
                    }
                } else if (currExpectedPlayerIdentity === "SPlayer") {
                    if (mpris2CurrentPlayerIdentity === "SPlayer") {
                        splayerTimer.start();
                    }
                } else if (currExpectedPlayerIdentity === "Open Orpheus") {
                    if (mpris2CurrentPlayerIdentity === "Open Orpheus") {
                        openOrpheusTimer.start();
                    }
                }
            }
        }
    }

    Timer {
        id: openOrpheusTimer
        interval: 1000
        repeat: true
        onTriggered: openOrpheusHandler()
    }

    Timer {
        id: compatibleTimeout
        interval: 5000
        onTriggered: {
            if (compatibleRequest) compatibleRequest.abort();
            compatibleRequest = null;
            compatibleRetryAt = Date.now() + 30000;
        }
    }

    Timer {
        id: openOrpheusTimeout
        interval: 5000
        onTriggered: {
            if (openOrpheusRequest) {
                openOrpheusRequest.abort();
                openOrpheusRequest = null;
            }
        }
    }

    Timer {
        id: yesPlayMusicTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            ypmHandler();
        }
    }

    /**
        must set this one to repeat.
        这玩意的API有问题。加载速度太随机了，完全依赖音源。并且有时候开始放歌了，结果lyric API还没有响应出来。
    */
    Timer {
        id: lxMusicTimer
        interval: 200
        running: false
        repeat: true 
        onTriggered: {
            lxHandler();
        }
    }

    Timer {
        id: splayerTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            splayerHandler();
        }
    }
    
    /**
        Same as above, only one Lyric Fetching Timer will be running.
        If the:
            current media artists does not match the previous media artists
            current media title does not match the previous media title
            current media title and artists are empty
        Then we will stop the timer and start a new one.

        Otherwise, we will keep the timer running and fetch the lyric from the lrclib API.
        
    */
    Timer {
        id: compatibleModeTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            // console.log("reached here")
            if ((currentMediaArtists === "" && currentMediaTitle === "") || (currentMediaTitle != previousMediaTitle) || currentMediaArtists != previousMediaArtists) {
                reset();
                // console.log("keeping reset()")
            } else {
                fetchLyricsCompatibleMode();
            }
        }
    }

    Timer {
        id: lyricDisplayTimer
        interval: 1
        running: false
        repeat: true
        onTriggered: { 
            // If the current playing media source in mpris2 datasource doesn't match the expected media source, then no lyric will be displayed
            if ((currExpectedPlayerIdentity !== 'compatible') && (mpris2CurrentPlayerIdentity !== currExpectedPlayerIdentity)) {
                lyricText.text = " ";
            } else {
                if (currentMediaTitle === "Advertisement") {
                    lyricText.text = currentMediaTitle;
                } else {
                    var isOpenOrpheus = config_openOrpheusChecked;
                    var ready = !isOpenOrpheus || (openOrpheusSongId !== "" && openOrpheusLyricsLoaded);
                    lyricText.text = LyricDisplay.displayText(lyricsWTimes, position, ready, lrc_not_exists);
                }
            }
        }
    }

    // Global constant
    readonly property string ypm_base_url: "http://localhost:27232"
    readonly property string lxmusic_base_url: {
        return "http://localhost:" + config_lxMusicPort;
    }

    readonly property string splayer_base_url: "http://localhost:25884"

    readonly property string lrclib_base_url: "https://lrclib.net"

    // Successfully fetched the lyrics from the yesplaymusic API?
    property bool isYPMLyricFound: false;

    property bool isLXLyricFound: false;

    property bool isSPlayerLyricFound: false;

    // Current Media Title (Song's name), default is empty string
    property string currentMediaTitle: config_openOrpheusChecked
        ? (openOrpheusMetadata["xesam:title"] || "") : (mpris2Model.currentPlayer?.track ?? "")

    // Current Media Artists (Song's artist), default is empty string
    property string currentMediaArtists: config_openOrpheusChecked
        ? String(openOrpheusMetadata["xesam:artist"] || "") : (mpris2Model.currentPlayer?.artist ?? "")

    // Current Media Album (Song's album), default is empty string
    property string currentMediaAlbum: config_openOrpheusChecked
        ? (openOrpheusMetadata["xesam:album"] || "") : (mpris2Model.currentPlayer?.album ?? "")

    // Current Media Playback Status (Song's playback status), default is 0
    property int playbackStatus: config_openOrpheusChecked
        ? (DbusValues.scalar(openOrpheusProperties.properties.PlaybackStatus, "Stopped") === "Playing"
            ? Mpris.PlaybackStatus.Playing : Mpris.PlaybackStatus.Paused)
        : (mpris2Model.currentPlayer?.playbackStatus ?? -1)

    // Retrieve if the current media is playing (Unused)
    property bool isPlaying: root.playbackStatus === Mpris.PlaybackStatus.Playing

    // Retrieve the identity of current music/media player
    // YesPlayMusic Spotify lx-music-desktop xxx
    property string mpris2CurrentPlayerIdentity: config_openOrpheusChecked
        ? (openOrpheusWatcher.registered ? "Open Orpheus" : "") : (mpris2Model.currentPlayer?.identity ?? "")
        
    // Retrieve the current media position (in microseconds)
    property double position: config_openOrpheusChecked
        ? DbusValues.number(openOrpheusProperties.properties.Position) : (mpris2Model.currentPlayer?.position ?? 0)


    // Retrieve the current media length (in microseconds)
    property double length: config_openOrpheusChecked
        ? DbusValues.number(openOrpheusMetadata["mpris:length"]) : (mpris2Model.currentPlayer?.length ?? 0)

    /**
        A list of dictionaries. Each dictionary contains a timestamp and the corresponding lyric. Below is an example

        [
            {timestamp: 1, lyric: "Hello"}, 
            {timestamp: 2, lyric: "World"}, 
            {timestamp: 3, lyric: "!"}
        ]
    */
    ListModel {
        id: lyricsWTimes
    }

    // Other Media Player's mpris2 data
    property double mprisCurrentPlayingSongTimeMS: {
        if (position == 0) {
            return -1;
        } else {
            return position;
        }
    }

    // YesPlayMusic only, don't get misleaded. We can use http://localhost:27232/api/currentMediaYPMId to get lyrics of the current playing song, then upload it to lrclib
    property string currentMediaYPMId: ""

    property string currentMediaSPId: ""

    // Just the index of the LyricWTimes lists. Retrieve the element from the list using the index. The retrieved element contains a timestamp and the corresponding lyric.
    property int currentLyricIndex: 0

    property string previousMediaTitle: ""

    property string previousMediaArtists: ""

    property string prevNonEmptyLyric: ""

    // The id of the lyric that has been fetched from the lrclib API. Only used in compatible mode when querying the lrclib API.
    property string previousLrcId: ""

    // Indicating whether we need to use the needFallback fetching strategy
    property bool needFallback: false;

    property bool isCompatibleLRCFound: false;

    property string mpris2PreviousPlayerIdentity: ""

    property string prevExpectedPlayerIdentity: "";

    property string currExpectedPlayerIdentity: {
        if (config_openOrpheusChecked) {
            return "Open Orpheus";
        } else if (config_yesPlayMusicChecked) {
            return "YesPlayMusic";
        } else if (config_spotifyChecked) {
            return "Spotify";
        } else if (config_lxMusicChecked) {
            return "lx-music-desktop";
        } else if (config_splayerChecked) {
            return "SPlayer";
        } else {
            return "compatible";
        }
    }

    // Construct the lrclib's request url
    property string lrcQueryUrl: {
        if (needFallback) { // 如果失败了就用歌名做一次模糊查询。lrclib只支持模糊查询一个field.所以只能专辑|歌手名|歌名选一个， 很明显歌名的结果最准确。
            return lrclib_base_url + "/api/search?q=" + encodeURIComponent(currentMediaTitle);
        } else { // accruate matching
            return lrclib_base_url + "/api/search" + "?track_name=" + encodeURIComponent(currentMediaTitle) + 
                  "&artist_name=" + encodeURIComponent(currentMediaArtists) + "&album_name=" + encodeURIComponent(currentMediaAlbum);
        }
    }
    
    // exception handling: no lyric => only display title - artists
    property string lrc_not_exists: {
        if (currentMediaTitle && currentMediaArtists) {
            return currentMediaTitle + " - " + currentMediaArtists;
        } else if (currentMediaTitle && !currentMediaArtists) {
            return currentMediaTitle;
        } else {
            return "";
        }
    }

    // fetch the current media id from yesplaymusic(ypm);
    function fetchMediaIdYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/player");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                if (xhr.responseText) {
                    var response = JSON.parse(xhr.responseText);
                    if (response && response.currentTrack && response.currentTrack.name === currentMediaTitle) {
                        previousMediaTitle = currentMediaTitle;
                        previousMediaArtists = currentMediaArtists;
                        currentMediaYPMId = response.currentTrack.id;
                        fetchSyncLyricYPM();
                    }
                }
            }
        };
        xhr.send();
    }

    // fetch the current media lyric from yesplaymusic by media id
    function fetchSyncLyricYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/api/lyric?id=" + currentMediaYPMId);
        xhr.onreadystatechange = function() {
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                print(xhr.responseText)
                //console.log("YPM Network OK");
                if (response && response.lrc && response.lrc.lyric) {
                    lyricsWTimes.clear();
                    //console.log("Successfully fetched YPM lyrics");
                    isYPMLyricFound = true;
                    parseLyric(response.lrc.lyric);
                    //parseAndUpload(response.lrc.lyric);
                } else if (!response.lrc || !response.lrc.lyric) {
                    //console.log("YPM lyric not found");
                    lyricsWTimes.clear();
                    lyricText.text = lrc_not_exists;
                }
            }
        };
        xhr.send();
    }

    function isLXPlaying() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", lxmusic_base_url + "/status");
        xhr.onreadystatechange = function() {
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response && response.status === "playing") {
                    return true;
                } else {
                    return false;
                }
            }
        };
        xhr.send();
    }

    function fetchSyncLyricLX() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", lxmusic_base_url + "/lyric");
        xhr.onreadystatechange = function() {
            if (xhr.status === 200) {
                var lrc_raw = xhr.responseText;
                if (lrc_raw) {
                    lyricsWTimes.clear();
                    isLXLyricFound = true;
                    parseLyric(lrc_raw);
                } else if (!lrc_raw) {
                    lyricsWTimes.clear();
                    lyricText.text = lrc_not_exists;
                }
            }
        };
        xhr.send();
    }

    function fetchMediaInfoSP() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", splayer_base_url + "/api/control/song-info");
        xhr.onreadystatechange = function() {
            if (xhr.status === 200 && xhr.readyState === XMLHttpRequest.DONE) {
                var response = JSON.parse(xhr.responseText);
                if (response && response.data && !response.data.lyricLoading) {
                    parseSyncLyricSP(response.data.lrcData);
                } else {
                    lyricsWTimes.clear();
                    lyricText.text = lrc_not_exists;
                }
            }
        };
        xhr.send();
    }

    function parseSyncLyricSP(lyricsOriginList) {
        var finalLyrics = new Array();
        for (var i = 0; i < lyricsOriginList.length; i++) {
            for (var j = 0; j < lyricsOriginList[i].words.length; j++) {
                var lyric = "[mm:ss]{lyric}"
                var currentTime = lyricsOriginList[i].words[j].startTime;
                var currentLyric =  lyricsOriginList[i].words[j].word;
                var currentMM = currentTime/1000/60;
                var currentSS = (currentTime/1000) % 60;
                finalLyrics.push(lyric
                    .replace("mm", parseInt(currentMM))
                    .replace("ss", currentSS.toFixed(3))
                    .replace("{lyric}", currentLyric)
                );
            }
        }
        if (finalLyrics.length > 0) {
            lyricsWTimes.clear();
            parseLyric(finalLyrics.join("\n"));
        } else {
            lyricsWTimes.clear();
            lyricText.text = lrc_not_exists;
        }
        isSPlayerLyricFound = true;
    }


    // todo: contribute an lrc file to the lrclib API
    function parseAndUpload(ypmLrc) {
        //console.log("Ypm Lrc", ypmLrc);
    }

    // todo: like the current music after clicking the like icon
    function likeMusicYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/api/like" + "?id=");
    }

    /**
        Parse the lyric file and convert it to a list of dictionaries. Each dictionary contains a timestamp and the corresponding lyric.
        The format of the lyric file is as follows:
        [00:34.33] 妳說這一句 很有夏天的感覺
        [00:41.06] 手中的鉛筆 在紙上來來回回
        [00:47.45] 我用幾行字形容妳是我的誰
        [00:54.19] 秋刀魚 的滋味 貓跟妳都想瞭解
    */
    function parseLyric(lrcFile) {
        // console.log(lrcFile)
        var lrcList = lrcFile.split("\n");
        for (var i = 0; i < lrcList.length; i++) {
            var lyricPerRowWTime = lrcList[i].split("]");
            if (lyricPerRowWTime.length > 1) {
                var timestamp = parseTime(lyricPerRowWTime[0].replace("[", "").trim());
                var lyricPerRow = lyricPerRowWTime[1].trim();
                lyricsWTimes.append({time: timestamp, lyric: lyricPerRow});
            }
        }
        /** 
            Add an empty lyric at the end to avoid can't reach last correct lyric forever.
            This empty lyric like {song's length, ""}
        */
        lyricsWTimes.append({time: length, lyric: ""});
        lyricDisplayTimer.start()
    }

    /**
        ================================================================================================================================================================================
        If the current media title is advertisement, then we will not query the API. This happens in apps like Spotify and the user is not a premium user.
        Also, if we've already found the lyric, then we will not spam querying the API.
        ================================================================================================================================================================================
        Elsewise, Start querying the lrclib API for the current media title and artists. If the response is empty, then we will go to the fall back mode. 
        Specifically speaking, check the details in lrcQueryUrl variable.
        ================================================================================================================================================================================
        If the response is not empty and the current playing music is different from the previous plyaing music, then we will reset the timer, parse the lyric and display it on the screen. 

    */
    function fetchLyricsCompatibleMode() {
        if (currentMediaTitle === "Advertisement" || isCompatibleLRCFound
                || compatibleRequest || Date.now() < compatibleRetryAt) return;

        var generation = openOrpheusGeneration;
        var fuzzy = needFallback;
        var xhr = new XMLHttpRequest();
        compatibleRequest = xhr;
        xhr.open("GET", lrcQueryUrl);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (generation !== openOrpheusGeneration || config_openOrpheusChecked) return;
            compatibleTimeout.stop();
            compatibleRequest = null;
            if (xhr.status !== 200) {
                compatibleRetryAt = Date.now() + 30000;
                return;
            }
            try {
                var response = JSON.parse(xhr.responseText);
                for (var i = 0; i < response.length; i++) {
                    if (response[i].syncedLyrics) {
                        lyricsWTimes.clear();
                        isCompatibleLRCFound = true;
                        previousLrcId = String(response[i].id);
                        parseLyric(response[i].syncedLyrics);
                        return;
                    }
                }
                if (!fuzzy) {
                    needFallback = true;
                } else {
                    isCompatibleLRCFound = true;
                    lyricsWTimes.clear();
                    lyricText.text = lrc_not_exists;
                }
            } catch (error) {
                compatibleRetryAt = Date.now() + 30000;
            }
        };
        xhr.send();
        compatibleTimeout.start();
    }

    function log() {
        console.log("currentMediaArtists: ", currentMediaArtists);
        console.log("previousMediaArtists: ", previousMediaArtists);
        console.log("currentMediaTitle: ", currentMediaTitle);
        console.log("previousMediaTitle: ", previousMediaTitle);
        console.log("Mpris2 Model: ", JSON.stringify(mpris2Model))
        console.log("Current Player Identity: ", mpris2CurrentPlayerIdentity);
        console.log(mpris2Model);
        console.log(mpris2Model.toString());
        console.log("Is wrong player: ", isWrongPlayer());
    }

    function parseTime(timeString) {
        var parts = timeString.split(":");
        var minutes = parseInt(parts[0], 10);
        var seconds = parseFloat(parts[1]);
        var parsedMicrosecond = (minutes * 60 + seconds) * 1000000
        return parsedMicrosecond;
    }

    function previous() {
        if (config_openOrpheusChecked) return controlOpenOrpheus("Previous");
        if (!isWrongPlayer()) {
           mpris2Model.currentPlayer.Previous(); 
        }
    }

    function play() {
        if (config_openOrpheusChecked) return controlOpenOrpheus("Play");
        if (!isWrongPlayer()) {
           mpris2Model.currentPlayer.Play(); 
        }
    }

    function pause() {
        if (config_openOrpheusChecked) return controlOpenOrpheus("Pause");
        if (!isWrongPlayer()) {
            mpris2Model.currentPlayer.Pause();
        }
    }

    function next() {
        if (config_openOrpheusChecked) return controlOpenOrpheus("Next");
        if (!isWrongPlayer()) {
            mpris2Model.currentPlayer.Next();
        }
    }

    // Fix the problem of current playing media doesn't match the selected mode.
    function isWrongPlayer() {
        if (mpris2CurrentPlayerIdentity != currExpectedPlayerIdentity) {
            if (currExpectedPlayerIdentity == "compatible") {
                return false;
            } else {
                return true;
            }
        } 
        return false;
    }

    function controlOpenOrpheus(action) {
        if (!openOrpheusWatcher.registered) return;
        DBus.SessionBus.asyncCall({
            service: openOrpheusService,
            path: "/org/mpris/MediaPlayer2",
            iface: "org.mpris.MediaPlayer2.Player",
            member: action
        });
    }

    function openOrpheusHandler() {
        if (!config_openOrpheusChecked || !openOrpheusSongId || openOrpheusRequest || openOrpheusLyricsLoaded
                || Date.now() < openOrpheusRetryAt) {
            return;
        }
        var songId = openOrpheusSongId;
        var generation = openOrpheusGeneration;
        var xhr = new XMLHttpRequest();
        openOrpheusRequest = xhr;
        openOrpheusRetryAt = Date.now() + 30000;
        xhr.open("GET", "https://music.163.com/api/song/lyric?id=" + songId
                 + "&os=pc&lv=-1&kv=-1&tv=-1&yv=-1&rv=-1");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (generation !== openOrpheusGeneration || songId !== openOrpheusSongId
                    || mpris2CurrentPlayerIdentity !== "Open Orpheus") return;
            openOrpheusTimeout.stop();
            openOrpheusRequest = null;
            if (xhr.status !== 200) return;
            try {
                var response = JSON.parse(xhr.responseText);
                if (response.code !== 200) return;
                openOrpheusLyricsLoaded = true;
                lyricsWTimes.clear();
                if (response.lrc && typeof response.lrc.lyric === "string" && response.lrc.lyric) {
                    parseLyric(response.lrc.lyric);
                } else {
                    lyricText.text = lrc_not_exists;
                }
            } catch (error) {
                console.log("Invalid Open Orpheus lyric response:", error);
            }
        };
        xhr.send();
        openOrpheusTimeout.start();
    }

    function ypmHandler() {
        if (currentMediaArtists === "" && currentMediaTitle === "") {
                lyricText.text = " ";
                lyricsWTimes.clear();
        } else {
            if (!isYPMLyricFound) {
                reset();
                fetchMediaIdYPM();  
            }
        }
    }

    function lxHandler() {
        if (currentMediaArtists === "" && currentMediaTitle === "") {
            lyricText.text = " ";
            lyricsWTimes.clear();
        } else {
            if (!isLXLyricFound) {
                fetchSyncLyricLX();
            }
        }
    }

    function splayerHandler() {
        if (currentMediaArtists === "" && currentMediaTitle === "") {
            lyricText.text = " ";
            lyricsWTimes.clear();
        } else {
            if (!isSPlayerLyricFound) {
                fetchMediaInfoSP();
            }
        }
    }

    /**
        1. Stop the compatible mode timer and yesplaymusic timer.
        2. Set the previous media title and artists to the current media title and artists.
        3. Set the previous player name to the current player name.
        4. Set the previous expected player Identity to the current expected player Identity
        5. Clear the lyricsWTimes list.
        6. Clear the previous non empty lyric.
        7. Clear the previous lrc id.
        8. Set the fallback mode to false, meaning that first query the lrclibAPI with precise matching, if failed, then go to the fallback mode.
        9. Set compatibleLRCFound to false, meaning that we haven't found the lyric yet(From LrcLib for compatible(global)/spotify mode).
        10. Set isYPMLyricFound to false, meaning that we haven't found the lyric yet(From YPM, YPM mode only).
    */
    function reset() {
        openOrpheusGeneration++;
        compatibleTimeout.stop();
        if (compatibleRequest) compatibleRequest.abort();
        compatibleRequest = null;
        compatibleRetryAt = 0;
        openOrpheusTimer.stop();
        openOrpheusTimeout.stop();
        if (openOrpheusRequest) openOrpheusRequest.abort();
        openOrpheusRequest = null;
        openOrpheusLyricsLoaded = false;
        openOrpheusRetryAt = 0;
        previousOpenOrpheusSongId = openOrpheusSongId;
        previousOpenOrpheusService = openOrpheusService;
        compatibleModeTimer.stop();
        yesPlayMusicTimer.stop();
        lxMusicTimer.stop();
        splayerTimer.stop();
        previousMediaTitle = currentMediaTitle;
        previousMediaArtists = currentMediaArtists;
        mpris2PreviousPlayerIdentity = mpris2CurrentPlayerIdentity;
        prevExpectedPlayerIdentity = currExpectedPlayerIdentity;
        lyricsWTimes.clear();
        prevNonEmptyLyric = "";
        previousLrcId = "";
        needFallback = false;
        lyricText.text = " ";
        isCompatibleLRCFound = false;
        isYPMLyricFound = false;
        isLXLyricFound = false;
        isSPlayerLyricFound = false;
    }

    /**
        This part is going to be enabled after we have a better backend instead of hybriding the GUI and backend logic in this same main.qml file. A qml file with more than 1000
    lines of code looks really horrible. Plus the Thus I'm planning to refact the current code with a C++ or Python backend. Or, alternatively, just use tauri or electron to rewrite 
    this widget with cross platform capability. 

        The backend should contain all the lyrics fetching logic, and exposed locally as a general lyrics fetching API. And this qml widget will only serve as frontend -- respon
    -sible for displaying lyrics and those icons.
    */

    // property bool dialogShowed: false;
    // property bool ypmLogined: false;
    // property string ypmUserName: "";
    // property string ypmCookie: "";
    // property string csrf_token: ""
    // property string neteaseID: ""
    // property bool currentMusicLiked: false
    
    // property string base64Image: "" # should be used as QR code login

    // PlasmaCore.Dialog {
    //     id: menuDialog
        
    //     visible: false
    //     width: column.implicitWidth
    //     height: column.implicitHeight

    //     Column {
    //         spacing: 5

    //         PlasmaComponents.MenuItem {
    //             id: userInfoMenuItem
    //             visible: true
    //             text: ypmLogined ? ypmUserName : i18n("登录")

    //             onTriggered: {
    //                 if (!ypmLogined) {
    //                    userInfoMenuItem.visible = false;
    //                    cookieTextField.visible = true;
    //                 }
    //             }
    //         }

    //         PlasmaComponents.TextField {
    //             id: cookieTextField
    //             visible: false
    //             placeholderText: i18n("Enter your Netease ID")

    //             onAccepted: {
    //                 ypmLogined = true
    //                 userInfoMenuItem.visible = true;
    //                 cookieTextField.visible = false;
    //                 neteaseID = cookieTextField.text
    //                 //need to add a cookie validation in the future 
    //             }
    //         }

    //         PlasmaComponents.MenuItem {
    //             id: ypmCreateDays
    //             visible: true // todo: 可以用ypmLogined做判定，但是有bug。会导致登录后元素显示不全。先这样子吧。
    //                             //edit: 估计是menuitem默认字体高宽的的问题。有空再搞。
    //             text: ""
    //         }

    //         PlasmaComponents.MenuItem {
    //             id: ypmSongsListened
    //             visible: true
    //             text: ""
    //         }

    //         PlasmaComponents.MenuItem {
    //             id: ypmFollowed
    //             visible: true
    //             text: ""
    //         }

    //         PlasmaComponents.MenuItem {
    //             id: ypmFollow
    //             visible: true
    //             text: "需要登录"
    //         }
            
    //         PlasmaComponents.MenuItem {
    //             id: logout
    //             visible: true
    //             text: "登出" // i18n

    //             onTriggered: {
    //                 ypmLogined = false;
    //                 neteaseID = ""
    //                 ypmSongsListened.text = ""; 
    //                 ypmFollowed.text = "";
    //                 ypmFollow.text = "";
    //                 ypmCreateDays.text = "";
    //             }
    //         }
    //     }
    // }

    // Timer {
    //     id: ypmUserInfoTimer
    //     interval: 1000
    //     running: false
    //     repeat: true
    //     onTriggered: {
    //         if (ypmLogined) {
    //             getUserDetail();
    //         }
    //     }
    // }

    // function getUserDetail() {
    //     var xhr = new XMLHttpRequest();
    //     xhr.open("GET", ypm_base_url + "/api/user/detail?uid=" + neteaseID);
    //     xhr.onreadystatechange = function() {
    //         if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
    //             if (xhr.responseText && xhr.responseText !== "[]") {
    //                 var response = JSON.parse(xhr.responseText);
    //                 ypmUserName = "你好， " + response.profile.nickname;
    //                 ypmCreateDays.text = "您已加入云村: " + response.createDays + "天";
    //                 ypmSongsListened.text = "总计听歌:" + response.listenSongs + "首";
    //                 ypmFollowed.text = "粉丝: " + response.profile.followeds;
    //                 ypmFollow.text =  "关注: " + response.profile.follows;
    //             }
    //         }
    //     };
    //     xhr.send();
    // }
}
