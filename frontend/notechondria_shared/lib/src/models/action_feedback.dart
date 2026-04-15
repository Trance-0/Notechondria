/// Reports user-facing success or failure feedback for an async action.
class ActionFeedback {
  const ActionFeedback({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}
