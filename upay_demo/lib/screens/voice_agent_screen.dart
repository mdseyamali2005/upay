import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/user_data.dart';
import '../services/agent_api.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_ai_mark.dart';

class VoiceAgentScreen extends StatefulWidget {
  const VoiceAgentScreen({super.key});

  @override
  State<VoiceAgentScreen> createState() => _VoiceAgentScreenState();
}

class _ChatLine {
  final bool fromAgent;
  final String text;
  final String tag;
  final bool warning;
  const _ChatLine(this.fromAgent, this.text, this.tag, {this.warning = false});
}

class _VoiceAgentScreenState extends State<VoiceAgentScreen> {
  static const _audioChannel = MethodChannel('upay/audio');
  AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSub;
  int _playToken = 0;
  int _armedToken = -1;
  bool _acceptPlayback = false;
  SpeechToText _stt = SpeechToText();
  final _recorder = AudioRecorder();
  final _scroll = ScrollController();
  final _speech = TextEditingController();
  final _lines = <_ChatLine>[];
  bool _deviceFailed = false;
  bool _micPrepared = false;
  bool _recovering = false;
  int _listenFaults = 0;
  bool _listening = false;
  bool _understanding = false;
  bool _closingMic = false;
  bool _openingMic = false;
  bool _heardVoice = false;
  bool _holdMic = false;
  bool _usingRecorder = false;
  bool _recordStarting = false;
  bool _restartQueued = false;
  bool _suppressStatus = false;
  int _restarts = 0;
  int _loudFrames = 0;
  int _speakGen = 0;
  double _micAmplitude = -160.0;
  DateTime? _micOpenedAt;
  DateTime _ignoreLevelsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final _micReady = Completer<void>();
  Timer? _restartTimer;
  String? _localeId;
  bool _micWarned = false;
  StreamSubscription<Amplitude>? _levels;
  Timer? _listenLimit;
  Timer? _silenceWait;

  String? _sessionId;
  String _expect = 'keypad';
  int? _digits;
  String _buffer = '';
  bool _busy = false;
  bool _speaking = false;
  bool _ended = false;
  bool _voiceMode = true;
  bool _awaitingTap = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listenToPlayer();
    _openCall();
  }

  Future<void> _openCall() async {
    await _useSpeaker();
    if (!mounted) return;
    await _beginCall();
  }

  void _listenToPlayer() {
    _player.setVolume(1);
    _playerSub = _player.playerStateStream.listen((state) {
      if (!_acceptPlayback) return;
      if (state.processingState == ProcessingState.ready ||
          state.processingState == ProcessingState.buffering) {
        _armedToken = _playToken;
      }
      if (!mounted || !_speaking || _armedToken != _playToken) return;
      if (state.processingState != ProcessingState.completed) return;
      final position = _player.position;
      final duration = _player.duration;
      final finished = duration == null || duration.inMilliseconds < 300
          ? position.inMilliseconds > 300
          : position.inMilliseconds >= duration.inMilliseconds - 400;
      if (!finished) return;
      _finishSpeaking();
    });
  }

  void _finishSpeaking() {
    if (!mounted || !_speaking) return;
    setState(() => _speaking = false);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _speaking || _busy || _ended) return;
      _startMic();
    });
  }

  @override
  void dispose() {
    _listenLimit?.cancel();
    _silenceWait?.cancel();
    _restartTimer?.cancel();
    _levels?.cancel();
    _stt.cancel();
    _recorder.dispose();
    _playerSub?.cancel();
    _player.dispose();
    _scroll.dispose();
    _speech.dispose();
    super.dispose();
  }

  void _onSttError(SpeechRecognitionError error) {
    if (!mounted) return;
    if (error.errorMsg == 'error_permission') {
      _releaseMic();
      _warnMic('মাইক্রোফোনের অনুমতি দিন, তাহলে এজেন্ট আপনার কথা শুনতে পারবে।');
      return;
    }
    final quiet = error.errorMsg == 'error_no_match' || error.errorMsg == 'error_speech_timeout';
    if (quiet) {
      if (_holdMic && !_usingRecorder) {
        if (_speech.text.trim().isNotEmpty) {
          _listenFaults = 0;
          _holdMic = false;
          _send('speech', _speech.text);
        } else {
          _queueRestart();
        }
      }
      return;
    }
    if (_holdMic && !_usingRecorder) _recoverListen();
  }

  void _onSttStatus(String status) {
    if (!mounted || !_holdMic || _usingRecorder || _suppressStatus) return;
    if (status == 'listening') {
      setState(() => _listening = true);
      return;
    }
    if (status == 'notListening' || status == 'done') {
      if (_speech.text.trim().isNotEmpty) {
        _listenFaults = 0;
        _holdMic = false;
        _send('speech', _speech.text);
      } else {
        _queueRestart();
      }
    }
  }

  Future<void> _prepareMic() async {
    if (_micPrepared) return;
    _micPrepared = true;
    try {
      final ok = await _stt.initialize(onError: _onSttError, onStatus: _onSttStatus);
      if (!ok || !mounted) {
        _localeId ??= 'bn-BD';
        return;
      }
      final locales = await _stt.locales();
      String? bangla;
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase();
        if (id.startsWith('bn')) {
          bangla = locale.localeId;
          if (id.contains('bd')) break;
        }
      }
      debugPrint('stt locales: ${locales.map((l) => l.localeId).join(", ")}');
      if (!mounted) return;
      setState(() => _localeId = bangla ?? 'bn-BD');
    } catch (error) {
      debugPrint('mic init failed: $error');
      _localeId ??= 'bn-BD';
    } finally {
      if (!_micReady.isCompleted) _micReady.complete();
    }
  }

  Future<void> _resetRecognizer() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    _stt = SpeechToText();
    try {
      await _stt.initialize(onError: _onSttError, onStatus: _onSttStatus);
    } catch (error) {
      debugPrint('mic reset failed: $error');
    }
  }

  Future<void> _recoverListen() async {
    if (_recovering || !_holdMic || !mounted) return;
    _recovering = true;
    try {
      _listenFaults++;
      if (_listenFaults <= 1) {
        await _resetRecognizer();
        if (_holdMic && mounted && !_usingRecorder) await _listenOnDevice();
        return;
      }
      await _recordForGoogle();
    } finally {
      _recovering = false;
    }
  }

  void _releaseMic() {
    _holdMic = false;
    _usingRecorder = false;
    _recordStarting = false;
    _restartQueued = false;
    _restartTimer?.cancel();
    if (mounted && _listening) setState(() => _listening = false);
  }

  void _queueRestart() {
    if (!_holdMic || _usingRecorder || _closingMic || _restartQueued || _openingMic) return;
    _restartQueued = true;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 500), () async {
      _restartQueued = false;
      if (!_holdMic || _usingRecorder || _closingMic || _openingMic || !mounted) return;
      if (_stt.isListening) return;
      _restarts++;
      if (_restarts >= 4) {
        _restarts = 0;
        await _recoverListen();
        return;
      }
      await _listenOnDevice();
    });
  }

  Future<void> _stopMic() async {
    _holdMic = false;
    _usingRecorder = false;
    _recordStarting = false;
    _restartQueued = false;
    _listenLimit?.cancel();
    _silenceWait?.cancel();
    _restartTimer?.cancel();
    await _levels?.cancel();
    _levels = null;
    if (_stt.isListening) await _stt.cancel();
    if (await _recorder.isRecording()) await _recorder.cancel();
    _closingMic = false;
    // The mic leaves the phone in call mode. Put the next voice back on the speaker.
    await _useSpeaker();
    if (mounted && _listening) {
      setState(() {
        _listening = false;
        _micAmplitude = -160.0;
      });
    }
  }

  Future<void> _startMic() async {
    if (!_voiceMode) return;
    if (_player.playing && _player.processingState != ProcessingState.completed) return;
    if (_openingMic || _holdMic || _busy || _ended || _understanding || _speaking) return;
    if (_expect != 'speech' || _closingMic) return;
    if (!mounted) return;
    _openingMic = true;
    _holdMic = true;
    _micOpenedAt = DateTime.now();
    _restarts = 0;
    _listenFaults = 0;
    _usingRecorder = false;
    _deviceFailed = false;
    setState(() => _listening = true);
    await _releasePlayback();
    if (!_micPrepared) await _prepareMic();
    if (!mounted || !_holdMic) {
      _openingMic = false;
      return;
    }
    _localeId ??= 'bn-BD';
    try {
      await _listenOnDevice();
    } finally {
      _openingMic = false;
    }
  }

  void _onMicTap() {
    if (_busy || _understanding) return;
    if (_speaking) {
      _interruptAndListen();
      return;
    }
    if (_holdMic) {
      final opened = _micOpenedAt;
      if (opened != null && DateTime.now().difference(opened) < const Duration(milliseconds: 800)) {
        return;
      }
      _finishListening();
      return;
    }
    _startMic();
  }

  Future<void> _interruptAndListen() async {
    _speakGen++;
    if (mounted) setState(() => _speaking = false);
    await _player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _startMic();
  }

  Future<void> _listenOnDevice() async {
    try {
      _suppressStatus = true;
      if (_stt.isListening) await _stt.cancel();
      _speech.clear();
      await _stt.listen(
        onResult: (result) {
          if (!mounted || !_holdMic) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) setState(() => _speech.text = words);
          if (!result.finalResult) return;
          if (words.isNotEmpty) {
            _listenFaults = 0;
            _holdMic = false;
            _send('speech', words);
            return;
          }
          if (_holdMic) {
            _queueRestart();
          } else {
            setState(() => _listening = false);
          }
        },
        onSoundLevelChange: (level) {
          if (mounted) setState(() => _micAmplitude = (level * 2) - 50.0);
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          onDevice: false,
          localeId: _localeId ?? 'bn-BD',
          listenFor: const Duration(seconds: 25),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      if (mounted) setState(() => _listening = true);
    } catch (error) {
      debugPrint('device listen failed: $error');
      if (_listenFaults >= 1) {
        await _recordForGoogle();
      } else {
        await _recoverListen();
      }
    } finally {
      _suppressStatus = false;
    }
  }

  Future<void> _recordForGoogle() async {
    if (_recordStarting) return;
    _recordStarting = true;
    if (await _recorder.isRecording()) {
      _recordStarting = false;
      return;
    }
    _usingRecorder = true;
    _restartTimer?.cancel();
    if (_stt.isListening) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }
    await _releasePlayback();
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      _recordStarting = false;
      _releaseMic();
      _warnMic('মাইক্রোফোনের অনুমতি দিন, তাহলে এজেন্ট আপনার কথা শুনতে পারবে।');
      return;
    }
    final config = await _recordConfig();
    if (config == null) {
      _recordStarting = false;
      _releaseMic();
      _warnMic('এই ফোনে কথা রেকর্ড করা যাচ্ছে না।');
      return;
    }
    final path = kIsWeb
        ? 'upay_user.wav'
        : '${Directory.systemTemp.path}${Platform.pathSeparator}upay_user.wav';
    try {
      await _recorder.start(config, path: path);
    } catch (error) {
      debugPrint('record failed: $error');
      _recordStarting = false;
      _releaseMic();
      _warnMic('মাইক চালু হচ্ছে না। আবার চাপুন।');
      return;
    }
    _recordStarting = false;
    _heardVoice = false;
    _loudFrames = 0;
    _ignoreLevelsUntil = DateTime.now().add(const Duration(milliseconds: 400));
    if (mounted) setState(() => _listening = true);
    _listenLimit?.cancel();
    _listenLimit = Timer(const Duration(seconds: 7), _finishListening);
    await _levels?.cancel();
    _levels = _recorder.onAmplitudeChanged(const Duration(milliseconds: 160)).listen((amp) {
      if (DateTime.now().isBefore(_ignoreLevelsUntil)) return;
      final level = amp.current;
      if (mounted) setState(() => _micAmplitude = level);
      final loud = level > -58 && level < 0;
      if (loud) {
        _loudFrames++;
        if (_loudFrames >= 2) _heardVoice = true;
        _silenceWait?.cancel();
        _silenceWait = null;
      } else {
        _loudFrames = 0;
        if (_heardVoice && _silenceWait == null) {
          _silenceWait = Timer(const Duration(milliseconds: 900), _finishListening);
        }
      }
    });
  }

  Future<RecordConfig?> _recordConfig() async {
    const android = AndroidRecordConfig(
      audioSource: AndroidAudioSource.mic,
      manageBluetooth: false,
    );
    const wav = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      audioInterruption: AudioInterruptionMode.none,
      androidConfig: android,
    );
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) return wav;
    const pcm = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      audioInterruption: AudioInterruptionMode.none,
      androidConfig: android,
    );
    if (await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) return pcm;
    return null;
  }

  Uint8List _ensureWav(Uint8List bytes) {
    if (bytes.length >= 4 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      return bytes;
    }
    const rate = 16000;
    final size = bytes.length;
    final header = ByteData(44);
    void write(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    write(0, 'RIFF');
    header.setUint32(4, 36 + size, Endian.little);
    write(8, 'WAVE');
    write(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, rate, Endian.little);
    header.setUint32(28, rate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    write(36, 'data');
    header.setUint32(40, size, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...bytes]);
  }

  void _warnMic(String message) {
    if (!mounted || _micWarned) return;
    _micWarned = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finishListening() async {
    if (_closingMic) return;
    _closingMic = true;
    _holdMic = false;
    _restartTimer?.cancel();
    _listenLimit?.cancel();
    _silenceWait?.cancel();
    await _levels?.cancel();
    _levels = null;
    try {
      final recording = await _recorder.isRecording();
      if (!recording && _stt.isListening) {
        await _stt.stop();
        return;
      }
      if (_stt.isListening) await _stt.cancel();
      if (!recording) return;
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _micAmplitude = -160.0;
          _understanding = true;
        });
      }
      if (path == null) return;
      final bytes = _ensureWav(await _clipBytes(path));
      if (bytes.length < 2000) return;
      final text = await AgentApi.transcribe(bytes);
      if (!mounted) return;
      setState(() => _understanding = false);
      if (text == null || text.isEmpty) {
        if (_heardVoice) _warnMic('বুঝতে পারিনি। আবার মাইকে চাপুন।');
        return;
      }
      _speech.text = text;
      await _send('speech', text);
    } finally {
      _closingMic = false;
      if (mounted && _understanding) setState(() => _understanding = false);
    }
  }

  Future<void> _beginCall() async {
    setState(() {
      _busy = true;
      _error = null;
      _ended = false;
      _lines.clear();
      _buffer = '';
    });
    try {
      final turn = await AgentApi.start();
      if (!mounted) return;
      setState(() {
        _sessionId = turn.sessionId;
        _apply(turn);
        _busy = false;
      });
    } on AgentException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'ইন্টারনেট চেক করে আবার কল করুন';
      });
    }
  }

  void _apply(AgentTurn turn) {
    _expect = turn.expect;
    _digits = turn.digits;
    _ended = turn.end;
    _buffer = '';
    _lines.add(_ChatLine(true, turn.say, _tagFor(turn.expect), warning: turn.say.contains('সতর্কতা')));
    if (turn.say.isNotEmpty) _speak(turn.say);
    _scrollDown();
    // Sync balance + transactions from backend when call ends
    if (turn.end) _syncBackend();
  }

  /// Pull latest balance & transaction history from the Voice Guard backend
  /// so HomeScreen, AccountScreen, and HistoryScreen show updated data.
  Future<void> _syncBackend() async {
    await UserData.syncFromBackend();
  }

  String _tagFor(String expect) {
    if (expect == 'keypad') return 'কীপ্যাড';
    if (expect == 'speech') return 'কথা';
    return 'কল শেষ';
  }

  Future<Uint8List> _clipBytes(String path) async {
    if (kIsWeb || path.startsWith('blob:') || path.startsWith('http')) {
      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200) {
        throw Exception('recording ${response.statusCode}');
      }
      return response.bodyBytes;
    }
    return File(path).readAsBytes();
  }

  Future<void> _releasePlayback() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (error) {
      debugPrint('release playback failed: $error');
    }
  }

  Future<void> _useSpeaker() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      if (!kIsWeb && Platform.isAndroid) {
        await _audioChannel.invokeMethod<void>('speaker');
      }
      await session.setActive(true);
    } catch (error) {
      debugPrint('speaker route failed: $error');
    }
  }

  /// True when the clip was allowed to play through. False when the browser
  /// is still waiting for a tap.
  Future<bool> _playLoaded() async {
    _playToken++;
    _armedToken = -1;
    _acceptPlayback = true;
    try {
      await _player.play();
      if (mounted && _awaitingTap) setState(() => _awaitingTap = false);
      return true;
    } catch (error) {
      final text = error.toString();
      if (text.contains('NotAllowed') || text.contains('interact')) {
        if (mounted) setState(() => _awaitingTap = true);
        return false;
      }
      rethrow;
    }
  }

  Future<void> _replacePlayer() async {
    await _playerSub?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
    _player = AudioPlayer();
    _listenToPlayer();
  }

  Future<void> _loadClip(int gen, Uint8List bytes) async {
    try {
      await _player.stop();
    } catch (_) {}
    if (_player.playing) {
      await _replacePlayer();
      if (!mounted || gen != _speakGen) return;
    }
    if (kIsWeb) {
      await _player.setAudioSource(
        AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/mpeg')),
      );
    } else {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}upay_agent_$gen.mp3');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted || gen != _speakGen) return;
      await _player.setFilePath(file.path);
    }
    await _player.seek(Duration.zero);
  }

  Future<void> _speak(String text) async {
    final gen = ++_speakGen;
    _acceptPlayback = false;
    _armedToken = -1;
    await _stopMic();
    if (!mounted || gen != _speakGen) return;
    setState(() => _speaking = true);
    try {
      final bytes = await AgentApi.speak(text);
      if (!mounted || gen != _speakGen) return;
      if (bytes == null || bytes.length < 200) throw Exception('empty voice');
      await _useSpeaker();
      if (!mounted || gen != _speakGen) return;
      await _replacePlayer();
      if (!mounted || gen != _speakGen) return;
      try {
        await _loadClip(gen, bytes);
      } catch (error) {
        debugPrint('reload player: $error');
        if (!mounted || gen != _speakGen) return;
        await _replacePlayer();
        if (!mounted || gen != _speakGen) return;
        await _loadClip(gen, bytes);
      }
      if (!mounted || gen != _speakGen) return;
      final played = await _playLoaded();
      if (!mounted || gen != _speakGen || !played) return;
      // A finished player can report "done" before the new clip starts.
      if (_player.processingState == ProcessingState.completed &&
          _player.position < const Duration(milliseconds: 200)) {
        await _player.seek(Duration.zero);
        if (!mounted || gen != _speakGen) return;
        await _player.play();
      }
    } catch (error) {
      debugPrint('speak failed: $error');
      if (!mounted || gen != _speakGen) return;
      setState(() => _speaking = false);
      _startMic();
    }
  }

  Future<void> _send(String kind, String value) async {
    final id = _sessionId;
    if (id == null || _busy || _ended || value.trim().isEmpty) return;
    final shown = kind == 'keypad' && _digits == 4 ? '••••' : value.trim();
    setState(() {
      _busy = true;
      _lines.add(_ChatLine(
        false,
        shown,
        kind == 'keypad' ? (_digits == 4 ? 'পিন' : 'কীপ্যাড') : 'কথা',
      ));
    });
    await _stopMic();
    _speech.clear();
    _scrollDown();
    try {
      final turn = await AgentApi.send(id, kind, value.trim());
      if (!mounted) return;
      setState(() {
        _apply(turn);
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('পাঠানো যায়নি। আবার চেষ্টা করুন।')),
      );
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _setMode(bool voice) {
    if (_voiceMode == voice) return;
    setState(() => _voiceMode = voice);
    if (!voice) {
      _stopMic();
      return;
    }
    if (_expect == 'speech' && !_ended && !_busy && !_speaking) {
      _startMic();
    }
  }

  void _press(String key) {
    // Enforce max digit limit: 4 for PIN, 11 for phone number
    if (_digits != null && _buffer.length >= _digits!) return;
    HapticFeedback.selectionClick();
    setState(() => _buffer += key);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_awaitingTap) return;
        _playLoaded().then((played) {
          if (played) _finishSpeaking();
        });
      },
      child: Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.accentYellow,
        foregroundColor: AppColors.black,
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AgentAiMark(size: 36),
            SizedBox(width: 8),
            Text(
              'উপায় এজেন্ট',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'কল শেষ',
            onPressed: () async {
              await _syncBackend();
              if (mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.call_end, color: AppColors.red),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              _buildModeSwitch(),
              Expanded(child: _buildChat()),
              if (_error != null) _buildError(),
              if (_error == null && !_ended) _buildHint(),
              if (_error == null && _expect == 'keypad' && !_ended) _buildKeypad(),
              if (_error == null && _expect == 'speech' && !_ended && _voiceMode) _buildVoicePad(),
              if (_error == null && _expect == 'speech' && !_ended && !_voiceMode) _buildSpeech(),
              if (_ended) _buildEnded(),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(child: _modeButton('কণ্ঠ', Icons.graphic_eq, true)),
          const SizedBox(width: 8),
          Expanded(child: _modeButton('টেক্সট', Icons.keyboard_alt_outlined, false)),
        ],
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, bool voice) {
    final selected = _voiceMode == voice;
    return Material(
      color: selected ? AppColors.primaryBlue : AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _setMode(voice),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.white : AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.white : AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoicePad() {
    final rawLevel = (_micAmplitude.clamp(-50.0, 0.0) + 50.0) / 50.0;
    final scale1 = _listening ? 1.0 + rawLevel * 0.4 : 1.0;
    final scale2 = _listening ? 1.0 + rawLevel * 0.8 : 1.0;
    final scale3 = _listening ? 1.0 + rawLevel * 1.3 : 1.0;
    
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (_listening) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 88 * scale3,
                  height: 88 * scale3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.red.withOpacity(0.1),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 88 * scale2,
                  height: 88 * scale2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.red.withOpacity(0.2),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 88 * scale1,
                  height: 88 * scale1,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.red.withOpacity(0.3),
                  ),
                ),
              ],
              GestureDetector(
                onTap: _busy ? null : _onMicTap,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? AppColors.red : AppColors.accentYellow,
                  ),
                  child: Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    size: 42,
                    color: AppColors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _speaking
                ? 'এজেন্ট বলছে। থামাতে মাইকে চাপুন'
                : _listening
                    ? 'বলুন। শেষ হলে আবার মাইকে চাপুন'
                    : 'মাইকে চাপুন, তারপর বলুন',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildChat() {
    if (_busy && _lines.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final line = _lines[i];
        final mine = !line.fromAgent;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            decoration: BoxDecoration(
              color: line.warning
                  ? const Color(0xFFFFF6CC)
                  : mine
                      ? AppColors.primaryBlue
                      : AppColors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: line.fromAgent ? Border.all(color: AppColors.lightGrey) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.tag,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: mine ? AppColors.accentYellow : AppColors.goldYellow,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: mine ? AppColors.white : AppColors.black,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHint() {
    final heard = _speech.text.trim();
    final text = _awaitingTap
        ? 'শব্দ চালু করতে স্ক্রিনে একবার চাপুন'
        : _understanding
        ? 'বুঝছি...'
        : _speaking
            ? 'বলছি...'
            : _listening
                ? (heard.isEmpty ? 'শুনছি, বলুন' : heard)
                : _expect == 'keypad'
            ? (_digits == 4
                ? '৪ সংখ্যার পিন কীপ্যাডে দিন'
                : _digits == 11
                    ? '১১ সংখ্যার নম্বর কীপ্যাডে দিন'
                    : 'টাকার পরিমাণ কীপ্যাডে দিন')
            : 'মাইকে চাপুন এবং বাংলায় বলুন';
    return Container(
      width: double.infinity,
      color: _expect == 'keypad' ? const Color(0xFFFFF6CC) : const Color(0xFFE8F0FC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: _expect == 'keypad' ? const Color(0xFF6B5400) : AppColors.primaryBlue,
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final shown = _digits == 4 ? '•' * _buffer.length : _buffer;
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 440.0);
    final cell = ((width - 48) / 3).clamp(1.0, 200.0);
    final keyAspect = (cell / 56).clamp(1.5, 4.0);
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    shown.isEmpty ? 'কীপ্যাডে দিন' : shown,
                    style: TextStyle(
                      fontSize: shown.isEmpty ? 14 : 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: shown.isEmpty ? 0 : 4,
                      color: shown.isEmpty ? AppColors.grey : AppColors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _digits == null ? '' : '${_buffer.length}/$_digits',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.grey),
              ),
              IconButton(
                onPressed: _buffer.isEmpty
                    ? null
                    : () => setState(() => _buffer = _buffer.substring(0, _buffer.length - 1)),
                icon: const Icon(Icons.backspace_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: keyAspect,
            children: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#']
                .map((key) => Material(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _busy ? null : () => _press(key),
                        child: Center(
                          child: Text(key, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentYellow,
                foregroundColor: AppColors.black,
              ),
              onPressed: _busy || _buffer.isEmpty ? null : () => _send('keypad', _buffer),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('পাঠান', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeech() {
    const chips = [
      ('হ্যাঁ', 'হ্যাঁ'),
      ('না', 'না'),
      ('ক্যাশ আউট', 'ক্যাশ আউট করতে চাই'),
      ('ব্যালেন্স', 'ব্যালেন্স কত'),
      ('অ্যাকাউন্ট', 'আমার অ্যাকাউন্টের সব তথ্য বল'),
      ('খরচ', 'গত মাসে কত খরচ হয়েছে'),
    ];
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _speech,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) => _send('speech', v),
                  decoration: InputDecoration(
                    hintText: 'কথা লিখুন',
                    filled: true,
                    fillColor: AppColors.offWhite,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                onPressed: _busy ? null : () => _send('speech', _speech.text),
                icon: const Icon(Icons.send, color: AppColors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: chips
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(c.$1),
                          onPressed: _busy ? null : () => _send('speech', c.$2),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _beginCall, child: const Text('আবার কল করুন')),
        ],
      ),
    );
  }

  Widget _buildEnded() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          onPressed: _beginCall,
          child: const Text('নতুন কল'),
        ),
      ),
    );
  }
}
