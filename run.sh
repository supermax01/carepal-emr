#!/bin/bash

# Check for dependencies
command -v python3 >/dev/null 2>&1 || { echo "Python 3 is required but not installed. Aborting."; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo "Flutter is required but not installed. Aborting."; exit 1; }
command -v ngrok >/dev/null 2>&1 || { echo "ngrok is required for OAuth2 HTTPS support but not installed. Install it from https://ngrok.com/"; exit 1; }

# Create virtual environment if it doesn't exist
if [ ! -d "backend/venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv backend/venv
fi

# Activate virtual environment
source backend/venv/bin/activate

# Install backend dependencies
echo "Installing backend dependencies..."
pip install -r backend/requirements.txt

# Ensure .env file exists
if [ ! -f "backend/.env" ]; then
    if [ -f "backend/.env.example" ]; then
        echo "Creating .env file from .env.example..."
        cp backend/.env.example backend/.env
        echo "IMPORTANT: Update the values in backend/.env with your OpenEMR settings."
    else
        echo "ERROR: .env.example file not found. Please create a .env file manually."
        exit 1
    fi
fi

# Start backend with ngrok in the background
echo "Starting FastAPI backend with ngrok..."
cd backend
python run_with_ngrok.py &
BACKEND_PID=$!

# Give backend time to start
echo "Waiting for backend to start..."
sleep 5

# Get Flutter dependencies
echo "Installing Flutter dependencies..."
cd ..
flutter pub get

# Remind the user
echo ""
echo "==================================================================="
echo "IMPORTANT: Update the following:"
echo "1. In your OpenEMR API Clients settings, update the Redirect URI"
echo "   with the ngrok URL shown in the backend output."
echo "2. In backend/.env, update OPENEMR_REDIRECT_URI with the same URL."
echo "3. In lib/main.dart, update _apiBaseUrl with the ngrok URL."
echo "==================================================================="
echo ""
echo "Press Enter to start the Flutter app, or Ctrl+C to exit"
read

# Launch the Flutter app
echo "Starting Flutter app..."
flutter run

# Clean up when Flutter app exits
echo "Shutting down backend..."
kill $BACKEND_PID

echo "Done!" 