# Google Cloud Run Deployment Instructions

## Problem
The deployment is using Gunicorn (WSGI) instead of Uvicorn (ASGI), causing FastAPI to fail.

## Solution: Configure Cloud Build Trigger

### Step 1: Update Cloud Build Trigger Configuration

1. Go to **Google Cloud Console** → **Cloud Build** → **Triggers**
2. Find your trigger for `spoonitbackend` (usually named something like "spoonitbackend-trigger")
3. Click **Edit** (pencil icon)
4. Scroll to **Configuration** section
5. Select **"Cloud Build configuration file (yaml or json)"**
6. Set **Location** to: `backend/cloudbuild.yaml`
7. Click **Save**

### Step 2: Verify Environment Variables in Cloud Run

1. Go to **Cloud Run** → **spoonitbackend** → **Edit & Deploy New Revision**
2. Click on **"Variables & Secrets"** tab
3. Ensure these environment variables are set:
   - `PORT` = `8080`
   - `GEMINI_API_KEY` = (your API key)
   - `LLM_PROVIDER` = `gemini` (optional, defaults to gemini)
   - `GEMINI_MODEL` = `gemini-2.5-flash` (optional)
4. Click **Deploy**

### Step 3: Verify Container Configuration

1. In the same **Edit & Deploy** page, go to **"Containers"** tab
2. Under **"Container command"** - leave this **EMPTY** (should use Dockerfile ENTRYPOINT)
3. Under **"Container arguments"** - leave this **EMPTY**
4. **Container port** should be: `8080`

### Step 4: Manual Deployment (Alternative)

If the trigger still doesn't work, you can manually deploy:

```bash
# Navigate to backend directory
cd backend

# Submit build using cloudbuild.yaml
gcloud builds submit --config=cloudbuild.yaml

# Or deploy directly with Docker
gcloud run deploy spoonitbackend \
  --source . \
  --region europe-west1 \
  --allow-unauthenticated \
  --port 8080 \
  --set-env-vars PORT=8080,GEMINI_API_KEY=your_key_here
```

### Step 5: Verify Deployment

After deployment, check the logs:
1. Go to **Cloud Run** → **spoonitbackend** → **Logs**
2. Look for: `INFO:     Uvicorn running on http://0.0.0.0:8080`
3. If you see `gunicorn` in the logs, the Dockerfile is still not being used

## Troubleshooting

### If Gunicorn error persists:

1. **Check Cloud Build logs**: Cloud Build → History → Latest build → View logs
2. **Verify Dockerfile is being used**: Look for "Step 1/10 : FROM python:3.11-slim" in build logs
3. **Check trigger configuration**: Ensure it's using `backend/cloudbuild.yaml`
4. **Delete and recreate trigger**: Sometimes triggers cache old configurations

### Force Docker Build:

If buildpacks are still being used, you can force Docker by:

1. **Delete the trigger** and create a new one
2. **Select "Cloud Build configuration file"** immediately
3. **Set location to `backend/cloudbuild.yaml`**
4. **Do NOT select "Autodetect" or "Dockerfile"** - use the YAML file

## Important Notes

- The `cloudbuild.yaml` file explicitly uses Docker to build the image
- The Dockerfile uses `ENTRYPOINT` to ensure uvicorn is always used
- Environment variables must be set in Cloud Run, not just in `.env` file
- The `.env` file is ignored in production (use Cloud Run environment variables)

