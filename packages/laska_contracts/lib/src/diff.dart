import 'model.dart';

/// How severe a change is for the consumers of a contract.
enum ChangeSeverity {
  /// Consumers have to change their code.
  breaking,

  /// Consumers keep working as they are.
  nonBreaking,
}

/// A single difference between two contracts.
class ContractChange {
  /// Creates a change.
  ContractChange({
    required this.severity,
    required this.subject,
    required this.message,
  });

  /// Severity of the change.
  final ChangeSeverity severity;

  /// What the change is about, e.g. `users.v1.User.email`.
  final String subject;

  /// Human readable description of the change.
  final String message;

  /// Whether the change breaks existing consumers.
  bool get isBreaking => severity == ChangeSeverity.breaking;

  @override
  String toString() =>
      '${isBreaking ? 'BREAKING' : 'NON-BREAKING'}  $subject: $message';
}

/// The result of comparing two contracts.
class ContractDiff {
  /// Creates a diff out of [changes].
  ContractDiff(this.changes);

  /// All detected changes.
  final List<ContractChange> changes;

  /// Whether any change breaks existing consumers.
  bool get hasBreakingChanges => changes.any((change) => change.isBreaking);

  /// Only the breaking changes.
  List<ContractChange> get breakingChanges =>
      changes.where((change) => change.isBreaking).toList();

  /// Renders the diff as a human readable report.
  String report() {
    if (changes.isEmpty) {
      return 'No changes detected.';
    }
    final buffer = StringBuffer();
    for (final change in changes) {
      buffer.writeln(change.toString());
    }
    final breaking = breakingChanges.length;
    buffer.writeln();
    buffer.writeln(
      '$breaking breaking change(s), '
      '${changes.length - breaking} non-breaking change(s).',
    );
    return buffer.toString();
  }
}

/// Compares two contracts and reports the differences.
///
/// The rules follow the semantics of protobuf: removing a field, changing a
/// field number or type, removing a method or changing its signature breaks
/// the consumers of a contract. Adding a field, a message or a method does
/// not.
ContractDiff diffContracts(Contract base, Contract candidate) {
  final changes = <ContractChange>[];

  final baseMessages = <String, Message>{
    for (final message in base.messages) message.fullName: message,
  };
  final candidateMessages = <String, Message>{
    for (final message in candidate.messages) message.fullName: message,
  };

  for (final entry in baseMessages.entries) {
    final updated = candidateMessages[entry.key];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: entry.key,
          message: 'message was removed',
        ),
      );
      continue;
    }
    _diffMessage(entry.value, updated, changes, base, candidate);
  }
  for (final entry in candidateMessages.entries) {
    if (!baseMessages.containsKey(entry.key)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: entry.key,
          message: 'message was added',
        ),
      );
    }
  }

  final baseEnums = <String, EnumType>{
    for (final value in base.enums) value.fullName: value,
  };
  final candidateEnums = <String, EnumType>{
    for (final value in candidate.enums) value.fullName: value,
  };

  for (final entry in baseEnums.entries) {
    final updated = candidateEnums[entry.key];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: entry.key,
          message: 'enum was removed',
        ),
      );
      continue;
    }
    _diffEnum(entry.value, updated, changes);
  }
  for (final entry in candidateEnums.entries) {
    if (!baseEnums.containsKey(entry.key)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: entry.key,
          message: 'enum was added',
        ),
      );
    }
  }

  final baseServices = <String, Service>{
    for (final service in base.services) service.fullName: service,
  };
  final candidateServices = <String, Service>{
    for (final service in candidate.services) service.fullName: service,
  };

  for (final entry in baseServices.entries) {
    final updated = candidateServices[entry.key];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: entry.key,
          message: 'service was removed',
        ),
      );
      continue;
    }
    _diffService(entry.value, updated, changes);
  }
  for (final entry in candidateServices.entries) {
    if (!baseServices.containsKey(entry.key)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: entry.key,
          message: 'service was added',
        ),
      );
    }
  }

  return ContractDiff(changes);
}

/// The name of the type a reference points to.
///
/// A type is written in a contract without a qualifier as often as it is
/// written with one, so the references of two versions of a contract are
/// compared by the type they point to, and not by the way they are written.
String? _canonicalType(Contract contract, String reference) {
  final message = contract.message(reference) ??
      contract.messageBySimpleName(reference.split('.').last);
  if (message != null) {
    return message.fullName;
  }
  final enumType = contract.enumType(reference) ??
      contract.enumBySimpleName(reference.split('.').last);
  if (enumType != null) {
    return enumType.fullName;
  }
  return reference;
}

void _diffMessage(
  Message base,
  Message candidate,
  List<ContractChange> changes,
  Contract baseContract,
  Contract candidateContract,
) {
  final candidateFields = <String, Field>{
    for (final field in candidate.allFields) field.name: field,
  };

  for (final field in base.allFields) {
    final updated = candidateFields[field.name];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message: 'field was removed',
        ),
      );
      continue;
    }

    if (updated.number != field.number) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message:
              'field number changed from ${field.number} to ${updated.number}',
        ),
      );
    }
    if (_canonicalType(baseContract, field.type) !=
        _canonicalType(candidateContract, updated.type)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message: 'field type changed from ${field.type} to ${updated.type}',
        ),
      );
    } else if (field.isMap &&
        updated.isMap &&
        _canonicalType(baseContract, field.mapValueType!) !=
            _canonicalType(candidateContract, updated.mapValueType!)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message: 'the type of the values of the map changed from '
              '${field.mapValueType} to ${updated.mapValueType}',
        ),
      );
    }
    if (updated.repeated != field.repeated) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message: updated.repeated
              ? 'field became repeated'
              : 'field is no longer repeated',
        ),
      );
    }
    if (field.optional && !updated.optional) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message: 'field is no longer optional',
        ),
      );
    } else if (!field.optional && updated.optional) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: '${base.fullName}.${field.name}',
          message: 'field became optional',
        ),
      );
    }
    if (field.oneof != updated.oneof) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${field.name}',
          message: field.oneof == null
              ? 'field moved into the oneof "${updated.oneof}"'
              : updated.oneof == null
                  ? 'field moved out of the oneof "${field.oneof}"'
                  : 'field moved from the oneof "${field.oneof}" into the '
                      'oneof "${updated.oneof}"',
        ),
      );
    }
  }

  for (final field in candidate.allFields) {
    if (base.field(field.name) == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: '${base.fullName}.${field.name}',
          message: 'field was added',
        ),
      );
    }
  }

  _diffOneofs(base, candidate, changes);
}

/// Compares the groups of a `oneof` of two versions of a message.
///
/// A member that leaves a group, and a member that joins a group that already
/// exists, break the consumers: the code that sets the group has to know
/// about the new member.
void _diffOneofs(
  Message base,
  Message candidate,
  List<ContractChange> changes,
) {
  final candidateGroups = <String, Oneof>{
    for (final group in candidate.oneofs) group.name: group,
  };

  for (final group in base.oneofs) {
    final updated = candidateGroups[group.name];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${group.name}',
          message: 'oneof was removed',
        ),
      );
      continue;
    }

    final updatedMembers = updated.fields.map((field) => field.name).toSet();
    for (final member in group.fields) {
      if (!updatedMembers.contains(member.name)) {
        changes.add(
          ContractChange(
            severity: ChangeSeverity.breaking,
            subject: '${base.fullName}.${group.name}.${member.name}',
            message: 'member of the oneof was removed',
          ),
        );
      }
    }

    for (final member in updated.fields) {
      if (!group.fields.any((existing) => existing.name == member.name)) {
        changes.add(
          ContractChange(
            severity: ChangeSeverity.breaking,
            subject: '${base.fullName}.${group.name}.${member.name}',
            message: 'a field was added to the oneof',
          ),
        );
      }
    }
  }

  for (final group in candidate.oneofs) {
    if (!base.oneofs.any((existing) => existing.name == group.name)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: '${base.fullName}.${group.name}',
          message: 'oneof was added',
        ),
      );
    }
  }
}

void _diffEnum(
  EnumType base,
  EnumType candidate,
  List<ContractChange> changes,
) {
  final candidateValues = <String, EnumValue>{
    for (final value in candidate.values) value.name: value,
  };

  for (final value in base.values) {
    final updated = candidateValues[value.name];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${value.name}',
          message: 'enum value was removed',
        ),
      );
      continue;
    }
    if (updated.number != value.number) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${value.name}',
          message:
              'enum value number changed from ${value.number} to ${updated.number}',
        ),
      );
    }
  }

  for (final value in candidate.values) {
    if (!base.values.any((existing) => existing.name == value.name)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: '${base.fullName}.${value.name}',
          message: 'enum value was added',
        ),
      );
    }
  }
}

void _diffService(
  Service base,
  Service candidate,
  List<ContractChange> changes,
) {
  final candidateMethods = <String, Method>{
    for (final method in candidate.methods) method.name: method,
  };

  for (final method in base.methods) {
    final updated = candidateMethods[method.name];
    if (updated == null) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${method.name}',
          message: 'method was removed',
        ),
      );
      continue;
    }
    if (updated.requestType != method.requestType) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${method.name}',
          message: 'request type changed from '
              '${method.requestType} to ${updated.requestType}',
        ),
      );
    }
    if (updated.responseType != method.responseType) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.breaking,
          subject: '${base.fullName}.${method.name}',
          message: 'response type changed from '
              '${method.responseType} to ${updated.responseType}',
        ),
      );
    }
    _diffHttpRules(base, method, updated, changes);
  }

  for (final method in candidate.methods) {
    if (!base.methods.any((existing) => existing.name == method.name)) {
      changes.add(
        ContractChange(
          severity: ChangeSeverity.nonBreaking,
          subject: '${base.fullName}.${method.name}',
          message: 'method was added',
        ),
      );
    }
  }
}

void _diffHttpRules(
  Service service,
  Method base,
  Method candidate,
  List<ContractChange> changes,
) {
  String describe(Method method) =>
      method.httpRules.map((rule) => '${rule.method} ${rule.path}').join(', ');

  final baseRules = describe(base);
  final candidateRules = describe(candidate);
  if (baseRules != candidateRules) {
    changes.add(
      ContractChange(
        severity: ChangeSeverity.breaking,
        subject: '${service.fullName}.${base.name}',
        message: 'HTTP binding changed from [$baseRules] to [$candidateRules]',
      ),
    );
  }
}
