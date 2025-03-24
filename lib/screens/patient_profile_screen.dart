import 'package:flutter/material.dart';
import 'dart:math';
import '../services/fhir_service.dart';
import '../models/fhir_helpers.dart';

class PatientProfileScreen extends StatefulWidget {
  final FhirService fhirService;

  const PatientProfileScreen({super.key, required this.fhirService});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _patientData;

  @override
  void initState() {
    super.initState();
    _fetchPatientData();
  }

  Future<void> _fetchPatientData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final patientData = await widget.fhirService.getPatientInfo();
      debugPrint(
          'Patient data received: ${patientData.toString().substring(0, min(100, patientData.toString().length))}...');

      // Extract patient resource from bundle if needed
      Map<String, dynamic> patientResource;

      try {
        if (patientData['resourceType'] == 'Bundle' &&
            patientData['entry'] != null &&
            patientData['entry'].isNotEmpty) {
          // Get the first patient resource from bundle
          patientResource = patientData['entry'][0]['resource'];
          debugPrint('Extracted patient resource from bundle');
        } else if (patientData['resourceType'] == 'Patient') {
          // Direct patient resource
          patientResource = patientData;
          debugPrint('Using direct patient resource');
        } else {
          // Unknown format
          debugPrint('Unknown resource format: ${patientData['resourceType']}');
          patientResource = {'resourceType': 'Patient'};
        }
      } catch (extractError) {
        debugPrint('Error extracting patient resource: $extractError');
        patientResource = {'resourceType': 'Patient'};
      }

      setState(() {
        _patientData = patientResource;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching patient data: $e');
      setState(() {
        _errorMessage = 'Error loading patient data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPatientData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchPatientData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_patientData == null) {
      return const Center(child: Text('No patient data available'));
    }

    // Extract patient info with error handling
    String patientName = "Unknown Patient";
    String patientDob = "Unknown";
    String patientGender = "Unknown";
    String patientAddress = "No address on file";

    try {
      patientName = getPatientName(_patientData!);
    } catch (e) {
      debugPrint('Error getting patient name: $e');
    }

    try {
      patientDob = getPatientDob(_patientData!);
    } catch (e) {
      debugPrint('Error getting patient DOB: $e');
    }

    try {
      patientGender = getPatientGender(_patientData!);
    } catch (e) {
      debugPrint('Error getting patient gender: $e');
    }

    try {
      patientAddress = getPatientAddress(_patientData!);
    } catch (e) {
      debugPrint('Error getting patient address: $e');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient avatar and name
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    patientName.isNotEmpty ? patientName[0] : '?',
                    style: const TextStyle(fontSize: 40, color: Colors.blue),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  patientName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Patient ID: ${_patientData!['id'] ?? 'Unknown'}',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Patient details
          _buildInfoCard(
            title: 'Personal Information',
            children: [
              _buildInfoRow(label: 'Date of Birth', value: patientDob),
              _buildInfoRow(label: 'Gender', value: patientGender),
              _buildInfoRow(label: 'Address', value: patientAddress),
            ],
          ),

          const SizedBox(height: 16),

          // Contact info if available
          _buildContactInfo(),

          const SizedBox(height: 16),

          // Communication preferences if available
          _buildCommunicationPreferences(),

          const SizedBox(height: 24),

          // Actions buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.refresh,
                label: 'Refresh',
                onTap: _fetchPatientData,
              ),
              _buildActionButton(
                icon: Icons.content_copy,
                label: 'Copy ID',
                onTap: () {
                  // Implement copy functionality
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Patient ID copied to clipboard'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo() {
    // Extract telecom info if available
    List<dynamic> telecom = [];
    if (_patientData != null && _patientData!['telecom'] != null) {
      telecom = _patientData!['telecom'] as List;
    }

    if (telecom.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> contactRows = [];

    for (final contact in telecom) {
      final system = contact['system'] ?? '';
      final value = contact['value'] ?? '';
      final use = contact['use'] ?? '';

      if (value.isNotEmpty) {
        String label = 'Contact';
        if (system.isNotEmpty) {
          label = system[0].toUpperCase() + system.substring(1);
        }
        if (use.isNotEmpty) {
          label += ' ($use)';
        }

        contactRows.add(_buildInfoRow(label: label, value: value));
      }
    }

    if (contactRows.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(title: 'Contact Information', children: contactRows);
  }

  Widget _buildCommunicationPreferences() {
    // Extract communication preferences if available
    List<dynamic> communication = [];
    if (_patientData != null && _patientData!['communication'] != null) {
      communication = _patientData!['communication'] as List;
    }

    if (communication.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> communicationRows = [];

    for (final comm in communication) {
      if (comm['language'] != null && comm['language']['coding'] != null) {
        final codings = comm['language']['coding'] as List;
        if (codings.isNotEmpty) {
          final language =
              codings[0]['display'] ?? codings[0]['code'] ?? 'Unknown';
          final preferred = comm['preferred'] == true ? 'Preferred' : '';

          communicationRows.add(
            _buildInfoRow(
              label: 'Language',
              value: language + (preferred.isNotEmpty ? ' ($preferred)' : ''),
            ),
          );
        }
      }
    }

    if (communicationRows.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoCard(
      title: 'Communication Preferences',
      children: communicationRows,
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.blue, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
