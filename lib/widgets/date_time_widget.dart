/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'animated_character.dart';

class DateTimeWidget extends StatefulWidget {
  final Duration? updateInterval;
  final String _dateTimeFormatString;
  final TextStyle? textStyle;
  final bool animate;

  const DateTimeWidget(String dateTimeFormatString, {
    super.key,
    this.updateInterval,
    this.textStyle,
    this.animate = true,
  }) :
      _dateTimeFormatString = dateTimeFormatString;

  @override
  State<DateTimeWidget> createState() => _DateTimeWidgetState();
}

class _DateTimeWidgetState extends State<DateTimeWidget> with WidgetsBindingObserver {
  /// Every second, so the time is right as soon as the minute rolls over or NTP sync completes.
  static const Duration _defaultInterval = Duration(seconds: 1);

  late DateFormat _dateFormat;
  String _formattedText = '';
  Timer? _timer;

  /// Hearth's language (its own App language setting, else the TV's), for day and month names.
  String? _locale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.maybeLocaleOf(context)?.toString() ?? Platform.localeName;
    if (locale != _locale) {
      _locale = locale;
      _initDateFormatAndRefresh();
    }
  }

  void _initDateFormatAndRefresh() {
    try {
      _dateFormat = DateFormat(widget._dateTimeFormatString, _locale ?? Platform.localeName);
    } catch (_) {
      try {
        _dateFormat = DateFormat(widget._dateTimeFormatString);
      } catch (_) {
        _dateFormat = DateFormat("EEE, MMM d", "en_US");
      }
    }
    _formattedText = _format(DateTime.now(), fallback: '');
  }

  String _format(DateTime time, {required String fallback}) {
    try {
      return _dateFormat.format(time);
    } catch (_) {
      return fallback;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.updateInterval ?? _defaultInterval, (_) => _refreshTime());
  }

  @override
  void didUpdateWidget(DateTimeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._dateTimeFormatString != widget._dateTimeFormatString ||
        oldWidget.updateInterval != widget.updateInterval) {
      _initDateFormatAndRefresh();
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTime();
      _startTimer();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Animated one character at a time only left to right: in a right-to-left language the characters would be
    // laid out back to front, and Arabic letters must join
    if (widget.animate && Directionality.of(context) == TextDirection.ltr) {
      return AnimatedTimeDisplay(
        displayText: _formattedText,
        textStyle: widget.textStyle,
      );
    }
    return Text(_formattedText, style: widget.textStyle);
  }

  void _refreshTime() {
    if (!mounted) return;
    final newFormattedText = _format(DateTime.now(), fallback: _formattedText);
    if (newFormattedText != _formattedText) {
      setState(() => _formattedText = newFormattedText);
    }
  }
}
