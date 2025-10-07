import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:recipe_keeper/config/env_config.dart';

class OllamaService {
  String get baseUrl => EnvConfig.apiBaseUrl;

  Future<String> sendMessage(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'];
      } else {
        throw Exception(
          'Failed to get response from Ollama: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error communicating with Ollama: $e');
    }
  }
}
