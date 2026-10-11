/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/widgets/ha_panel/ha_icons.dart';
import 'package:flutter/material.dart';

/// A block of a markdown card's text.
sealed class HaMdBlock {
  const HaMdBlock();
}

/// "# Heading" (level 1 to 6).
class HaMdHeading extends HaMdBlock {
  final int level;
  final String text;

  const HaMdHeading(this.level, this.text);
}

/// "- item" or "* item".
class HaMdBullet extends HaMdBlock {
  final String text;

  const HaMdBullet(this.text);
}

/// Lines of plain text (a paragraph's lines stay lines, as Home Assistant's cards show them).
class HaMdParagraph extends HaMdBlock {
  final String text;

  const HaMdParagraph(this.text);
}

/// A gap between paragraphs.
class HaMdGap extends HaMdBlock {
  const HaMdGap();
}

/// A table: a header row, the alignment row ("|:---|:---:|---:|"), then its rows.
class HaMdTable extends HaMdBlock {
  final List<String> header;
  final List<TextAlign> align;
  final List<List<String>> rows;

  const HaMdTable(this.header, this.align, this.rows);
}

/// A piece of a line: its text, bold or italic; or an icon (`<ha-icon icon="mdi:youtube">`), with [icon] its name
/// and no text. (An image would be one more kind of piece.)
class HaMdSpan {
  final String text;
  final bool bold;
  final bool italic;
  final String? icon;

  const HaMdSpan(this.text, {this.bold = false, this.italic = false}) : icon = null;

  const HaMdSpan.icon(String this.icon)
      : text = "",
        bold = false,
        italic = false;

  @override
  bool operator ==(Object other) =>
      other is HaMdSpan && other.text == text && other.bold == bold && other.italic == italic && other.icon == icon;

  @override
  int get hashCode => Object.hash(text, bold, italic, icon);

  @override
  String toString() => icon != null ? "[$icon]" : "${bold ? "**" : ""}${italic ? "_" : ""}$text";
}

/// The markdown Home Assistant's cards use most, read simply: headings, bullets, tables, **bold** and *italic*.
/// HTML tags are left out; anything else shows as written.
class HaMarkdown {
  static final RegExp _alignCell = RegExp(r"^:?-{1,}:?$");

  static List<HaMdBlock> parse(String text) {
    final lines = text.replaceAll("\r\n", "\n").split("\n");
    final out = <HaMdBlock>[];
    final paragraph = <String>[];
    void endParagraph() {
      if (paragraph.isNotEmpty) out.add(HaMdParagraph(paragraph.join("\n")));
      paragraph.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = _stripHtml(lines[i]).trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        endParagraph();
        if (out.isNotEmpty && out.last is! HaMdGap) out.add(const HaMdGap());
        i++;
        continue;
      }
      // A table: a row of cells, then the alignment row
      if (trimmed.startsWith("|") && i + 1 < lines.length && _isAlignRow(lines[i + 1])) {
        endParagraph();
        final header = _cells(trimmed);
        final align = [for (final c in _cells(lines[i + 1].trim())) _align(c)];
        final rows = <List<String>>[];
        i += 2;
        while (i < lines.length && lines[i].trim().startsWith("|")) {
          rows.add(_cells(_stripHtml(lines[i]).trim()));
          i++;
        }
        final columns = header.length;
        out.add(HaMdTable(
          header,
          [for (var c = 0; c < columns; c++) c < align.length ? align[c] : TextAlign.left],
          [
            for (final r in rows) [for (var c = 0; c < columns; c++) c < r.length ? r[c] : ""]
          ],
        ));
        continue;
      }
      final heading = RegExp(r"^(#{1,6})\s+(.*)$").firstMatch(trimmed);
      if (heading != null) {
        endParagraph();
        out.add(HaMdHeading(heading.group(1)!.length, heading.group(2)!.trim()));
      } else if (RegExp(r"^[-*+]\s+").hasMatch(trimmed)) {
        endParagraph();
        out.add(HaMdBullet(trimmed.replaceFirst(RegExp(r"^[-*+]\s+"), "")));
      } else {
        paragraph.add(trimmed);
      }
      i++;
    }
    endParagraph();
    while (out.isNotEmpty && out.last is HaMdGap) {
      out.removeLast();
    }
    return out;
  }

  static bool _isAlignRow(String line) {
    final cells = _cells(line.trim());
    return cells.isNotEmpty && cells.every((c) => _alignCell.hasMatch(c.replaceAll(" ", "")));
  }

  static TextAlign _align(String cell) {
    final c = cell.replaceAll(" ", "");
    final left = c.startsWith(":"), right = c.endsWith(":");
    if (left && right) return TextAlign.center;
    if (right) return TextAlign.right;
    return TextAlign.left;
  }

  /// "| a | b |" → ["a", "b"].
  static List<String> _cells(String row) {
    var r = row;
    if (r.startsWith("|")) r = r.substring(1);
    if (r.endsWith("|")) r = r.substring(0, r.length - 1);
    return [for (final c in r.split("|")) c.trim()];
  }

  /// Marks an icon in a line between parsing and drawing: [_iconStart] name [_iconEnd].
  static const String _iconStart = "", _iconEnd = "";

  /// HTML tags go, their text stays; `<ha-icon icon="...">` becomes an icon mark.
  static String _stripHtml(String line) => line
      .replaceAllMapped(
          RegExp(r"""<ha-icon\b[^>]*\bicon\s*=\s*["']([^"']+)["'][^>]*>(\s*</ha-icon>)?""", caseSensitive: false),
          (m) => "$_iconStart${m.group(1)}$_iconEnd")
      .replaceAll(RegExp(r"<br\s*/?>", caseSensitive: false), " ")
      .replaceAll(RegExp(r"</?[a-zA-Z][^>]*>"), "");

  /// A line's pieces: icons, **bold** and *italic* (or _italic_) text.
  static List<HaMdSpan> inline(String text) {
    final out = <HaMdSpan>[];
    final icons = RegExp("$_iconStart([^$_iconEnd]*)$_iconEnd");
    var from = 0;
    for (final m in icons.allMatches(text)) {
      if (m.start > from) out.addAll(_styled(text.substring(from, m.start)));
      out.add(HaMdSpan.icon(m.group(1)!));
      from = m.end;
    }
    if (from < text.length) out.addAll(_styled(text.substring(from)));
    return out;
  }

  static List<HaMdSpan> _styled(String text) {
    final out = <HaMdSpan>[];
    final pattern = RegExp(r"\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|(?<![A-Za-z0-9])_(.+?)_(?![A-Za-z0-9])");
    var at = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > at) out.add(HaMdSpan(text.substring(at, m.start)));
      final bold = m.group(1) ?? m.group(2);
      if (bold != null) {
        out.add(HaMdSpan(bold, bold: true));
      } else {
        out.add(HaMdSpan(m.group(3) ?? m.group(4)!, italic: true));
      }
      at = m.end;
    }
    if (at < text.length) out.add(HaMdSpan(text.substring(at)));
    return out;
  }
}

/// A markdown card's text drawn for the panel.
class HaMarkdownView extends StatelessWidget {
  final String text;

  const HaMarkdownView(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = theme.bodyMedium!.copyWith(color: Colors.white.withOpacity(0.85));
    final children = <Widget>[];
    for (final block in HaMarkdown.parse(text)) {
      switch (block) {
        case HaMdHeading(:final level, :final text):
          final style = (level <= 1 ? theme.titleMedium! : theme.titleSmall!)
              .copyWith(color: Colors.white, fontWeight: FontWeight.w700);
          children.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: _rich(text, style)));
        case HaMdBullet(:final text):
          children.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("•  ", style: body),
              Expanded(child: _rich(text, body)),
            ],
          ));
        case HaMdParagraph(:final text):
          children.add(_rich(text, body));
        case HaMdGap():
          children.add(const SizedBox(height: 8));
        case HaMdTable():
          children.add(_table(block, body));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  static Widget _rich(String text, TextStyle style) => Text.rich(TextSpan(children: spans(text, style)));

  /// [text]'s pieces drawn: styled text, and icons the size of the text.
  static List<InlineSpan> spans(String text, TextStyle style) => [
        for (final s in HaMarkdown.inline(text))
          if (s.icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child:
                    Icon(HaIcons.named(s.icon!) ?? Icons.apps, size: (style.fontSize ?? 14) * 1.2, color: style.color),
              ),
            )
          else
            TextSpan(
              text: s.text,
              style: style.copyWith(
                fontWeight: s.bold ? FontWeight.w700 : null,
                fontStyle: s.italic ? FontStyle.italic : null,
              ),
            )
      ];

  static Widget _table(HaMdTable table, TextStyle body) {
    final header = body.copyWith(color: Colors.white60, fontWeight: FontWeight.w700);
    Widget cell(String text, TextStyle style, TextAlign align) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: _cellText(text, style, align),
        );
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.15)))),
          children: [for (var c = 0; c < table.header.length; c++) cell(table.header[c], header, table.align[c])],
        ),
        for (final row in table.rows)
          TableRow(children: [for (var c = 0; c < row.length; c++) cell(row[c], body, table.align[c])]),
      ],
    );
  }

  static Widget _cellText(String text, TextStyle style, TextAlign align) =>
      Text.rich(TextSpan(children: spans(text, style)), textAlign: align);
}
