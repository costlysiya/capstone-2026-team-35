import 'dart:convert';

void main() {
  dynamic _decryptJson(dynamic data) {
    if (data is String) return data;
    if (data is List) return data.map((e) => _decryptJson(e)).toList();
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), _decryptJson(v)));
    return data;
  }

  final responseData = {
    "total": 1,
    "success": 2,
    "failed": 0,
    "results": [
      {
        "id": 1683,
        "original_index": 0,
        "type": "PLACE",
        "confidence": 1.0,
        "fields": {
          "name": "ShackShack",
          "region": "Gangnam"
        }
      },
      {
        "id": 1684,
        "original_index": 0,
        "type": "PLACE",
        "confidence": 1.0,
        "fields": {
          "name": "Meat",
          "region": "Jongro"
        }
      }
    ]
  };

  final results = responseData['results'] as List<dynamic>? ?? [];
  final decryptedResults = _decryptJson(results) as List<dynamic>;
  
  Map<int, List<Map<String, dynamic>>> groupedResults = {};
  for (var item in decryptedResults) {
    final res = item as Map<String, dynamic>;
    final origIdx = res['original_index'] as int?;
    if (origIdx != null) {
      groupedResults.putIfAbsent(origIdx, () => []).add(res);
    }
  }
  
  print(groupedResults);
  
  for (final entry in groupedResults.entries) {
    final dataList = entry.value;
    final firstData = dataList.first;
    final typeStr = firstData['type'] as String;
    final firstFields = firstData['fields'] as Map<String, dynamic>;
    
    final Map<String, dynamic> aiFieldsToSave = Map<String, dynamic>.from(firstFields);
    if (dataList.length > 1) {
      aiFieldsToSave['items'] = dataList.map((item) {
        final f = Map<String, dynamic>.from(item['fields'] as Map<String, dynamic>);
        f['type'] = item['type'];
        if (item['id'] != null) f['id'] = item['id'];
        return f;
      }).toList();
    }
    print(aiFieldsToSave);
    
    Map<String, dynamic> itemFields = dataList.length > 1 ? dataList.first['fields'] : firstFields;
    print(itemFields.runtimeType);
    
    if (itemFields['items'] != null && (itemFields['items'] as List).isNotEmpty) {
      itemFields = (itemFields['items'] as List).first as Map<String, dynamic>;
    }
    
    print(itemFields);
    String newTitle = itemFields['name'] ?? itemFields['title'] ?? 'New Place';
    print(newTitle);
  }
}
