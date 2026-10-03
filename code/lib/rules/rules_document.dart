// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A very small reader for the rules page in `assets/html`.
///
/// The rules live in an HTML file so that they are easy to edit and to read on
/// their own. Rather than pull in a whole web view just to show one page of
/// static prose, the markup is read into plain blocks here and drawn with
/// ordinary Flutter widgets.
///
/// Only the handful of tags the rules page actually uses is understood:
/// `<h1>` to `<h3>`, `<p>`, `<ul>`/`<li>`, and `<b>`, `<strong>`, `<i>` and
/// `<em>` for emphasis inside a block. Any other tag is ignored, and the text
/// inside it is kept.
library;

/// Where the rules page lives, as an asset path that [rootBundle] understands.
///
/// The `assets/html/` directory has to be listed in `pubspec.yaml` for this to
/// resolve.
const String kRulesAssetPath = 'assets/html/rules.html';

/// Parts of an HTML document that are not part of the page's prose: comments,
/// the doctype, and the contents of `<head>`, `<script>` and `<style>`.
///
/// These are removed before anything else, so that a page's metadata never
/// ends up on screen.
final RegExp _ignoredRegions = RegExp(
  r'<!--[\s\S]*?-->'
  r'|<!\w[^>]*>'
  r'|<(head|script|style)\b[^>]*>[\s\S]*?</\1\s*>',
  caseSensitive: false,
);

/// The named character entities the rules page is likely to use.
const Map<String, String> _namedEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
};

final RegExp _entity = RegExp(
  r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);',
);

/// Turns character entities such as `&#215;` and `&mdash;` into real
/// characters.
///
/// Anything that is not a recognised entity is left exactly as it was, so an
/// ampersand in ordinary prose survives untouched.
String _decodeEntities(String text) {
  if (!text.contains('&')) {
    return text;
  }
  return text.replaceAllMapped(_entity, (match) {
    final body = match.group(1)!;
    if (body.startsWith('#')) {
      final isHex = body[1] == 'x' || body[1] == 'X';
      final code = int.tryParse(
        isHex ? body.substring(2) : body.substring(1),
        radix: isHex ? 16 : 10,
      );
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    return _namedEntities[body.toLowerCase()] ?? match.group(0)!;
  });
}

/// What a block of the rules page represents.
enum RulesBlockKind {
  /// A section title.
  heading,

  /// A run of prose.
  paragraph,

  /// One entry in a bulleted list.
  listItem,
}

/// A run of text within a block, with any emphasis applied.
class RulesSpan {
  const RulesSpan(this.text, {this.bold = false, this.italic = false});

  /// The text of this run.
  final String text;

  /// Whether the text should be shown in bold.
  final bool bold;

  /// Whether the text should be shown in italics.
  final bool italic;

  /// A copy of this span with different text.
  RulesSpan withText(String text) =>
      RulesSpan(text, bold: bold, italic: italic);

  @override
  String toString() => text;
}

/// One block of the rules page, such as a heading or a paragraph.
class RulesBlock {
  const RulesBlock({required this.kind, required this.spans, this.level = 1});

  /// Whether this block is a heading, a paragraph, or a list entry.
  final RulesBlockKind kind;

  /// The runs of text making up the block, in order.
  final List<RulesSpan> spans;

  /// For a heading, how deep it sits: 1 for `<h1>`, 2 for `<h2>`, and so on.
  final int level;

  /// The block's text, with the emphasis dropped.
  String get plainText => spans.map((span) => span.text).join();

  @override
  String toString() => '$kind: $plainText';
}

/// Reads [html] into a list of blocks.
///
/// Returns an empty list when there is nothing to show, so that a missing or
/// malformed page leaves the screen blank rather than crashing.
List<RulesBlock> parseRulesDocument(String html) {
  final blocks = <RulesBlock>[];
  if (html.trim().isEmpty) {
    return blocks;
  }

  // Drop the document's metadata before reading any of its text.
  html = html.replaceAll(_ignoredRegions, '');

  // Text seen so far, waiting to be turned into a block.
  final spans = <RulesSpan>[];

  // What the next completed block should be called. A block tag takes effect
  // when it closes, because that is when its content has been collected.
  var pendingKind = RulesBlockKind.paragraph;
  var pendingLevel = 1;

  var bold = false;
  var italic = false;

  /// Emits whatever has been collected as a block and starts again.
  void flush() {
    final cleaned = _tidy(spans);
    spans.clear();
    if (cleaned.isEmpty) {
      return;
    }
    blocks.add(
      RulesBlock(kind: pendingKind, spans: cleaned, level: pendingLevel),
    );
  }

  /// Records a run of text with the emphasis that is in force right now.
  void emit(String text) {
    if (text.isEmpty) {
      return;
    }
    final decoded = _decodeEntities(text);
    if (decoded.isEmpty) {
      return;
    }
    spans.add(RulesSpan(decoded, bold: bold, italic: italic));
  }

  final tagPattern = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*>');

  var index = 0;
  for (final match in tagPattern.allMatches(html)) {
    emit(html.substring(index, match.start));
    index = match.end;

    final isClosing = match.group(1) == '/';
    final tag = match.group(2)!.toLowerCase();

    switch (tag) {
      // Emphasis runs, which can wrap any of the inline tags.
      case 'b' || 'strong':
        bold = !isClosing;
      case 'i' || 'em':
        italic = !isClosing;

      // Block tags. Opening one closes whatever was collected before it;
      // closing one names what has just been collected.
      case 'h1' || 'h2' || 'h3':
        if (isClosing) {
          pendingKind = RulesBlockKind.heading;
          pendingLevel = int.parse(tag.substring(1));
          flush();
        } else {
          flush();
        }
      case 'p':
        if (isClosing) {
          pendingKind = RulesBlockKind.paragraph;
          flush();
        } else {
          flush();
        }
      case 'li':
        if (isClosing) {
          // Nested lists are flattened; each entry reads as its own bullet.
          pendingKind = RulesBlockKind.listItem;
          flush();
        } else {
          flush();
        }

      // A list, or any other wrapper such as <body>, <div> or <span>, holds no
      // text of its own: its entries are flushed by the tags inside it, and its
      // text is already being collected.
      default:
        break;
    }
  }

  // Whatever is left over belongs to a block that was never closed.
  emit(html.substring(index));
  flush();

  return blocks;
}

/// Normalises the whitespace in a block's spans and drops the empty ones.
///
/// Words are put back together with exactly one space between them wherever
/// the markup had whitespace, so that a word split across two tags, as in
/// `you <b>must</b> move`, reads correctly, while `super<b>man</b>` stays one
/// word.
List<RulesSpan> _tidy(List<RulesSpan> spans) {
  final cleaned = <RulesSpan>[];

  /// Whether whitespace was seen and a single space is owed before the next
  /// word. This is deliberately separate from having just emitted a word: two
  /// words inside one run are separated by whitespace just as two runs are.
  var owed = false;

  void add(String word, RulesSpan source) {
    if (owed && cleaned.isNotEmpty) {
      cleaned[cleaned.length - 1] = cleaned.last.withText(
        '${cleaned.last.text} ',
      );
    }
    cleaned.add(RulesSpan(word, bold: source.bold, italic: source.italic));
    owed = false;
  }

  final startsWithSpace = RegExp(r'^\s');
  final endsWithSpace = RegExp(r'\s$');

  for (final span in spans) {
    if (startsWithSpace.hasMatch(span.text)) {
      owed = true;
    }

    final trimmed = span.text.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final words = trimmed.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length; i++) {
      // Any word after the first is preceded by whitespace in the source.
      if (i > 0) {
        owed = true;
      }
      add(words[i], span);
    }

    if (endsWithSpace.hasMatch(span.text)) {
      owed = true;
    }
  }

  return cleaned;
}
