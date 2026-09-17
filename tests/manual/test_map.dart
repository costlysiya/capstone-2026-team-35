void main() {
  dynamic _decryptJson(dynamic data) {
    if (data is String) return data;
    if (data is List) return data.map((e) => _decryptJson(e)).toList();
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), _decryptJson(v)));
    return data;
  }

  final Map<dynamic, dynamic> myMap = {1: 'a'};
  final result = _decryptJson(myMap);
  print(result.runtimeType);
}
