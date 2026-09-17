void main() {
  dynamic _decryptJson(dynamic data) {
    if (data is String) return data;
    if (data is List) return data.map((e) => _decryptJson(e)).toList();
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), _decryptJson(v)));
    return data;
  }

  final response = {'results': [{'fields': {'a': 1}}]};
  final decrypted = _decryptJson(response['results']) as List<dynamic>;
  for (var item in decrypted) {
    final res = item as Map<String, dynamic>;
    print(res['fields'].runtimeType);
    final casted = res['fields'] as Map<String, dynamic>;
    print('Cast successful');
  }
}
