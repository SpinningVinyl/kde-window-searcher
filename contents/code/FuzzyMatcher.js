.pragma library

function prepare(s, ignoreCase) {
    let result = String(s).normalize("NFC");

    if (ignoreCase) {
        result = result.toLowerCase().normalize("NFC");
    }

    return result;
}

function indelDistance(first, second) {
    let a = Array.from(first);
    let b = Array.from(second);

    // Keep columns on the shorter sequence so memory usage is
    // O(min(m, n)).
    if (a.length < b.length) {
        const tmp = a;
        a = b;
        b = tmp;
    }

    let previous = new Array(b.length + 1);
    let current = new Array(b.length + 1);

    for (let column = 0; column <= b.length; ++column) {
        previous[column] = column;
    }

    for (let row = 1; row <= a.length; ++row) {
        current[0] = row;

        for (let column = 1; column <= b.length; ++column) {
            const substitutionCost =
                a[row - 1] === b[column - 1] ? 0 : 2;

            current[column] = Math.min(
                previous[column] + 1,
                current[column - 1] + 1,
                previous[column - 1] + substitutionCost
            );
        }

        const tmp = previous;
        previous = current;
        current = tmp;
    }

    return previous[b.length];
}

function score(first, second, ignoreCase) {
    if (!first || !String(first).trim()
            || !second || !String(second).trim()) {
        return -1;
    }

    const a = prepare(first, ignoreCase);
    const b = prepare(second, ignoreCase);

    if (a === b) {
        return 100;
    }

    const lengthA = Array.from(a).length;
    const lengthB = Array.from(b).length;
    const combinedLength = lengthA + lengthB;
    const distance = indelDistance(a, b);

    return Math.round(
        100 * (combinedLength - distance) / combinedLength
    );
}
