import 'dart:convert';
import 'package:http/http.dart' as http;

class DictionaryResult {
  final String word;
  final String? phonetic;
  final List<Meaning> meanings;

  DictionaryResult({
    required this.word,
    this.phonetic,
    required this.meanings,
  });

  factory DictionaryResult.fromJson(Map<String, dynamic> json) {
    final meaningsList = (json['meanings'] as List? ?? [])
        .map((m) => Meaning.fromJson(m))
        .toList();

    return DictionaryResult(
      word: json['word'] ?? '',
      phonetic: json['phonetic'],
      meanings: meaningsList,
    );
  }
}

class Meaning {
  final String partOfSpeech;
  final List<Definition> definitions;
  final List<String> synonyms;

  Meaning({
    required this.partOfSpeech,
    required this.definitions,
    required this.synonyms,
  });

  factory Meaning.fromJson(Map<String, dynamic> json) {
    final definitionsList = (json['definitions'] as List? ?? [])
        .map((d) => Definition.fromJson(d))
        .toList();

    final synonymsList = (json['synonyms'] as List? ?? [])
        .map((s) => s.toString())
        .toList();

    return Meaning(
      partOfSpeech: json['partOfSpeech'] ?? '',
      definitions: definitionsList,
      synonyms: synonymsList,
    );
  }
}

class Definition {
  final String definition;
  final String? example;

  Definition({
    required this.definition,
    this.example,
  });

  factory Definition.fromJson(Map<String, dynamic> json) {
    return Definition(
      definition: json['definition'] ?? '',
      example: json['example'],
    );
  }
}

class DictionaryService {
  static Future<DictionaryResult?> lookupWord(String word) async {
    final cleanWord = word.trim().replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (cleanWord.isEmpty) return null;

    try {
      final url = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$cleanWord');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        if (jsonList.isNotEmpty) {
          return DictionaryResult.fromJson(jsonList[0]);
        }
      }
    } catch (e) {
      print('Dictionary API Error: $e');
    }
    return null;
  }
}
