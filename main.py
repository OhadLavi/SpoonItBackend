# main.py
"""SpoonIt API - Recipe extraction and generation service."""

from __future__ import annotations

import os
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, HTMLResponse

from config import logger
from errors import APIError
from routes import chat, extraction, proxy

# =============================================================================
# FastAPI app
# =============================================================================
app = FastAPI(
    title="SpoonIt API",
    version="1.3.2",
    description="Generic recipe extraction via schema.org, DOM heuristics (Hebrew/English), and LLM fallback.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition", "Access-Control-Allow-Origin"],
)


@app.exception_handler(APIError)
async def api_error_handler(request, exc: APIError):
    """Handle custom API errors."""
    logger.error("APIError: %s | details=%s", exc.message, exc.details)
    return JSONResponse(status_code=exc.status_code, content={"error": exc.message, "details": exc.details})


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {"message": "Welcome to SpoonIt API", "docs": "/docs", "redoc": "/redoc"}


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok"}


@app.get("/test_zyte_page", response_class=HTMLResponse)
async def test_zyte_page():
    """Test page for Zyte API."""
    html_content = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Zyte API Test</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header p {
            opacity: 0.9;
            font-size: 1.1em;
        }
        .content {
            padding: 30px;
        }
        .input-section {
            margin-bottom: 30px;
        }
        .input-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            font-weight: 600;
            color: #333;
        }
        input[type="text"] {
            width: 100%;
            padding: 12px 16px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        input[type="text"]:focus {
            outline: none;
            border-color: #667eea;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 14px 32px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        button:active {
            transform: translateY(0);
        }
        button:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: none;
        }
        .loading {
            text-align: center;
            padding: 40px;
            color: #667eea;
            font-size: 18px;
        }
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #667eea;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .result-section {
            margin-top: 30px;
        }
        .result-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        .result-header h2 {
            color: #333;
        }
        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
        }
        .status-success {
            background: #4caf50;
            color: white;
        }
        .status-error {
            background: #f44336;
            color: white;
        }
        .json-container {
            background: #f5f5f5;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            max-height: 600px;
            overflow: auto;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            line-height: 1.6;
        }
        .json-container pre {
            margin: 0;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .error-message {
            background: #ffebee;
            border-left: 4px solid #f44336;
            padding: 15px;
            border-radius: 4px;
            color: #c62828;
            margin-bottom: 15px;
        }
        .info-box {
            background: #e3f2fd;
            border-left: 4px solid #2196f3;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        .info-box strong {
            color: #1976d2;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Zyte API Test</h1>
            <p>Test Zyte API extraction for recipe URLs</p>
        </div>
        <div class="content">
            <div class="input-section">
                <div class="input-group">
                    <label for="url-input">Recipe URL:</label>
                    <input 
                        type="text" 
                        id="url-input" 
                        value="https://kerenagam.co.il/%d7%a8%d7%95%d7%9c%d7%93%d7%aa-%d7%98%d7%99%d7%a8%d7%9e%d7%99%d7%a1%d7%95-%d7%99%d7%a4%d7%99%d7%a4%d7%99%d7%99%d7%94/"
                        placeholder="Enter recipe URL here"
                    />
                </div>
                <button id="fetch-btn" onclick="fetchZyteData()">Fetch from Zyte</button>
            </div>
            
            <div id="loading" class="loading" style="display: none;">
                <div class="spinner"></div>
                <p>Fetching data from Zyte API...</p>
            </div>
            
            <div id="result-section" class="result-section" style="display: none;">
                <div class="result-header">
                    <h2>Zyte API Response</h2>
                    <span id="status-badge" class="status-badge"></span>
                </div>
                <div id="error-message" class="error-message" style="display: none;"></div>
                <div id="info-box" class="info-box" style="display: none;"></div>
                <div class="json-container">
                    <pre id="json-output"></pre>
                </div>
            </div>
        </div>
    </div>

    <script>
        async function fetchZyteData() {
            const urlInput = document.getElementById('url-input');
            const fetchBtn = document.getElementById('fetch-btn');
            const loading = document.getElementById('loading');
            const resultSection = document.getElementById('result-section');
            const jsonOutput = document.getElementById('json-output');
            const statusBadge = document.getElementById('status-badge');
            const errorMessage = document.getElementById('error-message');
            const infoBox = document.getElementById('info-box');
            
            const url = urlInput.value.trim();
            if (!url) {
                alert('Please enter a URL');
                return;
            }
            
            // Show loading, hide results
            loading.style.display = 'block';
            resultSection.style.display = 'none';
            fetchBtn.disabled = true;
            errorMessage.style.display = 'none';
            infoBox.style.display = 'none';
            
            try {
                const response = await fetch(`/extraction/test_zyte?url=${encodeURIComponent(url)}`);
                const data = await response.json();
                
                // Hide loading, show results
                loading.style.display = 'none';
                resultSection.style.display = 'block';
                fetchBtn.disabled = false;
                
                if (data.success) {
                    statusBadge.textContent = '✓ Success';
                    statusBadge.className = 'status-badge status-success';
                    errorMessage.style.display = 'none';
                    
                    // Show info
                    if (data.response_keys) {
                        infoBox.innerHTML = `<strong>Response Keys:</strong> ${data.response_keys.join(', ')}`;
                        infoBox.style.display = 'block';
                    }
                    
                    // Format and display JSON
                    jsonOutput.textContent = JSON.stringify(data.zyte_response, null, 2);
                } else {
                    statusBadge.textContent = '✗ Error';
                    statusBadge.className = 'status-badge status-error';
                    errorMessage.innerHTML = `<strong>Error:</strong> ${data.error || 'Unknown error'}`;
                    errorMessage.style.display = 'block';
                    
                    if (data.response_preview) {
                        infoBox.innerHTML = `<strong>Response Preview:</strong><br><pre style="margin-top: 10px; white-space: pre-wrap;">${data.response_preview}</pre>`;
                        infoBox.style.display = 'block';
                    }
                    
                    jsonOutput.textContent = JSON.stringify(data, null, 2);
                }
            } catch (error) {
                loading.style.display = 'none';
                resultSection.style.display = 'block';
                fetchBtn.disabled = false;
                
                statusBadge.textContent = '✗ Error';
                statusBadge.className = 'status-badge status-error';
                errorMessage.innerHTML = `<strong>Network Error:</strong> ${error.message}`;
                errorMessage.style.display = 'block';
                jsonOutput.textContent = `Error: ${error.message}`;
            }
        }
        
        // Allow Enter key to trigger fetch
        document.getElementById('url-input').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                fetchZyteData();
            }
        });
    </script>
</body>
</html>
    """
    return HTMLResponse(content=html_content)


# =============================================================================
# Include routers
# =============================================================================
app.include_router(chat.router, tags=["Chat"])
app.include_router(extraction.router, tags=["Extraction"])
app.include_router(proxy.router, tags=["Proxy"])
@app.get("/ip")
async def ip_check():
    """Return the public IP of outbound Cloud Run traffic"""
    r = requests.get("https://api64.ipify.org?format=json", timeout=5)
    return {"ip": r.json().get("ip")}
# =============================================================================
# Entrypoint
# =============================================================================
if __name__ == "__main__":
    # Cloud Run requires listening on 0.0.0.0:$PORT (defaults to 8080).
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
