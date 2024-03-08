import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    id: generalPage
  
    property alias cfg_yesPlayMusicChecked: yesPlayMusicPropriataryRadioButton.checked
    property alias cfg_spotifyChecked: spotifyPropriataryRadioButton.checked
    property alias cfg_compatibleModeChecked: compatibleModeRadioButton.checked
    property alias cfg_spotifyToken: spotifyToken.text

    Column {
        id: column
        QQC2.RadioButton {
            id: yesPlayMusicPropriataryRadioButton
            Kirigami.FormData.label: i18n("Options:")
            text: i18n("Yes Play Music Propriatary Lyrics Displayer")
            checked: true
        }
        QQC2.RadioButton {
            id: spotifyPropriataryRadioButton
            text: i18n("Spotify Propriatary Lyrics Displayer")
        }
        QQC2.RadioButton {
            id: compatibleModeRadioButton
            text: i18n("Not using Spotify or YPM as your music player? Try this one.")
        }
    }

    QQC2.TextField {
        id: spotifyToken
        Kirigami.FormData.label: i18n("Your Spotify Token:")
        placeholderText: i18n("Placeholder")
    }
}