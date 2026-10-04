.pragma library

// Plasma wraps D-Bus scalars in typed values. Properties.update() can also
// return a QML sequence containing the value (Array.isArray is false for it).
function scalar(value, fallback) {
    for (var depth = 0; depth < 8 && value !== null && typeof value === "object"; depth++) {
        if (value.value !== undefined) {
            value = value.value;
        } else if (value.length === 1) {
            value = value[0];
        } else {
            return fallback;
        }
    }
    return value === null || value === undefined ? fallback : value;
}

function number(value) {
    var result = Number(scalar(value, 0));
    return isFinite(result) ? result : 0;
}

// Metadata can arrive as a map, a typed D-Bus dictionary, or a one-item
// reply sequence, depending on whether it was read or refreshed.
function dictionary(value) {
    for (var depth = 0; depth < 8 && value !== null && typeof value === "object"; depth++) {
        if (value.value !== undefined) {
            value = value.value;
        } else if (value.length === 1) {
            value = value[0];
        } else {
            return value.length === undefined ? value : {};
        }
    }
    return {};
}
