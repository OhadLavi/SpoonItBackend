import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  final String baseUrl = 'http://localhost:8000';

  Future<String> sendMessage(String message, {String language = 'he'}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message, 'language': language}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['response'] as String;
      } else {
        throw Exception('Failed to get response from server');
      }
    } catch (e) {
      throw Exception('Error communicating with server: $e');
    }
  }
}
