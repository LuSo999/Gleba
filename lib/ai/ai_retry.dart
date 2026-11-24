import 'ai_models.dart';

/// One provider + model to try.
typedef AiAttempt = ({AiProvider provider, String? model});

/// What [runWithFallback] is doing after a failure, for the UI.
typedef AiRetryNote = ({AiAttempt attempt, int retry});

/// Runs [call] on the first attempt; a transient failure (overloaded, rate
/// limited, timeout) is retried with a backoff and then moves on to the next
/// model/provider. A non-transient failure (bad key, refused, …) moves on
/// straight away. Throws the first error when every attempt failed.
Future<T> runWithFallback<T>(
  List<AiAttempt> attempts,
  Future<T> Function(AiAttempt a) call, {
  void Function(AiRetryNote note)? onRetry,
  Future<void> Function(Duration d) sleep = _sleep,
  List<Duration> backoff = const [Duration(seconds: 2)],
}) async {
  Object? first;
  StackTrace? firstStack;
  for (var i = 0; i < attempts.length; i++) {
    final a = attempts[i];
    for (var retry = 0;; retry++) {
      if (i > 0 || retry > 0) onRetry?.call((attempt: a, retry: retry));
      try {
        return await call(a);
      } catch (e, st) {
        if (first == null) {
          first = e;
          firstStack = st;
        }
        final transient = e is AiException && e.transient;
        if (!transient || retry >= backoff.length) break;
        await sleep(backoff[retry]);
      }
    }
  }
  Error.throwWithStackTrace(first ?? const AiException('no-provider'), firstStack ?? StackTrace.current);
}

Future<void> _sleep(Duration d) => Future.delayed(d);
