# SpoonIt Backend

This is the backend server for the SpoonIt application that provides recipe extraction, chat, and image processing services using Google Gemini API (with Ollama as fallback).

## Prerequisites

- Python 3.8 or higher
- Google Gemini API key (recommended) or Ollama installed and running
- For Gemini: Get your API key from [Google AI Studio](https://makersuite.google.com/app/apikey)
- For Ollama: Install and run Ollama with Gemma 3B model on http://127.0.0.1:11434

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

3. Install Playwright browsers (required for web scraping):
```bash
playwright install chromium
```

4. Create a `.env` file in the backend directory:
```env
GEMINI_API_KEY=your_gemini_api_key_here
LLM_PROVIDER=gemini
GEMINI_MODEL=gemini-2.5-flash
```

## Running the Server

1. Make sure your `.env` file is configured (or Ollama is running if using fallback)
2. Start the server:
```bash
python main.py
```

The server will start on http://localhost:8001

## API Endpoints

### POST /extract_recipe
Extract recipe information from a URL.

Request body:
```json
{
    "url": "https://example.com/recipe"
}
```

### POST /extract_recipe_from_image
Extract recipe from a base64-encoded image.

Request body:
```json
{
    "image_data": "data:image/jpeg;base64,..."
}
```

### POST /upload_recipe_image
Upload and extract recipe from an image file.

### POST /chat
Send a message to the AI model and get a response.

Request body:
```json
{
    "message": "Your message here",
    "language": "en"
}
```

### POST /custom_recipe
Generate a custom recipe based on available groceries and description.

### GET /proxy_image
Proxy an image URL to bypass CORS restrictions.

### GET /health
Health check endpoint.

## Integration with Flutter App

The backend is configured to accept CORS requests from any origin. In production, you should restrict this to your Flutter app's domain.

Example Flutter API call:
```dart
final response = await http.post(
  Uri.parse('http://localhost:8001/extract_recipe'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'url': 'https://example.com/recipe'}),
);
```

## Deployment

### Google Cloud Run (Recommended)

This backend is configured for Google Cloud Run deployment with a custom Dockerfile:

1. Make sure you have the Google Cloud CLI installed and authenticated
2. Set your project ID:
```bash
gcloud config set project YOUR_PROJECT_ID
```

3. Deploy to Cloud Run:
```bash
gcloud run deploy spoonitbackend \
  --source . \
  --region europe-west1 \
  --allow-unauthenticated \
  --set-env-vars GEMINI_API_KEY=your_api_key_here
```

The Dockerfile includes all necessary dependencies including Playwright browsers and Tesseract OCR.

### Other Platforms

This backend can also be deployed to:
- Railway
- Render
- Heroku
- DigitalOcean App Platform
- AWS/GCP/Azure

Make sure to:
1. Set the `PORT` environment variable (most platforms do this automatically)
2. Configure your `GEMINI_API_KEY` in the platform's environment variables
3. Ensure Playwright browsers are installed (may require custom buildpack or Dockerfile) 