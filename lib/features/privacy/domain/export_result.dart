import 'local_data_export.dart';

enum ExportFailureCode {
  noActiveIdentity,
  localReadFailure,
  serializationFailure,
  unknown,
}

class ExportFailure {
  final ExportFailureCode code;
  final String message;

  const ExportFailure(this.code, this.message);
}

/// Typed result of [LocalDataExportService.export] — never throws across
/// its own boundary, mirroring the `CloudResult`/`SyncResult` pattern used
/// elsewhere in this app.
class ExportResult {
  final bool isSuccess;
  final LocalDataExport? export;
  final String? jsonString;
  final ExportFailure? failure;

  const ExportResult._({
    required this.isSuccess,
    this.export,
    this.jsonString,
    this.failure,
  });

  factory ExportResult.success(LocalDataExport export, String jsonString) =>
      ExportResult._(isSuccess: true, export: export, jsonString: jsonString);

  factory ExportResult.failure(ExportFailure failure) =>
      ExportResult._(isSuccess: false, failure: failure);
}
