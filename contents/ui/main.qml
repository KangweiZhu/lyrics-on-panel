import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 2.0 as PlasmaComponents

Item { 
    // connect to mpris2 source
    PlasmaCore.DataSource {
        id: mpris2Source
        engine: "mpris2"
        connectedSources: sources
        interval: 1 //how rapid it is.
    
        onConnectedSourcesChanged: {
            currentMediaYPMId = "";
            previousMediaTitle = "";
            previousMediaArtists = ""; 
            prevNonEmptyLyric = "";
            previousLrcId = "";
            queryFailed = false;
        }

        // triggered when there is a change in data. Prefect place for debugging
        onDataChanged: {
            
        }
    }

    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation // Otherwise it will only display your icon declared in the metadata.json file
    Layout.preferredWidth: 700;
    Layout.preferredHeight: lyricText.contentHeight;

    width: 700;
    height: lyricText.contentHeight;

    Text {
        id: lyricText
        text: "Please open the configuration of this widget and read the developer's note!"
        color: config_lyricTextColor
        font.pixelSize: config_lyricTextSize
        font.bold: config_lyricTextBold
        font.italic: config_lyricTextItalic
        //wrapMode: Text.wrap
        anchors.right: parent.right
        anchors.rightMargin: 6 * (config_mediaControllItemSize + config_mediaControllSpacing)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: config_lyricTextVerticalOffset
    }

    Item {
        id: iconsContainer
        anchors.right: parent.right
        anchors.rightMargin: 1 //10
        anchors.verticalCenter: parent.verticalCenter
        width: 5 * config_mediaControllItemSize + 4 * config_mediaControllSpacing // 5 icons + 4 spacings
        height: config_mediaControllItemSize
        anchors.verticalCenterOffset: config_mediaControllItemVerticalOffset

        Image {
            source: backwardIcon
            sourceSize.width: config_mediaControllItemSize //不能用width, 锯齿太严重，直接控制图片渲染svg的大小
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
            source: (mpris2Source && mpris2Source.data[mode] && mpris2Source.data[mode].PlaybackStatus === "Playing") ? pauseIcon : playIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: config_mediaControllItemSize + config_mediaControllSpacing
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (mpris2Source && mpris2Source.data[mode] && mpris2Source.data[mode].PlaybackStatus === "Playing") {
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
            source: config_yesPlayMusicChecked ? cloudMusicIcon : spotifyIcon
            sourceSize.width: config_mediaControllItemSize
            sourceSize.height: config_mediaControllItemSize
            anchors.left: parent.left
            anchors.leftMargin: 4 * (config_mediaControllItemSize + config_mediaControllSpacing)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Timer {
        id: schedulerTimer
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (config_compatibleModeChecked || config_spotifyChecked) {
                yesPlayMusicTimer.stop();
                compatibleModeTimer.start();
            } else {
                compatibleModeTimer.stop();
                yesPlayMusicTimer.start();
            } 
        }
    }

    Timer {
        id: yesPlayMusicTimer
        interval: 500
        running: false
        repeat: true
        onTriggered: {
            compatibleModeTimer.stop();
            if (currentMediaArtists === "No artists" && currentMediaTitle === "No title") {
                lyricText.text = "";
                lyricsWTimes.clear();
            } else {
                fetchMediaIdYPM();  
            }
        }
    }

    // compatible mode timer
    Timer {
        id: compatibleModeTimer
        interval: 500
        running: false
        repeat: true
        onTriggered: {
            if (currentMediaArtists === "No artists" && currentMediaTitle === "No title") {
                lyricText.text = "";
                lyricsWTimes.clear();
            } else {
                fetchLyricsCompatibleMode();
            }
        }
    }

    // List/Map that storing [{timestamp: xxx, lyric: xxx}, {timestamp: xxx, lyric: xxx}, {timestamp: xxx, lyric: xxx}]
    ListModel {
        id: lyricsWTimes
    }

    // Global constant
    readonly property string ypm_base_url: "http://localhost:27232"
    readonly property string lrclib_base_url: "https://lrclib.net"

    // ui variables
    property string backwardIcon: "../assets/media-backward.svg"
    property string pauseIcon: "../assets/media-pause.svg"
    property string forwardIcon: "../assets/media-forward.svg"
    property string likeIcon: "../assets/media-like.svg"
    property string likedIcon: "../assets/media-liked.svg"
    property string cloudMusicIcon: "../assets/netease-cloud-music.svg"
    property string spotifyIcon: "../assets/spotify.svg"
    property string playIcon: "../assets/media-play.svg"
    property bool liked: false;

    // config page variable
    property bool config_yesPlayMusicChecked: Plasmoid.configuration.yesPlayMusicChecked;
    property bool config_spotifyChecked: Plasmoid.configuration.spotifyChecked;
    property bool config_compatibleModeChecked: Plasmoid.configuration.compatibleModeChecked;
    property int config_lyricTextSize: Plasmoid.configuration.lyricTextSize;
    property string config_lyricTextColor: Plasmoid.configuration.lyricTextColor;
    property bool config_lyricTextBold: Plasmoid.configuration.lyricTextBold;
    property bool config_lyricTextItalic: Plasmoid.configuration.lyricTextItalic;
    property int config_mediaControllSpacing: Plasmoid.configuration.mediaControllSpacing
    property int config_mediaControllItemSize: Plasmoid.configuration.mediaControllItemSize
    property int config_mediaControllItemVerticalOffset: Plasmoid.configuration.mediaControllItemVerticalOffset;
    property int config_lyricTextVerticalOffset: Plasmoid.configuration.lyricTextVerticalOffset

    //Other Media Player's mpris2 data
    property var compatibleMetaData: mpris2Source ? mpris2Source.data[mode].Metadata : undefined
    property var compatibleData: mpris2Source.data[mode]
    property int compatibleSongTimeMS:compatibleData ? Math.floor(compatibleData.Position / 1000) : -1

    //YesPlayMusic only, don't be misleaded. We can use ypm_base_url + /api/currentMediaYPMId to get lyrics of the current playing song, then upload it to lrclib
    property string currentMediaYPMId: ""

    //Use to search the next row of lyric in lyricsWTimes
    property int currentLyricIndex: 0

    // variableeee
    property real currentSongTime: 0
    property string previousMediaTitle: ""
    property string previousMediaArtists: "" 
    property string prevNonEmptyLyric: ""
    property string previousLrcId: ""
    property string previousGlobalLrc: ""
    property bool queryFailed: false;
    property real previousSongTimeMS: 0
    property var globalLyrics;

    // lyric display mode
    // yesplaymusic: only yesplaymusic's lyric
    // spotify: only spotify's lyric
    // multiplex: global mode, depend on the current playing media. (Also priority dependent).
    property string mode: {
        if (config_yesPlayMusicChecked) { //[BUG FIXED]动态更新源，解决 多个媒体源存在于datasource时，yesplaymusic退出后重进，datasource没法更新的问题。spoity依旧unfixed.都是客户端自身的缺陷。
            return mpris2Source.data["@multiplex"].Identity === "YesPlayMusic" ? "@multiplex" : "yesplaymusic"; 
        } 
        if (config_spotifyChecked) {
            return "spotify"; 
        }
        if (config_compatibleModeChecked) {
            return "@multiplex";
        }
        return "@multiplex";
    }

    // title of current media
    property string currentMediaTitle: {
        if (compatibleData && compatibleMetaData["xesam:title"]) {
            return compatibleMetaData["xesam:title"];
        } else {
            return "No title";
        }
    }

    // artist of current media
    property string currentMediaArtists: {
        if (compatibleData && compatibleMetaData["xesam:artist"]) {
            return compatibleMetaData["xesam:artist"].toString();
        } else {
            return "No artists";
        }
    }

    // album name of current media
    property string currentMediaAlbum: {
        if (compatibleData && compatibleMetaData["xesam:album"]) {
            return compatibleMetaData["xesam:album"];
        } else {
            return "No Album";
        }
    }

    // construct the lrclib's request url
    property string lrcQueryUrl: {
        if (queryFailed) { // 如果失败了就用歌名做一次模糊查询。lrclib只支持模糊查询一个field.所以只能专辑|歌手名|歌名选一个， 很明显歌名的结果最准确。
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
            return "This song doesn't have any lyric";
        }
    }

    // [Feature haven't been implemented]
    // Case: When we are unable to find the correspond lyric via lrclib api while we are listening to the music from YESPLAYMUSIC(YPM). 
    // Then what we gonna do is to attempt to fetch the lyric from the "YPM lyric api" which is exposed to our localhost.
    // Then if we indeed find the correspond lyric, we will first post this lyric to liclib. So everyone later on will be able to 
    // get the lyric of this song once playing this musik at any media streaming platform. (Similar to p2p underlying principles)   
    // This function should be rarely called since it is a very edge case(Iterally speaking lyrics for every popular song have already been inside lrclib), so we don't care about the performance.
    // We should be careful when doing this since we don't want to ruin lrclib database.
    function isMediaFromYPM() {
        var ypmData = mpris2Source && mpris2Source.data["yesplaymusic"];
        var multiplexData = mpris2Source && mpris2Source.multiplexSourceKey;

        if (ypmData && multiplexData &&
            multiplexData.Identity === "YesPlayMusic" &&
            multiplexData["Source Name"] === "yesplaymusic" &&
            ypmData.PlaybackStatus === "Playing" &&
            multiplexData.PlaybackStatus === "Playing" &&
            currentMediaTitle === ypmData.Metadata["xesam:title"]) {
            //fetchMediaIdYPM();
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
                    if (response && response.currentTrack && response.currentTrack.name === currentMediaTitle && (previousMediaArtists !== currentMediaArtists || previousMediaTitle !== currentMediaTitle)) {
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
                if (response && response.lrc && response.lrc.lyric) {
                    lyricsWTimes.clear();
                    parseLyric(response.lrc.lyric);
                    //parseAndUpload(response.lrc.lyric);
                }
            }
        };
        xhr.send();
    }

    //[Feature haven't been implemented]
    function parseAndUpload(ypmLrc) {
        console.log("Ypm Lrc", ypmLrc);
    }

    function likeMusicYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/api/like" + "?id=");
    }

    // parse the lyric
    // [["[00:26.64] first row of lyric\n"]], ["[00:29.70] second row of lyric\n]"],etc...]
    function parseLyric(lyrics) {
        var lrcList = lyrics.split("\n");
        for (var i = 0; i < lrcList.length; i++) {
            var lyricPerRowWTime = lrcList[i].split("]");
            if (lyricPerRowWTime.length > 1) {
                var timestamp = parseTime(lyricPerRowWTime[0].replace("[", "").trim());
                var lyricPerRow = lyricPerRowWTime[1].trim();
                lyricsWTimes.append({time: timestamp, lyric: lyricPerRow});
            }
        }
        startLyricDisplayTimer();
    }

    function fetchLyricsCompatibleMode() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", lrcQueryUrl);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                if ((currentMediaTitle !== "Advertisement") && (previousMediaArtists !== currentMediaArtists || previousMediaTitle !== currentMediaTitle)) { //Advertisement
                    if (!xhr.responseText || xhr.responseText === "[]") {
                        queryFailed = true;
                        previousLrcId = Number.MIN_VALUE;
                        lyricsWTimes.clear();
                        lyricText.text = lrc_not_exists;
                    } else {
                        var response = JSON.parse(xhr.responseText)
                        queryFailed = false;
                        if (response && response.length > 0 && previousLrcId !== response[0].id.toString()) { //会出现 Spotify传给Mpris的歌曲名 与 lrclib中的歌曲名不一样的情况，改用id判断
                            lyricsWTimes.clear();
                            previousMediaTitle = currentMediaTitle;
                            previousMediaArtists = currentMediaArtists;
                            previousLrcId = response[0].id.toString();
                            parseLyric(response[0].syncedLyrics);
                        } else {
                            lyricsWTimes.clear();
                            lyricText.text = lrc_not_exists;
                        }
                    }
                }      
            }
        };
        xhr.send();
    }

    // parse time, ignore miliseconds
    function parseTime(timeString) {
        var parts = timeString.split(":");
        var minutes = parseInt(parts[0], 10);
        var seconds = parseFloat(parts[1]);
        return minutes * 60 + seconds;
    }

    // start lyric timer
    function startLyricDisplayTimer() {
        if (!lyricDisplayTimer.running) {
            lyricDisplayTimer.start();
        }
    }

    function previous() {
        serviceOps("Previous")
    }

    function play() {
        serviceOps("Play")
    }

    function pause() {
        serviceOps("Pause")
    }

    function next() {
        serviceOps("Next")
    }

    function serviceOps(ops) {
        var service = mpris2Source.serviceForSource(mode);
        var operation = service.operationDescription(ops);
        service.startOperationCall(operation);
    }

    Timer {
        id: lyricDisplayTimer
        interval: 1
        running: true
        repeat: true
        onTriggered: { 
            if (currentMediaTitle === "Advertisement") { //aim to solve Spotify non-premium bug report
                lyricText.text = currentMediaTitle;
            } else {
                currentSongTime = compatibleSongTimeMS / 1000;
                previousSongTimeMS = compatibleSongTimeMS;
                for (let i = 0; i < lyricsWTimes.count; i++) {
                    if (lyricsWTimes.get(i).time >= currentSongTime) {
                        currentLyricIndex = i > 0 ? i - 1 : 0;
                        if (lyricsWTimes.get(currentLyricIndex).lyric === "" || !lyricsWTimes.get(currentLyricIndex).lyric) {
                            lyricText.text = prevNonEmptyLyric;
                        } else {
                            var lyric = lyricsWTimes.get(currentLyricIndex).lyric;
                            lyricText.text = lyric;
                            prevNonEmptyLyric = lyric;
                        }
                        break;
                    }
                }
            }
        }
    }
}
