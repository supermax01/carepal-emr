import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uni_links/uni_links.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/api_client.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final String baseUrl;
  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final ApiClient apiClient;

  // Store code verifier at class level to ensure persistence
  String? _codeVerifier;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _codeVerifierKey = 'code_verifier';
  static const String _tokenExpiryKey = 'token_expiry';
  bool _deepLinkInitialized = false;
  bool _isProcessingAuth = false;
  bool _isAuthenticated = false;
  Timer? _authTimer;
  StreamSubscription? _uriLinkSubscription;
  final _authStateController = StreamController<bool>.broadcast();

  // Track if already processing a specific code
  String? _processingCode;

  Stream<bool> get authState => _authStateController.stream;

  AuthService({
    this.baseUrl = 'http://localhost:8000',
    this.clientId = 'YOUR_OPENEMR_CLIENT_ID',
    this.clientSecret =
        'YOUR_OPENEMR_CLIENT_SECRET', // Default client secret
    this.redirectUri = 'carepalemr://oauth/callback',
    required this.apiClient,
  }) {
    checkAuthentication();
  }

  Future<void> checkAuthentication() async {
    debugPrint('Checking authentication status...');
    try {
      // First check if token is valid in terms of expiration time
      final hasToken = await apiClient.hasValidToken();
      debugPrint('API client has valid token: $hasToken');

      if (hasToken) {
        // Try to refresh the token if needed
        if (await _shouldRefreshToken()) {
          debugPrint('Token is close to expiry, attempting to refresh');
          final refreshed = await apiClient.refreshToken();
          if (!refreshed) {
            debugPrint('Token refresh failed');
            _isAuthenticated = false;
          } else {
            debugPrint('Token refreshed successfully');
            _isAuthenticated = true;
          }
        } else {
          // Token is valid and not close to expiry
          _isAuthenticated = true;
        }
      } else {
        _isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('Error checking authentication: $e');
      _isAuthenticated = false;
    }

    _authStateController.add(_isAuthenticated);
    debugPrint('Auth state checked and set to: $_isAuthenticated');
  }

  // Single point of initialization for deep link listener
  void _initDeepLinkListener() {
    if (_deepLinkInitialized) {
      debugPrint('Deep link listener already initialized, skipping');
      return;
    }

    debugPrint('Initializing deep link listener');
    _deepLinkInitialized = true;

    _uriLinkSubscription?.cancel();
    _uriLinkSubscription = uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        debugPrint('Received deep link: $uri');
        _handleDeepLink(uri);
      }
    }, onError: (err) {
      debugPrint('URI Stream error: $err');
    });
  }

  Future<void> login({int? scopeOption, String? scopeValue}) async {
    // Prevent multiple concurrent login attempts
    if (_isProcessingAuth) {
      debugPrint('Auth processing already in progress, skipping');
      return;
    }

    _isProcessingAuth = true;
    _processingCode = null; // Reset the processing code

    try {
      // Clear any previous state to ensure a fresh start
      _isAuthenticated = false;
      _authStateController.add(false);

      // Generate PKCE code verifier upfront to ensure it exists
      _codeVerifier = _generateCodeVerifier();
      // Store the code verifier persistently
      await _secureStorage.write(key: _codeVerifierKey, value: _codeVerifier);
      debugPrint('Generated and stored new code verifier: $_codeVerifier');

      final uri =
          await _getLoginUrl(scopeOption: scopeOption, scopeValue: scopeValue);
      if (uri != null) {
        // Ensure we're listening for deep links
        _listenForCallback();

        // Launch the URL
        debugPrint('Launching URL: $uri');
        final launchResult = await launchUrl(Uri.parse(uri),
            mode: LaunchMode.externalApplication);

        if (!launchResult) {
          debugPrint('Failed to launch URL');
          _isProcessingAuth = false;
          _authStateController.add(false);
        }
      } else {
        debugPrint('Failed to get login URL');
        _isProcessingAuth = false;
        _authStateController.add(false);
      }
    } catch (e) {
      debugPrint('Error during login: $e');
      _isProcessingAuth = false;
      _authStateController.add(false);
    }
  }

  void _listenForCallback() {
    _authTimer?.cancel();
    _authTimer = Timer(const Duration(minutes: 5), () {
      debugPrint('Auth timeout - no callback received');
      _isProcessingAuth = false;
      _processingCode = null;
      _authStateController.add(false);
    });

    // Initialize deep link listener if not already set
    _initDeepLinkListener();
  }

  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint('Handling deep link: $uri');
    debugPrint('Path: "${uri.path}", Host: "${uri.host}"');

    // Check if this is an OAuth callback
    // The URI could be either:
    // 1. carepalemr://oauth/callback?code=...  (path contains /oauth/callback)
    // 2. carepalemr:oauth/callback?code=...    (path is empty, authority is oauth/callback)
    bool isOAuthCallback = false;

    if (uri.path.contains('oauth/callback')) {
      isOAuthCallback = true;
      debugPrint('Identified as OAuth callback via path');
    } else if (uri.toString().contains('oauth/callback')) {
      isOAuthCallback = true;
      debugPrint('Identified as OAuth callback via URI string');
    } else if (uri.host == 'oauth' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'callback') {
      isOAuthCallback = true;
      debugPrint('Identified as OAuth callback via host+pathSegments');
    }

    if (!isOAuthCallback) {
      debugPrint('Not an OAuth callback, ignoring');
      return;
    }

    // Cancel timeout timer as we've received the callback
    _authTimer?.cancel();

    // Avoid processing if not in authentication flow
    if (!_isProcessingAuth) {
      debugPrint(
          'OAuth callback received but not in authentication flow, ignoring');
      return;
    }

    // Extract code parameter regardless of URI structure
    String? code;
    if (uri.queryParameters.containsKey('code')) {
      code = uri.queryParameters['code'];
    } else {
      // In some cases, the URI might be malformed and we need to parse it manually
      final uriString = uri.toString();
      final codeIndex = uriString.indexOf('code=');
      if (codeIndex != -1) {
        // Extract from code= to either & or end of string
        final codeStart = codeIndex + 5; // 'code='.length
        final ampIndex = uriString.indexOf('&', codeStart);
        code = ampIndex != -1
            ? uriString.substring(codeStart, ampIndex)
            : uriString.substring(codeStart);

        debugPrint('Manually extracted code parameter');
      }
    }

    final error = uri.queryParameters['error'];
    final errorDescription = uri.queryParameters['error_description'];

    debugPrint(
        'Auth callback received with code: ${code != null ? 'present' : 'missing'}, error: $error');

    if (error != null) {
      debugPrint('OAuth error: $error - $errorDescription');
      _isProcessingAuth = false;
      _processingCode = null;
      _authStateController.add(false);
      return;
    }

    if (code != null) {
      // Check if we're already processing this code
      if (_processingCode == code) {
        debugPrint('Already processing this code, ignoring duplicate callback');
        return;
      }

      _processingCode = code; // Mark this code as being processed
      debugPrint('Processing authentication code - length: ${code.length}');

      try {
        // Immediately exchange code for token to prevent timeout
        // Get the stored code verifier from secure storage if not in memory
        String? codeVerifier = _codeVerifier;
        if (codeVerifier == null || codeVerifier.isEmpty) {
          debugPrint('No code verifier in memory, checking secure storage');
          codeVerifier = await _secureStorage.read(key: _codeVerifierKey);
        }

        if (codeVerifier == null || codeVerifier.isEmpty) {
          debugPrint('No code verifier found in memory or storage');
          _isProcessingAuth = false;
          _processingCode = null;
          _authStateController.add(false);
          return;
        }

        debugPrint('Got authorization code of length: ${code.length}');
        if (code.length > 30) {
          debugPrint('Code starts with: ${code.substring(0, 30)}...');
        } else {
          debugPrint('Code: $code');
        }
        debugPrint('Using code verifier: $codeVerifier');

        // Exchange code for token with the verifier
        await _exchangeCodeForToken(code, codeVerifier);
      } catch (e) {
        debugPrint('Error handling callback: $e');
        _isProcessingAuth = false;
        _processingCode = null;
        _authStateController.add(false);
      }
    } else {
      debugPrint('No code found in callback URI: $uri');
      _isProcessingAuth = false;
      _processingCode = null;
      _authStateController.add(false);
    }
  }

  Future<String?> _getLoginUrl({int? scopeOption, String? scopeValue}) async {
    try {
      // Use the already generated code verifier
      if (_codeVerifier == null || _codeVerifier!.isEmpty) {
        debugPrint('No code verifier found, generating a new one');
        _codeVerifier = _generateCodeVerifier();
        // Store it immediately
        await _secureStorage.write(key: _codeVerifierKey, value: _codeVerifier);
      }

      // Generate code challenge from the verifier
      final codeChallenge = _generateCodeChallenge(_codeVerifier!);

      debugPrint('Code Verifier: $_codeVerifier');
      debugPrint('Code Challenge: $codeChallenge');

      // Define different scope combinations to try
      final scopeOptions = [
        // Option 1: Complete set of patient scopes as listed by user
        'openid fhirUser online_access offline_access launch/patient api:oemr api:fhir '
            'patient/AllergyIntolerance.read patient/Appointment.read patient/Binary.read '
            'patient/CarePlan.read patient/CareTeam.read patient/Condition.read patient/Coverage.read '
            'patient/Device.read patient/DiagnosticReport.read patient/DocumentReference.read '
            'patient/Encounter.read patient/Goal.read patient/Immunization.read patient/Location.read '
            'patient/Medication.read patient/MedicationRequest.read patient/Observation.read '
            'patient/Organization.read patient/Patient.read patient/Person.read patient/Practitioner.read '
            'patient/Procedure.read patient/Provenance.read',

        // Option 2: Basic patient identification only
        'openid fhirUser patient/Patient.read offline_access',

        // Option 3: Minimal read-only scopes for patient context
        'openid patient/Patient.read patient/Observation.read patient/MedicationRequest.read offline_access',
      ];

      // Use the explicitly provided scopeValue if available, otherwise use the predefined options
      final String scope;
      if (scopeValue != null && scopeValue.isNotEmpty) {
        scope = scopeValue;
        debugPrint('Using explicitly provided scope: $scope');
      } else {
        scope = scopeOptions[scopeOption ?? 0];
        debugPrint('Using predefined scope option: $scope');
      }

      // Construct authorization URL with query parameters
      final authUrl = '$baseUrl/oauth2/default/authorize';
      final state = _generateRandomString(32);

      final uri = Uri.parse(authUrl).replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'scope': scope,
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

      debugPrint('Complete authorization URL: $uri');
      return uri.toString();
    } catch (e) {
      debugPrint('Error building authorization URL: $e');
      return null;
    }
  }

  Future<void> _exchangeCodeForToken(String code, String codeVerifier) async {
    try {
      debugPrint('=== OAUTH DEBUG: Starting token exchange ===');
      debugPrint(
          'Code length: ${code.length}, Verifier length: ${codeVerifier.length}');

      // Build token request
      final tokenUrl = '$baseUrl/oauth2/default/token';
      debugPrint('Token endpoint URL: $tokenUrl');

      // Create properly encoded form data
      final formData = {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      };

      // Log parameters for debugging
      debugPrint('Token request parameters:');
      formData.forEach((key, value) {
        if (key == 'code') {
          // Don't log the entire code as it might be very long
          if (value.length > 30) {
            debugPrint(
                '  $key: ${value.substring(0, 30)}... (length: ${value.length})');
          } else {
            debugPrint('  $key: $value');
          }
        } else if (key == 'client_secret') {
          debugPrint('  $key: [REDACTED]'); // Don't log the secret
        } else {
          debugPrint('  $key: $value');
        }
      });

      // Convert to form-urlencoded format
      final encodedBody = formData.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      debugPrint('Making POST request to token endpoint...');

      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: encodedBody,
      );

      debugPrint('=== OAUTH DEBUG: Token Response Received ===');
      debugPrint('Token Response Status: ${response.statusCode}');

      // Log headers for troubleshooting
      debugPrint('Response Headers:');
      response.headers.forEach((key, value) {
        debugPrint('  $key: $value');
      });

      // Log the response body regardless of status code (for debugging)
      debugPrint('=== OAUTH DEBUG: Token Response Body ===');
      debugPrint(response.body);

      if (response.statusCode == 200) {
        try {
          debugPrint('=== OAUTH DEBUG: Token Exchange Successful ===');
          debugPrint('Full response body: ${response.body}');

          final tokens = jsonDecode(response.body);
          debugPrint('Successfully received tokens:');
          // Safely log token info without exposing full tokens
          if (tokens['access_token'] != null) {
            final accessToken = tokens['access_token'] as String;
            debugPrint(
                '  access_token: ${accessToken.substring(0, min(10, accessToken.length))}...');
          } else {
            debugPrint('  WARNING: access_token is missing!');
          }
          if (tokens['refresh_token'] != null) {
            debugPrint('  refresh_token: present');
          } else {
            debugPrint('  WARNING: refresh_token is missing!');
          }
          if (tokens['expires_in'] != null) {
            debugPrint('  expires_in: ${tokens['expires_in']}');
          } else {
            debugPrint('  WARNING: expires_in is missing!');
          }

          // Save tokens to ApiClient
          await apiClient.saveTokens(tokens);

          debugPrint('Tokens stored successfully');

          // Update authentication state
          _isAuthenticated = true;
          _isProcessingAuth = false;
          _processingCode = null;

          // Broadcast auth state change with slight delay to ensure UI can update
          debugPrint(
              '=== OAUTH DEBUG: Broadcasting authentication success ===');
          // First broadcast immediately to trigger quick state change
          _authStateController.add(true);

          // Then broadcast again after a delay to ensure UI has time to react
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (_isAuthenticated) {
              debugPrint('Delayed auth broadcast - still authenticated');
              _authStateController.add(true);
            }
          });
        } catch (e) {
          debugPrint('=== OAUTH DEBUG: Error processing tokens: $e ===');
          debugPrint('Error parsing or storing tokens: $e');
          _isProcessingAuth = false;
          _processingCode = null;
          _authStateController.add(false);
          throw Exception('Failed to parse or store tokens: $e');
        }
      } else {
        debugPrint('=== OAUTH DEBUG: Token Exchange Failed ===');
        final errorBody = response.body;
        debugPrint('Failed to exchange code: $errorBody');

        // Try to parse the error for more details
        try {
          final errorJson = jsonDecode(errorBody);
          final errorMessage = errorJson['error_description'] ??
              errorJson['error'] ??
              'Unknown error';
          debugPrint('Token error: $errorMessage');
        } catch (e) {
          debugPrint('Could not parse error response: $e');
        }

        _isProcessingAuth = false;
        _processingCode = null;
        _authStateController.add(false);
        throw Exception('Failed to exchange code for token: $errorBody');
      }
    } catch (e) {
      debugPrint('=== OAUTH DEBUG: Exception during token exchange: $e ===');
      debugPrint('Error exchanging code for token: $e');
      _isProcessingAuth = false;
      _processingCode = null;
      _authStateController.add(false);
      rethrow;
    }
  }

  Future<void> logout() async {
    await apiClient.clearTokens();
    // Clear the code verifier when logging out
    await _secureStorage.delete(key: _codeVerifierKey);
    _isAuthenticated = false;
    _isProcessingAuth = false;
    _processingCode = null;
    _authStateController.add(false);
  }

  Future<bool> isAuthenticated() async {
    return _isAuthenticated;
  }

  // PKCE Helpers
  String _generateCodeVerifier() {
    // Generate a code verifier between 43-128 characters
    final random = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    const length = 64; // Good balance between security and size

    final verifier =
        List.generate(length, (_) => chars[random.nextInt(chars.length)])
            .join();

    debugPrint(
        'Generated code verifier: $verifier (length: ${verifier.length})');
    return verifier;
  }

  String _generateCodeChallenge(String verifier) {
    debugPrint('Generating code challenge for verifier: $verifier');
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    final challenge = base64UrlEncode(digest.bytes)
        .replaceAll('=', '') // Remove base64 padding
        .replaceAll('+', '-') // Replace + with - (for URL safety)
        .replaceAll('/', '_'); // Replace / with _ (for URL safety)
    debugPrint(
        'Generated code challenge: $challenge (length: ${challenge.length})');
    return challenge;
  }

  void dispose() {
    _authTimer?.cancel();
    _uriLinkSubscription?.cancel();
    _authStateController.close();
  }

  // Public method to initialize deep link handling from app startup
  void initializeDeepLinkHandling() {
    _initDeepLinkListener();
  }

  // Check if token should be refreshed (if it expires within 2 minutes)
  Future<bool> _shouldRefreshToken() async {
    try {
      // Get token expiry from secure storage
      final expiryStr = await _secureStorage.read(key: _tokenExpiryKey);
      if (expiryStr == null) {
        return true; // No expiry time means we should refresh
      }

      final expiryTime = DateTime.parse(expiryStr);
      final timeUntilExpiry = expiryTime.difference(DateTime.now());
      debugPrint(
          'Time until token expiry: ${timeUntilExpiry.inSeconds} seconds');

      // Refresh if token expires within 2 minutes
      return timeUntilExpiry.inSeconds < 120;
    } catch (e) {
      debugPrint('Error checking token expiry: $e');
      return true; // Refresh on error to be safe
    }
  }

  // Add a method to force token refresh with fallback to full re-auth
  Future<bool> forceTokenRefresh() async {
    debugPrint('Force refreshing token...');

    // First try to refresh the token
    final refreshed = await apiClient.refreshToken();
    if (refreshed) {
      _isAuthenticated = true;
      _authStateController.add(true);
      debugPrint('Force token refresh successful');
      return true;
    } else {
      debugPrint('Token refresh failed, attempting full re-authentication');

      // If refresh fails, we need to do a full re-auth
      try {
        // Clear tokens but maintain code verifier if possible
        // Don't clear _codeVerifier as we want to keep the existing one if possible
        await apiClient.clearTokens();
        _isAuthenticated = false;
        _isProcessingAuth = false;
        _processingCode = null;

        // Update auth state immediately
        _authStateController.add(false);

        // Try to re-authenticate
        return await reAuthenticate();
      } catch (e) {
        debugPrint('Re-authentication failed: $e');
        _isAuthenticated = false;
        _authStateController.add(false);
        return false;
      }
    }
  }

  // Method to perform a full re-authentication when needed
  Future<bool> reAuthenticate() async {
    debugPrint('Performing full re-authentication');

    // Set flags to indicate we're in authentication flow
    _isAuthenticated = false;
    _isProcessingAuth = true;
    _processingCode = null;

    // Use the existing login flow
    try {
      await login();

      // Wait for authentication to complete (with timeout)
      bool authenticated = false;
      int attempts = 0;

      // Check every second for up to 30 seconds
      while (!authenticated && attempts < 30) {
        await Future.delayed(const Duration(seconds: 1));
        authenticated = await isAuthenticated();
        attempts++;

        debugPrint(
            'Waiting for re-authentication... attempt $attempts, authenticated: $authenticated');

        if (authenticated) {
          debugPrint('Re-authentication successful after $attempts attempts');
          return true;
        }
      }

      debugPrint('Re-authentication timed out after $attempts attempts');
      return false;
    } catch (e) {
      debugPrint('Error during re-authentication: $e');
      _isProcessingAuth = false;
      return false;
    }
  }

  // Generate a random string for PKCE
  String _generateRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }
}
