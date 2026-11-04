import 'package:engram_mobile/theme.dart';
import 'package:engram_mobile/widgets/card_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _render(WidgetTester tester, String markdown) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: SingleChildScrollView(child: CardMarkdown(markdown))),
  ),
);

Finder _text(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('raw HTML is dropped, never shown or interpreted', (tester) async {
    await _render(
      tester,
      'Before\n\n<script>alert("x")</script>\n\n<div onclick="steal()">block</div>\n\n'
      'An <b>inline</b> tag and <img src=x onerror=alert(1)> image.',
    );
    expect(_text('Before'), findsOneWidget);
    expect(_text('<'), findsNothing);
    expect(_text('alert'), findsNothing);
    expect(_text('steal'), findsNothing);
    expect(_text('An inline tag and  image.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  test('only http, https and mailto links open', () {
    expect(isSafeLink('https://example.com'), isTrue);
    expect(isSafeLink('http://example.com'), isTrue);
    expect(isSafeLink('mailto:a@example.com'), isTrue);
    expect(isSafeLink('javascript:alert(1)'), isFalse);
    expect(isSafeLink(' JavaScript:alert(1)'), isFalse);
    expect(isSafeLink('data:text/html,<script>'), isFalse);
    expect(isSafeLink('intent://evil#Intent;end'), isFalse);
    expect(isSafeLink('/relative'), isFalse);
    expect(isSafeLink(null), isFalse);
  });

  testWidgets('a javascript: link renders as text and does nothing when tapped', (tester) async {
    await _render(tester, '[click me](javascript:alert(1))');
    expect(_text('click me'), findsOneWidget);
    await tester.tap(_text('click me'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('images load from https only; others show their alt text', (tester) async {
    await _render(
      tester,
      '![a diagram](http://example.com/a.png)\n\n![data](data:image/png;base64,AAAA)',
    );
    expect(find.byType(Image), findsNothing);
    expect(_text('[a diagram]'), findsOneWidget);
    expect(_text('[data]'), findsOneWidget);

    await _render(tester, '![a photo](https://example.com/a.png)');
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('math is typeset, inline and as a block', (tester) async {
    await _render(
      tester,
      r'Euler: $e^{i\pi} + 1 = 0$'
      '\n\n'
      r'$$'
      '\n'
      r'\int_0^1 x\,dx = \frac{1}{2}'
      '\n'
      r'$$',
    );
    expect(find.byType(Math), findsNWidgets(2));
    expect(_text(r'$'), findsNothing);
  });

  testWidgets('a formula that does not parse shows its source', (tester) async {
    await _render(tester, r'Broken: $\frac{1$');
    expect(_text(r'\frac{1'), findsOneWidget);
  });

  testWidgets('code blocks are highlighted and inline code is kept literal', (tester) async {
    await _render(tester, '```dart\nvoid main() => print(r"\$x\$");\n```\n\nUse `\$PATH` here.');
    expect(find.byType(HighlightView), findsOneWidget);
    expect(_text(r'$PATH'), findsOneWidget);
  });
}
