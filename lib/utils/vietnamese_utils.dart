/// Utility for Vietnamese text processing (diacritics removal, search normalization)
class VietnameseUtils {
  VietnameseUtils._();

  static final _vietnameseMap = <RegExp, String>{
    RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'): 'a',
    RegExp(r'[ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ]'): 'A',
    RegExp(r'[èéẹẻẽêềếệểễ]'): 'e',
    RegExp(r'[ÈÉẸẺẼÊỀẾỆỂỄ]'): 'E',
    RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'): 'o',
    RegExp(r'[ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ]'): 'O',
    RegExp(r'[ùúụủũưừứựửữ]'): 'u',
    RegExp(r'[ÙÚỤỦŨƯỪỨỰỬỮ]'): 'U',
    RegExp(r'[ìíịỉĩ]'): 'i',
    RegExp(r'[ÌÍỊỈĨ]'): 'I',
    RegExp(r'đ'): 'd',
    RegExp(r'Đ'): 'D',
    RegExp(r'[ỳýỵỷỹ]'): 'y',
    RegExp(r'[ỲÝỴỶỸ]'): 'Y',
  };

  /// Remove Vietnamese diacritics from a string.
  /// Example: "Điện thoại" → "Dien thoai"
  static String removeDiacritics(String str) {
    var result = str;
    _vietnameseMap.forEach((regex, replacement) {
      result = result.replaceAll(regex, replacement);
    });
    return result;
  }

  /// Normalize a string for search: lowercase + remove diacritics.
  /// Supports both "có dấu" and "không dấu" input.
  static String normalize(String str) {
    return removeDiacritics(str.toLowerCase());
  }

  /// Check if [source] contains [query], supporting Vietnamese with/without diacritics.
  static bool containsVietnamese(String source, String query) {
    final normalizedSource = normalize(source);
    final normalizedQuery = normalize(query);
    return normalizedSource.contains(normalizedQuery);
  }
}
