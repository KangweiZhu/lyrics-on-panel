import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.1
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0

Item {
    width: lyricText.contentWidth;
    height: lyricText.contentHeight

    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation // Otherwise it will only display your icon declared in the metadata.json file
    Layout.preferredWidth: lyricText.contentWidth;
    Layout.preferredHeight: lyricText.contentHeight;

    ListModel {
        id: lyricsWTimes
    }

    PlasmaCore.DataSource {
        id: mpris2Source
        engine: "mpris2"
        connectedSources: sources
        readonly property var ypmSourceKey: data["yesplaymusic"]
        readonly property var multiplexSourceKey: data["@multiplex"]
        readonly property var spotifySourceKey: data["spotify"];

        //readonly property var buggySourceKey: data["chromium.instancexx"]
        interval: 1 //how rapid it is.

        // immediately do some ops after connected
        onConnectedSourcesChanged: {
            //solveBug.start();
        }

        // triggered when there is a change in data. Prefect place for debugging
        onDataChanged: {
            //console.log(JSON.stringify(mpris2Source.multiplexSourceKey));
            if (mpris2Source.multiplexSourceKey.Identity === "YesPlayMusic") {
                compatibleModeTimer.stop();
                yesPlayMusicTimer.start();
                if (mpris2Source.ypmSourceKey.PlaybackStatus === "Paused") {
                    yesPlayMusicTimer.stop();
                }
            } else { //compatible mode
                yesPlayMusicTimer.stop();
                compatibleModeTimer.start();   
            }
        }
    }

    readonly property string ypm_base_url: "http://localhost:27232"
    readonly property string lrclib_base_url: "https://lrclib.net"
    
    //YesPlayMusic mpris2 data
    property var ypmMetaData: mpris2Source ? mpris2Source.ypmSourceKey.Metadata : undefined
    property var ypmData: mpris2Source.ypmSourceKey
    property int ypmSongTimeMS: ypmData ? Math.floor(ypmData.Position / 1000) : -1;

    //Other Media Player's mpris2 data
    property var compatibleMetaData: mpris2Source ? mpris2Source.multiplexSourceKey.Metadata : undefined
    property var compatibleData: mpris2Source.multiplexSourceKey
    property int compatibleSongTimeMS:compatibleData ? Math.floor(compatibleData.Position / 1000) : -1

    //YesPlayMusic only, don't be misleaded. We can use ypm_base_url + /api/currentMediaYPMId to get lyrics of the current playing song
    property string currentMediaYPMId: ""

    //Use to search the next row of lyric in lyricsWTimes
    property int currentLyricIndex: 0

    property real currentSongTime: 0
    property string globalLyrics: lrc_not_exists
    property string previousMediaTitle: ""
    property string previousMediaArtists: "" 
    property string prevNonEmptyLyric: ""
    property string previousLrcId: ""
    property bool queryFailed: false;

    // title of current media
    property string currentMediaTitle: {
        if (yesPlayMusicTimer.running) {
            if (ypmMetaData && ypmMetaData["xesam:title"]) {
                return ypmMetaData["xesam:title"];
            } else {
                return i18n("No media playing right now")
            }
        } else {
            if (compatibleData && compatibleMetaData["xesam:title"]) {
                return compatibleMetaData["xesam:title"];
            } else {
                return i18n("No media playing right now")
            }
        }
    }

    // artist of current media
    property string currentMediaArtists: {
        if (yesPlayMusicTimer.running) {
            if (ypmMetaData && ypmMetaData["xesam:artist"]) {
                return ypmMetaData["xesam:artist"].toString();
            } else {
                return i18n("Unknown Artists")
            }
        } else {
            if (compatibleData && compatibleMetaData["xesam:artist"]) {
                return compatibleMetaData["xesam:artist"].toString();
            } else {
                return i18n("Unknown Artists")
            }
        }
    }

    // album name of current media
    property string currentMediaAlbum: {
        if (yesPlayMusicTimer.running) {
            if (ypmMetaData && ypmMetaData["xesam:album"]) {
                return ypmMetaData["xesam:album"];
            } else {
                return i18n("No album name for current media")
            }
        } else {
            if (compatibleData && compatibleMetaData["xesam:album"]) {
                return compatibleMetaData["xesam:album"];
            } else {
                return i18n("No album name for current media")
            }
        }
    }

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
    
    property string lrc_not_exists: {
        if (currentMediaTitle && currentMediaArtists) {
            return currentMediaTitle + " - " + currentMediaArtists;
        } else if (currentMediaTitle && !currentMediaArtists) {
            return currentMediaTitle;
        } else {
            return "This song doesn't have any lyric";
        }
    }

    Timer {
        id: yesPlayMusicTimer
        interval: 500
        running:  false
        repeat: false
        onTriggered: {
            fetchMediaIdYPM();
        }
    }

    Timer {
        id: compatibleModeTimer
        interval: 500
        running: false
        repeat: false
        onTriggered: {
            fetchLyricsCompatibleMode();
        }
    }

    function fetchMediaIdYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/player");
        xhr.onreadystatechange = function() {
            if (xhr.status === 200) {
                if (currentMediaTitle !== previousMediaTitle || currentMediaArtists !== previousMediaArtists) {
                    if (!xhr.responseText) {
                        lyricsWTimes.clear();
                        lyricText.text = lrc_not_exists;
                    } else {
                        var response = JSON.parse(xhr.responseText);
                        if (response && response.currentTrack.name === currentMediaTitle) {
                            lyricsWTimes.clear();
                            previousMediaTitle = currentMediaTitle;
                            previousMediaArtists = currentMediaArtists;
                            currentMediaYPMId = response.currentTrack.id;
                            fetchSyncLyricYPM();
                        }
                    }
                } 
            }
        };
        xhr.send();
    }

    function fetchSyncLyricYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/api/lyric?id=" + currentMediaYPMId);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response && response.lrc && response.lrc.lyric) {
                    globalLyrics = response.lrc.lyric;
                    parseLyric();
                } else {
                    globalLyrics = lrc_not_exists;
                    lyricText.text = globalLyrics;
                }
            }
        };
        xhr.send();
    }

    function parseLyric() {
        var lrcList = globalLyrics.split("\n");
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
            if (xhr.status === 200) {
                if (previousMediaArtists !== currentMediaArtists || previousMediaTitle !== currentMediaTitle) {
                    if (!xhr.responseText || xhr.responseText === "[]") {
                        queryFailed = true;
                        previousLrcId = Number.MIN_VALUE;
                        lyricsWTimes.clear();
                        lyricText.text = lrc_not_exists;
                    } else {
                        var response = JSON.parse(xhr.responseText)
                        queryFailed = false;
                        if (response && response.length > 0 && previousLrcId !== response[0].id.toString()) { //会出现 Spotify传给Mpris的歌曲名 与 lrclib中的歌曲名不一样的情况，改用id判断
                            globalLyrics = response[0].syncedLyrics;
                            previousMediaTitle = currentMediaTitle;
                            previousMediaArtists = currentMediaArtists;
                            previousLrcId = response[0].id.toString();
                            parseLyric();
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

    function parseTime(timeString) {
        var parts = timeString.split(":");
        var minutes = parseInt(parts[0], 10);
        var seconds = parseFloat(parts[1]);
        return minutes * 60 + seconds;
    }

    function startLyricDisplayTimer() {
        if (!lyricDisplayTimer.running) {
            lyricDisplayTimer.start();
        }
    }

    function debugLog() {
        console.log("current track id", currentMediaTitle);
        console.log("current artist", currentMediaArtists);
        console.log("current album name", currentMediaAlbum);
        console.log("previous track id", previousMediaTitle);
        console.log("previous artist", previousMediaArtists);
    }

    /**
        The defect originates from the application build with Electron(Chromium) and will produce sound.

        You will see error msg like  "kde.dataengine.mpris: "org.mpris.MediaPlayer2.chromium.instance15451" has an invalid URL for the mpris:artUrl
        entry of the "Metadata" property" spamming at your terminal

        If you lower down the mpris2 interval, then the spam rate will decrease. But the lyric synchronization accuracy will be lowered

        The Electron app will dispatch a signal with its application name along with an additional signal named like chromium.instanceXXX to mpris2. 
            -The latter signal is redundant, potentially misleading, and carries erroneous information
    */  
    Timer {
        id: solveBug
        repeat: true
        running: false
        interval: 50
        onTriggered: {
            mpris2Source.buggySourceKey.Metadata["mpris:artUrl"] = "https://p2.music.126.net/gppxEmYWJ6TppMuDikrLCQ==/109951169046901248.jpg?param=224y224";
        }
    }

    Text {
        id: lyricText
        text: "[Beta Version] Please regularly check this config page and kde store to see if there is any feature update or fix"
        color: PlasmaCore.Theme.textColor
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }

    Timer {
        id: lyricDisplayTimer
        interval: 1
        running: false
        repeat: true
        onTriggered: {
            if (yesPlayMusicTimer.running) {
                currentSongTime = ypmSongTimeMS / 1000;
            } else {
                currentSongTime = compatibleSongTimeMS / 1000;
            }
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