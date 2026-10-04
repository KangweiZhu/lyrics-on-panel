.pragma library

// Derive the line from playback time so mode changes and seeks need no history.
function currentLine(model, position) {
    for (var i = model.count - 1; i >= 0; i--) {
        var line = model.get(i);
        if (isFinite(line.time) && line.time <= position && line.lyric.trim()) {
            return line.lyric;
        }
    }
    return "";
}

function displayText(model, position, ready, fallback) {
    if (!ready) return "";
    // Before the first timestamp, lyrics exist but are not due yet.
    return currentLine(model, position) || (model.count === 0 ? fallback : "");
}
