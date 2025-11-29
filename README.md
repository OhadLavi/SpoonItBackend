# SpoonIt Backend

A FastAPI-based backend server for the SpoonIt recipe application. Provides recipe extraction from URLs and images, recipe generation from ingredients, and AI-powered chat functionality using Google's Gemini API.

## Features

- 🍳 **Recipe Extraction**: Extract recipes from public URLs or uploaded images
- 🤖 **AI Recipe Generation**: Generate recipes from a list of ingredients using Gemini AI
- 💬 **Chat Interface**: Interactive recipe-focused conversations with AI
- 🔒 **Security**: Rate limiting, CORS, security headers, and request validation
- 📊 **Logging**: Comprehensive request logging with request IDs
- 🐳 **Docker Support**: Ready for containerized deployment (Cloud Run compatible)

## Prerequisites

- Python 3.11 or higher
- Google Gemini API key ([Get one here](https://makersuite.google.com/app/apikey))
- Zyte API key for web scraping ([Get one here](https://www.zyte.com/))

## Setup

1. **Clone the repository** (if not already done):
```bash
cd backend
```

2. **Create a virtual environment** (recommended):
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. **Install dependencies**:
```bash
pip install -r requirements.txt
```

4. **Configure environment variables**:
   - Copy `env.example` to `.env`
   - Fill in your API keys and configuration:
```bash
cp env.example .env
```

Edit `.env` and set:
- `GEMINI_API_KEY`: Your Google Gemini API key
- `ZYTE_API_KEY`: Your Zyte API key (for web scraping)
- Adjust other settings as needed (see `env.example` for all options)

## Running the Server

### Development Mode

Start the server using uvicorn:
```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

The server will start on `http://localhost:8080`

### Production Mode

For production, use gunicorn with uvicorn workers:
```bash
gunicorn app.main:app --workers 1 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8080
```

### Docker

Build and run with Docker:
```bash
docker build -t spoonit-backend .
docker run -p 8080:8080 --env-file .env spoonit-backend
```

## API Documentation

Once the server is running, interactive API documentation is available at:
- **Swagger UI**: `http://localhost:8080/docs`
- **ReDoc**: `http://localhost:8080/redoc`

## API Endpoints

### Health Check

- **GET** `/health` - Basic health check
- **GET** `/health/ready` - Readiness check for Cloud Run

### Recipe Extraction

#### Extract from URL
- **POST** `/recipes/from-url`
  - Accepts: JSON body `{"url": "..."}` or form data `url=...`
  - Returns: Recipe object in unified format

#### Extract from Image
- **POST** `/recipes/from-image`
  - Accepts: Multipart form data with image file
  - Supported formats: JPEG, PNG, WebP (max 10MB)
  - Returns: Recipe object in unified format

#### Generate Recipe
- **POST** `/recipes/generate`
  - Accepts: Form data with `ingredients` list
  - Returns: Generated recipe object

#### Upload Image
- **POST** `/recipes/upload-image`
  - Accepts: Multipart form data with image file
  - Returns: Image validation status and metadata

### Chat

- **POST** `/chat`
  - Request body:
    ```json
    {
      "message": "Your message here",
      "language": "he",
      "conversation_history": []
    }
    ```
  - Returns: Chat response with optional recipe
    ```json
    {
      "response": "AI response text",
      "model": "gemini-1.5-pro",
      "is_recipe": true,
      "recipe": { ... }
    }
    ```

### Legacy Compatibility Endpoints

- **POST** `/extract_recipe` - Legacy URL extraction endpoint
- **POST** `/extract_recipe_from_image` - Legacy image extraction endpoint

### Utilities

- **GET** `/proxy_image?url=...` - Proxy images to avoid CORS issues

## Configuration

All configuration is done via environment variables (see `env.example`):

### Required
- `GEMINI_API_KEY`: Google Gemini API key
- `ZYTE_API_KEY`: Zyte API key for web scraping

### Optional
- `PORT`: Server port (default: 8080)
- `HOST`: Server host (default: 0.0.0.0)
- `LOG_LEVEL`: Logging level (default: INFO)
- `RATE_LIMIT_PER_HOUR`: Rate limit per IP (default: 100)
- `CORS_ORIGINS`: Allowed CORS origins (default: *)
- `GEMINI_MODEL`: Gemini model to use (default: gemini-2.5-pro)
- `GEMINI_TEMPERATURE`: Model temperature (default: 0.3)
- `GEMINI_MAX_TOKENS`: Max response tokens (default: 4096)

## Project Structure

```
backend/
├── app/
│   ├── api/
│   │   ├── routes/          # API route handlers
│   │   └── dependencies.py  # Dependency injection
│   ├── core/                # Core utilities
│   ├── middleware/          # Request middleware
│   ├── models/              # Data models
│   ├── services/            # Business logic services
│   ├── utils/               # Utility functions
│   ├── config.py            # Configuration
│   └── main.py              # Application entry point
├── tests/                   # Test files
├── Dockerfile               # Docker configuration
├── requirements.txt         # Python dependencies
└── README.md               # This file
```

## Development

### Running Tests

```bash
pytest tests/
```

### Code Quality

The project uses:
- FastAPI for the web framework
- Pydantic for data validation
- SlowAPI for rate limiting
- Structured logging with request IDs

## Deployment

### Google Cloud Run

The project is configured for Google Cloud Run deployment:
- Dockerfile included
- Health check endpoints configured
- Environment variables via Cloud Run configuration

Build and deploy:
```bash
gcloud builds submit --config cloudbuild.yaml
```

## Error Handling

The API uses structured error responses with:
- HTTP status codes
- Error messages
- Request IDs for tracking
- Detailed error information in development

## Rate Limiting

Rate limiting is enabled by default (100 requests/hour per IP). Adjust via `RATE_LIMIT_PER_HOUR` environment variable.

## CORS

CORS is configured to allow all origins by default. For production, set `CORS_ORIGINS` to your frontend domain(s).