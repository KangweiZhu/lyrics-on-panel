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
        //readonly property var ypmSourceKey: data["yesplaymusic"]
        readonly property var multiplexSourceKey: data["@multiplex"]
        //readonly property var spotifySourceKey: data["spotify"];
        interval: 1 //how rapid it is.

        // immediately do some ops after connected
        onConnectedSourcesChanged: {
           
        }

        // triggered when there is a change in data. Prefect place for debugging
        onDataChanged: {

        }
    }

    readonly property string ypm_base_url: "http://localhost:27232"
    readonly property string lrclib_base_url: "https://lrclib.net"
    
    //YesPlayMusic mpris2 data
    //property var ypmMetaData: mpris2Source ? mpris2Source.ypmSourceKey.Metadata : undefined
    //property var ypmData: mpris2Source.ypmSourceKey
    //property int ypmSongTimeMS: ypmData ? Math.floor(ypmData.Position / 1000) : -1;

    //Other Media Player's mpris2 data
    property var compatibleMetaData: mpris2Source ? mpris2Source.multiplexSourceKey.Metadata : undefined
    property var compatibleData: mpris2Source.multiplexSourceKey
    property int compatibleSongTimeMS:compatibleData ? Math.floor(compatibleData.Position / 1000) : -1

    //YesPlayMusic only, don't be misleaded. We can use ypm_base_url + /api/currentMediaYPMId to get lyrics of the current playing song, then upload it to lrclib
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
    property int freezeCounter: 0;
    property real previousSongTimeMS: 0
    // title of current media
    property string currentMediaTitle: {
        if (compatibleData && compatibleMetaData["xesam:title"]) {
            return compatibleMetaData["xesam:title"];
        } else {
            return i18n("No media playing right now")
        }
    }

    // artist of current media
    property string currentMediaArtists: {
        if (compatibleData && compatibleMetaData["xesam:artist"]) {
            return compatibleMetaData["xesam:artist"].toString();
        } else {
            return i18n("Unknown Artists")
        }
    }

    // album name of current media
    property string currentMediaAlbum: {
        if (compatibleData && compatibleMetaData["xesam:album"]) {
            return compatibleMetaData["xesam:album"];
        } else {
            return i18n("No album name for current media")
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
        id: compatibleModeTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            debugLog();
            console.log(queryFailed);
            fetchLyricsCompatibleMode();
        }
    }

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

    function fetchMediaIdYPM() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", ypm_base_url + "/player");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                if (xhr.responseText) {
                    var response = JSON.parse(xhr.responseText);
                    if (response && response.currentTrack && response.currentTrack.name === currentMediaTitle) {
                        fetchSyncLyricYPM();
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
                    parseAndUpload(response.lrc.lyric);
                }
            }
        };
        xhr.send();
    }

    function parseAndUpload(ypmLrc) {
        console.log("Ypm Lrc", ypmLrc);
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
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                if ((currentMediaTitle !== "Advertisement") && (previousMediaArtists !== currentMediaArtists || previousMediaTitle !== currentMediaTitle) ) { //Advertisement
                    if (!xhr.responseText || xhr.responseText === "[]") {
                        console.log("entered");
                        queryFailed = true;
                        previousLrcId = Number.MIN_VALUE;
                        lyricsWTimes.clear();
                        lyricText.text = lrc_not_exists;
                        //isMediaFromYPM();
                    } else {
                        var response = JSON.parse(xhr.responseText)
                        queryFailed = false;
                        if (response && response.length > 0 && previousLrcId !== response[0].id.toString()) { //会出现 Spotify传给Mpris的歌曲名 与 lrclib中的歌曲名不一样的情况，改用id判断
                            lyricsWTimes.clear();
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
        running: true
        repeat: true
        onTriggered: { 
            console.log(JSON.stringify(mpris2Source.multiplexSourceKey));
            currentSongTime = compatibleSongTimeMS / 1000;
            previousSongTimeMS = compatibleSongTimeMS;
            //console.log(globalLyrics);
            for (let i = 0; i < lyricsWTimes.count; i++) {
                if (lyricsWTimes.get(i).time >= currentSongTime) {
                    console.log("lyricWTimes", lyricsWTimes.get(i).time);
                    console.log("curentSongTime", currentSongTime)
                    console.log("compatibleSongTimeMS", compatibleSongTimeMS);
                    currentLyricIndex = i > 0 ? i - 1 : 0;
                    console.log("currentLyricIndex", currentLyricIndex);
                    if (lyricsWTimes.get(currentLyricIndex).lyric === "" || !lyricsWTimes.get(currentLyricIndex).lyric) {
                        console.log("entered 1");
                        lyricText.text = prevNonEmptyLyric;
                    } else {
                        console.log("entered 2")
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