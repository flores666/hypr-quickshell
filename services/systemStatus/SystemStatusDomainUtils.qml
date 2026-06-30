import QtQml

QtObject {
    id: root

    function sameList(left, right) {
        try {
            return JSON.stringify(left || []) === JSON.stringify(right || []);
        } catch (e) {
            return false;
        }
    }

    function listOrEmpty(value) {
        return Array.isArray(value) ? value : [];
    }

    function objectOrEmpty(value) {
        return value && typeof value === "object" && !Array.isArray(value) ? value : {};
    }

    function stringValue(value, fallback) {
        if (value === undefined || value === null)
            return fallback === undefined || fallback === null ? "" : String(fallback);
        return String(value);
    }

    function intValue(value, fallback) {
        var parsed = Number(value);
        return isFinite(parsed) ? Math.round(parsed) : Math.round(Number(fallback || 0));
    }

    function clampInt(value, minValue, maxValue) {
        return Math.max(Number(minValue || 0), Math.min(Number(maxValue || 0), intValue(value, minValue || 0)));
    }

    function nonEmptyLine(line) {
        return stringValue(line).trim().length > 0;
    }

    function commandName(args) {
        return args && args.length > 0 ? stringValue(args[0]) : "";
    }

    function commandIn(args, names) {
        var command = commandName(args);
        var list = listOrEmpty(names);
        for (var i = 0; i < list.length; i++) {
            if (command === stringValue(list[i]))
                return true;
        }
        return false;
    }

    function runAction(actionRunner, args) {
        if (actionRunner)
            actionRunner(listOrEmpty(args));
    }

    function copyObject(source) {
        var input = objectOrEmpty(source);
        var result = {};
        for (var key in input)
            result[key] = input[key];
        return result;
    }
}
