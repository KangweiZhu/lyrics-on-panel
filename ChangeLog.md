# Change Log
----
## [1.1] Deprecated
> Not usable version for spotify users. But it will be still able to download at the File(Archived) section of this page https://www.pling.com/p/2148373.


## [1.1 & 1.2] 05/28/2024 BRING THIS WIDGET BACK TO LIVE IN PLASMA6!
### Key Points
1. Usable version. Apologize for uploading the previous broken version.
2. Fixed the issue with failing to display lyrics from Spotify.
3. Refactored the logic for displaying lyrics and removed unnecessary code.




## [1.3] 05/29/2024 Major Bug Fix, Improve Accuracy.
### Key Points
1. Removed the Developer-note section in the configuration page and added a Changelog & tutorial section.
2. Now, if you switch from YesPlayMusic mode to Spotify mode, we will first pause the currently playing music from YesPlayMusic. Then, you need to manually open Spotify and click the play (resume) button. Vice versa.
3. Fixed the problem where lyrics from Spotify would still appear even when the mode is switched to YesPlayMusic.
4. Now you can control the width of this widget on the configuration page.



## [1.4] 05/23/2025 Final Pure-QML Edition
> Currently I decide not actively make any feature update for the **current pure-QML version** of this KDE Plasma Widget. However, bug fixes will still be maintained. Also, I may consider working on feature requests listed in the issues section if they are both feasible and valuable. If a pull request adheres to the existing design principles, I will merge it as soon as possible.


I am planning to make a python backend for lyrics fetching and for more advanced features e.g,. Star/Like the current playing music through making a request towards those online streaming platform. The main reason why I am giveup writting backend through pure-QML or QML + QT is simply because QML itself cannot make modern HTTP requests, and using C++ to build a 'compromised' Network QML Plugin under KFrameworks seems really stupid and causing extra time.

In the upcoming release(temporarily call as lyrics-on-panel6 v2), users can:

* Still able to download this widget from KDE / Pling.

* The widget is by default, no difference with that of current version. But, user could select and enable a **python backend** in the configuration page. User then will need to download the python script from certain Repo, and running it at backend(TBD, maybe a login item, or a system service, or both). 

### Key changes
1. The panel background is configurably transparent now. ([benchile55](https://github.com/KangweiZhu/lyrics-on-panel/issues/8))
2. The default text("check developer's note") is now removed. ([ShayBox](https://github.com/KangweiZhu/lyrics-on-panel/issues/9))
3. When there is no media playing. The entire widgets is configurably to be invisible. PR by: ([uiYzzi](https://github.com/KangweiZhu/lyrics-on-panel/pull/6))
4. Milliseconds are now included in lyric timestamp parsing (previously only minutes and seconds were parsed from LRC files).
5. Now Spotify / YesPlayMusic mode will correctly display the current track's title and artists(if there are) when lyrics are not found.
6. Now, in Spotify / Compatible(now called as Global) mode, the widget will correctly handle multiple results for the same song returned by querying LrcLib one time, and only pick the one that contains syncedLyrics.
7. The widgets is supporting **LX-Music Mode** Now! ([ChouYih](https://github.com/KangweiZhu/lyrics-on-panel/issues/7))
8. The Compatible mode has been fixed and renamed to **Global mode**. Users should use global mode unless unexpected behavior happened and a switch is needed.
9. Spotify White icon is created now. 

> In Global mode, playback control icons are always interactable regardless of the currently active media source.

This differs from app-specific modes (e.g., Spotify mode or YesPlayMusic mode), where — if multiple media apps are active and the currently playing media source (as reported by the QML Mpris2Source object) does not match the selected mode — the playback icons will be disabled, even if music is playing from the selected mode. This is a defect in Plasma6, as KDE devs haven't implemented the Mpris.MultiplexerModel.





