import 'package:flutter/material.dart';
import '../services/fhir_service.dart';
import '../models/fhir_helpers.dart';
import 'dart:math';

class MedicationsScreen extends StatefulWidget {
  final FhirService fhirService;

  const MedicationsScreen({super.key, required this.fhirService});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _medications = [];

  @override
  void initState() {
    super.initState();
    _fetchMedications();
  }

  Future<void> _fetchMedications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await widget.fhirService.getMedications();

      debugPrint(
          'Medications response: ${response.toString().substring(0, min(100, response.toString().length))}...');

      // Safely extract medication resources from the bundle
      List<Map<String, dynamic>> meds = [];

      try {
        // Check if we have a valid Bundle response
        if (response['resourceType'] == 'Bundle' && response['entry'] != null) {
          // Extract resources from bundle entries
          meds = (response['entry'] as List)
              .where((entry) =>
                  entry is Map<String, dynamic> && entry['resource'] != null)
              .map<Map<String, dynamic>>(
                  (entry) => entry['resource'] as Map<String, dynamic>)
              .toList();
        } else {
          // If it's not a bundle with entries, log what we received
          debugPrint(
              'Response is not a bundle with entries. Response type: ${response['resourceType']}');
          if (response['total'] != null) {
            debugPrint('Total items: ${response['total']}');
          }
        }
      } catch (parseError) {
        debugPrint('Error parsing medication response: $parseError');
        debugPrint('Response structure: $response');
      }

      setState(() {
        _medications = meds;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error in _fetchMedications: $e');
      setState(() {
        _errorMessage = 'Error loading medications: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchMedications,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_medications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medication_outlined, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No medications found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchMedications,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMedications,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _medications.length,
        itemBuilder: (context, index) {
          final medication = _medications[index];
          return _buildMedicationCard(medication);
        },
      ),
    );
  }

  Widget _buildMedicationCard(Map<String, dynamic> medication) {
    // Debug the medication data
    debugPrint(
        'Building card for medication: ${medication.toString().substring(0, min(100, medication.toString().length))}...');

    // Safely get medication name
    String medicationName = "Unknown Medication";
    try {
      medicationName = getMedicationName(medication);
    } catch (e) {
      debugPrint('Error getting medication name: $e');
      // Try to extract name directly if helper function fails
      if (medication['medicationCodeableConcept'] != null &&
          medication['medicationCodeableConcept']['text'] != null) {
        medicationName = medication['medicationCodeableConcept']['text'];
      } else if (medication['medicationReference'] != null &&
          medication['medicationReference']['display'] != null) {
        medicationName = medication['medicationReference']['display'];
      } else if (medication['code'] != null &&
          medication['code']['text'] != null) {
        medicationName = medication['code']['text'];
      }
    }

    // Safely get dosage information
    String medicationDosage = "No dosage information";
    try {
      medicationDosage = getMedicationDosage(medication);
    } catch (e) {
      debugPrint('Error getting medication dosage: $e');
      // Try to extract dosage directly if helper function fails
      if (medication['dosageInstruction'] != null &&
          medication['dosageInstruction'] is List &&
          medication['dosageInstruction'].isNotEmpty) {
        final dosage = medication['dosageInstruction'][0];
        if (dosage['text'] != null) {
          medicationDosage = dosage['text'];
        }
      }
    }

    // Get status and date information safely
    String status = medication['status'] ?? 'Unknown';
    String statusText = status.toString().substring(0, 1).toUpperCase() +
        status.toString().substring(1);

    // Format date if available
    String dateText = 'Unknown date';
    if (medication['authoredOn'] != null) {
      try {
        final dateStr = medication['authoredOn'].toString();
        dateText = dateStr.split('T')[0]; // Simple date extraction
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    // Extract prescriber information if available
    String prescriberText = 'Unknown prescriber';
    try {
      if (medication['requester'] != null &&
          medication['requester']['display'] != null) {
        prescriberText = medication['requester']['display'];
      }
    } catch (e) {
      debugPrint('Error extracting prescriber: $e');
    }

    // Determine status color
    Color statusColor;
    switch (status) {
      case 'active':
        statusColor = Colors.green;
        break;
      case 'completed':
        statusColor = Colors.blue;
        break;
      case 'stopped':
      case 'cancelled':
        statusColor = Colors.red;
        break;
      case 'on-hold':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medication name and status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    medicationName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Dosage information
            if (medicationDosage != 'No dosage information')
              _buildInfoRow(
                icon: Icons.medical_services_outlined,
                label: 'Dosage',
                value: medicationDosage,
              ),

            // Prescriber information
            _buildInfoRow(
              icon: Icons.person_outline,
              label: 'Prescriber',
              value: prescriberText,
            ),

            // Date information
            _buildInfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Prescribed',
              value: dateText,
            ),

            // Add note if available
            if (medication['note'] != null &&
                medication['note'] is List &&
                (medication['note'] as List).isNotEmpty)
              _buildInfoRow(
                icon: Icons.note_outlined,
                label: 'Note',
                value:
                    (medication['note'][0]['text'] ?? 'No details').toString(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
