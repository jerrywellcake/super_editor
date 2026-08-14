import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/document_ime/document_serialization.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  group('IME serialization of a document that changed underneath it >', () {
    // `TextDeltasDocumentEditor.applyDeltas()` serializes the document, applies the
    // platform's deltas - which can delete or merge nodes - and only then maps the
    // composing region back through that same, now-stale serialization. A range that
    // points at a deleted node used to be dereferenced with `!`, throwing
    // "Null check operator used on a null value" out of the IME delta handler.

    late MutableDocument document;
    late DocumentImeSerializer serializer;

    setUp(() {
      document = MutableDocument(
        nodes: [
          ParagraphNode(id: 'first', text: AttributedText('Hello')),
          ParagraphNode(id: 'second', text: AttributedText('World')),
        ],
      );
      serializer = DocumentImeSerializer(
        document,
        const DocumentSelection(
          base: DocumentPosition(nodeId: 'first', nodePosition: TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: 'second', nodePosition: TextNodePosition(offset: 5)),
        ),
        null,
        PrependedCharacterPolicy.exclude,
      );
    });

    test('serializes both nodes into one IME string', () {
      // Anchors the offsets the rest of the tests rely on: "Hello\nWorld".
      expect(serializer.imeText, 'Hello\nWorld');
    });

    test('returns a null range when the mapped node is gone', () {
      document.deleteNode('second');

      expect(
        serializer.imeToDocumentRange(const TextRange(start: 6, end: 11)),
        isNull,
      );
    });

    test('returns a null range when only one end of the range is gone', () {
      document.deleteNode('second');

      // Starts inside the surviving node and ends inside the deleted one.
      expect(
        serializer.imeToDocumentRange(const TextRange(start: 0, end: 11)),
        isNull,
      );
    });

    test('still maps a range whose nodes are all present', () {
      // The stale-node tolerance must not disturb ordinary mapping.
      final range = serializer.imeToDocumentRange(const TextRange(start: 0, end: 5));

      expect(range, isNotNull);
      expect(range!.start.nodeId, 'first');
      expect((range.start.nodePosition as TextNodePosition).offset, 0);
      expect(range.end.nodeId, 'first');
      expect((range.end.nodePosition as TextNodePosition).offset, 5);
    });

    test('still maps a range in a surviving node after another node is deleted', () {
      document.deleteNode('second');

      final range = serializer.imeToDocumentRange(const TextRange(start: 0, end: 5));

      expect(range, isNotNull);
      expect(range!.start.nodeId, 'first');
      expect(range.end.nodeId, 'first');
    });
  });
}
