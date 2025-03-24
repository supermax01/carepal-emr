import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  final String baseUrl;
  final String fhirBaseUrl;
  final http.Client _httpClient = http.Client();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  ApiClient({required this.baseUrl})
      : fhirBaseUrl = 'https://YOUR_OPENEMR_HOST/apis/default/fhir';

  // Token storage keys
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenExpiryKey = 'token_expiry';

  // Token storage
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiryTime;

  // Store the patient ID once retrieved
  String? _patientId;

  // Get access token
  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _accessTokenKey);
  }

  // Get refresh token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _refreshTokenKey);
  }

  // Add auth token to headers
  Future<Map<String, String>> _getHeaders({bool requireAuth = true}) async {
    final headers = {'Content-Type': 'application/json'};

    if (requireAuth) {
      // Check if we have the token in memory first
      if (_accessToken == null) {
        _accessToken = await getAccessToken();
        debugPrint(
            'Retrieved access token from storage: ${_accessToken != null ? 'Found' : 'Not found'}');
      }

      // Check if token is expired or about to expire, and refresh if needed
      if (_accessToken != null) {
        final isExpired = await _isTokenExpired();
        if (isExpired) {
          debugPrint(
              'Token is expired or about to expire, attempting to refresh');
          final refreshed = await refreshToken();
          if (!refreshed) {
            debugPrint('Token refresh failed, clearing tokens');
            await clearTokens();
            throw Exception(
                'Authentication required - token expired and refresh failed');
          }
        }

        debugPrint('Adding authorization header with token');
        headers['Authorization'] = 'Bearer $_accessToken';
      } else if (requireAuth) {
        debugPrint('No access token available but authorization is required');
        throw Exception('Authentication required');
      }
    }

    return headers;
  }

  // Check if token is expired or about to expire (within 30 seconds)
  Future<bool> _isTokenExpired() async {
    if (_expiryTime == null) {
      final expiryStr = await _secureStorage.read(key: _tokenExpiryKey);
      if (expiryStr != null) {
        _expiryTime = DateTime.parse(expiryStr);
      } else {
        return true; // No expiry time, assume expired
      }
    }

    // Check if token expires in the next 30 seconds
    final timeUntilExpiry = _expiryTime!.difference(DateTime.now());
    debugPrint('Time until token expiry: ${timeUntilExpiry.inSeconds} seconds');
    return timeUntilExpiry.inSeconds < 30;
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null;
  }

  // Process the OAuth tokens
  Future<void> saveTokens(Map<String, dynamic> tokenData) async {
    debugPrint('Saving new tokens to secure storage');

    if (tokenData['access_token'] != null) {
      _accessToken = tokenData['access_token'];

      // Always update refresh token if provided in the response
      if (tokenData['refresh_token'] != null) {
        _refreshToken = tokenData['refresh_token'];
        debugPrint('Received new refresh token, updating storage');
        await _secureStorage.write(key: _refreshTokenKey, value: _refreshToken);
      } else {
        debugPrint(
            'No refresh token in response, keeping existing one if available');
      }

      // Store client ID associated with this token
      if (tokenData['client_id'] != null) {
        await _secureStorage.write(
            key: 'client_id', value: tokenData['client_id']);
        debugPrint('Stored client ID: ${tokenData['client_id']}');
      }

      // Save expiry time if provided
      if (tokenData['expires_in'] != null) {
        final expiresIn = tokenData['expires_in'];
        debugPrint('Token expires in $expiresIn seconds');
        _expiryTime = DateTime.now().add(Duration(seconds: expiresIn));
        debugPrint('Token expiry set to: $_expiryTime');
        await _secureStorage.write(
            key: _tokenExpiryKey, value: _expiryTime!.toIso8601String());
      }

      // Store access token
      await _secureStorage.write(key: _accessTokenKey, value: _accessToken);
      debugPrint('Tokens successfully stored');

      // Log token details for debugging (safely)
      if (_accessToken != null && _accessToken!.length > 10) {
        final tokenStart = _accessToken!.substring(0, 5);
        final tokenEnd = _accessToken!.substring(_accessToken!.length - 5);
        debugPrint('Access Token: $tokenStart...$tokenEnd');
      }
    } else {
      debugPrint('Warning: No access_token found in token data, nothing saved');
    }
  }

  // Clear all tokens
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _expiryTime = null;

    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _tokenExpiryKey);
  }

  // Handle logout
  Future<bool> logout() async {
    await clearTokens();
    return true;
  }

  // Make a GET request to a given FHIR resource endpoint
  Future<Map<String, dynamic>> getFhirResource(String resourceType,
      {String? id, Map<String, String>? parameters}) async {
    // Check token validity before making the request
    final hasToken = await hasValidToken();
    debugPrint('Has valid token before $resourceType request: $hasToken');

    // Get headers with auth token
    final headers = await _getHeaders();

    // Build the endpoint URL
    String endpoint = resourceType;
    if (id != null) {
      endpoint = '$resourceType/$id';
    }

    // Add query parameters if provided
    final queryParams = parameters ?? {};
    final uri = Uri.parse('$fhirBaseUrl/$endpoint')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    debugPrint('Making FHIR request to: $uri');

    final response = await _httpClient.get(
      uri,
      headers: headers,
    );

    debugPrint('$resourceType response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      // Attempt token refresh on 401
      debugPrint('Got 401 on $resourceType request, attempting token refresh');
      final refreshed = await refreshToken();

      if (refreshed) {
        debugPrint('Token refreshed successfully, retrying request');
        // Get fresh headers with new token
        final newHeaders = await _getHeaders();

        // Retry the request
        final retryResponse = await _httpClient.get(
          uri,
          headers: newHeaders,
        );

        if (retryResponse.statusCode == 200) {
          return jsonDecode(retryResponse.body);
        } else {
          throw Exception(
              'Failed to get $resourceType after token refresh: ${retryResponse.statusCode}');
        }
      } else {
        throw Exception('Failed to refresh token for $resourceType request');
      }
    } else {
      // Log the error response for debugging
      debugPrint('Error response: ${response.body}');
      throw Exception('Failed to get $resourceType: ${response.statusCode}');
    }
  }

  // Get patient info using requested scopes
  Future<Map<String, dynamic>> getPatientInfo() async {
    debugPrint('Getting patient information');

    try {
      // First, try to get the patient resource directly
      return await getFhirResource('Patient', parameters: {'_id': 'me'});
    } catch (e) {
      debugPrint('Error using Patient?_id=me: $e');

      try {
        // Try the Patient/me endpoint
        return await getFhirResource('Patient', id: 'me');
      } catch (e) {
        debugPrint('Error using Patient/me: $e');

        try {
          // Try getting the patient list and use the first entry
          final bundle =
              await getFhirResource('Patient', parameters: {'_count': '1'});

          if (bundle['resourceType'] == 'Bundle' &&
              bundle['entry'] != null &&
              bundle['entry'].length > 0) {
            final patientResource = bundle['entry'][0]['resource'];
            _patientId = patientResource['id'];
            debugPrint('Found patient ID from bundle: $_patientId');
            return patientResource;
          }

          throw Exception('No patient resources found in bundle');
        } catch (e) {
          debugPrint('All patient lookup methods failed: $e');
          throw Exception(
              'Unable to retrieve patient information. Please verify your access permissions.');
        }
      }
    }
  }

  // Get patient observations
  Future<Map<String, dynamic>> getObservations({String? category}) async {
    String url = '$fhirBaseUrl/Observation';

    // Build query parameters
    final queryParams = <String, String>{};

    // Filter by patient (using subject=Patient/me for the logged-in patient)
    queryParams['subject'] = 'Patient/me';

    // Add category filter if specified
    if (category != null) {
      queryParams['category'] = category;
    }

    // Sort by date
    queryParams['_sort'] = '-date';

    // Limit results
    queryParams['_count'] = '50';

    final uri = Uri.parse(url).replace(queryParameters: queryParams);

    final response = await _httpClient.get(
      uri,
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          'Failed to load observations: ${response.statusCode} - ${response.body}');
    }
  }

  // Get patient medications
  Future<Map<String, dynamic>> getMedications() async {
    debugPrint('Fetching medications for patient...');

    // Try multiple approaches to get medication data
    try {
      // First attempt: MedicationRequest with patient=Patient/me
      debugPrint('Attempt 1: Using MedicationRequest with patient=Patient/me');
      final queryParams1 = <String, String>{
        'patient': 'Patient/me',
        '_sort': '-authored',
        '_count': '50'
      };

      final uri1 = Uri.parse('$fhirBaseUrl/MedicationRequest').replace(
        queryParameters: queryParams1,
      );

      final response1 = await _httpClient.get(
        uri1,
        headers: await _getHeaders(),
      );

      debugPrint('MedicationRequest response status: ${response1.statusCode}');
      final data1 = jsonDecode(response1.body);

      // If we got results, return them
      if (response1.statusCode == 200 &&
          data1['total'] != null &&
          data1['total'] > 0) {
        debugPrint('Found ${data1['total']} medications via MedicationRequest');
        return data1;
      }

      // If no results, try another approach
      debugPrint(
          'No medications found via MedicationRequest, trying Medication resource');

      // Second attempt: Try direct Medication resource
      final queryParams2 = <String, String>{
        'subject': 'Patient/me',
        '_count': '50'
      };

      final uri2 = Uri.parse('$fhirBaseUrl/Medication').replace(
        queryParameters: queryParams2,
      );

      final response2 = await _httpClient.get(
        uri2,
        headers: await _getHeaders(),
      );

      debugPrint(
          'Medication resource response status: ${response2.statusCode}');
      final data2 = jsonDecode(response2.body);

      if (response2.statusCode == 200 &&
          data2['total'] != null &&
          data2['total'] > 0) {
        debugPrint(
            'Found ${data2['total']} medications via Medication resource');
        return data2;
      }

      // Third attempt: Try with the patient ID we have in memory
      if (_patientId != null) {
        debugPrint('Trying with specific patient ID: $_patientId');

        final queryParams3 = <String, String>{
          'patient': 'Patient/$_patientId',
          '_count': '50'
        };

        final uri3 = Uri.parse('$fhirBaseUrl/MedicationRequest').replace(
          queryParameters: queryParams3,
        );

        final response3 = await _httpClient.get(
          uri3,
          headers: await _getHeaders(),
        );

        debugPrint(
            'MedicationRequest with ID response status: ${response3.statusCode}');
        final data3 = jsonDecode(response3.body);

        if (response3.statusCode == 200) {
          return data3;
        }
      }

      // If we reach here, we had no errors but found no medications
      debugPrint('All medication lookup approaches returned empty results');
      return {
        'resourceType': 'Bundle',
        'type': 'collection',
        'total': 0,
        'entry': []
      };
    } catch (e) {
      debugPrint('Error fetching medications: $e');
      throw Exception('Failed to load medications: $e');
    }
  }

  // Get patient appointments
  Future<Map<String, dynamic>> getAppointments() async {
    final queryParams = <String, String>{
      'patient': 'Patient/me',
      '_sort': '-date',
      '_count': '10'
    };

    final uri = Uri.parse('$fhirBaseUrl/Appointment').replace(
      queryParameters: queryParams,
    );

    final response = await _httpClient.get(
      uri,
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          'Failed to load appointments: ${response.statusCode} - ${response.body}');
    }
  }

  Future<bool> hasValidToken() async {
    try {
      // First check if token exists
      final token = await getAccessToken();
      if (token == null) {
        debugPrint('No access token available');
        return false;
      }

      // Then check if it's expired
      final isExpired = await _isTokenExpired();
      if (isExpired) {
        debugPrint('Token is expired or about to expire');
        return false;
      }

      debugPrint('Valid token exists');
      return true;
    } catch (e) {
      debugPrint('Error checking token validity: $e');
      return false;
    }
  }

  // Add a method to set client credentials from auth service
  void setClientCredentials(String clientId, String clientSecret) async {
    // Store client credentials securely
    await _secureStorage.write(key: 'client_id', value: clientId);
    await _secureStorage.write(key: 'client_secret', value: clientSecret);
    debugPrint('Client credentials stored securely');
  }

  // Refresh the token
  Future<bool> refreshToken() async {
    try {
      debugPrint('Attempting to refresh token');

      // Get the refresh token from storage if not already in memory
      if (_refreshToken == null) {
        _refreshToken = await getRefreshToken();
        if (_refreshToken == null) {
          debugPrint('No refresh token available');
          return false;
        }
      }

      // Get client ID from storage
      final clientId = await _secureStorage.read(key: 'client_id');
      if (clientId == null) {
        debugPrint('No client ID available for token refresh');
        return false;
      }

      // Build token request URL
      final tokenUrl = '$baseUrl/oauth2/default/token';
      debugPrint('Refreshing token at: $tokenUrl');

      // Make the refresh token request
      final response = await _httpClient.post(
        Uri.parse(tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: Uri(queryParameters: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
          'client_id': clientId,
        }).query,
      );

      debugPrint('Refresh token response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Parse response and save new tokens
        final responseData = jsonDecode(response.body);

        if (responseData['access_token'] != null) {
          await saveTokens(responseData);
          debugPrint('Token refreshed successfully');
          return true;
        } else {
          debugPrint('Invalid refresh response: No access token found');
          return false;
        }
      } else {
        // Log the error response
        debugPrint('Token refresh failed: ${response.statusCode}');
        debugPrint('Error response: ${response.body}');

        // If unauthorized, clear the tokens
        if (response.statusCode == 401 || response.statusCode == 400) {
          debugPrint('Clearing invalid tokens');
          await clearTokens();
        }

        return false;
      }
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      return false;
    }
  }
}
