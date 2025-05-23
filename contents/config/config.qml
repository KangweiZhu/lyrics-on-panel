import QtQuick 2.0
import org.kde.plasma.configuration 2.0

// will create two tabs on the side-view of the settings page.
// Assigning id to ConfigCategory will cause error and lead these tabs probably not going to show up.
ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }

    // ConfigCategory {
    //     name: i18n("Changelog & Tutorials")
    //     icon: "note"
    //     source: "notification.qml"
    // }

    // ConfigCategory {
    //     name: i18n("Upload Lyrics")
    //     icon: "note"
    //     source: "lyricUpload.qml"
    // }
}