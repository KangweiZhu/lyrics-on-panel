import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import QtQuick.Window 2.15

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root

    Mpris.Mpris2Model {
        id: mpris2Model
    }


    property string currentMediaTitle: mpris2Model.currentPlayer?.track ?? ""

    property string currentMediaArtists: mpris2Model.currentPlayer?.artist ?? ""

    property string currentMediaAlbum: mpris2Model.currentPlayer?.album ?? ""

    property int playbackStatus: mpris2Model.currentPlayer?.playbackStatus ?? 0

    property bool isPlaying: root.playbackStatus === Mpris.PlaybackStatus.Playing

    property string nameOfCurrentPlayer: mpris2Model.currentPlayer?.objectName ?? ""

    property int position: mpris2Model.currentPlayer?.position ?? 0

    preferredRepresentation: fullRepresentation // Otherwise it will only display your icon declared in the metadata.json file
    Layout.preferredWidth: 0;
    Layout.preferredHeight: lyricText.contentHeight;
    
    width: 0;
    height: lyricText.contentHeight;

    Text {
        id: lyricText
        text: "Please open the configuration of this widget and read the developer's note!"
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
        anchors.rightMargin: 1 //10
        anchors.verticalCenter: parent.verticalCenter
        width: 5 * config_mediaControllItemSize + 4 * config_mediaControllSpacing
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
            source: (playbackStatus == 2) ? pauseIcon : playIcon
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
                    var globalPos = mediaPlayerIcon.mapToGlobal(0, 0);
                    if (config_yesPlayMusicChecked) {
                        menuDialog.x = globalPos.x;
                        menuDialog.y = globalPos.y * 3.5;
                        if (!dialogShowed) { //苯办法了，后面看下怎么判定失去焦点
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

    // variables that are neccessary for ypm like/dislike and others new features in the future
    property bool dialogShowed: false;
    property bool ypmLogined: false;
    property string ypmUserName: "";
    property string ypmCookie: "";//qml不让设。
    property string csrf_token: ""
    property string neteaseID: ""
    property bool currentMusicLiked: false

    PlasmaCore.Dialog {
        id: menuDialog
        visible: false

        // onActiveFocusChanged: {
        //     console.log("entered");
        // } //用mouseArea做试试

        width: column.implicitWidth
        height: column.implicitHeight

        Column {
            spacing: 5

            PlasmaComponents.MenuItem {
                id: userInfoMenuItem
                visible: true
                text: ypmLogined ? ypmUserName : i18n("登录")

                onTriggered: {
                    if (!ypmLogined) {
                       userInfoMenuItem.visible = false;
                       cookieTextField.visible = true;
                    }
                }
            }

            PlasmaComponents.TextField {
                id: cookieTextField
                visible: false
                placeholderText: i18n("Enter your netease id")

                onAccepted: {
                    ypmLogined = true
                    userInfoMenuItem.visible = true;
                    cookieTextField.visible = false;
                    neteaseID = cookieTextField.text
                    //need to add a cookie validation in the future 
                }
            }

            PlasmaComponents.MenuItem {
                id: ypmCreateDays
                visible: true // todo: 可以用ypmLogined做判定，但是有bug。会导致登录后元素显示不全。先这样子吧。
                                //edit: 估计是menuitem默认字体高宽的的问题。有空再搞。
                text: ""
            }

            PlasmaComponents.MenuItem {
                id: ypmSongsListened
                visible: true
                text: ""
            }

            PlasmaComponents.MenuItem {
                id: ypmFollowed
                visible: true
                text: ""
            }

            PlasmaComponents.MenuItem {
                id: ypmFollow
                visible: true
                text: "需要登录"
            }
            
            PlasmaComponents.MenuItem {
                id: logout
                visible: true
                text: "登出" // i18n

                onTriggered: {
                    ypmLogined = false;
                    neteaseID = ""
                    ypmSongsListened.text = ""; //同理，原本是可以三元做的
                    ypmFollowed.text = "";
                    ypmFollow.text = "";
                    ypmCreateDays.text = "";
                }
            }
        }
    }

    Timer {
        id: ypmUserInfoTimer
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            if (ypmLogined) {
                getUserDetail();
            }
        }
    }

    Timer {
        id: schedulerTimer
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            //console.log(JSON.stringify(mpris2Model))
            log();
            if (nameOfPreviousPlayer != nameOfCurrentPlayer) {
                reset();
            }
            if (currentMediaTitle != previousMediaTitle || currentMediaArtists != previousMediaArtists) {
                //console.log("update current media artist and title");
                if (config_compatibleModeChecked || config_spotifyChecked) {
                    isCompatibleLRCFound = false;
                    previousMediaTitle = currentMediaTitle;
                    previousMediaArtists = currentMediaArtists;
                }
                lyricsWTimes.clear();
            }
            nameOfPreviousPlayer = nameOfCurrentPlayer;
            if (nameOfCurrentPlayer === "yesplaymusic") {
                compatibleModeTimer.stop();
                yesPlayMusicTimer.start();
                ypmUserInfoTimer.start();
            } else {
                yesPlayMusicTimer.stop();
                ypmUserInfoTimer.stop();
                compatibleModeTimer.start();
            }
        }
    }

    Timer {
        id: yesPlayMusicTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            compatibleModeTimer.stop();
            if (currentMediaArtists === "" && currentMediaTitle === "") {
                lyricText.text = "";
                lyricsWTimes.clear();
            } else {
                fetchMediaIdYPM();  
            }
        }
    }

    function log() {
        console.log("currentMediaArtists: ", currentMediaArtists);
        console.log("previousMediaArtists: ", previousMediaArtists);
        console.log("currentMediaTitle: ", currentMediaTitle);
        console.log("previousMediaTitle: ", previousMediaTitle);
    }
    
    // compatible mode timer
    Timer {
        id: compatibleModeTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: {
            if ((currentMediaArtists === "" && currentMediaTitle === "") || (currentMediaTitle != previousMediaTitle) || currentMediaArtists != previousMediaArtists) {
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
    property string backwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-backward-white.svg" : "../assets/media-backward.svg"
    property string pauseIcon: config_whiteMediaControlIconsChecked ? "../assets/media-pause-white.svg" : "../assets/media-pause.svg"
    property string forwardIcon: config_whiteMediaControlIconsChecked ? "../assets/media-forward-white.svg" : "../assets/media-forward.svg"
    property string likeIcon: config_whiteMediaControlIconsChecked ? "../assets/media-like-white.svg" : "../assets/media-like.svg"
    property string likedIcon: "../assets/media-liked.svg"
    property string cloudMusicIcon: config_whiteMediaControlIconsChecked ? "../assets/netease-cloud-music-white.svg" : "../assets/netease-cloud-music.svg"
    property string spotifyIcon: config_whiteMediaControlIconsChecked ? "../assets/spotify-white.svg" : "../assets/spotify.svg"
    property string playIcon: config_whiteMediaControlIconsChecked ? "../assets/media-play-white.svg" : "../assets/media-play.svg"
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
    property int config_whiteMediaControlIconsChecked: Plasmoid.configuration.whiteMediaControlIconsChecked;

    //Other Media Player's mpris2 data
    property int compatibleSongTimeMS: {
        if (position == 0) {
            return -1;
        } else {
            return Math.floor(position / 1000);
        }
    }

    //YesPlayMusic only, don't be misleaded. We can use ypm_base_url + /api/currentMediaYPMId to get lyrics of the current playing song, then upload it to lrclib
    property string currentMediaYPMId: ""

    //Use to search the next row of lyric in lyricsWTimes
    property int currentLyricIndex: 0

    // variables
    property real currentSongTime: 0;

    property string previousMediaTitle: "avoidnullfxxx"

    property string previousMediaArtists: "avoidnullfxxx"

    property string prevNonEmptyLyric: ""

    property string previousLrcId: ""

    property string previousGlobalLrc: ""

    property real previousSongTimeMS: -1

    // indicating we need to use the back up fetching strategy
    property bool queryFailed: false;

    property bool isCompatibleLRCFound: false;

    property string nameOfPreviousPlayer: ""

    property string base64Image: ""

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

    // fetch the current media id from yesplaymusic(ypm);
    function fetchMediaIdYPM() {
        console.log("entered");
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
        console.log("entered fetchlyrics cm");
        xhr.open("GET", lrcQueryUrl);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                console.log("Network OK");
                if ((currentMediaTitle !== "Advertisement") && !isCompatibleLRCFound) { //Advertisement
                    console.log("Start parsing fetch result");
                    if (!xhr.responseText || xhr.responseText === "[]") {
                        console.log("failed to get the lyrics");
                        queryFailed = true;
                        previousLrcId = Number.MIN_VALUE;
                        lyricsWTimes.clear();
                        lyricText.text = lrc_not_exists;
                    } else {
                        var response = JSON.parse(xhr.responseText)
                        queryFailed = false;
                        if (response && response.length > 0 && previousLrcId !== response[0].id.toString()) { //会出现 Spotify传给Mpris的歌曲名 与 lrclib中的歌曲名不一样的情况，改用id判断
                            lyricsWTimes.clear();
                            manualCounter = 0;
                            console.log("get the desired lyric");
                            firstTime = true;
                            previousMediaTitle = currentMediaTitle;
                            previousMediaArtists = currentMediaArtists;
                            previousLrcId = response[0].id.toString();
                            isCompatibleLRCFound = true;
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
        if (config_yesPlayMusicChecked) {
            if (!lyricDisplayTimer.running) {
                if (lyricDisplayTimerGG.running) {
                    lyricDisplayTimerGG.stop();
                }
                lyricDisplayTimer.start();
            }
        } else {
            if (!lyricDisplayTimerGG.running) {
                if (lyricDisplayTimer.running) {
                    lyricDisplayTimer.stop();
                }
                lyricDisplayTimerGG.start();
            }
        }

    }

    function previous() {
        mpris2Model.currentPlayer.Previous();
    }

    function play() {
        mpris2Model.currentPlayer.Play();
    }

    function pause() {
        mpris2Model.currentPlayer.Pause();
    }

    function next() {
        mpris2Model.currentPlayer.Next();
    }

    function reset() {
        currentSongTime = 0;
        previousMediaTitle = "";
        previousMediaArtists = "";
        prevNonEmptyLyric = "";
        previousLrcId = "";
        previousGlobalLrc = "";
        queryFailed = false;
        previousSongTimeMS = -1;
        lyricsWTimes.clear();
        firstTime = true;
        manualCounter = 0;
    }

    function getUserDetail() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/api/user/detail?uid=" + neteaseID);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                if (xhr.responseText && xhr.responseText !== "[]") {
                    var response = JSON.parse(xhr.responseText);
                    ypmUserName = "你好， " + response.profile.nickname;
                    ypmCreateDays.text = "您已加入云村: " + response.createDays + "天";
                    ypmSongsListened.text = "总计听歌:" + response.listenSongs + "首";
                    ypmFollowed.text = "粉丝: " + response.profile.followeds;
                    ypmFollow.text =  "关注: " + response.profile.follows;
                }
            }
        };
        xhr.send();
    }

    // its broken due to the datasource issue. not my fault. Apparently both plasma browser integration and spotify haven't implement "Updating the music position" correctly.
    // so right now, only yesplaymusic could update the position corectly.
    Timer {
        id: lyricDisplayTimer
        interval: 1
        running: false
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

    property int manualCounter: 0;
    property bool firstTime: true;
    Timer {
        id: lyricDisplayTimerGG
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            if (currentMediaTitle === "Advertisement") { //aim to solve Spotify non-premium bug report
                lyricText.text = currentMediaTitle;
            } else {
                currentSongTime = compatibleSongTimeMS / 1000;
                //handling the spotify bug
                if (previousSongTimeMS == compatibleSongTimeMS) {
                    if (firstTime) {
                        manualCounter = currentSongTime;
                        firstTime = false;
                    }
                    if (playbackStatus == 2) {
                        manualCounter++;
                    }
                } else {
                    manualCounter = currentSongTime // pause clicked, synced
                }
                previousSongTimeMS = compatibleSongTimeMS;
                for (let i = 0; i < lyricsWTimes.count; i++) {
                    if (lyricsWTimes.get(i).time >= manualCounter) {
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
