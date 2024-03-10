import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami
import org.kde.kquickcontrols 2.0 as KQControls
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQuick.Layouts 1.0 as QQLayouts

Kirigami.FormLayout {
    id: generalPage
  
    property alias cfg_yesPlayMusicChecked: yesPlayMusicPropriataryRadioButton.checked //default false
    property alias cfg_spotifyChecked: spotifyPropriataryRadioButton.checked    // defaylt true
    property alias cfg_compatibleModeChecked: compatibleModeRadioButton.checked // default false
    property alias cfg_lyricTextSize: lyricTextSizeSpinBox.value    //default 13
    property alias cfg_lyricTextColor: lyricTextColorButton.color   //default follow system theme
    property alias cfg_lyricTextBold: boldButton.checked    // default true
    property alias cfg_lyricTextItalic: italicButton.checked //default false

    QQC2.RadioButton {
        id: yesPlayMusicPropriataryRadioButton
        Kirigami.FormData.label: i18n("Modes: ")
        text: i18n("YesPlayMusic(YPM) Only")
    }

    QQC2.RadioButton {
        id: spotifyPropriataryRadioButton
        text: i18n("Spotify Only")
    }

    QQC2.RadioButton {
        id: compatibleModeRadioButton
        text: i18n("Global(Compatible)")
    }

    QQC2.SpinBox {
        id: lyricTextSizeSpinBox
        Kirigami.FormData.label: i18n("Lyric Text Size: ")
    }
    
    QQLayouts.RowLayout {
        Kirigami.FormData.label: i18n("Lyric Text Color: ")

        KQControls.ColorButton {
            id: lyricTextColorButton
        }

        QQC2.Button {
            id: boldButton
            QQC2.ToolTip {
                text: i18n("set text to bold")
            }
            icon.name: "format-text-bold"
            checkable: true
        }

        QQC2.Button {
            id: italicButton
            QQC2.ToolTip {
                text: i18n("set text to Italic")
            }
            icon.name: "format-text-italic"
            checkable: true
        }
    }

    // trackName	true	string	Title of the track
    // artistName	true	string	Track's artist name
    // albumName	true	string	Track's album name
    // duration	true	number	Track's duration
    // plainLyrics	true	string	Plain lyrics for the track
    // syncedLyrics	true	string	Synchronized lyrics for the track
}   