import requests
from fastapi import HTTPException
from . import config, auth

class FHIRClient:
    """Client for making FHIR API calls to OpenEMR"""
    
    @staticmethod
    def get_patient(user_id):
        """Get the patient resource for the authenticated user"""
        headers = auth.get_auth_header(user_id)
        
        response = requests.get(
            f"{config.OPENEMR_FHIR_BASE_URL}/Patient",
            headers=headers
        )
        
        if response.status_code != 200:
            print(f"Patient fetch failed: {response.status_code} {response.text}")
            raise HTTPException(status_code=response.status_code, 
                               detail=f"Failed to fetch patient data: {response.text}")
        
        # Extract patient ID from the bundle
        try:
            data = response.json()
            # If we get a Bundle, extract the first Patient resource
            if data.get("resourceType") == "Bundle" and data.get("entry"):
                patient = data["entry"][0]["resource"]
                patient_id = patient.get("id")
                
                # Store the patient ID with the user's tokens
                tokens = auth.get_user_tokens(user_id)
                auth.store_user_tokens(user_id, tokens, patient_id)
                
                return patient
            elif data.get("resourceType") == "Patient":
                # If we get a single Patient resource directly
                return data
            else:
                raise HTTPException(status_code=400, detail="Invalid patient data received")
        except Exception as e:
            print(f"Error processing patient data: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Error processing patient data: {str(e)}")
    
    @staticmethod
    def get_patient_observations(user_id, category=None):
        """Get observations for the patient"""
        headers = auth.get_auth_header(user_id)
        tokens = auth.get_user_tokens(user_id)
        
        # Get patient ID from tokens, if available
        patient_id = tokens.get("patient_id")
        
        # Build query parameters
        params = {}
        if patient_id:
            params["patient"] = patient_id
        if category:
            params["category"] = category
            
        response = requests.get(
            f"{config.OPENEMR_FHIR_BASE_URL}/Observation",
            headers=headers,
            params=params
        )
        
        if response.status_code != 200:
            print(f"Observations fetch failed: {response.status_code} {response.text}")
            raise HTTPException(status_code=response.status_code, 
                               detail=f"Failed to fetch observations: {response.text}")
        
        return response.json()
    
    @staticmethod
    def get_patient_medications(user_id):
        """Get medication requests for the patient"""
        headers = auth.get_auth_header(user_id)
        tokens = auth.get_user_tokens(user_id)
        
        # Get patient ID from tokens, if available
        patient_id = tokens.get("patient_id")
        
        # Build query parameters
        params = {}
        if patient_id:
            params["patient"] = patient_id
            
        response = requests.get(
            f"{config.OPENEMR_FHIR_BASE_URL}/MedicationRequest",
            headers=headers,
            params=params
        )
        
        if response.status_code != 200:
            print(f"Medications fetch failed: {response.status_code} {response.text}")
            raise HTTPException(status_code=response.status_code, 
                               detail=f"Failed to fetch medications: {response.text}")
        
        return response.json()
    
    @staticmethod
    def get_patient_appointments(user_id):
        """Get appointments for the patient"""
        headers = auth.get_auth_header(user_id)
        tokens = auth.get_user_tokens(user_id)
        
        # Get patient ID from tokens, if available
        patient_id = tokens.get("patient_id")
        
        # Build query parameters
        params = {}
        if patient_id:
            params["patient"] = patient_id
            
        response = requests.get(
            f"{config.OPENEMR_FHIR_BASE_URL}/Appointment",
            headers=headers,
            params=params
        )
        
        if response.status_code != 200:
            print(f"Appointments fetch failed: {response.status_code} {response.text}")
            raise HTTPException(status_code=response.status_code, 
                               detail=f"Failed to fetch appointments: {response.text}")
        
        return response.json() 