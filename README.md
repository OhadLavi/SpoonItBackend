# SpoonIt Backend

A FastAPI-based backend server for the SpoonIt recipe application. Provides recipe extraction from URLs and images, recipe generation from ingredients, and AI-powered chat functionality using Google's Gemini API.

## Features

- **Recipe Extraction**: Extract recipes from URLs using BrightData for HTML fetching + Gemini for structured extraction, with a JSON-LD fast path for supported sites
- **Image Extraction**: Extract recipes from uploaded images using OCR (Tesseract) + Gemini structuring
- **AI Recipe Generation**: Generate recipes from a list of ingredients or free-text prompts using Gemini AI
- **Chat Interface**: Interactive recipe-focused conversations with AI
- **Instruction Groups**: Support for organized instruction groups (e.g., "הכנת הבצק", "הגשה")
- **Notes Support**: Extract tips, notes, and recommendations from recipes
- **Security**: Rate limiting, CORS, security headers, and request validation
- **Logging**: Comprehensive request logging with request IDs and performance tracking
- **Docker Support**: Ready for containerized deployment on Google Cloud Run

## Prerequisites

- Python 3.11 or higher
- Google Gemini API key ([Get one here](https://makersuite.google.com/app/apikey))
- BrightData API key (for web content fetching)

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
- `BRIGHTDATA_API_KEY`: Your BrightData Web Unlocker API key
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
gunicorn app.main:app --workers 2 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8080
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

### Legacy Compatibility Endpoints

- **POST** `/extract_recipe` - Legacy URL extraction endpoint
- **POST** `/extract_recipe_from_image` - Legacy image extraction endpoint

### Utilities

- **GET** `/proxy_image?url=...` - Proxy images to avoid CORS issues

## Configuration

All configuration is done via environment variables (see `env.example`):

### Required
- `GEMINI_API_KEY`: Google Gemini API key
- `BRIGHTDATA_API_KEY`: BrightData Web Unlocker API key

### Optional
- `PORT`: Server port (default: 8080)
- `HOST`: Server host (default: 0.0.0.0)
- `LOG_LEVEL`: Logging level (default: INFO)
- `RATE_LIMIT_PER_HOUR`: Rate limit per IP (default: 100)
- `CORS_ORIGINS`: Allowed CORS origins (default: *)
- `GEMINI_MODEL`: Gemini model to use (default: gemini-2.5-flash-lite)
- `GEMINI_TEMPERATURE`: Model temperature (default: 0.3)
- `GEMINI_MAX_TOKENS`: Max response tokens (default: 4096)
- `GEMINI_MAX_CONTENT_CHARS`: Max characters of page content sent to Gemini (default: 25000)
- `RATE_LIMIT_STORAGE_URI`: Rate limit storage backend (default: `memory://`, use `redis://host:port` for shared rate limiting across workers)

## Project Structure

```
backend/
├── app/
│   ├── api/
│   │   ├── routes/              # API route handlers
│   │   │   ├── chat.py          # Chat endpoint
│   │   │   ├── health.py        # Health check endpoints
│   │   │   ├── recipes.py       # Recipe extraction/generation endpoints
│   │   │   ├── subscriptions.py # Subscription management
│   │   │   └── webhooks.py      # Webhook handlers
│   │   └── dependencies.py      # Dependency injection
│   ├── core/                    # Core utilities (request ID)
│   ├── middleware/               # Request middleware
│   │   ├── logging.py           # Request/response logging
│   │   ├── performance.py       # Performance tracking (slow request alerts)
│   │   ├── rate_limit.py        # Rate limiting
│   │   └── security.py          # Security headers, CORS
│   ├── models/                  # Pydantic data models
│   │   └── recipe.py            # Recipe model
│   ├── services/                # Business logic services
│   │   ├── scraper_service.py   # URL recipe extraction (BrightData + Gemini)
│   │   ├── gemini_service.py    # Gemini API integration (image/text)
│   │   ├── recipe_extractor.py  # High-level extraction orchestrator
│   │   ├── food_detector.py     # Food image detection (MobileNetV2)
│   │   └── subscriptions/       # Subscription management
│   ├── utils/                   # Shared utility functions
│   │   ├── gemini_helpers.py    # Schema cleaning & caching for Gemini API
│   │   ├── recipe_normalization.py # Unified recipe data normalization
│   │   ├── validators.py        # URL validation
│   │   ├── exceptions.py        # Custom exception classes
│   │   └── logging_config.py    # Logging setup
│   ├── config.py                # Configuration (pydantic-settings)
│   └── main.py                  # Application entry point
├── tests/                       # Test files
├── Dockerfile                   # Docker configuration
├── cloudbuild.yaml              # Google Cloud Build config
├── requirements.txt             # Python dependencies
├── env.example                  # Environment variable template
└── README.md                    # This file
```

## How It Works

### Recipe Extraction from URLs

The backend uses a multi-strategy approach for extracting recipes from URLs:

1. **JSON-LD Fast Path**: If the page contains structured JSON-LD recipe data, it's extracted directly without needing the LLM -- this is the fastest and cheapest path.
2. **BrightData HTML Fetching**: For pages without JSON-LD, BrightData Web Unlocker fetches the page HTML (handles JavaScript rendering, anti-bot protections).
3. **Content Extraction**: HTML is parsed with BeautifulSoup and Trafilatura to extract the main content.
4. **Gemini Structuring**: The extracted text is sent to Gemini with a strict JSON schema to produce structured recipe data.
5. **Social Media Fallback**: For Instagram/TikTok/Facebook, a dedicated extraction path handles these platforms.

All paths produce normalized output through a shared `normalize_recipe_data()` function that handles edge cases, Hebrew unit repair, and schema conformance.

### Recipe Model

Recipes support:
- **Ingredient Groups**: Organized ingredient lists (e.g., "לבסיס", "לקרם")
- **Instruction Groups**: Organized instruction sections (e.g., "הכנת הבצק", "הגשה")
- **Notes**: Tips, recommendations, and additional information
- **Nutrition**: Calories, protein, fat, and carbs per serving
- **Images**: Filtered and validated image URLs

## Development

### Running Tests

```bash
pytest tests/
```

### Code Quality

The project uses:
- FastAPI for the web framework
- Pydantic for data validation
- Google Genai SDK for Gemini integration
- SlowAPI for rate limiting
- Structured logging with request IDs

## Deployment

### Google Cloud Run

The project is configured for Google Cloud Run deployment:
- Dockerfile with pre-downloaded MobileNetV2 model
- Health check endpoints configured
- Environment variables via Cloud Run configuration
- Minimum 1 instance to reduce cold starts

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
- Hard timeouts on URL extraction (120s) and Gemini API calls (90s) to prevent hung requests

## Rate Limiting

Rate limiting is enabled by default (100 requests/hour per IP). Adjust via `RATE_LIMIT_PER_HOUR` environment variable. For multi-worker deployments, set `RATE_LIMIT_STORAGE_URI` to a Redis URL for shared state.

## CORS

CORS is configured to allow all origins by default. For production, set `CORS_ORIGINS` to your frontend domain(s).
