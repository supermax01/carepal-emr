import secrets
import time
import requests
from fastapi import HTTPException
from . import config
from urllib.parse import urlencode
from dotenv import load_dotenv

# In-memory token storage (in production, use a database)
# Format: {user_id: {access_token, refresh_token, expires_at, patient_id}}
token_store = {}

def generate_state():
    """Generate a random state string for OAuth security"""
    return secrets.token_urlsafe(32)

def get_authorization_url(state=None):
    """Generate the OpenEMR OAuth2 authorization URL"""
    # Reload environment variables
    load_dotenv()
    
    if state is None:
        state = generate_state()
    
    # Debug logging
    print("Authorization URL parameters:")
    print(f"OPENEMR_BASE_URL: {config.OPENEMR_BASE_URL}")
    print(f"OPENEMR_AUTHORIZE_URL: {config.OPENEMR_AUTHORIZE_URL}")
    print(f"Client ID: {config.OPENEMR_CLIENT_ID}")
    print(f"Redirect URI: {config.OPENEMR_REDIRECT_URI}")
    print(f"Scopes: {config.OPENEMR_SCOPES}")
    
    params = {
        "response_type": "code",
        "client_id": config.OPENEMR_CLIENT_ID,
        "redirect_uri": config.OPENEMR_REDIRECT_URI,
        "scope": config.OPENEMR_SCOPES,
        "state": state
    }
    
    # Use urlencode for proper URL encoding
    query = urlencode(params)
    final_url = f"{config.OPENEMR_AUTHORIZE_URL}?{query}"
    print(f"Final authorization URL: {final_url}")
    return final_url, state

def exchange_code_for_token(code):
    """Exchange authorization code for access and refresh tokens"""
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": config.OPENEMR_REDIRECT_URI
    }
    
    # Use HTTP Basic Auth for client authentication
    response = requests.post(
        config.OPENEMR_TOKEN_URL,
        data=data,
        auth=(config.OPENEMR_CLIENT_ID, config.OPENEMR_CLIENT_SECRET)
    )
    
    if response.status_code != 200:
        print(f"Token exchange failed: {response.status_code} {response.text}")
        raise HTTPException(status_code=400, detail="Failed to obtain token")
    
    token_data = response.json()
    
    # Calculate token expiration time
    expires_at = time.time() + token_data.get("expires_in", 3600)
    
    # Return token information
    return {
        "access_token": token_data.get("access_token"),
        "refresh_token": token_data.get("refresh_token"),
        "expires_at": expires_at
    }

def refresh_access_token(refresh_token):
    """Get a new access token using the refresh token"""
    data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token
    }
    
    response = requests.post(
        config.OPENEMR_TOKEN_URL,
        data=data,
        auth=(config.OPENEMR_CLIENT_ID, config.OPENEMR_CLIENT_SECRET)
    )
    
    if response.status_code != 200:
        print(f"Token refresh failed: {response.status_code} {response.text}")
        raise HTTPException(status_code=401, detail="Failed to refresh token")
    
    token_data = response.json()
    expires_at = time.time() + token_data.get("expires_in", 3600)
    
    return {
        "access_token": token_data.get("access_token"),
        "refresh_token": token_data.get("refresh_token", refresh_token),
        "expires_at": expires_at
    }

def store_user_tokens(user_id, token_data, patient_id=None):
    """Store user tokens in our token store"""
    # Add patient_id if available
    if patient_id:
        token_data["patient_id"] = patient_id
    
    token_store[user_id] = token_data
    return token_data

def get_user_tokens(user_id):
    """Get user tokens from storage, refreshing if necessary"""
    if user_id not in token_store:
        raise HTTPException(status_code=401, detail="User not authenticated")
    
    token_data = token_store[user_id]
    
    # Check if token is expired or about to expire (within 5 minutes)
    if token_data.get("expires_at", 0) < time.time() + 300:
        if "refresh_token" not in token_data:
            raise HTTPException(status_code=401, detail="No refresh token available")
        
        # Refresh the token
        new_token_data = refresh_access_token(token_data["refresh_token"])
        
        # Preserve patient_id if it exists
        if "patient_id" in token_data:
            new_token_data["patient_id"] = token_data["patient_id"]
            
        # Update stored tokens
        token_store[user_id] = new_token_data
        return new_token_data
    
    return token_data

def get_auth_header(user_id):
    """Get the Authorization header for FHIR API requests"""
    tokens = get_user_tokens(user_id)
    return {"Authorization": f"Bearer {tokens['access_token']}"}

def logout_user(user_id):
    """Remove user tokens"""
    if user_id in token_store:
        del token_store[user_id]
    return True 