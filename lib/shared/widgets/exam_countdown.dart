import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class ExamCountdown extends StatefulWidget {
  final Duration remaining;
  final VoidCallback? onExpired;
  final bool large;

  const ExamCountdown({
    super.key,
    required this.remaining,
    this.onExpired,
    this.large = false,
  });

  @override
  State<ExamCountdown> createState() => _ExamCountdownState();
}

class _ExamCountdownState extends State<ExamCountdown> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.remaining;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 0) {
        _timer?.cancel();
        widget.onExpired?.call();
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color get _color {
    if (_remaining.inMinutes <= 5) return AppColors.error;
    if (_remaining.inMinutes <= 15) return AppColors.warning;
    if (_remaining.inMinutes <= 30) return AppColors.accent;
    return AppColors.success;
  }

  String get _formatted {
    final h = _remaining.inHours;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.large) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: _color.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _color, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, color: _color, size: 24),
            const SizedBox(width: 10),
            Text(
              _formatted,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _color,
                letterSpacing: 2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            _formatted,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
