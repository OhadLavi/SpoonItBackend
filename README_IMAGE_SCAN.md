# Recipe Image Scanning Feature

This document describes how to set up and use the recipe image scanning feature in the SpoonIt app.

## Overview

The SpoonIt app now supports extracting recipe information from images. This feature uses:

1. Tesseract OCR for text extraction from images
2. An LLM (Ollama) for understanding and parsing the recipe text
3. A FastAPI backend to process the images and communicate with the LLM
4. A Flutter frontend that allows uploading images

## Backend Setup

The backend requires Python and several dependencies:

### Prerequisites

1. Python 3.9+ installed
2. Tesseract OCR installed on your system

#### Installing Tesseract OCR:

- **Windows**: Download and install from [UB Mannheim](https://github.com/UB-Mannheim/tesseract/wiki)
  - Make sure it's in your PATH or set the `TESSDATA_PREFIX` environment variable
- **macOS**: `brew install tesseract`
- **Linux**: `sudo apt-get install tesseract-ocr`
  - For Hebrew support: `sudo apt-get install tesseract-ocr-heb`

### Python Dependencies

```bash
pip install pytesseract==0.3.13 Pillow==11.1.0 fastapi==0.110.0 uvicorn==0.27.1 beautifulsoup4==4.12.3 python-multipart==0.0.9 selenium==4.18.1
```

### Running the Backend

From the project root directory:

```bash
cd backend
python main.py
```

The API will be available at `http://localhost:8000`.

## Flutter App Setup

The app requires the following dependencies:

```bash
flutter pub add file_picker image_picker http
```

## Using the Feature

1. Launch the backend server (`python main.py` in the backend directory)
2. Launch the Flutter app
3. Navigate to the "Scan Recipe" section
4. Click on the upload area or "Select Image" button
5. Choose an image that contains a recipe
6. Click "Scan Image" to process the image
7. Review and edit the extracted recipe in the form that appears
8. Save the recipe to add it to your collection

## Troubleshooting

### Backend Issues

- **OCR errors**: Make sure Tesseract is properly installed and accessible
- **Language support**: For non-English recipes, ensure you have the appropriate language packs installed for Tesseract
- **Connectivity**: Ensure the app can connect to the backend server (default: http://localhost:8000)

### Image Quality Tips

For best results:
- Use well-lit, clear images
- Ensure text is readable and not blurry
- Avoid glare or shadows on the recipe
- Crop the image to include only the recipe content if possible

## API Endpoints

- `POST /extract_recipe_from_image` - Extract recipe from base64-encoded image
- `POST /upload_recipe_image` - Extract recipe from an uploaded image file

## Technical Details

The process works as follows:

1. The user selects or uploads an image
2. The image is sent to the backend API as base64-encoded data
3. Tesseract OCR extracts text from the image
4. The text is sent to the LLM with a prompt to extract recipe information
5. The LLM returns structured JSON data
6. The backend processes and normalizes the data
7. The frontend displays the structured recipe for the user to edit and save 