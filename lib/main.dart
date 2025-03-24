import 'package:flutter/material.dart';
import 'package:carepal_emr/services/auth_service.dart';
import 'package:carepal_emr/models/api_client.dart';
import 'package:carepal_emr/services/fhir_service.dart';
import 'package:carepal_emr/screens/login_screen.dart';
import 'dart:math';
import 'dart:async';
import 'screens/medications_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CarepalEMRApp());
}

class CarepalEMRApp extends StatefulWidget {
  const CarepalEMRApp({super.key});

  @override
  State<CarepalEMRApp> createState() => _CarepalEMRAppState();
}

class _CarepalEMRAppState extends State<CarepalEMRApp> {
  // Services
  late AuthService _authService;
  late FhirService _fhirService;
  bool _isAuthenticated = false;
  bool _isLoading = true;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Create API client
    final apiClient = ApiClient(
      baseUrl: 'https://YOUR_OPENEMR_HOST',
    );

    // Create auth service
    final authService = AuthService(
      baseUrl: 'https://YOUR_OPENEMR_HOST',
      clientId: 'YOUR_OPENEMR_CLIENT_ID',
      clientSecret:
          'YOUR_OPENEMR_CLIENT_SECRET',
      redirectUri: 'carepalemr://oauth/callback',
      apiClient: apiClient,
    );

    // Store services for global access
    _authService = authService;
    _fhirService = FhirService(apiClient: apiClient);

    // Initialize deep link handling
    authService.initializeDeepLinkHandling();

    // Pass the client credentials to the API client
    apiClient.setClientCredentials(
        'YOUR_OPENEMR_CLIENT_ID',
        'YOUR_OPENEMR_CLIENT_SECRET');

    // Listen for auth state changes
    authService.authState.listen((isAuthenticated) {
      debugPrint('=== MAIN APP: Auth state changed to: $isAuthenticated ===');

      if (!mounted) {
        debugPrint('Widget not mounted, skipping state update');
        return;
      }

      setState(() {
        _isAuthenticated = isAuthenticated;
        debugPrint('Updated _isAuthenticated state to: $_isAuthenticated');
      });

      // Navigate based on auth state change
      if (isAuthenticated && !_isLoading) {
        debugPrint("Authentication successful, navigating to dashboard");

        // Force navigation to dashboard on the next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint("Post-frame callback: pushing dashboard route");
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => HomeScreen(
                      authService: _authService,
                      fhirService: _fhirService,
                    )),
            (route) => false, // Remove all previous routes
          );
        });
      } else if (!isAuthenticated && !_isLoading) {
        debugPrint("Not authenticated, ensuring we're on login screen");

        // Force navigation to login on the next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_navigatorKey.currentState?.canPop() ?? false) {
            debugPrint("Post-frame callback: popping to first route");
            _navigatorKey.currentState?.popUntil((route) => route.isFirst);
          }
        });
      }
    });

    // Check current auth state
    await authService.checkAuthentication();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'CarepalEMR',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: _isLoading
          ? const _LoadingScreen()
          : _isAuthenticated
              ? HomeScreen(
                  authService: _authService,
                  fhirService: _fhirService,
                )
              : LoginScreen(authService: _authService),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Initializing CarepalEMR..."),
          ],
        ),
      ),
    );
  }
}

class _PatientDashboard extends StatefulWidget {
  const _PatientDashboard();

  @override
  State<_PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<_PatientDashboard> {
  bool _loadingPatientData = false;
  String _error = '';
  bool _checkedAuth = false;
  Map<String, dynamic>? _patientInfo;
  FhirService? _fhirService;

  @override
  void initState() {
    super.initState();
    debugPrint("=== DASHBOARD: Initialized ===");
    _verifyAuthentication();
  }

  Future<void> _verifyAuthentication() async {
    try {
      // Get the AuthService instance
      if (!mounted) return;

      final appState = context.findAncestorStateOfType<_CarepalEMRAppState>();
      final authService = appState?._authService;
      _fhirService = appState?._fhirService;

      if (authService == null) {
        debugPrint("=== DASHBOARD: AuthService not found ===");
        if (mounted) {
          setState(() {
            _error = 'Authentication service not available';
            _checkedAuth = true;
          });
        }
        return;
      }

      final isAuthenticated = await authService.isAuthenticated();
      debugPrint("=== DASHBOARD: Authentication check: $isAuthenticated ===");

      if (mounted) {
        setState(() {
          _checkedAuth = true;
          if (!isAuthenticated) {
            _error = 'Not authenticated - should not be on this screen';
          }
        });
      }
    } catch (e) {
      debugPrint("=== DASHBOARD: Auth check error: $e ===");
      if (mounted) {
        setState(() {
          _error = 'Error verifying authentication';
          _checkedAuth = true;
        });
      }
    }
  }

  Future<void> _fetchPatientData() async {
    if (_fhirService == null) {
      if (mounted) {
        setState(() {
          _error = 'FHIR service not available';
          _loadingPatientData = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loadingPatientData = true);
    }

    try {
      debugPrint('=== DASHBOARD: Fetching patient data ===');

      // Get the AuthService instance to verify authentication
      final appState = context.findAncestorStateOfType<_CarepalEMRAppState>();
      final authService = appState?._authService;

      if (authService != null) {
        final isAuth = await authService.isAuthenticated();
        debugPrint('=== DASHBOARD: Current authentication status: $isAuth ===');

        // If not authenticated, try to refresh the auth state
        if (!isAuth) {
          debugPrint(
              '=== DASHBOARD: Not authenticated, checking auth state ===');
          await authService.checkAuthentication();
          final refreshedAuth = await authService.isAuthenticated();
          debugPrint(
              '=== DASHBOARD: Refreshed auth status: $refreshedAuth ===');

          if (!refreshedAuth) {
            if (mounted) {
              setState(() {
                _error = 'Not authenticated. Please log in again.';
                _loadingPatientData = false;
              });
            }
            return;
          }
        }
      }

      final patientInfo = await _fhirService!.getPatientInfo();
      debugPrint(
          'Patient info received: ${patientInfo.toString().substring(0, min(200, patientInfo.toString().length))}...');

      if (mounted) {
        setState(() {
          _patientInfo = patientInfo;
          _loadingPatientData = false;
          _error = '';
        });
      }
    } catch (e) {
      debugPrint('=== DASHBOARD: Error fetching patient data: $e ===');

      // Try to refresh the token if we got a 401 error
      if (e.toString().contains('401')) {
        debugPrint(
            '=== DASHBOARD: Detected 401 error, attempting token refresh ===');

        final appState = context.findAncestorStateOfType<_CarepalEMRAppState>();
        final authService = appState?._authService;

        if (authService != null) {
          // Force token refresh
          final refreshed = await authService.forceTokenRefresh();
          if (refreshed && mounted) {
            debugPrint(
                '=== DASHBOARD: Token refreshed successfully, retrying request ===');
            // Retry the request with fresh token
            setState(() => _loadingPatientData = true);
            try {
              final patientInfo = await _fhirService!.getPatientInfo();
              if (mounted) {
                setState(() {
                  _patientInfo = patientInfo;
                  _loadingPatientData = false;
                  _error = '';
                });
              }
              // Return early since we handled the error
              return;
            } catch (retryError) {
              debugPrint(
                  '=== DASHBOARD: Retry failed after token refresh: $retryError ===');
              // Continue to the error handling below
            }
          } else {
            debugPrint('=== DASHBOARD: Token refresh failed ===');
          }
        }
      }

      if (mounted) {
        setState(() {
          if (e.toString().contains('401')) {
            _error =
                'Authentication error: Your session has expired. Please try logging out and logging back in.';
          } else {
            _error = 'Error fetching patient data: $e';
          }
          _loadingPatientData = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (!mounted) return;

              debugPrint('=== DASHBOARD: Manual refresh requested ===');
              // Clear any errors and refresh authentication state
              setState(() {
                _error = '';
                _patientInfo = null;
              });

              // Get the AuthService and force refresh token
              final appState =
                  context.findAncestorStateOfType<_CarepalEMRAppState>();
              final authService = appState?._authService;
              if (authService != null) {
                await authService.forceTokenRefresh();
              }

              // Re-verify authentication
              if (mounted) {
                await _verifyAuthentication();
              }
            },
            tooltip: 'Refresh Session',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              if (!mounted) return;

              // Get the AuthService instance from ancestor widget
              final authService = context
                  .findAncestorStateOfType<_CarepalEMRAppState>()
                  ?._authService;

              if (authService != null) {
                authService.logout();
              }
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Center(
        child: _error.isNotEmpty
            ? _buildErrorDisplay()
            : _patientInfo != null
                ? _buildPatientInfoDisplay()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'You are logged in!',
                        style: TextStyle(fontSize: 24),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed:
                            _loadingPatientData ? null : _fetchPatientData,
                        child: _loadingPatientData
                            ? const CircularProgressIndicator()
                            : const Text('View Your Health Records'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildErrorDisplay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 48,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Error: $_error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        // Different options based on error type
        if (_error.contains('authentication') ||
            _error.contains('session') ||
            _error.contains('401'))
          _buildAuthRecoveryOptions()
        else
          _buildGeneralRecoveryOptions(),
      ],
    );
  }

  Widget _buildAuthRecoveryOptions() {
    return Column(
      children: [
        const Text(
          'Your session appears to have expired or there\'s an issue with your authentication.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _loadingPatientData
                  ? null
                  : () async {
                      if (!mounted) return;
                      setState(() => _loadingPatientData = true);

                      final appState = context
                          .findAncestorStateOfType<_CarepalEMRAppState>();
                      final authService = appState?._authService;

                      if (authService != null) {
                        final refreshed = await authService.forceTokenRefresh();
                        if (mounted) {
                          if (refreshed) {
                            // Token refreshed successfully
                            setState(() {
                              _error = '';
                              _loadingPatientData = false;
                            });
                            _fetchPatientData();
                          } else {
                            // Need to logout and login again
                            setState(() {
                              _error =
                                  'Could not refresh session. Please log in again.';
                              _loadingPatientData = false;
                            });
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: _loadingPatientData
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Refresh Session'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () {
                if (!mounted) return;
                // Logout
                final authService = context
                    .findAncestorStateOfType<_CarepalEMRAppState>()
                    ?._authService;

                if (authService != null) {
                  authService.logout();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Log Out'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGeneralRecoveryOptions() {
    return ElevatedButton(
      onPressed: _loadingPatientData
          ? null
          : () {
              if (!mounted) return;
              setState(() {
                _error = '';
              });
              _fetchPatientData();
            },
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: _loadingPatientData
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Try Again'),
    );
  }

  Widget _buildPatientInfoDisplay() {
    // Get the patient resource from the response
    final patient = _patientInfo!['resourceType'] == 'Patient'
        ? _patientInfo!
        : _patientInfo!['entry']?.firstWhere(
            (entry) => entry['resource']['resourceType'] == 'Patient',
            orElse: () => {'resource': {}},
          )['resource'];

    if (patient == null || patient.isEmpty) {
      return const Text('No patient information available');
    }

    final name = patient['name']?[0];
    final firstName = name?['given']?[0] ?? 'Unknown';
    final lastName = name?['family'] ?? '';
    final dob = patient['birthDate'] ?? 'Unknown';
    final gender = patient['gender'] ?? 'Unknown';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patient Information',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          _infoRow('Name', '$firstName $lastName'),
          _infoRow('Date of Birth', dob),
          _infoRow('Gender', gender),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _patientInfo = null;
              });
            },
            child: const Text('Back to Dashboard'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadingPatientData
                ? null
                : () async {
                    // Navigate to dedicated medications screen
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => MedicationsScreen(
                          fhirService: _fhirService!,
                        ),
                      ),
                    );
                  },
            child: _loadingPatientData
                ? const CircularProgressIndicator()
                : const Text('View Medications'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
