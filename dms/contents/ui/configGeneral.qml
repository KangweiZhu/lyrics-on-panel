import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "lyricsOnPanel"

    StyledText {
        width: parent.width
        text: "Lyrics on Panel"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Display lyrics and media controls in the bar"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // Player Selection
    SelectionSetting {
        settingKey: "playerMode"
        label: "Player Mode"
        description: "Select which player's lyric to show"
        options: [
            { label: "Global Mode", value: "global" },
            { label: "YesPlayMusic", value: "yesplaymusic" },
            { label: "Spotify", value: "spotify" },
            { label: "LX Music", value: "lxmusic" }
        ]
        defaultValue: "global"
    }

    // Text Settings
    StyledText {
        width: parent.width
        text: "Lyric Text"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    SliderSetting {
        settingKey: "lyricTextSize"
        label: "Lyric text size"
        defaultValue: 12
        minimum: 1
        maximum: 24
    }

    SliderSetting {
        settingKey: "lyricTextVerticalOffset"
        label: "Lyric text vertical offset"
        defaultValue: 1
        minimum: -10
        maximum: 10
    }

    ColorSetting {
        settingKey: "lyricTextColor"
        label: "Lyric text color"
        defaultValue: "#ffffff"
    }

    ToggleSetting {
        settingKey: "lyricTextBold"
        label: "Bold text"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "lyricTextItalic"
        label: "Italic text"
        defaultValue: false
    }

    // Media Control Settings
    StyledText {
        width: parent.width
        text: "Media Controls"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    SliderSetting {
        settingKey: "mediaControllSpacing"
        label: "Media control items spacing"
        defaultValue: 8
        minimum: 1
        maximum: 20
    }

    SliderSetting {
        settingKey: "mediaControllItemSize"
        label: "Media control items size"
        defaultValue: 12
        minimum: 1
        maximum: 32
    }

    SliderSetting {
        settingKey: "mediaControllItemVerticalOffset"
        label: "Media control items vertical offset"
        defaultValue: 0
        minimum: -10
        maximum: 10
    }

    ToggleSetting {
        settingKey: "whiteMediaControlIconsChecked"
        label: "White Media Control Icons"
        defaultValue: true
    }

    // Widget Settings
    StyledText {
        width: parent.width
        text: "Widget"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StringSetting {
        settingKey: "preferedWidgetWidth"
        label: "Prefered Widget Width"
        placeholder: "550"
        defaultValue: "550"
    }

    ToggleSetting {
        settingKey: "hideItemWhenNoControlChecked"
        label: "Hide Item When No Media Control"
        defaultValue: true
    }

    StringSetting {
        settingKey: "lxMusicPort"
        label: "LX Music Local Port"
        placeholder: "23330"
        defaultValue: "23330"
    }
}
