import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami
import org.kde.kquickcontrols 2.0 as KQControls
import org.kde.plasma.core 2.0 as PlasmaCore
import QtQuick.Layouts 1.0 as QQLayouts

Kirigami.FormLayout {
    id: generalPage
    signal configurationChanged

    property alias cfg_yesPlayMusicChecked: yesPlayMusicPropriataryRadioButton.checked 
    property alias cfg_spotifyChecked: spotifyPropriataryRadioButton.checked   
    property alias cfg_compatibleModeChecked: compatibleModeRadioButton.checked
    property alias cfg_lyricTextSize: lyricTextSizeSpinBox.value 
    property alias cfg_lyricTextColor: lyricTextColorButton.color
    property alias cfg_lyricTextBold: boldButton.checked   
    property alias cfg_lyricTextItalic: italicButton.checked 
    property alias cfg_lyricTextVerticalOffset: lyricTextVerticalOffsetSpinBox.value
    property alias cfg_mediaControllSpacing: mediaControllSpacingSpinBox.value
    property alias cfg_mediaControllItemSize: mediaControllItemSizeSpinBox.value
    property alias cfg_mediaControllItemVerticalOffset: mediaControllItemVerticalOffsetSpinBox.value
    property alias cfg_whiteMediaControlIconsChecked: whiteMediaControlIconsChecked.checked
    property alias cfg_preferedWidgetWidth: preferedWidgetWidthTextField.text
    property alias cfg_hideItemWhenNoControlChecked: hideItemWhenNoControlChecked.checked

    QQC2.RadioButton {
        id: yesPlayMusicPropriataryRadioButton
        Kirigami.FormData.label: i18n("Modes: ")
        text: i18n("YesPlayMusic(YPM)")
    }

    QQC2.RadioButton {
        id: spotifyPropriataryRadioButton
        text: i18n("Spotify")
    }

    QQC2.RadioButton {
        id: compatibleModeRadioButton
        text: i18n("Global (currently broken)")
    }

    QQC2.SpinBox {
        id: lyricTextSizeSpinBox
        Kirigami.FormData.label: i18n("Lyric text size: ")
    }

    QQC2.SpinBox {
        id: lyricTextVerticalOffsetSpinBox
        Kirigami.FormData.label: i18n("Lyric text vertical offset: ")
    }

    QQC2.SpinBox {
        id: mediaControllSpacingSpinBox
        Kirigami.FormData.label: i18n("Media control items spacing: ")
    }

    QQC2.SpinBox {
        id: mediaControllItemSizeSpinBox
        Kirigami.FormData.label: i18n("Media control items size: ")
    }

    QQC2.SpinBox {
        id: mediaControllItemVerticalOffsetSpinBox
        Kirigami.FormData.label: i18n("Media control items vertical offset: ")
    }
    
    QQLayouts.RowLayout {
        Kirigami.FormData.label: i18n("Lyric text color: ")

        KQControls.ColorButton {
            id: lyricTextColorButton
        }

        QQC2.Button {
            id: boldButton
            QQC2.ToolTip {
                text: i18n("Bold text")
            }
            icon.name: "format-text-bold"
            checkable: true
        }

        QQC2.Button {
            id: italicButton
            QQC2.ToolTip {
                text: i18n("Italic text")
            }
            icon.name: "format-text-italic"
            checkable: true
        }
    }

    QQC2.CheckBox {
        id: whiteMediaControlIconsChecked
        Kirigami.FormData.label: i18n("White Media Control Icons: ")
        checkable: true
    }

    QQC2.TextField {
        id: preferedWidgetWidthTextField
        Kirigami.FormData.label: i18n("Prefered Widget Width: ")
    }

    QQC2.CheckBox {
        id: hideItemWhenNoControlChecked
        Kirigami.FormData.label: i18n("Hide Item When No Media Control: ")
        checkable: true
    }
    // trackName	true	string	Title of the track
    // artistName	true	string	Track's artist name
    // albumName	true	string	Track's album name
    // duration	true	number	Track's duration
    // plainLyrics	true	string	Plain lyrics for the track
    // syncedLyrics	true	string	Synchronized lyrics for the track
}   
