// Shared data types for the Panda AI service abstraction.
// Imported by GeminiService, ClaudeService, AIService, and PandaScreen.

class PandaSessionData {
  PandaSessionData({
    required this.openerMessage,
    required this.questions,
    required this.overallNotes,
    required this.rawSpikes,
  });

  final String openerMessage;
  final List<PandaQuestion> questions;
  final String overallNotes;

  /// Raw spike JSON kept so the dialogue LLM has health data for context.
  final List<Map<String, dynamic>> rawSpikes;
}

class PandaQuestion {
  PandaQuestion({
    required this.questionId,
    required this.prompt,
    required this.options,
    this.depthPrompts = const [],
  });

  final String questionId;
  final String prompt;
  final List<String> options;

  /// Follow-up prompts to use when user wants to go deeper on this topic.
  final List<String> depthPrompts;
}

// ---------------------------------------------------------------------------
// Intent classification (ICM+LLM hybrid pattern)
// ---------------------------------------------------------------------------
enum PandaIntent {
  answerLabel,
  wantDeeperAnswer,
  digress,
  digressionComplete,
  newStressor,
  recommend,
  chitchat,
  skip,
}

/// Full structured reply from a single dialogue turn.
class PandaTurnReply {
  PandaTurnReply({
    required this.intent,
    required this.message,
    this.depthFollowUp,
    this.injectedQuestion,
    this.filledSlots,
    this.recHint,
  });

  final PandaIntent intent;

  /// What Panda says (always present, never empty).
  final String message;

  /// When intent == wantDeeperAnswer: a follow-up probing question.
  final String? depthFollowUp;

  /// When intent == newStressor: inject this question into the queue.
  final PandaQuestion? injectedQuestion;

  /// Slot values extracted from this turn (accumulated across session).
  final Map<String, String>? filledSlots;

  /// When intent == recommend: comma-separated keywords for the rec engine.
  final String? recHint;
}
