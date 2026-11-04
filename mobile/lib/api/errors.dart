/// An error whose message is written for the person using the app and can be shown as is.
class UserFacingError implements Exception {
  const UserFacingError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// An error answer from the API. [message] is the server's `detail` sentence when it sent one.
class ApiError extends UserFacingError {
  const ApiError(this.status, super.message);

  /// The HTTP status, or 0 when the server couldn't be reached.
  final int status;

  bool get isNotFound => status == 404;
}

const unreachableMessage = "Can't reach the server. Check your connection and try again.";
const sessionExpiredMessage = 'Your session has expired. Sign in again.';

String errorMessage(Object error) =>
    error is UserFacingError ? error.message : 'Something went wrong. Try again.';
