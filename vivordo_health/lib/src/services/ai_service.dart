import 'panda_types.dart';

export 'panda_types.dart';

// ---------------------------------------------------------------------------
// Token budget constants — shared by every AIService implementation.
// ---------------------------------------------------------------------------

/// Hard-reject any call whose estimated input exceeds this many tokens.
/// Protects against runaway prompt costs and latency spikes.
/// 1 token ≈ 4 characters (conservative English estimate).
const int kMaxInputTokens = 2500;

/// Output cap for a single dialogue turn (processTurn).
const int kMaxOutputTokensChat = 300;

/// Output cap for session spike analysis (analyzePandaSession).
const int kMaxOutputTokensSpike = 1800;

// ---------------------------------------------------------------------------

/// Common interface implemented by GeminiService and ClaudeService.
/// Switch between them at runtime via AIServiceFactory + Remote Config.
abstract class AIService {
  /// Run spike analysis and return the initial Panda session data
  /// (opener message, labeling questions, raw spike context).
  ///
  /// [userId] — real Firebase uid; when null/empty, demo path is used.
  Future<PandaSessionData> analyzePandaSession({
    String? extraUserContext,
    String? userName,
    String? userId,
  });

  /// Process a single dialogue turn.
  Future<PandaTurnReply> processTurn({
    required String userMessage,
    required List<Map<String, String>> conversationHistory,
    required List<Map<String, dynamic>> spikeContext,
    required bool isOnPredefinedPath,
    required bool isInDigression,
    required int digressionTurnCount,
    String? pendingQuestionId,
    String? pendingQuestionPrompt,
    String? digressionTopic,
    Map<String, String>? accumulatedSlots,
  });
}
