import 'package:flutter/material.dart';

import '../../api/errors.dart';
import '../../reminders/reminders.dart';
import '../../reminders/schedule.dart';
import '../../theme.dart';
import '../../widgets/states.dart';

/// The Reminders part of Settings: on or off, and up to [maxReminderTimes] times a day.
class ReminderSettings extends StatefulWidget {
  const ReminderSettings({super.key, required this.reminders});

  final Reminders reminders;

  @override
  State<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<ReminderSettings> {
  Object? _error;

  Reminders get reminders => widget.reminders;

  Future<void> _toggle(bool on) async {
    setState(() => _error = null);
    final applied = await reminders.setEnabled(on);
    if (!applied && mounted) {
      setState(
        () => _error = const UserFacingError(
          "Notifications are off for Engram. Turn them on in your phone's settings, then try "
          'again.',
        ),
      );
    }
  }

  Future<void> _add() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: defaultReminderTime,
      helpText: 'Remind me at',
    );
    if (picked != null) await reminders.addTime(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: reminders,
      builder: (context, _) {
        final localizations = MaterialLocalizations.of(context);
        final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
        String format(TimeOfDay time) =>
            localizations.formatTimeOfDay(time, alwaysUse24HourFormat: use24);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me to study'),
              value: reminders.enabled,
              onChanged: _toggle,
            ),
            FormError(_error),
            if (reminders.enabled) ...[
              for (final time in reminders.times)
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_none, size: 18, color: c.inkMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          format(time),
                          style: const TextStyle(
                            fontSize: 16,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${format(time)}',
                        onPressed: () => reminders.removeTime(time),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (reminders.canAddTime)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a time'),
                  ),
                )
              else
                Text(
                  'Up to $maxReminderTimes reminders a day.',
                  style: TextStyle(fontSize: 14, color: c.inkMuted),
                ),
            ],
          ],
        );
      },
    );
  }
}
