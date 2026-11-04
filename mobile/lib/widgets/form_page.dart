import 'package:flutter/material.dart';

import '../theme.dart';
import 'engram_mark.dart';
import 'glass.dart';

/// A centered page with the Engram mark, a heading and a form: server, sign-in and sign-up.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.children,
    this.intro,
    this.footer,
    this.showBack = false,
  });

  final String title;
  final String? intro;
  final List<Widget> children;
  final Widget? footer;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Backdrop(
      child: Scaffold(
        appBar: showBack ? AppBar(shape: const Border()) : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: EngramMark(size: 40)),
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (intro != null) ...[
                        const SizedBox(height: 8),
                        Text(intro!, style: text.bodyLarge?.copyWith(color: c.inkMuted)),
                      ],
                      const SizedBox(height: 24),
                      for (final (index, child) in children.indexed) ...[
                        if (index > 0) const SizedBox(height: 16),
                        child,
                      ],
                      if (footer != null) ...[const SizedBox(height: 24), footer!],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
