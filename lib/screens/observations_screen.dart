import 'package:flutter/material.dart';
import '../services/fhir_service.dart';
import '../models/fhir_helpers.dart';

class ObservationsScreen extends StatefulWidget {
  final FhirService fhirService;

  const ObservationsScreen({super.key, required this.fhirService});

  @override
  State<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends State<ObservationsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _vitalSigns = [];
  List<Map<String, dynamic>> _labResults = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAllObservations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllObservations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Fetch both vital signs and lab results
      await Future.wait([_fetchVitalSigns(), _fetchLabResults()]);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading observations: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchVitalSigns() async {
    try {
      final response = await widget.fhirService.getVitalSigns();

      // Extract vital sign resources from the bundle
      List<Map<String, dynamic>> vitalSigns = widget.fhirService
          .extractResourcesFromBundle(response);

      // Sort by date (newest first)
      vitalSigns.sort((a, b) {
        final aDate = a['effectiveDateTime'] ?? '';
        final bDate = b['effectiveDateTime'] ?? '';
        return bDate.compareTo(aDate);
      });

      setState(() {
        _vitalSigns = vitalSigns;
      });
    } catch (e) {
      print('Error fetching vital signs: $e');
      // Do not set error message here, as we handle it in _fetchAllObservations
    }
  }

  Future<void> _fetchLabResults() async {
    try {
      final response = await widget.fhirService.getLabResults();

      // Extract lab result resources from the bundle
      List<Map<String, dynamic>> labResults = widget.fhirService
          .extractResourcesFromBundle(response);

      // Sort by date (newest first)
      labResults.sort((a, b) {
        final aDate = a['effectiveDateTime'] ?? '';
        final bDate = b['effectiveDateTime'] ?? '';
        return bDate.compareTo(aDate);
      });

      setState(() {
        _labResults = labResults;
      });
    } catch (e) {
      print('Error fetching lab results: $e');
      // Do not set error message here, as we handle it in _fetchAllObservations
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
              onPressed: _fetchAllObservations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tab bar
        TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Vital Signs'), Tab(text: 'Lab Results')],
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Vital Signs Tab
              _buildObservationsList(
                _vitalSigns,
                emptyMessage: 'No vital signs found',
                refreshCallback: _fetchVitalSigns,
              ),

              // Lab Results Tab
              _buildObservationsList(
                _labResults,
                emptyMessage: 'No lab results found',
                refreshCallback: _fetchLabResults,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildObservationsList(
    List<Map<String, dynamic>> observations, {
    required String emptyMessage,
    required Future<void> Function() refreshCallback,
  }) {
    if (observations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assessment_outlined, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: refreshCallback,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    // Group observations by date
    final Map<String, List<Map<String, dynamic>>> groupedObservations = {};

    for (final observation in observations) {
      final date = getObservationDate(observation);
      if (!groupedObservations.containsKey(date)) {
        groupedObservations[date] = [];
      }
      groupedObservations[date]!.add(observation);
    }

    // Convert to list of entries, sorted by date
    final sortedDates =
        groupedObservations.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: refreshCallback,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final date = sortedDates[index];
          final dateObservations = groupedObservations[date]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  date,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),

              // Observations for this date
              ...dateObservations.map(
                (observation) => _buildObservationCard(observation),
              ),

              // Add space between date groups
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildObservationCard(Map<String, dynamic> observation) {
    // Get observation details
    String observationName = 'Unknown Observation';

    // Try to get name from code
    if (observation['code'] != null && observation['code']['coding'] != null) {
      final codings = observation['code']['coding'] as List;
      if (codings.isNotEmpty) {
        observationName =
            codings[0]['display'] ??
            codings[0]['code'] ??
            'Unknown Observation';
      }
    }

    // If code doesn't have a display, try text
    if (observationName == 'Unknown Observation' &&
        observation['code'] != null &&
        observation['code']['text'] != null) {
      observationName = observation['code']['text'];
    }

    // Get value
    final observationValue = getObservationValue(observation);

    // Get status
    final status = observation['status'] ?? 'unknown';
    String statusText =
        status.toString().substring(0, 1).toUpperCase() +
        status.toString().substring(1);

    // Determine status color
    Color statusColor;
    switch (status) {
      case 'final':
        statusColor = Colors.green;
        break;
      case 'preliminary':
        statusColor = Colors.orange;
        break;
      case 'corrected':
        statusColor = Colors.blue;
        break;
      case 'cancelled':
      case 'entered-in-error':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    // Set reference range if available
    String referenceRange = '';
    if (observation['referenceRange'] != null &&
        (observation['referenceRange'] as List).isNotEmpty) {
      final range = observation['referenceRange'][0];
      if (range['low'] != null && range['high'] != null) {
        referenceRange = '${range['low']['value']} - ${range['high']['value']}';
        if (range['low']['unit'] != null) {
          referenceRange += ' ${range['low']['unit']}';
        }
      } else if (range['text'] != null) {
        referenceRange = range['text'];
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Observation name and status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    observationName,
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

            // Value
            Row(
              children: [
                const Text(
                  'Value: ',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                ),
                Text(
                  observationValue,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Reference range if available
            if (referenceRange.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Reference: $referenceRange',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],

            // Performer if available
            if (observation['performer'] != null &&
                (observation['performer'] as List).isNotEmpty &&
                observation['performer'][0]['display'] != null) ...[
              const SizedBox(height: 12),
              Text(
                'Performed by: ${observation['performer'][0]['display']}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],

            // Interpretation if available
            if (observation['interpretation'] != null &&
                (observation['interpretation'] as List).isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInterpretationWidget(observation['interpretation'][0]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInterpretationWidget(Map<String, dynamic> interpretation) {
    // Default interpretation text and color
    String interpretationText = 'Interpretation not available';
    Color interpretationColor = Colors.grey;

    // Try to get interpretation from coding
    if (interpretation['coding'] != null &&
        (interpretation['coding'] as List).isNotEmpty) {
      final coding = interpretation['coding'][0];
      if (coding['display'] != null) {
        interpretationText = coding['display'];
      } else if (coding['code'] != null) {
        // Try to map common codes to readable text
        switch (coding['code']) {
          case 'N':
            interpretationText = 'Normal';
            interpretationColor = Colors.green;
            break;
          case 'L':
            interpretationText = 'Low';
            interpretationColor = Colors.orange;
            break;
          case 'H':
            interpretationText = 'High';
            interpretationColor = Colors.orange;
            break;
          case 'LL':
            interpretationText = 'Critical Low';
            interpretationColor = Colors.red;
            break;
          case 'HH':
            interpretationText = 'Critical High';
            interpretationColor = Colors.red;
            break;
          case 'A':
            interpretationText = 'Abnormal';
            interpretationColor = Colors.orange;
            break;
          case 'AA':
            interpretationText = 'Critical Abnormal';
            interpretationColor = Colors.red;
            break;
          default:
            interpretationText = coding['code'];
            interpretationColor = Colors.grey;
        }
      }
    } else if (interpretation['text'] != null) {
      interpretationText = interpretation['text'];
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: interpretationColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: interpretationColor),
      ),
      child: Text(
        interpretationText,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: interpretationColor,
        ),
      ),
    );
  }
}
