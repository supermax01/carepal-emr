import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;

  const LoginScreen({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  int _selectedScopeOption = 0;
  String? _errorMessage;

  final List<String> _scopeOptions = [
    'Complete patient health record access',
    'Basic patient identification only',
    'Medical records (minimal)',
  ];

  final List<String> _scopeDescriptions = [
    'Full access to all your health records including medications, allergies, appointments, and more',
    'Basic patient profile information only',
    'Limited access to patient profile, medications and observations',
  ];

  // Corresponding actual FHIR scope values (these match OpenEMR scope requirements)
  final List<String> _scopeValues = [
    'launch/patient patient/*.read offline_access',
    'launch/patient patient/Patient.read offline_access',
    'launch/patient patient/Patient.read patient/Medication.read patient/Observation.read offline_access',
  ];

  void _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Pass the selected scope value to the login method
      await widget.authService.login(
        scopeOption: _selectedScopeOption,
        scopeValue: _scopeValues[_selectedScopeOption],
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Login failed: ${e.toString()}';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'CarepalEMR',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Image.asset(
                'assets/images/logo.png',
                height: 120,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.health_and_safety,
                    size: 120,
                    color: Colors.blue,
                  );
                },
              ),
              const SizedBox(height: 48),
              const Text(
                'Your Secure Health Records Portal',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Scope selection
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Access Level:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _scopeOptions.length; i++)
                      RadioListTile<int>(
                        title: Text(_scopeOptions[i]),
                        subtitle: Text(_scopeDescriptions[i]),
                        value: i,
                        groupValue: _selectedScopeOption,
                        onChanged: (int? value) {
                          if (value != null) {
                            setState(() {
                              _selectedScopeOption = value;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Display error message if there is one
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),

              if (_errorMessage != null) const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text(
                        'Login with OpenEMR',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
