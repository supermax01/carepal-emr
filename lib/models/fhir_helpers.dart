/// Helper functions to extract information from FHIR resources

// Safely extract a value from a map, with error handling
dynamic safeExtract(Map<String, dynamic>? data, List<dynamic> path,
    {dynamic defaultValue}) {
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

// Extract patient name from a FHIR Patient resource
String getPatientName(Map<String, dynamic>? patient) {
  if (patient == null) return 'Unknown Patient';

  try {
    // Try to get name from the resource
    final namesList = safeExtract(patient, ['name'], defaultValue: []) as List?;
    if (namesList == null || namesList.isEmpty) return 'Unknown Patient';

    final name = namesList[0];

    // Extract given names (may be a list)
    final given = safeExtract(name, ['given'], defaultValue: []) as List?;
    final givenName = given != null && given.isNotEmpty
        ? given.where((n) => n != null).map((n) => n.toString()).join(' ')
        : '';

    // Extract family name
    final family = safeExtract(name, ['family'], defaultValue: null);

    if (givenName.isNotEmpty && family != null) {
      return '$givenName $family';
    } else if (family != null) {
      return family.toString();
    } else if (givenName.isNotEmpty) {
      return givenName;
    }
  } catch (e) {
    // If anything goes wrong, return the unknown label
  }

  return 'Unknown Patient';
}

// Extract patient date of birth from a FHIR Patient resource
String getPatientDob(Map<String, dynamic>? patient) {
  if (patient == null) return 'Unknown';
  try {
    final birthDate =
        safeExtract(patient, ['birthDate'], defaultValue: 'Unknown');
    return birthDate.toString();
  } catch (e) {
    return 'Unknown';
  }
}

// Extract patient gender from a FHIR Patient resource
String getPatientGender(Map<String, dynamic>? patient) {
  if (patient == null) return 'Unknown';

  try {
    final gender = safeExtract(patient, ['gender'], defaultValue: 'Unknown');
    if (gender == null || gender == 'Unknown') return 'Unknown';

    // Capitalize first letter
    return gender.toString().substring(0, 1).toUpperCase() +
        gender.toString().substring(1).toLowerCase();
  } catch (e) {
    return 'Unknown';
  }
}

// Extract patient address from a FHIR Patient resource
String getPatientAddress(Map<String, dynamic>? patient) {
  if (patient == null) return 'No address on file';

  try {
    final addressList =
        safeExtract(patient, ['address'], defaultValue: []) as List?;
    if (addressList == null || addressList.isEmpty) return 'No address on file';

    final address = addressList[0];
    final List<String> addressParts = [];

    // Add line parts
    final lines = safeExtract(address, ['line'], defaultValue: []) as List?;
    if (lines != null && lines.isNotEmpty) {
      addressParts.addAll(
          lines.where((line) => line != null).map((line) => line.toString()));
    }

    // Add city, state, postal code
    final city = safeExtract(address, ['city'], defaultValue: null);
    final state = safeExtract(address, ['state'], defaultValue: null);
    final postalCode = safeExtract(address, ['postalCode'], defaultValue: null);

    if (city != null) addressParts.add(city.toString());
    if (state != null) addressParts.add(state.toString());
    if (postalCode != null) addressParts.add(postalCode.toString());

    return addressParts.isEmpty
        ? 'No address on file'
        : addressParts.join(', ');
  } catch (e) {
    return 'No address on file';
  }
}

// Extract medication name from a FHIR MedicationRequest resource
String getMedicationName(Map<String, dynamic>? medicationRequest) {
  if (medicationRequest == null) return 'Unknown Medication';

  try {
    // Try to get from medicationCodeableConcept first
    final coding = safeExtract(
        medicationRequest, ['medicationCodeableConcept', 'coding'],
        defaultValue: []) as List?;

    if (coding != null && coding.isNotEmpty) {
      // Return display name if available
      final display = safeExtract(coding[0], ['display'], defaultValue: null);
      if (display != null) return display.toString();

      // Otherwise return code
      final code = safeExtract(coding[0], ['code'], defaultValue: null);
      if (code != null) return code.toString();
    }

    // Try text field
    final text = safeExtract(
        medicationRequest, ['medicationCodeableConcept', 'text'],
        defaultValue: null);
    if (text != null) return text.toString();

    // Try medication reference
    final referenceDisplay = safeExtract(
        medicationRequest, ['medicationReference', 'display'],
        defaultValue: null);
    if (referenceDisplay != null) return referenceDisplay.toString();

    final reference = safeExtract(
        medicationRequest, ['medicationReference', 'reference'],
        defaultValue: null);
    if (reference != null) return reference.toString();
  } catch (e) {
    // If anything goes wrong, return the unknown label
  }

  return 'Unknown Medication';
}

// Extract medication dosage from a FHIR MedicationRequest resource
String getMedicationDosage(Map<String, dynamic>? medicationRequest) {
  if (medicationRequest == null) return 'No dosage information';

  try {
    final dosageList =
        safeExtract(medicationRequest, ['dosageInstruction'], defaultValue: [])
            as List?;
    if (dosageList == null || dosageList.isEmpty) {
      return 'No dosage information';
    }

    final dosage = dosageList[0];

    // Try to get dosage text
    final text = safeExtract(dosage, ['text'], defaultValue: null);
    if (text != null) return text.toString();

    // Try to construct from parts
    final List<String> dosageParts = [];

    // Get dose quantity
    final doseAndRateList =
        safeExtract(dosage, ['doseAndRate'], defaultValue: []) as List?;
    if (doseAndRateList != null && doseAndRateList.isNotEmpty) {
      final doseAndRate = doseAndRateList[0];

      final quantity = safeExtract(doseAndRate, ['doseQuantity', 'value'],
          defaultValue: null);
      final unit = safeExtract(doseAndRate, ['doseQuantity', 'unit'],
          defaultValue: null);

      if (quantity != null) {
        String dosePart = quantity.toString();
        if (unit != null) {
          dosePart += ' $unit';
        }
        dosageParts.add(dosePart);
      }
    }

    // Get timing
    final timingText =
        safeExtract(dosage, ['timing', 'code', 'text'], defaultValue: null);
    if (timingText != null) {
      dosageParts.add(timingText.toString());
    } else {
      final timingCoding = safeExtract(
          dosage, ['timing', 'code', 'coding', 0, 'display'],
          defaultValue: null);
      if (timingCoding != null) {
        dosageParts.add(timingCoding.toString());
      }
    }

    return dosageParts.isEmpty
        ? 'No dosage information'
        : dosageParts.join(' ');
  } catch (e) {
    return 'No dosage information';
  }
}

// Extract observation value from a FHIR Observation resource
String getObservationValue(Map<String, dynamic>? observation) {
  if (observation == null) return 'No value';

  try {
    // Try valueQuantity first (most common)
    final value = safeExtract(observation, ['valueQuantity', 'value'],
        defaultValue: null);
    final unit =
        safeExtract(observation, ['valueQuantity', 'unit'], defaultValue: null);

    if (value != null) {
      String valuePart = value.toString();
      if (unit != null) {
        valuePart += ' $unit';
      }
      return valuePart;
    }

    // Try other value types
    final valueString =
        safeExtract(observation, ['valueString'], defaultValue: null);
    if (valueString != null) return valueString.toString();

    final valueBoolean =
        safeExtract(observation, ['valueBoolean'], defaultValue: null);
    if (valueBoolean != null) return valueBoolean ? 'Yes' : 'No';

    final valueInteger =
        safeExtract(observation, ['valueInteger'], defaultValue: null);
    if (valueInteger != null) return valueInteger.toString();

    // Check CodeableConcept
    final valueConceptText = safeExtract(
        observation, ['valueCodeableConcept', 'text'],
        defaultValue: null);
    if (valueConceptText != null) return valueConceptText.toString();

    final valueConceptDisplay = safeExtract(
        observation, ['valueCodeableConcept', 'coding', 0, 'display'],
        defaultValue: null);
    if (valueConceptDisplay != null) return valueConceptDisplay.toString();

    final valueConceptCode = safeExtract(
        observation, ['valueCodeableConcept', 'coding', 0, 'code'],
        defaultValue: null);
    if (valueConceptCode != null) return valueConceptCode.toString();

    // For component-based observations (like BP)
    final componentsList =
        safeExtract(observation, ['component'], defaultValue: []) as List?;
    if (componentsList != null && componentsList.isNotEmpty) {
      final List<String> componentValues = [];

      for (final component in componentsList) {
        String name = '';
        String value = '';

        // Try to get component name
        final display = safeExtract(component, ['code', 'coding', 0, 'display'],
            defaultValue: null);
        final code = safeExtract(component, ['code', 'coding', 0, 'code'],
            defaultValue: null);

        name = display?.toString() ?? code?.toString() ?? '';

        // Try to get component value
        final compValue = safeExtract(component, ['valueQuantity', 'value'],
            defaultValue: null);
        if (compValue != null) {
          value = compValue.toString();
          final compUnit = safeExtract(component, ['valueQuantity', 'unit'],
              defaultValue: null);
          if (compUnit != null) {
            value += ' $compUnit';
          }
        }

        if (name.isNotEmpty && value.isNotEmpty) {
          componentValues.add('$name: $value');
        }
      }

      if (componentValues.isNotEmpty) {
        return componentValues.join(', ');
      }
    }
  } catch (e) {
    // If anything goes wrong, return the default value
  }

  return 'No value';
}

// Extract observation date from a FHIR Observation resource
String getObservationDate(Map<String, dynamic>? observation) {
  if (observation == null) return 'Unknown date';

  try {
    final effectiveDateTime =
        safeExtract(observation, ['effectiveDateTime'], defaultValue: null);
    if (effectiveDateTime != null) {
      final dateStr = effectiveDateTime.toString();
      return dateStr.split('T')[0]; // Simple date extraction
    }

    final issued = safeExtract(observation, ['issued'], defaultValue: null);
    if (issued != null) {
      final dateStr = issued.toString();
      return dateStr.split('T')[0];
    }
  } catch (e) {
    // If anything goes wrong, return the default value
  }

  return 'Unknown date';
}

// Extract appointment date and time from a FHIR Appointment resource
String getAppointmentDateTime(Map<String, dynamic>? appointment) {
  if (appointment == null) return 'Unknown date';

  try {
    final start = safeExtract(appointment, ['start'], defaultValue: null);
    if (start != null) {
      final startDateTime = start.toString();

      // Try to format the date and time in a human-readable way
      try {
        final dateTime = DateTime.parse(startDateTime);
        final date =
            '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
        final time =
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        return '$date $time';
      } catch (e) {
        // If parsing fails, just return the raw string
        return startDateTime;
      }
    }
  } catch (e) {
    // If anything goes wrong, return the default value
  }

  return 'Unknown date';
}

// Extract appointment status from a FHIR Appointment resource
String getAppointmentStatus(Map<String, dynamic>? appointment) {
  if (appointment == null) return 'Unknown';

  try {
    final status =
        safeExtract(appointment, ['status'], defaultValue: 'unknown');
    if (status == null) return 'Unknown';

    // Capitalize and format the status
    switch (status.toString().toLowerCase()) {
      case 'proposed':
        return 'Proposed';
      case 'pending':
        return 'Pending';
      case 'booked':
        return 'Booked';
      case 'arrived':
        return 'Arrived';
      case 'fulfilled':
        return 'Fulfilled';
      case 'cancelled':
        return 'Cancelled';
      case 'noshow':
        return 'No Show';
      case 'entered-in-error':
        return 'Entered in Error';
      default:
        return status.toString().substring(0, 1).toUpperCase() +
            status.toString().substring(1).toLowerCase();
    }
  } catch (e) {
    return 'Unknown';
  }
}

// Extract appointment description from a FHIR Appointment resource
String getAppointmentDescription(Map<String, dynamic>? appointment) {
  if (appointment == null) return 'No description';

  try {
    // Try description first
    final description =
        safeExtract(appointment, ['description'], defaultValue: null);
    if (description != null) return description.toString();

    // Try reason code
    final reasonCode =
        safeExtract(appointment, ['reasonCode', 0, 'text'], defaultValue: null);
    if (reasonCode != null) return reasonCode.toString();

    // Try service type
    final serviceType = safeExtract(appointment, ['serviceType', 0, 'text'],
        defaultValue: null);
    if (serviceType != null) return serviceType.toString();

    // Try participant type - usually the practitioner
    final participants =
        safeExtract(appointment, ['participant'], defaultValue: []) as List?;
    if (participants != null && participants.isNotEmpty) {
      for (final participant in participants) {
        final reference =
            safeExtract(participant, ['actor', 'display'], defaultValue: null);
        if (reference != null) return 'With: ${reference.toString()}';
      }
    }
  } catch (e) {
    // If anything goes wrong, return the default value
  }

  return 'No description';
}
