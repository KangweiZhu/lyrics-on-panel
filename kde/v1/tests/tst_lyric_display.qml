import QtQuick
import QtTest
import "../contents/ui/LyricDisplay.js" as LyricDisplay

TestCase {
    name: "LyricDisplayAfterModeSwitch"
    ListModel { id: lines }

    function init() {
        lines.clear();
        lines.append({time: 1000000, lyric: "previous line"});
        lines.append({time: 3000000, lyric: ""});
        lines.append({time: 8000000, lyric: "next line"});
        lines.append({time: 10000000, lyric: ""});
    }

    function test_switch_into_empty_gap_without_previous_display_state() {
        compare(LyricDisplay.currentLine(lines, 5000000), "previous line");
    }

    function test_exact_timestamp_and_seek_backwards() {
        compare(LyricDisplay.currentLine(lines, 8000000), "next line");
        compare(LyricDisplay.currentLine(lines, 2000000), "previous line");
    }

    function test_final_line_remains_visible_after_end_marker() {
        compare(LyricDisplay.currentLine(lines, 11000000), "next line");
    }

    function test_before_first_line_is_blank() {
        compare(LyricDisplay.currentLine(lines, 0), "");
        compare(LyricDisplay.displayText(lines, 0, true, "Song - Artist"), "");
    }

    function test_missing_id_or_pending_request_is_blank() {
        compare(LyricDisplay.displayText(lines, 5000000, false, "Song - Artist"), "");
        lines.clear();
        compare(LyricDisplay.displayText(lines, 5000000, false, "Song - Artist"), "");
    }

    function test_completed_response_without_lyrics_uses_fallback() {
        lines.clear();
        compare(LyricDisplay.displayText(lines, 5000000, true, "Song - Artist"), "Song - Artist");
        compare(LyricDisplay.displayText(lines, 5000000, true, ""), "");
    }
}
