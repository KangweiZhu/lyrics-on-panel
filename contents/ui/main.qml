import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import QtQuick.Window 2.15

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.mpris as Mpris


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
    Plasmoid.status: mpris2Model.currentPlayer?.canControl || !config_hideItemWhenNoControlChecked ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus;

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
            source: config_yesPlayMusicChecked ? cloudMusicIcon : spotifyIcon
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
    property string cloudMusicIcon: config_whiteMediaControlIconsChecked ? "../assets/netease-cloud-music-white.svg" : "../assets/netease-cloud-music.svg"
    property string spotifyIcon: config_whiteMediaControlIconsChecked ? "../assets/spotify-white.svg" : "../assets/spotify.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"
    property bool liked: false;

    // Applet UI behavior configuration
    property bool config_yesPlayMusicChecked: Plasmoid.configuration.yesPlayMusicChecked;
    property bool config_lxMusicChecked: Plasmoid.configuration.lxMusicChecked;
    property bool config_spotifyChecked: Plasmoid.configuration.spotifyChecked;
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
        running: true
        repeat: true
        onTriggered: {
            mpris2Model.currentPlayer.updatePosition();
        }
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
                    1. mpris 里面，当前播放音乐的title和artists都为空, 则尝试重置。
                    2. mpris 里面，当前播放器和之前的播放器不一样，就重置。
                    3. 设置 里面， 当前播放器和之前设置的播放器不一样(即更新了当前追踪的播放器),就重置。
                    4. 前后歌名，前后歌手不一样，重置。
                
                重置后，重新判断当前预期的播放器是哪个。并且开启对应的timer（线程）
            */ 
            if (
                !currentMediaTitle && !currentMediaArtists ||
                mpris2PreviousPlayerIdentity != mpris2CurrentPlayerIdentity ||
                prevExpectedPlayerIdentity != currExpectedPlayerIdentity ||
                currentMediaTitle != previousMediaTitle || 
                currentMediaArtists != previousMediaArtists
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
                }
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
                if (mpris2CurrentPlayerIdentity === "YesPlayMusic") {
                    // console.log("YPM Timer Triggered");
                    ypmHandler();
                } else if (mpris2CurrentPlayerIdentity === "lx-music-desktop") {
                    // console.log("lx music triggered")
                    lxHandler();
                } else {
                    if (!isCompatibleLRCFound || needFallback) {
                        //console.log("spotify compatible mode triggered")
                        fetchLyricsCompatibleMode();
                    }
                }
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
                    for (let i = 0; i < lyricsWTimes.count; i++) {
                        if (lyricsWTimes.get(i).time >= mprisCurrentPlayingSongTimeMS) {
                            currentLyricIndex = i > 0 ? i - 1 : 0;
                            var currentLWT = lyricsWTimes.get(currentLyricIndex);
                            var currentLyric = currentLWT.lyric;
                            if (!currentLWT || !currentLyric || currentLyric === "" && prevNonEmptyLyric != "") {
                                lyricText.text = prevNonEmptyLyric;
                            } else {
                                lyricText.text = currentLyric;
                                prevNonEmptyLyric = currentLyric;
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    // Global constant
    readonly property string ypm_base_url: "http://localhost:27232"
    readonly property string lxmusic_base_url: {
        return "http://localhost:" + config_lxMusicPort;
    }
    readonly property string lrclib_base_url: "https://lrclib.net"

    // Successfully fetched the lyrics from the yesplaymusic API?
    property bool isYPMLyricFound: false;

    property bool isLXLyricFound: false;

    // Current Media Title (Song's name), default is empty string
    property string currentMediaTitle: mpris2Model.currentPlayer?.track ?? ""

    // Current Media Artists (Song's artist), default is empty string
    property string currentMediaArtists: mpris2Model.currentPlayer?.artist ?? ""

    // Current Media Album (Song's album), default is empty string
    property string currentMediaAlbum: mpris2Model.currentPlayer?.album ?? ""

    // Current Media Playback Status (Song's playback status), default is 0
    property int playbackStatus: mpris2Model.currentPlayer?.playbackStatus ?? -1

    // Retrieve if the current media is playing (Unused)
    property bool isPlaying: root.playbackStatus === Mpris.PlaybackStatus.Playing

    // Retrieve the identity of current music/media player
    // YesPlayMusic Spotify lx-music-desktop xxx
    property string mpris2CurrentPlayerIdentity: mpris2Model.currentPlayer?.identity ?? ""
        
    // Retrieve the current media position (in microseconds)
    property int position: mpris2Model.currentPlayer?.position ?? 0

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
    property int mprisCurrentPlayingSongTimeMS: {
        if (position == 0) {
            return -1;
        } else {
            return position;
        }
    }

    // YesPlayMusic only, don't get misleaded. We can use http://localhost:27232/api/currentMediaYPMId to get lyrics of the current playing song, then upload it to lrclib
    property string currentMediaYPMId: ""

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
        if (config_yesPlayMusicChecked) {
            return "YesPlayMusic";
        } else if (config_spotifyChecked) {
            return "Spotify";
        } else if (config_lxMusicChecked) {
            return "lx-music-desktop";
        } else {
            return "compatible";
        }
    }

    // Construct the lrclib's request url
    property string lrcQueryUrl: {
        if (needFallback) { // 如果失败了就用歌名做一次模糊查询。lrclib只支持模糊查询一个field.所以只能专辑|歌手名|歌名选一个， 很明显歌名的结果最准确。
            return lrclib_base_url + "/api/search" + "?track_name=" + encodeURIComponent(currentMediaTitle) + 
                  "&artist_name=" + encodeURIComponent(currentMediaArtists) + "&album_name=" + encodeURIComponent(currentMediaAlbum) + "&q=" 
                  + encodeURIComponent(currentMediaTitle);
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
            return "This song doesn't contain any lyric/title/artist.";
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
        if (currentMediaTitle === "Advertisement" || isCompatibleLRCFound) {
            return;
        }

        var xhr = new XMLHttpRequest();
        xhr.open("GET", lrcQueryUrl);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                if (!xhr.responseText || xhr.responseText === "[]") {
                    needFallback = true;
                    previousLrcId = Number.MIN_VALUE;
                    lyricsWTimes.clear();
                    lyricText.text = lrc_not_exists;
                } else {
                    var response = JSON.parse(xhr.responseText);

                    /**
                        Fix: LrcLib might return multiple result for the same [track_name, artist_name, album_name], some of the result doesn't contain the syncedLyrics field.

                        An example could be as listed below
                        [
                            {"id":13957,"name":"Jar Of Love","trackName":"Jar Of Love","artistName":"Wanting","albumName":"Everything In The World", xxx},
                            {"id":18131162,"name":"Jar Of Love","trackName":"Jar Of Love","artistName":"Wanting 曲婉婷","albumName":"Everything In The World","duration":229.026667, xxxx}
                        ]
                    */
                    for (var i = 0; i < response.length; i++) {
                        var responseItem = response[i]
                        if (previousLrcId !== responseItem.id.toString()) {
                            if (responseItem.syncedLyrics) {
                                reset()
                                previousLrcId = responseItem.id.toString();
                                isCompatibleLRCFound = true;
                                parseLyric(responseItem.syncedLyrics);
                                break;
                            } 
                        }
                    }

                    // If reached here, it means the lrc file is just broken or doesn't follow the standard format. No need to fallback again since actually we can retrieve it. 
                    isCompatibleLRCFound = true;
                    lyricText.text = lrc_not_exists;
                }
            }
        };
        xhr.send();
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
        if (!isWrongPlayer()) {
           mpris2Model.currentPlayer.Previous(); 
        }
    }

    function play() {
        if (!isWrongPlayer()) {
           mpris2Model.currentPlayer.Play(); 
        }
    }

    function pause() {
        if (!isWrongPlayer()) {
            mpris2Model.currentPlayer.Pause();
        }
    }

    function next() {
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
        compatibleModeTimer.stop();
        yesPlayMusicTimer.stop();
        lxMusicTimer.stop();
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
