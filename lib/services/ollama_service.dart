import 'dart:convert';
import 'package:http/http.dart' as http;

class OllamaService {
  static const String baseUrl = 'http://localhost:8000';

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
