import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/src/default_editor/document_ime/document_ime_communication.dart';

void main() {
  group('IME platform selection >', () {
    // The offsets in these tests are the ones observed in production crash reports.
    //
    // On Safari, `DocumentImeInputClient` adopts the selection from the platform's most
    // recent delta while sending its own, freshly serialized text. Those offsets index
    // the platform's text, which can be longer than ours, so they can point past the end
    // of the text we're sending.
    //
    // The web engine keeps whatever we hand it as its `lastEditingState`, but the DOM
    // clamps `setSelectionRange()` to the text length. An out-of-bounds offset therefore
    // desyncs the engine from the DOM, and the next delta the engine infers carries a
    // replacement range that is inverted or past the end of our text. Applying that delta
    // throws `RangeError` out of `TextEditingDelta.apply()`.

    test('is clamped when it points past the end of the text', () {
      // "Not in inclusive range 0..11: 12" - the platform reports offset 12 for text
      // that's only 11 characters long.
      const text = 'Hello world'; // 11 characters.
      const value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 11),
      );

      final adopted = adoptPlatformSelection(
        value,
        const TextSelection.collapsed(offset: 12),
      );

      expect(adopted.selection.baseOffset, 11);
      expect(adopted.selection.extentOffset, 11);
      expect(adopted.text, text);
    });

    test('is clamped when the platform reports an expanded out-of-bounds range', () {
      // "Not in inclusive range 0..11: 16" - an expanded selection whose offsets both
      // run past the end of our text. Left alone, base > extent produces the inverted
      // range that throws RangeError (start).
      const text = 'Hello world'; // 11 characters.
      const value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 0),
      );

      final adopted = adoptPlatformSelection(
        value,
        const TextSelection(baseOffset: 16, extentOffset: 13),
      );

      expect(adopted.selection.baseOffset, 11);
      expect(adopted.selection.extentOffset, 11);
    });

    test('never produces a selection outside the text it is sent with', () {
      // This is the invariant the fix exists to hold. `TextEditingValue` asserts it in
      // debug builds, so an out-of-bounds selection only survives in release - which is
      // exactly why this crashed in production and never in development.
      const text = 'Hi'; // 2 characters.
      const value = TextEditingValue(text: text);

      for (final platformSelection in const [
        TextSelection.collapsed(offset: 3),
        TextSelection.collapsed(offset: 188),
        TextSelection(baseOffset: 5, extentOffset: 2),
        TextSelection(baseOffset: 0, extentOffset: 99),
      ]) {
        final adopted = adoptPlatformSelection(value, platformSelection);

        expect(adopted.selection.baseOffset, inInclusiveRange(0, text.length));
        expect(adopted.selection.extentOffset, inInclusiveRange(0, text.length));
      }
    });

    test('is adopted unchanged when it already fits the text', () {
      // The clamp must be a no-op for in-bounds offsets. This is what keeps the fix a
      // correctness repair rather than a behavior change: the Safari workaround still
      // adopts the platform's selection exactly as before.
      const value = TextEditingValue(
        text: 'Hello world',
        selection: TextSelection.collapsed(offset: 0),
      );

      final adopted = adoptPlatformSelection(
        value,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );

      expect(adopted.selection.baseOffset, 2);
      expect(adopted.selection.extentOffset, 7);
    });

    test('is ignored when the platform reports no selection', () {
      // Adopting -1 offsets would make the whole value invalid, and the engine drops
      // invalid values without ever writing them to the DOM - a guaranteed desync. We
      // keep our own selection instead.
      const value = TextEditingValue(
        text: 'Hello world',
        selection: TextSelection.collapsed(offset: 4),
      );

      final adopted = adoptPlatformSelection(
        value,
        const TextSelection.collapsed(offset: -1),
      );

      expect(adopted, value);
    });
  });
}
