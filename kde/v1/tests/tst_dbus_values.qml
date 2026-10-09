import QtQuick
import QtTest
import org.kde.plasma.workspace.dbus as DBus
import "../contents/ui/DbusValues.js" as DbusValues

TestCase {
    name: "MprisDbusValues"

    property var initialPosition: new DBus.int64(162298000)
    property list<var> refreshedPosition: [new DBus.int64(163298000)]
    property var metadata: ({"mpris:trackid": new DBus.objectPath("/com/163/music/2111993059"),
                             "xesam:title": new DBus.string("Test song")})
    property list<var> refreshedMetadata: [metadata]

    function test_metadata_read_and_refresh() {
        var inputs = [metadata, new DBus.dict(metadata), refreshedMetadata];
        for (var i = 0; i < inputs.length; i++) {
            var result = DbusValues.dictionary(inputs[i]);
            compare(String(result["mpris:trackid"]), "/com/163/music/2111993059");
            compare(DbusValues.scalar(result["xesam:title"], ""), "Test song");
        }
    }

    function test_missing_metadata() {
        compare(Object.keys(DbusValues.dictionary(undefined)).length, 0);
        compare(Object.keys(DbusValues.dictionary([])).length, 0);
    }

    function test_initial_position() {
        compare(DbusValues.number(initialPosition), 162298000);
    }

    function test_refreshed_qml_sequence() {
        compare(DbusValues.number(refreshedPosition), 163298000);
    }

    function test_wrapped_playback_status() {
        compare(DbusValues.scalar(new DBus.string("Playing"), "Stopped"), "Playing");
    }

    function test_long_tracks_do_not_overflow_32_bit_microseconds() {
        compare(DbusValues.number(new DBus.int64(3600000000)), 3600000000);
    }

    function test_missing_and_invalid_values() {
        compare(DbusValues.number(undefined), 0);
        compare(DbusValues.number([]), 0);
        compare(DbusValues.number({}), 0);
        compare(DbusValues.number("invalid"), 0);
        compare(DbusValues.number(123), 123);
    }
}
