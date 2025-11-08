# SpoonIt Backend

This is the backend server for the SpoonIt application that communicates with Ollama's Gemma 3B model.

## Prerequisites

- Python 3.8 or higher
- Ollama installed and running with Gemma 3B model
- Ollama should be running on http://127.0.0.1:11434

## Setup

1. Create a virtual environment (recommended):
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

## Running the Server

1. Make sure Ollama is running with the Gemma 3B model
2. Start the server:
```bash
python main.py
```

The server will start on http://localhost:8000

## API Endpoints

### POST /chat
Send a message to the Gemma 3B model and get a response.

Request body:
```json
{
    "message": "Your message here"
}
```

Response:
```json
{
    "response": "Model's response",
    "model": "gemma:3b"
}
```

## Integration with Flutter App

The backend is configured to accept CORS requests from any origin. In production, you should restrict this to your Flutter app's domain.

Example Flutter API call:
```dart
final response = await http.post(
  Uri.parse('http://localhost:8000/chat'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'message': 'Your message here'}),
);
``` 