import '../models/api_client.dart';

class FhirService {
  final ApiClient _apiClient;

  FhirService({required ApiClient apiClient}) : _apiClient = apiClient;

  // Get patient information
  Future<Map<String, dynamic>> getPatientInfo() async {
    try {
      return await _apiClient.getPatientInfo();
    } catch (e) {
      print('Error fetching patient info: $e');
      rethrow;
    }
  }

  // Get patient vital signs
  Future<Map<String, dynamic>> getVitalSigns() async {
    try {
      return await _apiClient.getObservations(category: 'vital-signs');
    } catch (e) {
      print('Error fetching vital signs: $e');
      rethrow;
    }
  }

  // Get patient lab results
  Future<Map<String, dynamic>> getLabResults() async {
    try {
      return await _apiClient.getObservations(category: 'laboratory');
    } catch (e) {
      print('Error fetching lab results: $e');
      rethrow;
    }
  }

  // Get all patient observations
  Future<Map<String, dynamic>> getAllObservations() async {
    try {
      return await _apiClient.getObservations();
    } catch (e) {
      print('Error fetching observations: $e');
      rethrow;
    }
  }

  // Get patient medications
  Future<Map<String, dynamic>> getMedications() async {
    try {
      return await _apiClient.getMedications();
    } catch (e) {
      print('Error fetching medications: $e');
      rethrow;
    }
  }

  // Get patient appointments
  Future<Map<String, dynamic>> getAppointments() async {
    try {
      return await _apiClient.getAppointments();
    } catch (e) {
      print('Error fetching appointments: $e');
      rethrow;
    }
  }

  // Extract resources from a FHIR Bundle
  List<Map<String, dynamic>> extractResourcesFromBundle(
    Map<String, dynamic>? bundle,
  ) {
    // Handle null bundle
    if (bundle == null) {
      print('Warning: Null bundle passed to extractResourcesFromBundle');
      return [];
    }

    try {
      // Check if it's a Bundle resource
      if (bundle['resourceType'] != 'Bundle') {
        print(
            'Warning: Resource is not a Bundle type: ${bundle['resourceType']}');

        // If this is a single resource, return it in a list
        if (bundle['resourceType'] != null) {
          return [bundle];
        }
        return [];
      }

      // Check if bundle has entries
      if (bundle['entry'] == null) {
        print('Warning: Bundle has no entries');
        return [];
      }

      final List<dynamic> entries = bundle['entry'];
      if (entries.isEmpty) {
        print('Warning: Bundle has empty entries array');
        return [];
      }

      // Extract and validate each resource
      final resources = entries
          .where((entry) => entry is Map && entry['resource'] != null)
          .map<Map<String, dynamic>>((entry) {
        try {
          return entry['resource'] as Map<String, dynamic>;
        } catch (e) {
          print('Error processing bundle entry: $e');
          return {'resourceType': 'Error', 'error': e.toString()};
        }
      }).toList();

      print('Extracted ${resources.length} resources from bundle');
      return resources;
    } catch (e) {
      print('Error extracting resources from bundle: $e');
      return [];
    }
  }
}
