import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

// The one renderer for card text, with the same rules as the web app's <Markdown>
// (frontend/src/components/markdown/Markdown.tsx, docs/security.md):
//
// 1. Raw HTML is dropped, never shown or interpreted.
// 2. Links open only for http, https and mailto, in the browser outside the app.
// 3. Images load only from https addresses; anything else shows its alt text.
// 4. Math ($…$ and $$…$$) is typeset; code blocks are highlighted.

const _safeLinkSchemes = {'http', 'https', 'mailto'};

/// Whether a link in a card may be opened.
bool isSafeLink(String? href) {
  if (href == null) return false;
  final uri = Uri.tryParse(href.trim());
  return uri != null && _safeLinkSchemes.contains(uri.scheme.toLowerCase());
}

/// Whether an image in a card may be loaded.
bool isSafeImage(Uri uri) => uri.isScheme('https') && uri.host.isNotEmpty;

/// Drops inline HTML (tags, comments, declarations) instead of showing it as text.
class _DropInlineHtml extends md.InlineHtmlSyntax {
  @override
  bool onMatch(md.InlineParser parser, Match match) => true;
}

/// Drops HTML blocks.
class _DropHtmlBlock extends md.BlockSyntax {
  const _DropHtmlBlock();

  static const _html = md.HtmlBlockSyntax();

  @override
  RegExp get pattern => _html.pattern;

  @override
  bool canEndBlock(md.BlockParser parser) => _html.canEndBlock(parser);

  @override
  md.Node? parse(md.BlockParser parser) {
    _html.parseChildLines(parser);
    return null;
  }
}

/// `$$` on a line of its own opens a display-math block that the next `$$` line closes.
class _MathBlockSyntax extends md.BlockSyntax {
  const _MathBlockSyntax();

  static final _fence = RegExp(r'^ {0,3}\$\$\s*$');
  static final _oneLine = RegExp(r'^ {0,3}\$\$(.+)\$\$\s*$');

  @override
  RegExp get pattern => RegExp(r'^ {0,3}\$\$');

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content;
    return _fence.hasMatch(line) || _oneLine.hasMatch(line);
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final first = parser.current.content;
    final single = _oneLine.firstMatch(first);
    parser.advance();
    if (single != null) return _math(single.group(1)!, display: true);
    final lines = <String>[];
    while (!parser.isDone && !_fence.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return _math(lines.join('\n'), display: true);
  }
}

/// Inline math: `$$…$$` (display) or `$…$`, as remark-math reads it.
class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax()
    : super(r'\$\$([^$]+?)\$\$|\$(?![\s$])((?:\\\$|[^$\n])+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match.group(1);
    parser.addNode(_math(display ?? match.group(2)!, display: display != null, inline: true));
    return true;
  }
}

md.Element _math(String tex, {required bool display, bool inline = false}) =>
    md.Element.empty(inline ? 'math' : 'math-block')
      ..attributes['tex'] = tex.trim()
      ..attributes['display'] = display.toString();

class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({required this.block});

  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.attributes['tex'] ?? '';
    final display = element.attributes['display'] == 'true';
    final style = parentStyle ?? DefaultTextStyle.of(context).style;
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style,
      // A typo in a formula shows the source, the way KaTeX does with strict off.
      onErrorFallback: (error) => Text(tex, style: style.copyWith(fontFamily: monoFamily)),
    );
    if (!block) return math;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: math),
    );
  }
}

/// Fenced and indented code, highlighted with token colors that alias the text colors, as the
/// web app's --code-token-* do.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final source = (code ?? element).textContent.replaceFirst(RegExp(r'\n$'), '');
    final language = code?.attributes['class']?.replaceFirst('language-', '');
    final c = context.colors;
    final token = <String, TextStyle>{
      'root': TextStyle(color: c.ink, backgroundColor: c.surfaceSunken),
      'comment': TextStyle(color: c.inkMuted, fontStyle: FontStyle.italic),
      'punctuation': TextStyle(color: c.inkMuted),
      'keyword': TextStyle(color: c.ratingAgain),
      'built_in': TextStyle(color: c.ratingHard),
      'title': TextStyle(color: c.ratingHard),
      'function': TextStyle(color: c.ratingHard),
      'string': TextStyle(color: c.ratingGood),
      'link': TextStyle(color: c.ratingGood),
      'number': TextStyle(color: c.ratingEasy),
      'literal': TextStyle(color: c.ratingEasy),
      'type': TextStyle(color: c.ratingEasy),
      'params': TextStyle(color: c.ink),
      'addition': TextStyle(color: c.ratingGood),
      'deletion': TextStyle(color: c.danger),
    };
    return Semantics(
      label: language == null ? 'Code' : 'Code, $language',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: HighlightView(
          source,
          language: language ?? 'plaintext',
          theme: token,
          padding: const EdgeInsets.all(12),
          textStyle: const TextStyle(fontFamily: monoFamily, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }
}

final _extensionSet = md.ExtensionSet(md.ExtensionSet.gitHubFlavored.blockSyntaxes, [
  for (final syntax in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
    if (syntax is! md.InlineHtmlSyntax) syntax,
]);

/// Renders a card's Markdown. [large] is the study size, for the card's front and back.
class CardMarkdown extends StatelessWidget {
  const CardMarkdown(this.data, {super.key, this.large = false});

  final String data;
  final bool large;

  Future<void> _openLink(BuildContext context, String? href) async {
    if (!isSafeLink(href)) return;
    final opened = await launchUrl(Uri.parse(href!.trim()), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This link couldn't be opened. No app on this device handles it."),
        ),
      );
    }
  }

  Widget _image(BuildContext context, Uri uri, String? alt) {
    final altText = Text(
      alt?.isNotEmpty == true ? '[$alt]' : '[image]',
      style: TextStyle(color: context.colors.inkMuted),
    );
    if (!isSafeImage(uri)) return altText;
    return Semantics(
      label: alt,
      image: true,
      child: Image.network(
        uri.toString(),
        errorBuilder: (context, error, stack) => altText,
        semanticLabel: alt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final body = (large ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)!.copyWith(
      color: c.ink,
      height: 1.5,
      fontWeight: FontWeight.w400,
    );
    final codeStyle = TextStyle(
      fontFamily: monoFamily,
      fontSize: (body.fontSize ?? 16) * 0.875,
      color: c.ink,
      backgroundColor: c.surfaceSunken,
    );
    return MarkdownBody(
      data: data,
      selectable: false,
      extensionSet: _extensionSet,
      blockSyntaxes: const [_DropHtmlBlock(), _MathBlockSyntax()],
      inlineSyntaxes: [_DropInlineHtml(), _InlineMathSyntax()],
      builders: {
        'math': _MathBuilder(block: false),
        'math-block': _MathBuilder(block: true),
        'pre': _CodeBlockBuilder(),
      },
      onTapLink: (text, href, title) => _openLink(context, href),
      imageBuilder: (uri, title, alt) => _image(context, uri, alt),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body,
        a: body.copyWith(
          color: c.pine,
          decoration: TextDecoration.underline,
          decorationColor: c.pine,
        ),
        code: codeStyle,
        h1: body.copyWith(fontSize: (body.fontSize ?? 16) * 1.25, fontWeight: FontWeight.w600),
        h2: body.copyWith(fontSize: (body.fontSize ?? 16) * 1.15, fontWeight: FontWeight.w600),
        h3: body.copyWith(fontSize: (body.fontSize ?? 16) * 1.05, fontWeight: FontWeight.w600),
        h4: body.copyWith(fontWeight: FontWeight.w600),
        h5: body.copyWith(fontWeight: FontWeight.w600),
        h6: body.copyWith(fontWeight: FontWeight.w600),
        listBullet: body,
        tableBody: body,
        tableHead: body.copyWith(fontWeight: FontWeight.w600),
        tableBorder: TableBorder.all(color: c.line),
        blockquote: body.copyWith(color: c.inkMuted),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.lineStrong, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        codeblockDecoration: BoxDecoration(
          color: c.surfaceSunken,
          borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
          border: Border.all(color: c.line),
        ),
        codeblockPadding: EdgeInsets.zero,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
      ),
    );
  }
}
