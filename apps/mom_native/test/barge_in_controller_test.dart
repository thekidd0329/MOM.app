import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/barge_in_controller.dart';

void main() {
  group('MomBargeInController', () {
    test('interrupt preserves unfinished thought from current chunk', () {
      final controller = MomBargeInController();
      controller.begin(
        originalText: 'One. Two. Three.',
        chunks: const ['One.', 'Two.', 'Three.'],
      );
      controller.markChunkStarted(0);
      controller.markChunkCompleted(0);
      controller.markChunkStarted(1);

      final thought = controller.interrupt();
      expect(thought, isNotNull);
      expect(thought!.completedText, 'One.');
      expect(thought.resumeText, 'Two. Three.');
      expect(thought.interruptedChunkIndex, 1);
      expect(thought.currentChunkMayBePartial, isTrue);
      expect(thought.hasUnfinishedText, isTrue);
    });

    test('interrupt between chunks resumes at next unspoken chunk', () {
      final controller = MomBargeInController();
      controller.begin(
        originalText: 'One. Two. Three.',
        chunks: const ['One.', 'Two.', 'Three.'],
      );
      controller.markChunkStarted(0);
      controller.markChunkCompleted(0);

      final thought = controller.interrupt();
      expect(thought, isNotNull);
      expect(thought!.completedText, 'One.');
      expect(thought.resumeText, 'Two. Three.');
      expect(thought.currentChunkMayBePartial, isFalse);
    });

    test('barge-in invalidates the active playback generation', () {
      final controller = MomBargeInController();
      final generation = controller.begin(
        originalText: 'One. Two.',
        chunks: const ['One.', 'Two.'],
      );
      expect(controller.isCurrent(generation), isTrue);
      controller.interrupt();
      expect(controller.isCurrent(generation), isFalse);
    });

    test('pending interrupted thought is consumed once', () {
      final controller = MomBargeInController();
      controller.begin(
        originalText: 'One. Two.',
        chunks: const ['One.', 'Two.'],
      );
      controller.markChunkStarted(0);
      final interrupted = controller.interrupt();
      expect(controller.pendingThought, same(interrupted));
      expect(controller.consumePendingThought(), same(interrupted));
      expect(controller.consumePendingThought(), isNull);
    });

    test('next-turn context prioritizes the interruption before continuation', () {
      const thought = InterruptedThought(
        originalText: 'You should call her. And then take a shower.',
        completedText: 'You should call her.',
        resumeText: 'And then take a shower.',
        interruptedChunkIndex: 1,
        currentChunkMayBePartial: false,
      );
      final context = thought.contextForNextTurn('Wait, she just texted me.');
      expect(context, contains('Your person cut in with: Wait, she just texted me.'));
      expect(context, contains('Respond to what they just said first.'));
      expect(context, contains('Continue the unfinished thought only if it still matters naturally.'));
    });

    test('cancel without continuity clears all interruption state', () {
      final controller = MomBargeInController();
      controller.begin(
        originalText: 'One. Two.',
        chunks: const ['One.', 'Two.'],
      );
      controller.markChunkStarted(0);
      controller.cancelWithoutContinuity();
      expect(controller.speaking, isFalse);
      expect(controller.pendingThought, isNull);
      expect(controller.interrupt(), isNull);
    });
  });
}
