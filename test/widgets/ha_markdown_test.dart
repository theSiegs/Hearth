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

import 'package:flauncher/widgets/ha_panel/ha_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("A table: header, alignments (left, center, right), rows", () {
    final blocks = HaMarkdown.parse('''
| Kid | Today | YouTube left |
|:---|:---:|---:|
| Alex | 1 h 35 min | 25 min |
| Sam | **40 min** | 50 min |
''');
    final table = blocks.single as HaMdTable;
    expect(table.header, ["Kid", "Today", "YouTube left"]);
    expect(table.align, [TextAlign.left, TextAlign.center, TextAlign.right]);
    expect(table.rows, [
      ["Alex", "1 h 35 min", "25 min"],
      ["Sam", "**40 min**", "50 min"],
    ]);
  });

  test("A table's plain alignment row, and rows short of cells", () {
    final table = HaMarkdown.parse("|a|b|\n|---|---|\n|1|\n").single as HaMdTable;
    expect(table.align, [TextAlign.left, TextAlign.left]);
    expect(table.rows, [
      ["1", ""]
    ]);
  });

  test("Lines, headings, bullets, gaps; HTML tags left out", () {
    final blocks = HaMarkdown.parse('''
## Tonight
Nothing is playing.
Second line<br>

- one
* two

<ha-icon icon="mdi:home"></ha-icon>Done''');
    expect((blocks[0] as HaMdHeading).level, 2);
    expect((blocks[0] as HaMdHeading).text, "Tonight");
    expect((blocks[1] as HaMdParagraph).text, "Nothing is playing.\nSecond line");
    expect(blocks[2], isA<HaMdGap>());
    expect((blocks[3] as HaMdBullet).text, "one");
    expect((blocks[4] as HaMdBullet).text, "two");
    expect(blocks[5], isA<HaMdGap>());
    expect(HaMarkdown.inline((blocks[6] as HaMdParagraph).text), const [HaMdSpan.icon("mdi:home"), HaMdSpan("Done")]);
    expect(blocks, hasLength(7));
  });

  test("A kid's card: a heading, then lines that end in two spaces, each with an icon", () {
    const card = "## Alex · 3 h 16 min\n"
        "<ha-icon icon=\"mdi:youtube\"></ha-icon> YouTube — 1 h 11 min  \n"
        "<ha-icon icon='mdi:minecraft'></ha-icon> **Minecraft** — 45 min  \n"
        "<ha-icon icon=\"mdi:something-new\"></ha-icon> <b>Other</b> — 5 min  ";
    final blocks = HaMarkdown.parse(card);
    expect(blocks, hasLength(2));
    expect((blocks[0] as HaMdHeading).level, 2);
    expect((blocks[0] as HaMdHeading).text, "Alex · 3 h 16 min");
    final lines = (blocks[1] as HaMdParagraph).text.split("\n");
    expect(lines, hasLength(3));
    expect(HaMarkdown.inline(lines[0]), const [HaMdSpan.icon("mdi:youtube"), HaMdSpan(" YouTube — 1 h 11 min")]);
    expect(HaMarkdown.inline(lines[1]), const [
      HaMdSpan.icon("mdi:minecraft"),
      HaMdSpan(" "),
      HaMdSpan("Minecraft", bold: true),
      HaMdSpan(" — 45 min")
    ]);
    // Other tags go and their text stays
    expect(HaMarkdown.inline(lines[2]), const [HaMdSpan.icon("mdi:something-new"), HaMdSpan(" Other — 5 min")]);
  });

  test("An empty day, and every heading level", () {
    final blocks = HaMarkdown.parse("# Sam · 0 min\n### Today\nNo app use yet today.");
    expect((blocks[0] as HaMdHeading).level, 1);
    expect((blocks[1] as HaMdHeading).level, 3);
    expect((blocks[2] as HaMdParagraph).text, "No app use yet today.");
  });

  testWidgets("Icons draw through the icon map, with an app icon for names it doesn't know", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: HaMarkdownView("## Alex · 1 h\n"
              "<ha-icon icon=\"mdi:youtube\"></ha-icon> YouTube — 1 h  \n"
              "<ha-icon icon=\"mdi:not-a-real-icon\"></ha-icon> Other — 5 min  "),
        ),
      ),
    ));
    expect(find.byIcon(Icons.smart_display), findsOneWidget);
    expect(find.byIcon(Icons.apps), findsOneWidget);
    expect(find.text("Alex · 1 h", findRichText: true), findsOneWidget);
  });

  test("A line that only starts with a bar isn't a table without its alignment row", () {
    expect(HaMarkdown.parse("| not a table").single, isA<HaMdParagraph>());
  });

  test("Bold and italic", () {
    expect(HaMarkdown.inline("**2** playing or _paused_ in *the* den"), const [
      HaMdSpan("2", bold: true),
      HaMdSpan(" playing or "),
      HaMdSpan("paused", italic: true),
      HaMdSpan(" in "),
      HaMdSpan("the", italic: true),
      HaMdSpan(" den"),
    ]);
    expect(HaMarkdown.inline("snake_case_name stays"), const [HaMdSpan("snake_case_name stays")]);
  });

  testWidgets("Draws a table's cells and bold text", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: HaMarkdownView("**Screen time**\n\n| Kid | Today |\n|---|---:|\n| Alex | 25 min |"),
        ),
      ),
    ));
    expect(find.byType(Table), findsOneWidget);
    expect(find.text("Alex", findRichText: true), findsOneWidget);
    expect(find.text("25 min", findRichText: true), findsOneWidget);
    final bold = tester.widget<RichText>(find.text("Screen time", findRichText: true));
    final spans = <TextSpan>[];
    bold.text.visitChildren((s) {
      if (s is TextSpan && s.text == "Screen time") spans.add(s);
      return true;
    });
    expect(spans.single.style!.fontWeight, FontWeight.w700);
  });
}
