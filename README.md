# CarepalEMR: Integration of Flutter with OpenEMR via HL7 FHIR

[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![HL7 FHIR R4](https://img.shields.io/badge/HL7%20FHIR-R4-E8542E)](https://hl7.org/fhir/R4/)
[![SMART on FHIR](https://img.shields.io/badge/SMART%20on%20FHIR-OAuth%202.0%20%2B%20PKCE-4B5563)](https://hl7.org/fhir/smart-app-launch/)
[![OpenEMR](https://img.shields.io/badge/OpenEMR-FHIR%20API-2E7D32)](https://www.open-emr.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Status:** research prototype (March 2025), part of the [Carepal](https://github.com/supermax01/Carepal) project.
> A patient-facing Flutter client that authenticates against OpenEMR's SMART-on-FHIR OAuth 2.0 server with PKCE
> and reads the patient's own FHIR R4 resources (Patient, Observation, MedicationRequest, Appointment, AllergyIntolerance)
> through a thin FastAPI proxy. Not a medical device; not for clinical use.
>
> **Configuration:** copy `backend/.env.example` to `backend/.env`, then replace the `YOUR_OPENEMR_HOST`,
> `YOUR_OPENEMR_CLIENT_ID`, and `YOUR_OPENEMR_CLIENT_SECRET` placeholders in `lib/main.dart`,
> `lib/services/auth_service.dart`, and `lib/models/api_client.dart` with the values from your OpenEMR
> *API Clients* registration. Never commit real credentials.

## Table of Contents

1. [Project Overview](#project-overview)
2. [System Architecture](#system-architecture)
3. [OAuth 2.0 Authentication Flow](#oauth-20-authentication-flow)
4. [FHIR Implementation](#fhir-implementation)
5. [API Layer with FastAPI](#api-layer-with-fastapi)
6. [Mobile App Architecture](#mobile-app-architecture)
7. [Security Considerations](#security-considerations)
8. [Challenges and Solutions](#challenges-and-solutions)

## Project Overview

CarepalEMR is a mobile healthcare application built with Flutter that integrates with OpenEMR (an open-source Electronic Medical Record system) through HL7 FHIR APIs. The application allows patients to:

- View their medical records
- Access lab results and vital signs
- Manage medications
- View upcoming appointments
- Access and update their personal health information

The integration leverages the standardized FHIR (Fast Healthcare Interoperability Resources) protocol, enabling interoperability with various healthcare systems beyond OpenEMR.

## System Architecture

Our system employs a multi-tier architecture with the following components:

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│                 │      │                  │      │                 │
│   Flutter App   │◄────►│  FastAPI Server  │◄────►│    OpenEMR      │
│  (Mobile Client)│      │(API Intermediary)│      │  (FHIR Server)  │
│                 │      │                  │      │                 │
└─────────────────┘      └──────────────────┘      └─────────────────┘
```

### Key Components:

1. **Flutter Mobile App**: The frontend application built with Flutter that provides a responsive and intuitive interface for patients.

2. **FastAPI Server**: An intermediary API layer built with Python's FastAPI framework that:
   - Handles OAuth token management
   - Processes FHIR queries and responses
   - Implements caching and rate limiting
   - Provides additional security controls

3. **OpenEMR FHIR API**: The OpenEMR system exposes FHIR-compliant endpoints that allow standardized access to healthcare data.

### Data Flow:

```
┌──────────┐     ┌────────────┐     ┌───────────┐      ┌────────────┐     ┌──────────┐
│          │     │            │     │           │      │            │     │          │
│  Flutter │     │  Auth      │     │  FastAPI  │      │  OpenEMR   │     │  OpenEMR │
│  Client  │◄───►│  Service   │◄───►│  Server   │◄────►│  FHIR API  │◄───►│  Database│
│          │     │            │     │           │      │            │     │          │
└──────────┘     └────────────┘     └───────────┘      └────────────┘     └──────────┘
      ▲                                    ▲                                     ▲
      │                                    │                                     │
      │                                    │                                     │
      │                                    │                                     │
      └────────────────────────────────────┴─────────────────────────────────────┘
                              Secure HTTPS Communication
```

## OAuth 2.0 Authentication Flow

Our authentication implementation uses OAuth 2.0 with PKCE (Proof Key for Code Exchange) for secure patient authorization.

### Authentication Sequence Diagram:

```
┌─────────┐          ┌────────────┐          ┌─────────┐          ┌─────────────┐
│ Flutter │          │ FastAPI    │          │ OpenEMR │          │ OpenEMR     │
│ App     │          │ Server     │          │ Auth    │          │ FHIR API    │
└────┬────┘          └─────┬──────┘          └────┬────┘          └──────┬──────┘
     │                     │                      │                      │
     │  1. Generate PKCE   │                      │                      │
     │  Code Verifier &    │                      │                      │
     │  Code Challenge     │                      │                      │
     │                     │                      │                      │
     │  2. Authorization Request                  │                      │
     │─────────────────────────────────────────────>                    │
     │                     │                      │                      │
     │                     │                      │  3. User Login       │
     │                     │                      │  & Consent           │
     │                     │                      │                      │
     │  4. Authorization Code                     │                      │
     │<─────────────────────────────────────────────                    │
     │                     │                      │                      │
     │  5. Token Request with                     │                      │
     │  Code & Code Verifier                      │                      │
     │─────────────────────>                      │                      │
     │                     │                      │                      │
     │                     │  6. Validate Code    │                      │
     │                     │  & Exchange for      │                      │
     │                     │  Access Token        │                      │
     │                     │─────────────────────>│                      │
     │                     │                      │                      │
     │                     │  7. Access & Refresh │                      │
     │                     │  Tokens              │                      │
     │                     │<─────────────────────│                      │
     │                     │                      │                      │
     │  8. Return Tokens   │                      │                      │
     │<────────────────────│                      │                      │
     │                     │                      │                      │
     │  9. Request FHIR Resource with Access Token│                      │
     │───────────────────────────────────────────────────────────────────>
     │                     │                      │                      │
     │                     │                      │  10. Validate Token  │
     │                     │                      │────────────────────> │
     │                     │                      │                      │
     │                     │                      │  11. Return FHIR     │
     │                     │                      │  Resource            │
     │                     │                      │<────────────────────│
     │                     │                      │                      │
     │  12. FHIR Resource  │                      │                      │
     │<───────────────────────────────────────────────────────────────────
     │                     │                      │                      │
     │  13. Token Refresh when Expired            │                      │
     │─────────────────────>                      │                      │
     │                     │                      │                      │
     │                     │  14. Request New     │                      │
     │                     │  Access Token        │                      │
     │                     │─────────────────────>│                      │
     │                     │                      │                      │
     │                     │  15. New Access Token│                      │
     │                     │<─────────────────────│                      │
     │                     │                      │                      │
     │  16. New Access Token                      │                      │
     │<────────────────────│                      │                      │
     │                     │                      │                      │
```

### Implementation Details:

1. **PKCE Flow**: We implement the PKCE extension of OAuth 2.0 for enhanced security on mobile devices:
   - The app generates a cryptographically secure random `code_verifier`
   - A `code_challenge` is derived through SHA-256 hashing of the verifier
   - The challenge is sent in the authorization request, and the verifier is used in the token exchange

2. **Scope Management**: Our login screen allows users to select different access levels:
   ```dart
   final List<String> _scopeValues = [
     'launch/patient patient/*.read offline_access',
     'launch/patient patient/Patient.read offline_access',
     'launch/patient patient/Patient.read patient/Medication.read patient/Observation.read offline_access',
   ];
   ```

3. **Token Storage**: We securely store access and refresh tokens using `flutter_secure_storage`.

4. **Token Refresh**: Automatic token refresh when the access token is about to expire:
   ```dart
   Future<bool> refreshToken() async {
     // Implementation details for token refresh
     // Using offline_access scope to enable refresh tokens
   }
   ```

## FHIR Implementation

We implemented FHIR R4 (Release 4) standard for healthcare data exchange with OpenEMR.

### FHIR Resources Used:

| FHIR Resource     | Purpose                        | Endpoints Used                            |
|-------------------|--------------------------------|-------------------------------------------|
| Patient           | Patient demographics           | `/Patient/$id`, `/Patient?_id=me`         |
| Observation       | Vital signs and lab results    | `/Observation?category=vital-signs`       |
| MedicationRequest | Current and past medications   | `/MedicationRequest?patient=Patient/me`   |
| Appointment       | Scheduled appointments         | `/Appointment?patient=Patient/me`         |
| AllergyIntolerance| Patient allergies              | `/AllergyIntolerance?patient=Patient/me`  |

### FHIR Data Model:

```
┌─────────────────┐       ┌────────────────┐       ┌─────────────────────┐
│    Patient      │       │  Observation   │       │   MedicationRequest │
├─────────────────┤       ├────────────────┤       ├─────────────────────┤
│ - id            │       │ - id           │       │ - id                │
│ - name          │◄──┐   │ - status       │       │ - status            │
│ - gender        │   │   │ - category     │       │ - medicationCodeable│
│ - birthDate     │   │   │ - code         │       │   Concept           │
│ - address       │   │   │ - subject      │─────► │ - subject           │─────┐
│ - telecom       │   │   │ - effectiveDate│       │ - authoredOn        │     │
│ - maritalStatus │   │   │ - value[x]     │       │ - dosageInstruction │     │
└─────────────────┘   │   └────────────────┘       └─────────────────────┘     │
                      │                                                         │
                      │    ┌────────────────┐      ┌─────────────────────┐      │
                      │    │  Appointment   │      │  AllergyIntolerance │      │
                      │    ├────────────────┤      ├─────────────────────┤      │
                      └────│ - participant  │      │ - id                │      │
                           │ - status       │      │ - clinicalStatus    │      │
                           │ - start        │      │ - verificationStatus│      │
                           │ - end          │      │ - patient           │◄─────┘
                           │ - serviceType  │      │ - code              │
                           └────────────────┘      │ - reaction          │
                                                   └─────────────────────┘
```

### Resource Extraction Utilities:

To handle FHIR data, we implemented robust extraction helpers that safely parse FHIR resources:

```dart
// Safely extract a value from a map, with error handling
dynamic safeExtract(Map<String, dynamic>? data, List<dynamic> path, {dynamic defaultValue}) {
  if (data == null) return defaultValue;
  
  dynamic current = data;
  for (var key in path) {
    if (current == null) return defaultValue;
    
    if (current is Map) {
      if (!current.containsKey(key)) return defaultValue;
      current = current[key];
    } else if (current is List) {
      if (key is int) {
        if (key < 0 || key >= current.length) return defaultValue;
        current = current[key];
      } else {
        return defaultValue;
      }
    } else {
      return defaultValue;
    }
  }
  
  return current ?? defaultValue;
}
```

These utilities help us handle variable FHIR response structures and ensure stability when unexpected data formats are encountered.

## API Layer with FastAPI

We built a FastAPI-based intermediary service to enhance security, provide additional functionality, and abstract the complexity of directly interfacing with OpenEMR's FHIR API.

### FastAPI Architecture:

```
┌────────────────────────────────────────┐
│           FastAPI Application          │
├────────────────────────────────────────┤
│                                        │
│ ┌─────────────────┐ ┌────────────────┐ │
│ │ Authentication  │ │  FHIR Resource │ │
│ │   Endpoints     │ │    Endpoints   │ │
│ └─────────────────┘ └────────────────┘ │
│           │                 │          │
│ ┌─────────┴─────────┐ ┌─────┴───────┐  │
│ │ OAuth2 Management │ │ FHIR Client │  │
│ └───────────────────┘ └─────────────┘  │
│           │                 │          │
│ ┌─────────┴─────────┐ ┌─────┴───────┐  │
│ │ Token Management  │ │ API Response│  │
│ │    Service        │ │  Processing │  │
│ └───────────────────┘ └─────────────┘  │
│                                        │
└────────────────────────────────────────┘
         │                    │
┌────────┴───────────┐ ┌─────┴───────────┐
│ JWT Token          │ │ Redis Cache     │
│ Validation Layer   │ │                 │
└────────────────────┘ └─────────────────┘
         │                    │
         └────────┬───────────┘
                  │
         ┌────────┴───────────┐
         │     OpenEMR        │
         │     FHIR API       │
         └────────────────────┘
```

### FastAPI Benefits:

1. **Performance**: FastAPI is built on Starlette and Pydantic, providing high performance with automatic validation.

2. **Security Layer**: Implements additional security measures:
   - Rate limiting
   - JWT token validation
   - Access control rules
   - Request/response logging

3. **Error Handling**: Provides standardized error responses and appropriate status codes.

4. **Caching**: Implements Redis-based caching for frequently accessed FHIR resources to reduce load on OpenEMR.

### Key FastAPI Endpoints:

```python
# OAuth2 token endpoints
@app.post("/oauth/token")
async def token_exchange(
    grant_type: str = Form(...),
    code: Optional[str] = Form(None),
    refresh_token: Optional[str] = Form(None),
    code_verifier: Optional[str] = Form(None),
    client_id: str = Form(...),
    client_secret: Optional[str] = Form(None),
    redirect_uri: Optional[str] = Form(None)
):
    # Token exchange implementation
    pass

# FHIR proxy endpoints
@app.get("/fhir/{resource_type}")
async def get_fhir_resource(
    resource_type: str,
    request: Request,
    current_user: User = Depends(get_current_user)
):
    # Proxy FHIR resource requests
    pass

# Patient-specific endpoint
@app.get("/fhir/Patient/me")
async def get_patient_info(current_user: User = Depends(get_current_user)):
    # Get current patient information
    pass
```

## Mobile App Architecture

Our Flutter application follows a layered architecture that separates concerns and promotes maintainability.

### App Architecture Diagram:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Presentation Layer                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Login Screen│  │ Home Screen │  │Other Screens│  Widgets    │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────┐
│                      Business Logic Layer                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │AuthService  │  │ FhirService │  │Other Services│ State Mgmt │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────┐
│                        Data Layer                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  ApiClient  │  │FHIR Helpers │  │Secure Storage│ Data Models│
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────┐
│                      External Services                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ FastAPI     │  │  OpenEMR    │  │Other Systems│             │
│  │  Server     │  │  FHIR API   │  │             │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components:

1. **ApiClient**: Handles HTTP requests, token management, and FHIR resource retrieval:
   ```dart
   class ApiClient {
     final String baseUrl;
     final String fhirBaseUrl;
     
     // Makes a GET request to FHIR resource endpoint
     Future<Map<String, dynamic>> getFhirResource(String resourceType, {String? id}) async {
       // Implementation details
     }
     
     // Handles token refresh
     Future<bool> refreshToken() async {
       // Implementation details
     }
   }
   ```

2. **FhirService**: Provides domain-specific methods to work with FHIR resources:
   ```dart
   class FhirService {
     final ApiClient _apiClient;
     
     // Get patient information
     Future<Map<String, dynamic>> getPatientInfo() async {
       // Implementation details
     }
     
     // Extract resources from a FHIR Bundle
     List<Map<String, dynamic>> extractResourcesFromBundle(Map<String, dynamic>? bundle) {
       // Implementation details
     }
   }
   ```

3. **AuthService**: Manages OAuth flow, deep links, and authentication state:
   ```dart
   class AuthService {
     final String baseUrl;
     final String clientId;
     final String redirectUri;
     final ApiClient apiClient;
     
     // Initiate OAuth flow
     Future<void> login({int? scopeOption, String? scopeValue}) async {
       // Implementation details
     }
     
     // Check authentication status
     Future<bool> isAuthenticated() async {
       // Implementation details
     }
   }
   ```

4. **FHIR Helper Functions**: Utilities to safely extract data from FHIR resources:
   ```dart
   // Extract patient name from a FHIR Patient resource
   String getPatientName(Map<String, dynamic>? patient) {
     // Implementation details
   }
   
   // Extract observation value from a FHIR Observation resource
   String getObservationValue(Map<String, dynamic>? observation) {
     // Implementation details
   }
   ```

### Screen Implementation:

Our screens are designed to handle loading states, errors, and display FHIR data:

```dart
class ObservationsScreen extends StatefulWidget {
  final FhirService fhirService;
  
  // Implementation details
}

class _ObservationsScreenState extends State<ObservationsScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _vitalSigns = [];
  
  // Fetch FHIR data
  Future<void> _fetchVitalSigns() async {
    try {
      final response = await widget.fhirService.getVitalSigns();
      List<Map<String, dynamic>> vitalSigns = 
          widget.fhirService.extractResourcesFromBundle(response);
      setState(() => _vitalSigns = vitalSigns);
    } catch (e) {
      setState(() => _errorMessage = 'Error loading vital signs: $e');
    }
  }
  
  // Build UI based on loaded data
  Widget _buildVitalSignsList() {
    // Implementation details
  }
}
```

## Security Considerations

Security is paramount in healthcare applications. Our implementation includes:

1. **OAuth 2.0 with PKCE**: Prevents authorization code interception attacks.

2. **Secure Storage**: All tokens are stored in the platform's secure storage.

3. **Token Refresh**: Automatic refresh of expired tokens with proper error handling.

4. **TLS/SSL**: All communications secured with HTTPS.

5. **Minimal Scope Access**: Requesting only the needed FHIR resource access.

6. **Data Sanitization**: Input validation and output sanitization to prevent injection attacks.

7. **Error Handling**: Careful error handling that doesn't expose sensitive information.

## Challenges and Solutions

### Challenge 1: OAuth Implementation in Mobile Apps

**Solution**: Implemented OAuth 2.0 with PKCE for enhanced security, with custom deep link handling to capture authorization callbacks.

### Challenge 2: Varying FHIR Resource Formats

**Solution**: Created robust helper functions that safely extracted data from FHIR resources, handling missing or malformed data gracefully.

### Challenge 3: Token Management

**Solution**: Implemented automatic token refresh, secure token storage, and graceful handling of authentication failures.

### Challenge 4: Performance with Large FHIR Resources

**Solution**: Added pagination support, implemented caching in the FastAPI layer, and optimized queries with specific parameters.

### Challenge 5: Inconsistent OpenEMR FHIR Implementation

**Solution**: Built a flexible API client that can try alternative endpoints and query parameters when the primary approach fails.

## Conclusion

The CarepalEMR app demonstrates a comprehensive integration between Flutter and OpenEMR using HL7 FHIR standards. The architecture employs modern security practices, resilient data handling, and a clean separation of concerns.

By leveraging industry standards like OAuth 2.0 and FHIR R4, the application achieves interoperability while maintaining security and performance. The FastAPI intermediate layer adds flexibility and additional security controls beyond what's available in the base OpenEMR FHIR API.

---

## Appendix: Key Technologies

- **Flutter**: For cross-platform mobile development
- **Dart**: Programming language for Flutter
- **FastAPI**: Python web framework for API development
- **OAuth 2.0 with PKCE**: Authentication protocol
- **HL7 FHIR R4**: Healthcare interoperability standard
- **OpenEMR**: Open-source electronic medical record system
- **Redis**: For caching frequently accessed data
- **JWT**: For token-based authentication
- **PostgreSQL**: For data persistence in FastAPI service
