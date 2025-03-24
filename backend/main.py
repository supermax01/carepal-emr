from fastapi import FastAPI, HTTPException, Request, Query
from fastapi.responses import RedirectResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
import httpx
import os
from urllib.parse import urlencode
import logging
import base64
import hashlib
import secrets
from typing import Optional

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

app = FastAPI(title="CarepalEMR API")

# Add CORS middleware for Flutter development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def generate_code_verifier() -> str:
    token = secrets.token_urlsafe(32)
    return token

def generate_code_challenge(code_verifier: str) -> str:
    """
    Generate a code challenge for PKCE.
    """
    sha256_hash = hashlib.sha256(code_verifier.encode('ascii')).digest()
    code_challenge = base64.urlsafe_b64encode(sha256_hash).decode('ascii').rstrip('=')
    return code_challenge

@app.get("/")
def root():
    return {"status": "ok", "message": "CarepalEMR API is running"}

@app.get("/api/oauth/login")
async def oauth_login(
    client_id: str = Query(..., description="OAuth client ID"),
    redirect_uri: str = Query(..., description="OAuth redirect URI"),
    response_type: str = Query("code", description="OAuth response type"),
    scope: str = Query("launch/patient openid fhirUser offline_access patient/Patient.read patient/Observation.read patient/MedicationRequest.read patient/Appointment.read", description="Patient portal scopes"),
    state: str = Query("12345", description="OAuth state parameter")
):
    """
    Start OAuth flow with PKCE support for patient portal access
    """
    try:
        logger.debug("Starting OAuth login flow with PKCE")
        logger.debug(f"Client ID: {client_id}")
        logger.debug(f"Redirect URI: {redirect_uri}")
        
        # Generate PKCE values
        code_verifier = generate_code_verifier()
        code_challenge = generate_code_challenge(code_verifier)
        
        logger.debug(f"Generated code_verifier: {code_verifier}")
        logger.debug(f"Generated code_challenge: {code_challenge}")

        # Store code_verifier for later use
        app.state.code_verifier = code_verifier

        base_url = os.getenv("OPENEMR_BASE_URL")
        if not base_url:
            raise HTTPException(status_code=500, detail="OpenEMR base URL not configured")

        logger.debug(f"Base URL: {base_url}")

        # Build authorization parameters
        params = {
            "client_id": client_id,
            "response_type": response_type,
            "redirect_uri": redirect_uri,
            "scope": scope,
            "state": state,
            "code_challenge": code_challenge,
            "code_challenge_method": "S256"
        }

        authorization_url = f"{base_url}/oauth2/default/authorize"
        full_url = f"{authorization_url}?{urlencode(params)}"
        
        logger.debug(f"Authorization URL: {full_url}")

        return JSONResponse(content={
            "authorization_url": full_url,
            "code_verifier": code_verifier,
            "state": state
        })

    except Exception as e:
        logger.error(f"Error in oauth_login: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/oauth/callback")
async def oauth_callback(
    code: Optional[str] = None,
    error: Optional[str] = None,
    error_description: Optional[str] = None
):
    logger.debug(f"Received callback with code: {code}")
    logger.debug(f"Error: {error}")
    logger.debug(f"Error description: {error_description}")

    if error:
        logger.error(f"OAuth error: {error}. Description: {error_description}")
        raise HTTPException(
            status_code=400,
            detail=f"OAuth error: {error}. Description: {error_description}"
        )

    if not code:
        logger.error("No authorization code received")
        raise HTTPException(
            status_code=400,
            detail="No authorization code received"
        )

    # Get the stored code_verifier
    code_verifier = getattr(app.state, 'code_verifier', None)
    logger.debug(f"Retrieved code_verifier: {code_verifier}")

    if not code_verifier:
        logger.error("Code verifier not found")
        raise HTTPException(
            status_code=400,
            detail="Code verifier not found"
        )

    # Exchange the authorization code for tokens
    token_url = f"{os.getenv('OPENEMR_BASE_URL')}/oauth2/default/token"
    client_id = os.getenv("OPENEMR_CLIENT_ID")
    redirect_uri = os.getenv("OPENEMR_REDIRECT_URI")

    logger.debug(f"Token URL: {token_url}")
    logger.debug(f"Using client_id: {client_id}")
    logger.debug(f"Using redirect_uri: {redirect_uri}")

    token_params = {
        "grant_type": "authorization_code",
        "code": code,
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "code_verifier": code_verifier
    }
    
    logger.debug(f"Token request parameters: {token_params}")

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(token_url, data=token_params)
            logger.debug(f"Token response status: {response.status_code}")
            
            # Log headers for debugging, but remove any sensitive info
            safe_headers = dict(response.headers)
            if 'Authorization' in safe_headers:
                safe_headers['Authorization'] = '[REDACTED]'
            logger.debug(f"Token response headers: {safe_headers}")
            
            # Log response body but truncate if too large
            response_text = response.text
            if len(response_text) > 1000:
                logger.debug(f"Token response body (truncated): {response_text[:1000]}...")
            else:
                logger.debug(f"Token response body: {response_text}")
            
            if response.status_code != 200:
                error_detail = f"Token exchange failed: {response.text}"
                logger.error(error_detail)
                raise HTTPException(
                    status_code=response.status_code,
                    detail=error_detail
                )

            return response.json()
    except httpx.RequestError as e:
        error_msg = f"Error during token exchange request: {str(e)}"
        logger.error(error_msg)
        raise HTTPException(
            status_code=500,
            detail=error_msg
        )
    except Exception as e:
        error_msg = f"Token exchange failed: {str(e)}"
        logger.error(error_msg)
        raise HTTPException(
            status_code=500,
            detail=error_msg
        )

@app.get("/api/oauth/status")
async def oauth_status():
    # Add status check implementation
    logger.debug("Checking OAuth status")
    return {"authenticated": False}  # Implement proper status check

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True) 