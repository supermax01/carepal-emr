import os
from dotenv import load_dotenv

# Always reload environment variables
load_dotenv(override=True)

# OpenEMR Configuration
OPENEMR_BASE_URL = os.getenv("OPENEMR_BASE_URL")
OPENEMR_SITE_ID = os.getenv("OPENEMR_SITE_ID", "default")
OPENEMR_CLIENT_ID = os.getenv("OPENEMR_CLIENT_ID")
OPENEMR_CLIENT_SECRET = os.getenv("OPENEMR_CLIENT_SECRET")
OPENEMR_REDIRECT_URI = os.getenv("OPENEMR_REDIRECT_URI")

# API Endpoints
OPENEMR_AUTHORIZE_URL = f"{OPENEMR_BASE_URL}/oauth2/{OPENEMR_SITE_ID}/authorize"
OPENEMR_TOKEN_URL = f"{OPENEMR_BASE_URL}/oauth2/{OPENEMR_SITE_ID}/token"
OPENEMR_FHIR_BASE_URL = f"{OPENEMR_BASE_URL}/apis/{OPENEMR_SITE_ID}/fhir"

# App Settings
FLUTTER_APP_REDIRECT_SCHEME = os.getenv("FLUTTER_APP_REDIRECT_SCHEME", "carepalemr")

# API Configuration
API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = int(os.getenv("API_PORT", "8000"))
DEBUG = os.getenv("DEBUG", "false").lower() == "true"

# OAuth Scopes required for our application
OPENEMR_SCOPES = "launch/patient openid fhirUser offline_access api:fhir patient/Patient.read patient/Observation.read patient/MedicationRequest.read patient/Appointment.read" 