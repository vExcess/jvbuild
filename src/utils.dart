import 'dart:io';
import 'dart:math' as Math;

void printOutAndErrIfExist(ProcessResult procRes) {
    final stdOut = procRes.stdout.toString().trimRight();
    if (stdOut.trimLeft().isNotEmpty) {
        print(stdOut);
    }
    
    final stdErr = procRes.stderr.toString().trimRight();
    if (stdErr.trimLeft().isNotEmpty) {
        print(stdErr);
    }
}

// ported from https://stackoverflow.com/questions/10473745/compare-strings-javascript-return-of-likely
int editDistance(String s1, String s2) {
    s1 = s1.toLowerCase();
    s2 = s2.toLowerCase();

    var costs = List.filled(s2.length + 1, 0);
    for (var i = 0; i <= s1.length; i++) {
        var lastValue = i;
        for (var j = 0; j <= s2.length; j++) {
            if (i == 0) {
                costs[j] = j;
            } else if (j > 0) {
                var newValue = costs[j - 1];
                if (s1[i - 1] != s2[j - 1]) {
                    newValue = Math.min(Math.min(newValue, lastValue), costs[j]) + 1;
                }
                costs[j - 1] = lastValue;
                lastValue = newValue;
            }
        }
        if (i > 0) {
            costs[s2.length] = lastValue;
        }
    }
    return costs[s2.length];
}
double LevDist(String s1, String s2) {
    var longer = s1;
    var shorter = s2;
    if (s1.length < s2.length) {
        longer = s2;
        shorter = s1;
    }
    var longerLength = longer.length;
    if (longerLength == 0) {
        return 1.0;
    }
    return (longerLength - editDistance(longer, shorter)) / longerLength;
}


dynamic findOne(List<dynamic> arr, bool Function(dynamic) filter) {
    for (var i = 0; i < arr.length; i++) {
        if (filter(arr[i])) {
            return arr[i];
        }
    }
    return null;
}

T assertType<T>(dynamic obj) {
    if (obj is! T) {
        throw "jvbuild: ${obj} must be of type ${T}";
    }
    return obj;
}

bool assertArr<T>(dynamic arr) {
    if (arr is! List) return false;
    for (final item in arr) {
        if (item is! T) return false;
    }
    return true;
}

bool assertMap<K, V>(dynamic map) {
    if (map is! Map) return false;
    for (final key in map.keys) {
        if (key is! K) return false;
    }
    for (final val in map.values) {
        if (val is! V) return false;
    }
    return true;
}

List<T> castArr<T>(List arr) {
    List<T> newArr = [];
    for (final item in arr) {
        newArr.add(item as T);
    }
    return newArr;
}

Map<K, V> castMap<K, V>(Map map) {
    Map<K, V> newMap = {};
    for (final key in map.keys) {
        newMap[key] = map[key];
    }
    return newMap;
}