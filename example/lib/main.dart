import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speak/speak.dart';

void main() => runApp(const SpeakDemoApp());

/// The `speak` demo: voices, availability, speak/stop/pause, word progress
/// and the audio modes.
class SpeakDemoApp extends StatelessWidget {
  /// Creates the app.
  const SpeakDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'speak',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const DemoPage(),
  );
}

/// The one page of the demo.
class DemoPage extends StatefulWidget {
  /// Creates the page.
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const _audioModes = {
    'Prompt (duck)': SpeakAudio.prompt,
    'Navigation (duck)': SpeakAudio.navigation,
    'Navigation (pause podcasts)': SpeakAudio(
      otherAudio: OtherAudio.pauseSpoken,
      usage: AudioUsage.navigation,
    ),
    'Plain (mix)': SpeakAudio.plain,
    'Exclusive (pause)': SpeakAudio.exclusive,
  };

  final _text = TextEditingController(
    text: 'In two hundred metres, turn left onto the river path.',
  );
  final _language = TextEditingController(text: 'en-US');

  Speak _speak = Speak();
  String _audioMode = 'Prompt (duck)';
  List<AndroidEngine> _engines = const [];
  String? _engine;
  List<Voice> _voices = const [];
  Voice? _voice;
  double _rate = 1;
  double _pitch = 1;
  SpeechProgress? _progress;
  String? _availability;
  final _log = <String>[];

  @override
  void initState() {
    super.initState();
    if (Speak.isSupported) unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_speak.dispose());
    _text.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final engines = await Speak.androidEngines();
    final voices = await _speak.voices();
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _voices = voices;
      if (_voice != null && !voices.contains(_voice)) _voice = null;
    });
  }

  /// A new speaker for a new audio mode or engine: both are fixed for the
  /// life of a `Speak`.
  Future<void> _recreate() async {
    final old = _speak;
    _speak = Speak(
      audio: _audioModes[_audioMode]!,
      android: AndroidSpeakOptions(engine: _engine),
    );
    await old.dispose();
    _voice = null;
    await _load();
  }

  void _note(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  Future<void> _say(SpeakQueue queue) async {
    final text = _text.text;
    final language = _language.text.trim();
    try {
      final outcome = await _speak(
        text,
        voice: _voice,
        language: _voice == null && language.isNotEmpty ? language : null,
        rate: _rate,
        pitch: _pitch,
        queue: queue,
        onProgress: (progress) => setState(() => _progress = progress),
      );
      _note('${outcome.name}: ${_short(text)}');
    } on SpeakException catch (error) {
      _note('failed (${error.error.name}): ${error.message ?? ''}');
    }
    if (mounted) setState(() => _progress = null);
  }

  Future<void> _checkAvailability() async {
    final language = _language.text.trim();
    if (language.isEmpty) return;
    final availability = await _speak.availability(language);
    setState(() => _availability = '$language: ${availability.name}');
  }

  static String _short(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}...' : text;

  @override
  Widget build(BuildContext context) {
    if (!Speak.isSupported) {
      return const Scaffold(
        body: Center(child: Text('Text-to-speech is not supported here.')),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('speak')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _spokenText(theme),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _say(SpeakQueue.append),
                child: const Text('Speak'),
              ),
              FilledButton.tonal(
                onPressed: () => _say(SpeakQueue.interrupt),
                child: const Text('Speak now'),
              ),
              OutlinedButton(
                onPressed: () => _speak.stop(),
                child: const Text('Stop'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await (_speak.isPaused ? _speak.resume() : _speak.pause());
                  setState(() {});
                },
                child: Text(_speak.isPaused ? 'Resume' : 'Pause'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _language,
                  decoration: const InputDecoration(
                    labelText: 'Language (BCP-47), used without a voice',
                  ),
                ),
              ),
              TextButton(
                onPressed: _checkAvailability,
                child: const Text('Available?'),
              ),
            ],
          ),
          if (_availability case final availability?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(availability),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Voice?>(
            initialValue: _voice,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Voice (${_voices.length} installed)',
            ),
            items: [
              const DropdownMenuItem(child: Text('Best for the language')),
              for (final voice in _voices)
                DropdownMenuItem(
                  value: voice,
                  child: Text(
                    '${voice.name} · ${voice.language} · ${voice.quality.name}'
                    '${voice.requiresNetwork ? ' · online' : ''}'
                    '${voice.isInstalled ? '' : ' · not installed'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (voice) => setState(() => _voice = voice),
          ),
          _slider('Rate', _rate, 0.25, 2, (v) => _rate = v),
          _slider('Pitch', _pitch, 0.5, 2, (v) => _pitch = v),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _audioMode,
            decoration: const InputDecoration(labelText: 'Other audio'),
            items: [
              for (final mode in _audioModes.keys)
                DropdownMenuItem(value: mode, child: Text(mode)),
            ],
            onChanged: (mode) {
              _audioMode = mode!;
              unawaited(_recreate());
            },
          ),
          if (_engines.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: _engine,
              decoration: const InputDecoration(labelText: 'Android engine'),
              items: [
                for (final engine in _engines)
                  DropdownMenuItem(
                    value: engine.isDefault ? null : engine.name,
                    child: Text(
                      '${engine.label}${engine.isDefault ? ' (default)' : ''}',
                    ),
                  ),
              ],
              onChanged: (engine) {
                _engine = engine;
                unawaited(_recreate());
              },
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                kIsWeb
                    ? 'A web page cannot lower other audio: the audio mode '
                          'does nothing in the browser.'
                    : 'Try ducking: play music in another app, choose '
                          '"Prompt (duck)" and tap Speak. The music dips '
                          'while the text is spoken and comes back after. '
                          '"Navigation (pause podcasts)" leaves music alone '
                          'but pauses a podcast.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final line in _log) Text(line, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// The text with the word being spoken highlighted.
  Widget _spokenText(ThemeData theme) {
    final progress = _progress;
    final style = theme.textTheme.titleMedium!;
    if (progress == null) return Text(_text.text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: progress.text.substring(0, progress.start)),
          TextSpan(
            text: progress.word,
            style: TextStyle(
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          ),
          TextSpan(text: progress.text.substring(progress.end)),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) set,
  ) => Row(
    children: [
      SizedBox(width: 48, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / 0.05).round(),
          label: value.toStringAsFixed(2),
          onChanged: (v) => setState(() => set(v)),
        ),
      ),
    ],
  );
}
