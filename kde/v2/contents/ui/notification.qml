import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    id: generalPage

    Text {
        id: notificationText
        text: "This widget is only for Plasma 6 and is not available for Plasma 5. If you are in Plasma 5, please search for lyric-on-panel-plasma5. \n\nDue to the Plasma API change, I refactored most of the code and only kept the core lyric querying logic. Therefore, please expect some differences in the quality of these two versions of the widgets. \n\nI am currently busy looking for an internship, so my temporary goal is to make this widget usable. I apologize for not having much time to explore the new Plasma API. \nIf time allows, I will try to make the implementation of several logics more elegant and add more functionality by integrating C++ into this widget."
        color: "red"
    }

    Text {
        id: latestVersionUpdate
        text: "\n[v1.1.3] 05/29/2024 - Major Bug Fix, Improve Accuracy.\n\n    1. Removed the Developer-note section in the configuration page and added a Changelog & tutorial section.\n\n    2. Now, if you switch from YesPlayMusic mode to Spotify mode, we will first pause the currently playing music from YesPlayMusic. Then, you need to manually open Spotify and click the play (resume) button. Vice versa.\n\n    3. Fixed the problem where lyrics from Spotify would still appear even when the mode is switched to YesPlayMusic.\n\n    4. Now you can control the width of this widget on the configuration page.\n\n\n"
    }

    Text {
        id: notificationText2
        text: "[Note to YesPlayMusic Users only]: Please close Network Global Proxy and use Proxy with Rules. YPM has known defects for handling proxy and will likely cause this widget to be unable to fetch lyrics from YPM localhost API."
        color: "red"
    }

    Text {
        id: notificationH2
        text: "If you encounter any bugs, feel free to let me know. There are two ways to reset this widget:\n"
    }

    Text {
        id: notificationText3
        text: "         1. In terminal, enter: plasmashell --replace"
    }

    Text {
        id: notificationText4
        text: "         2. Remove this widget from your panel and add it back."
    }

    Text {
        id: notificationText5
        text: "\n\n\nIf you find this widget useful, please give it a thumbs up and star my GitHub repository! For bug reports or feature suggestions, post a comment on the KDE store or submit an issue on GitHub."
    }
}
