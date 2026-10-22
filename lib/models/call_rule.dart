enum CallCategory {
  spam,
  contacts,
  unknown,
}

enum CallAction {
  allow,
  silence,
  reject,
  askMe,
}

extension CallActionX on CallAction {
  String get label {
    switch (this) {
      case CallAction.allow:
        return 'Allow';
      case CallAction.silence:
        return 'Silence';
      case CallAction.reject:
        return 'Reject';
      case CallAction.askMe:
        return 'Silence';
    }
  }

  static CallAction fromLabel(String label) {
    switch (label) {
      case 'Allow':
        return CallAction.allow;
      case 'Reject':
        return CallAction.reject;
      case 'Silence':
      case 'Ask me':
      default:
        return CallAction.silence;
    }
  }
}

class CallRulesConfig {
  final CallAction spamAction;
  final CallAction contactAction;
  final CallAction unknownAction;

  const CallRulesConfig({
    this.spamAction = CallAction.silence,
    this.contactAction = CallAction.allow,
    this.unknownAction = CallAction.silence,
  });

  CallRulesConfig copyWith({
    CallAction? spamAction,
    CallAction? contactAction,
    CallAction? unknownAction,
  }) {
    return CallRulesConfig(
      spamAction: spamAction ?? this.spamAction,
      contactAction: contactAction ?? this.contactAction,
      unknownAction: unknownAction ?? this.unknownAction,
    );
  }
}

