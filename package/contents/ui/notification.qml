import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    id: generalPage

    Text {
        id: notificationText
        text: "[Beta Version] Please regularly check this config page and kde store to see if there is any \nfeature update or fix. You can find the link of set up tutorials on github page"
        color: "red"
    }

    //[Note to YesPlayMusic Users only]: Please close Network Global Proxy and use Proxy with Rules. \n YPM has knowing defects for handling proxy and will likely to cause this widget unable to fetch lyric from YPM localhost api.:"

    Text {
        id: notificationText2
        text: "[Note to YesPlayMusic Users only]: Please close Network Global Proxy and use Proxy with Rules.\nYPM has knowing defects for handling proxy and will likely to cause this widget unable to \nfetch lyric from YPM localhost api.:"
        color: "red"
    }

    Text {
        id: notificationText3
        text: "If you encounter any bugs, there are two ways to reset this widget."
    }

    Text {
        id: notificationText4
        text: "1. in terminal: enter  plasmashell --replace"
    }

    Text {
        id: notificationText5
        text: "2. Right click this widget's  spotify/yesplaymusic icon,  open this widget's configuration, choose another mode, and then choose back."
    }

    Text {
        id: notificationText6
        text: "If you find this widget useful, please give it a thumbs up or star my GitHub repository! Your support is my biggest motivation to maintain this widget! If you wish to report bugs or suggest new features for this widget, feel free to post a comment on the KDE store or submit an issue on GitHub."
    }

}