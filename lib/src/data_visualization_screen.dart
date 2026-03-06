import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Formata data/hora para exibição (dd/MM/yyyy HH:mm).
String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final d = DateTime.parse(iso);
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year;
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$min';
  } catch (_) {
    return iso;
  }
}

String formatDateOnly(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final d = DateTime.parse(iso);
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year;
    return '$day/$month/$year';
  } catch (_) {
    return iso;
  }
}

const _cyan = Color(0xFF00d4ff);
const _bgDark = Color(0xFF0a0e17);

/// Tela que lista eventos, notas de reunião e itens de ação criados pela voz (com data/hora).
class DataVisualizationScreen extends StatefulWidget {
  const DataVisualizationScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<DataVisualizationScreen> createState() => _DataVisualizationScreenState();
}

class _DataVisualizationScreenState extends State<DataVisualizationScreen> {
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _actionItems = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final events = await client
          .from('events')
          .select('id, title, description, location, start_time, end_time, all_day, status, created_at')
          .order('start_time', ascending: false);
      final notes = await client
          .from('meeting_notes')
          .select('id, title, content, created_at')
          .order('created_at', ascending: false);
      final items = await client
          .from('action_items')
          .select('id, description, due_date, status, created_at')
          .order('due_date', ascending: true);
      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(events as List);
          _notes = List<Map<String, dynamic>>.from(notes as List);
          _actionItems = List<Map<String, dynamic>>.from(items as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgDark, Color(0xFF0d1321), _bgDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _cyan),
                  ),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Tentar de novo'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    color: _cyan,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _sectionTitle('Eventos e reuniões'),
                        if (_events.isEmpty)
                          _emptyCard('Nenhum evento ou reunião criado ainda.')
                        else
                          ..._events.map(_eventCard),
                        const SizedBox(height: 24),
                        _sectionTitle('Notas de reunião'),
                        if (_notes.isEmpty)
                          _emptyCard('Nenhuma nota de reunião.')
                        else
                          ..._notes.map(_noteCard),
                        const SizedBox(height: 24),
                        _sectionTitle('Itens de ação'),
                        if (_actionItems.isEmpty)
                          _emptyCard('Nenhum item de ação.')
                        else
                          ..._actionItems.map(_actionItemCard),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, color: _cyan),
            tooltip: 'Voltar',
          ),
          const SizedBox(width: 8),
          Text(
            'Meus dados',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, color: _cyan),
            tooltip: 'Atualizar',
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withValues(alpha: 0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: _cyan,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _eventCard(Map<String, dynamic> e) {
    final start = e['start_time'] as String?;
    final end = e['end_time'] as String?;
    final allDay = e['all_day'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e['title'] as String? ?? '—',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (e['description'] != null && (e['description'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                e['description'] as String,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: _cyan.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(
                allDay
                    ? '${formatDateOnly(start)} (dia inteiro)'
                    : '${formatDateTime(start)} → ${formatDateTime(end)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
              ),
            ],
          ),
          if (e['location'] != null && (e['location'] as String).isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  e['location'] as String,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _noteCard(Map<String, dynamic> n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n['title'] as String? ?? 'Nota',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: _cyan.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(
                formatDateTime(n['created_at'] as String?),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
              ),
            ],
          ),
          if (n['content'] != null && (n['content'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              n['content'] as String,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionItemCard(Map<String, dynamic> a) {
    final status = a['status'] as String? ?? 'open';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a['description'] as String? ?? '—',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event, size: 14, color: _cyan.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(
                'Entrega: ${formatDateOnly(a['due_date'] as String?)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: status == 'open' ? _cyan.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status == 'open' ? 'Aberto' : status,
                  style: TextStyle(color: _cyan, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
