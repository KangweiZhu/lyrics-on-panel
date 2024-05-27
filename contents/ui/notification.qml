import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    id: generalPage

    Text {
        id: patch-note
        text: "[v1.1.3]"
        color: "red"
    }

    Text {
        id: notificationText
        text: "This widget is only for the Plasma6 environment. And hence will not be avilable for Plasma5. If you are in Plasma5, please search lyric-on-panel-plasma5\n\n\n"
        color: "red"
    }

    //[Note to YesPlayMusic Users only]: Please close Network Global Proxy and use Proxy with Rules. \n YPM has knowing defects for handling proxy and will likely to cause this widget unable to fetch lyric from YPM localhost api.:"

    Text {
        id: notificationText2
        text: "[Note to YesPlayMusic Users only]: Please close Network Global Proxy and use Proxy with Rules.YPM has knowing defects for handling proxy and will likely to cause this widget unable to fetch lyric from YPM localhost api.\n\n\n"
        color: "red"
    }

    Text {
        id: notificationText3
        text: "If you encounter any bugs, there are three ways to reset this widget.\n\n\n"
    }

    Text {
        id: notificationText4
        text: "                 1. in terminal: enter  plasmashell --replace\n\n\n"
    }

    Text {
        id: notificationText5
        text: "                 2. Right click this widget's  spotify/yesplaymusic icon,  open this widget's configuration, switch to another mode, and then switch back.\n\n\n"
    }

    Text {
        id: notificationText5
        text: "                 3. Remove this widget from your panel, and then add it back.\n\n\n"
    }

    Text {
        id: notificationText6
        text: "If you find this widget useful, please give it a thumbs up and star my GitHub repository! If you wish to report bugs or suggest new features for this widget, feel free to post a comment on the KDE store or submit an issue on GitHub.\n\n\n"
    }
}
