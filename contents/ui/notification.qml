import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    id: generalPage

    Text {
        id: notificationText
        text: "[Beta Version] Please regularly check this config page and kde store to see if there is any \nfeature update or fix. [Note to YesPlayMusic Users only]: Please close Network Global Proxy and use Proxy with Rules. \n YPM has knowing defects for handling proxy and will likely to cause this widget unable to fetch lyric from YPM localhost api.:"
        color: "red"
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
}