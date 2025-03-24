from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
from . import auth, config, fhir_client
import uuid

# Simple session management
sessions = {}

app = FastAPI(title="CarePal EMR API", description="Backend for CarePal EMR Flutter App")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Update this with your Flutter app origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dependency to get the current user ID from the request
async def get_current_user(request: Request):
    # Get session ID from cookies or Authorization header
    session_id = request.cookies.get("session_id") or request.headers.get("X-Session-ID")
    
    if not session_id or session_id not in sessions:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Return user ID from session
    return sessions[session_id]

# OAuth routes
@app.get("/api/oauth/login")
async def login():
    """Initiate the OpenEMR OAuth login process"""
    try:
        # Generate a new session ID
        session_id = str(uuid.uuid4())
        
        # Generate a state for OAuth and store it with the session
        auth_url, state = auth.get_authorization_url()
        sessions[session_id] = {"state": state}
        
        print(f"Generated session ID: {session_id}")
        print(f"Generated state: {state}")
        print(f"Redirecting to: {auth_url}")
        
        # Redirect to OpenEMR's authorization endpoint
        response = RedirectResponse(url=auth_url)
        response.set_cookie(key="session_id", value=session_id, httponly=True, secure=True)
        return response
    except Exception as e:
        print(f"Error in login route: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Login error: {str(e)}")

@app.get("/api/oauth/callback")
async def oauth_callback(request: Request, code: str, state: Optional[str] = None):
    """Handle the OAuth callback from OpenEMR"""
    # Get session ID from cookies
    session_id = request.cookies.get("session_id")
    
    if not session_id or session_id not in sessions:
        return HTMLResponse(content="<h1>Invalid session</h1><p>Please try logging in again.</p>")
    
    # Verify state if we have it
    if state and sessions[session_id].get("state") != state:
        return HTMLResponse(content="<h1>Invalid state</h1><p>Security verification failed. Please try again.</p>")
    
    try:
        # Exchange code for tokens
        token_data = auth.exchange_code_for_token(code)
        
        # Generate a user ID for this session
        user_id = str(uuid.uuid4())
        
        # Store the tokens with this user ID
        auth.store_user_tokens(user_id, token_data)
        
        # Update session with user ID
        sessions[session_id]["user_id"] = user_id
        
        # Fetch patient info to get patient ID
        fhir_client.FHIRClient.get_patient(user_id)
        
        # Redirect to Flutter app using custom URL scheme
        return HTMLResponse(content=f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Login Successful</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script>
                // Redirect to app
                window.location.href = "{config.FLUTTER_APP_REDIRECT_SCHEME}://oauth_complete";
            </script>
        </head>
        <body>
            <h1>Login Successful</h1>
            <p>You have successfully logged in. You can close this window and return to the app.</p>
        </body>
        </html>
        """)
    except Exception as e:
        print(f"Error in OAuth callback: {str(e)}")
        return HTMLResponse(content=f"<h1>Authentication Error</h1><p>Error: {str(e)}</p>")

@app.get("/api/oauth/status")
async def oauth_status(request: Request):
    """Check if the user is authenticated"""
    session_id = request.cookies.get("session_id") or request.headers.get("X-Session-ID")
    
    if not session_id or session_id not in sessions:
        return {"authenticated": False}
    
    if "user_id" not in sessions[session_id]:
        return {"authenticated": False}
    
    user_id = sessions[session_id]["user_id"]
    
    # Verify we have valid tokens
    try:
        # This will refresh the token if needed
        auth.get_user_tokens(user_id)
        return {"authenticated": True}
    except HTTPException:
        return {"authenticated": False}

@app.post("/api/oauth/logout")
async def logout(request: Request):
    """Log out the user"""
    session_id = request.cookies.get("session_id") or request.headers.get("X-Session-ID")
    
    if session_id and session_id in sessions:
        if "user_id" in sessions[session_id]:
            # Clear tokens
            auth.logout_user(sessions[session_id]["user_id"])
        
        # Remove session
        del sessions[session_id]
        
    response = JSONResponse(content={"success": True})
    response.delete_cookie(key="session_id")
    return response

# FHIR API routes
@app.get("/api/fhir/patient")
async def get_patient_info(user_id: str = Depends(get_current_user)):
    """Get patient information from OpenEMR"""
    try:
        # Extract actual user ID from session
        if isinstance(user_id, dict) and "user_id" in user_id:
            user_id = user_id["user_id"]
            
        patient_data = fhir_client.FHIRClient.get_patient(user_id)
        return patient_data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/fhir/observations")
async def get_observations(
    category: Optional[str] = None,
    user_id: str = Depends(get_current_user)
):
    """Get patient observations from OpenEMR"""
    try:
        # Extract actual user ID from session
        if isinstance(user_id, dict) and "user_id" in user_id:
            user_id = user_id["user_id"]
            
        observations = fhir_client.FHIRClient.get_patient_observations(user_id, category)
        return observations
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/fhir/medications")
async def get_medications(user_id: str = Depends(get_current_user)):
    """Get patient medications from OpenEMR"""
    try:
        # Extract actual user ID from session
        if isinstance(user_id, dict) and "user_id" in user_id:
            user_id = user_id["user_id"]
            
        medications = fhir_client.FHIRClient.get_patient_medications(user_id)
        return medications
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/fhir/appointments")
async def get_appointments(user_id: str = Depends(get_current_user)):
    """Get patient appointments from OpenEMR"""
    try:
        # Extract actual user ID from session
        if isinstance(user_id, dict) and "user_id" in user_id:
            user_id = user_id["user_id"]
            
        appointments = fhir_client.FHIRClient.get_patient_appointments(user_id)
        return appointments
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) 