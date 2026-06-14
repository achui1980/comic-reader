import 'dart:math';

/// Pure Dart implementation of LZ-String compression algorithm.
/// Only implements decompressFromBase64 as that's what we need.
class LZString {
  static const String _keyStrBase64 =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

  static final Map<String, int> _baseReverseDic = _createBaseReverseDic();

  static Map<String, int> _createBaseReverseDic() {
    final map = <String, int>{};
    for (int i = 0; i < _keyStrBase64.length; i++) {
      map[_keyStrBase64[i]] = i;
    }
    return map;
  }

  /// Decompress a base64-encoded LZ-String.
  static String? decompressFromBase64(String? input) {
    if (input == null || input.isEmpty) return '';

    return _decompress(input.length, 32, (index) {
      return _baseReverseDic[input[index]] ?? 0;
    });
  }

  static String? _decompress(
      int length, int resetValue, int Function(int index) getNextValue) {
    final dictionary = <int, String>{};
    int enlargeIn = 4;
    int dictSize = 4;
    int numBits = 3;
    String entry = '';
    final result = StringBuffer();
    int next;
    String w;
    String c;

    int bits = 0;
    int maxpower = pow(2, 2).toInt();
    int power = 1;

    int val = getNextValue(0);
    int position = resetValue;
    int index = 1;

    // Get first data segment
    int resb;
    for (int i = 0; i < 3; i++) {
      dictionary[i] = '';
    }

    bits = 0;
    maxpower = pow(2, 2).toInt();
    power = 1;
    while (power != maxpower) {
      resb = val & position;
      position >>= 1;
      if (position == 0) {
        position = resetValue;
        val = getNextValue(index++);
      }
      bits |= (resb > 0 ? 1 : 0) * power;
      power <<= 1;
    }

    next = bits;
    switch (next) {
      case 0:
        bits = 0;
        maxpower = pow(2, 8).toInt();
        power = 1;
        while (power != maxpower) {
          resb = val & position;
          position >>= 1;
          if (position == 0) {
            position = resetValue;
            val = getNextValue(index++);
          }
          bits |= (resb > 0 ? 1 : 0) * power;
          power <<= 1;
        }
        c = String.fromCharCode(bits);
        break;
      case 1:
        bits = 0;
        maxpower = pow(2, 16).toInt();
        power = 1;
        while (power != maxpower) {
          resb = val & position;
          position >>= 1;
          if (position == 0) {
            position = resetValue;
            val = getNextValue(index++);
          }
          bits |= (resb > 0 ? 1 : 0) * power;
          power <<= 1;
        }
        c = String.fromCharCode(bits);
        break;
      case 2:
        return '';
      default:
        return '';
    }
    dictionary[3] = c;
    w = c;
    result.write(c);

    while (true) {
      if (index > length) return '';

      bits = 0;
      maxpower = pow(2, numBits).toInt();
      power = 1;
      while (power != maxpower) {
        resb = val & position;
        position >>= 1;
        if (position == 0) {
          position = resetValue;
          if (index >= length) {
            // Avoid index out of bounds
            val = 0;
          } else {
            val = getNextValue(index++);
          }
        }
        bits |= (resb > 0 ? 1 : 0) * power;
        power <<= 1;
      }

      int cc = bits;
      switch (cc) {
        case 0:
          bits = 0;
          maxpower = pow(2, 8).toInt();
          power = 1;
          while (power != maxpower) {
            resb = val & position;
            position >>= 1;
            if (position == 0) {
              position = resetValue;
              val = getNextValue(index++);
            }
            bits |= (resb > 0 ? 1 : 0) * power;
            power <<= 1;
          }
          dictionary[dictSize++] = String.fromCharCode(bits);
          cc = dictSize - 1;
          enlargeIn--;
          break;
        case 1:
          bits = 0;
          maxpower = pow(2, 16).toInt();
          power = 1;
          while (power != maxpower) {
            resb = val & position;
            position >>= 1;
            if (position == 0) {
              position = resetValue;
              val = getNextValue(index++);
            }
            bits |= (resb > 0 ? 1 : 0) * power;
            power <<= 1;
          }
          dictionary[dictSize++] = String.fromCharCode(bits);
          cc = dictSize - 1;
          enlargeIn--;
          break;
        case 2:
          return result.toString();
      }

      if (enlargeIn == 0) {
        enlargeIn = pow(2, numBits).toInt();
        numBits++;
      }

      if (dictionary.containsKey(cc)) {
        entry = dictionary[cc]!;
      } else {
        if (cc == dictSize) {
          entry = w + w[0];
        } else {
          return null;
        }
      }
      result.write(entry);

      // Add w+entry[0] to the dictionary
      dictionary[dictSize++] = w + entry[0];
      enlargeIn--;

      w = entry;

      if (enlargeIn == 0) {
        enlargeIn = pow(2, numBits).toInt();
        numBits++;
      }
    }
  }
}
