import 'package:flutter/material.dart';
import 'dart:math';
import '../services/fhir_service.dart';
import '../models/fhir_helpers.dart';

class AppointmentsScreen extends StatefulWidget {
  final FhirService fhirService;

  const AppointmentsScreen({super.key, required this.fhirService});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _appointments = [];

  @override
  void initState() {
    super.initState();
    _fetchAppointments();
  }

  Future<void> _fetchAppointments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await widget.fhirService.getAppointments();
      debugPrint(
          'Appointments response: ${response.toString().substring(0, min(100, response.toString().length))}...');

      // Extract appointment resources from the bundle with error handling
      List<Map<String, dynamic>> appointments = [];

      try {
        if (response['resourceType'] == 'Bundle' &&
            response['entry'] != null &&
            response['entry'] is List) {
          // Extract resources from bundle entries
          appointments =
              widget.fhirService.extractResourcesFromBundle(response);
          debugPrint(
              'Extracted ${appointments.length} appointments from bundle');
        } else {
          // If it's not a bundle with entries, log what we received
          debugPrint(
              'Response is not a bundle with entries. Response type: ${response['resourceType']}');
          if (response['total'] != null) {
            debugPrint('Total items: ${response['total']}');
          }
        }
      } catch (parseError) {
        debugPrint('Error parsing appointment response: $parseError');
        debugPrint('Response structure: $response');
      }

      // Sort appointments by date (most recent first) with error handling
      try {
        appointments.sort((a, b) {
          final aDate = a['start'] ?? '';
          final bDate = b['start'] ?? '';
          return bDate.compareTo(aDate); // Reverse order for newest first
        });
      } catch (sortError) {
        debugPrint('Error sorting appointments: $sortError');
      }

      setState(() {
        _appointments = appointments;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error in _fetchAppointments: $e');
      setState(() {
        _errorMessage = 'Error loading appointments: $e';
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
              onPressed: _fetchAppointments,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No appointments found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchAppointments,
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    // Group appointments by status
    final upcomingAppointments = _appointments
        .where(
          (appointment) =>
              appointment['status'] == 'booked' ||
              appointment['status'] == 'pending',
        )
        .toList();

    final pastAppointments = _appointments
        .where(
          (appointment) =>
              appointment['status'] == 'fulfilled' ||
              appointment['status'] == 'arrived' ||
              appointment['status'] == 'checked-in',
        )
        .toList();

    final cancelledAppointments = _appointments
        .where(
          (appointment) =>
              appointment['status'] == 'cancelled' ||
              appointment['status'] == 'noshow',
        )
        .toList();

    return RefreshIndicator(
      onRefresh: _fetchAppointments,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Upcoming appointments section
          if (upcomingAppointments.isNotEmpty) ...[
            _buildSectionHeader('Upcoming Appointments'),
            ...upcomingAppointments.map(
              (appointment) => _buildAppointmentCard(appointment),
            ),
            const SizedBox(height: 16),
          ],

          // Past appointments section
          if (pastAppointments.isNotEmpty) ...[
            _buildSectionHeader('Past Appointments'),
            ...pastAppointments.map(
              (appointment) => _buildAppointmentCard(appointment),
            ),
            const SizedBox(height: 16),
          ],

          // Cancelled appointments section
          if (cancelledAppointments.isNotEmpty) ...[
            _buildSectionHeader('Cancelled Appointments'),
            ...cancelledAppointments.map(
              (appointment) => _buildAppointmentCard(appointment),
            ),
          ],

          // If there are no appointments in any category
          if (upcomingAppointments.isEmpty &&
              pastAppointments.isEmpty &&
              cancelledAppointments.isEmpty)
            const Center(
              child: Column(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 72,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No appointments found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    // Add error handling for all data extraction
    String appointmentDescription = "Appointment";
    String appointmentDateTime = "Unknown date";
    String appointmentStatus = "Unknown";

    try {
      appointmentDescription = getAppointmentDescription(appointment);
    } catch (e) {
      debugPrint('Error getting appointment description: $e');
      // Fallback to basic info if available
      if (appointment['description'] != null) {
        appointmentDescription = appointment['description'];
      } else if (appointment['serviceType'] != null &&
          appointment['serviceType']['text'] != null) {
        appointmentDescription = appointment['serviceType']['text'];
      }
    }

    try {
      appointmentDateTime = getAppointmentDateTime(appointment);
    } catch (e) {
      debugPrint('Error getting appointment date/time: $e');
      // Basic fallback for date extraction
      if (appointment['start'] != null) {
        try {
          final dateStr = appointment['start'].toString();
          appointmentDateTime = dateStr.split('T')[0];
        } catch (dateParseError) {
          debugPrint('Error parsing date string: $dateParseError');
        }
      }
    }

    try {
      appointmentStatus = getAppointmentStatus(appointment);
    } catch (e) {
      debugPrint('Error getting appointment status: $e');
      // Simple fallback for status
      if (appointment['status'] != null) {
        String status = appointment['status'].toString();
        appointmentStatus = status[0].toUpperCase() + status.substring(1);
      }
    }

    // Determine status color with safe access
    Color statusColor = Colors.grey; // Default color
    try {
      final status = appointment['status']?.toString().toLowerCase() ?? '';
      if (['booked', 'pending'].contains(status)) {
        statusColor = Colors.green;
      } else if (['fulfilled', 'arrived', 'checked-in'].contains(status)) {
        statusColor = Colors.blue;
      } else if (['cancelled', 'noshow'].contains(status)) {
        statusColor = Colors.red;
      }
    } catch (e) {
      debugPrint('Error determining status color: $e');
    }

    // Extract participant information with error handling
    List<Widget> participantWidgets = [];
    try {
      if (appointment['participant'] != null &&
          appointment['participant'] is List) {
        for (final participant in appointment['participant']) {
          try {
            if (participant is Map<String, dynamic> &&
                participant['actor'] != null &&
                participant['actor']['display'] != null) {
              final type = _getParticipantType(participant);
              final name = participant['actor']['display'];
              participantWidgets.add(
                _buildInfoRow(
                    icon: Icons.person_outline, label: type, value: name),
              );
            }
          } catch (participantError) {
            debugPrint('Error processing participant: $participantError');
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing participants: $e');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Appointment description and status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    appointmentDescription,
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
                    appointmentStatus,
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

            // Date and time
            _buildInfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'When',
              value: appointmentDateTime,
            ),

            // Location if available
            if (appointment['serviceProvider'] != null &&
                appointment['serviceProvider']['display'] != null)
              _buildInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Where',
                value: appointment['serviceProvider']['display'],
              ),

            // Participants
            ...participantWidgets,

            // Add comment if available
            if (appointment['comment'] != null)
              _buildInfoRow(
                icon: Icons.note_outlined,
                label: 'Notes',
                value: appointment['comment'],
              ),
          ],
        ),
      ),
    );
  }

  String _getParticipantType(Map<String, dynamic> participant) {
    // FHIR defines participant.type to indicate the role
    if (participant['type'] != null &&
        participant['type'] is List &&
        (participant['type'] as List).isNotEmpty) {
      final typeObj = participant['type'][0];
      if (typeObj['coding'] != null && (typeObj['coding'] as List).isNotEmpty) {
        final coding = typeObj['coding'][0];
        if (coding['display'] != null) {
          return coding['display'];
        } else if (coding['code'] != null) {
          // Try to return a readable name from code
          switch (coding['code']) {
            case 'PPRF':
              return 'Provider';
            case 'ATND':
              return 'Attendee';
            case 'PAT':
              return 'Patient';
            case 'PART':
              return 'Participant';
            default:
              return coding['code'];
          }
        }
      } else if (typeObj['text'] != null) {
        return typeObj['text'];
      }
    }

    // If no type, use participant.status if available
    if (participant['status'] != null) {
      final status = participant['status'].toString();
      return status[0].toUpperCase() + status.substring(1);
    }

    return 'Participant';
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
