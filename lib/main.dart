import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const RiassuntiSmartApp());
}

class RiassuntiSmartApp extends StatelessWidget {
  const RiassuntiSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Riassunti Smart',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF4F46E5),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class SavedItem {
  final String titolo;
  final String testo;

  SavedItem({
    required this.titolo,
    required this.testo,
  });

  Map<String, dynamic> toJson() {
    return {
      'titolo': titolo,
      'testo': testo,
    };
  }

  factory SavedItem.fromJson(Map<String, dynamic> json) {
    return SavedItem(
      titolo: json['titolo'] ?? '',
      testo: json['testo'] ?? '',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _savedScrollController = ScrollController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  String titolo = '';
  String riassunto = '';
  String errore = '';
  bool loading = false;

  bool _speechDisponibile = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  List<SavedItem> salvati = [];

  @override
  void initState() {
    super.initState();
    _caricaSalvati();
    _initSpeech();
    _initTts();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            errore = 'Errore microfono';
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _speechDisponibile = available;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechDisponibile = false;
      });
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('it-IT');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = true;
      });
    });

    _tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
      });
    });

    _tts.setCancelHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
      });
    });

    _tts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        errore = 'Errore lettura vocale';
      });
    });
  }

  Future<void> _caricaSalvati() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> dati = prefs.getStringList('salvati') ?? [];

    setState(() {
      salvati = dati.map((e) => SavedItem.fromJson(jsonDecode(e))).toList();
    });
  }

  Future<void> _salvaLista() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> dati =
        salvati.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('salvati', dati);
  }

  Future<void> cerca() async {
    FocusScope.of(context).unfocus();

    final query = _controller.text.trim();

    if (query.isEmpty) {
      setState(() {
        errore = 'Scrivi qualcosa, per esempio Napoleone';
        titolo = '';
        riassunto = '';
      });
      return;
    }

    await _fermaLettura();

    setState(() {
      loading = true;
      errore = '';
      titolo = '';
      riassunto = '';
    });

    try {
      // Usiamo l'API mobile-sections per ottenere l'introduzione completa (solitamente più ampia del summary)
      final url = Uri.parse(
        'https://it.wikipedia.org/api/rest_v1/page/mobile-sections/${Uri.encodeComponent(query)}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // La sezione 0 è sempre l'introduzione (lead section)
        final leadSection = data['lead']?['sections']?[0]?['text'] ?? '';
        final displayTitle = data['lead']?['displaytitle'] ?? query;

        // Puliamo l'HTML dai tag per avere solo il testo
        String cleanText = leadSection.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ').trim();
        // Rimuoviamo spazi multipli
        cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ');

        if (cleanText.isEmpty) {
          // Fallback al summary standard se mobile-sections fallisce o è vuoto
          final summaryUrl = Uri.parse(
            'https://it.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(query)}',
          );
          final summaryRes = await http.get(summaryUrl);
          if (summaryRes.statusCode == 200) {
            final summaryData = jsonDecode(summaryRes.body);
            cleanText = summaryData['extract'] ?? '';
          }
        }

        if (cleanText.isEmpty) {
          setState(() {
            errore = 'Nessun riassunto trovato';
          });
        } else {
          setState(() {
            titolo = displayTitle.replaceAll(RegExp(r'<[^>]*>'), '');
            riassunto = cleanText;
          });
        }
      } else {
        setState(() {
          errore = 'Argomento non trovato';
        });
      }
    } catch (e) {
      setState(() {
        errore = 'Errore di connessione';
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> salva() async {
    if (titolo.isEmpty || riassunto.isEmpty) return;

    final esisteGia = salvati.any(
      (item) => item.titolo.toLowerCase() == titolo.toLowerCase(),
    );

    if (esisteGia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questo riassunto è già salvato')),
      );
      return;
    }

    setState(() {
      salvati.insert(
        0,
        SavedItem(
          titolo: titolo,
          testo: riassunto,
        ),
      );
    });

    await _salvaLista();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Riassunto salvato')),
    );
  }

  Future<void> eliminaSalvato(int index) async {
    if (index < 0 || index >= salvati.length) return;

    final itemEliminato = salvati[index];

    setState(() {
      salvati.removeAt(index);
    });

    await _salvaLista();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${itemEliminato.titolo} eliminato')),
    );
  }

  Future<void> cancellaTutto() async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancella tutto'),
        content: const Text('Vuoi eliminare tutti i salvati?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sì'),
          ),
        ],
      ),
    );

    if (conferma == true) {
      setState(() {
        salvati.clear();
      });

      await _salvaLista();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tutti i salvati eliminati')),
      );
    }
  }

  Future<void> video() async {
    final query = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : titolo;

    if (query.isEmpty) return;

    final url = Uri.parse(
      'https://www.youtube.com/results?search_query=${Uri.encodeComponent("$query spiegazione")}',
    );

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> google() async {
    final query = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : titolo;

    if (query.isEmpty) return;

    final url = Uri.parse(
      'https://www.google.com/search?q=${Uri.encodeComponent("$query riassunto")}',
    );

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> chatgpt() async {
    final url = Uri.parse('https://chatgpt.com');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> toggleMicrofono() async {
    if (!_speechDisponibile) {
      setState(() {
        errore = 'Microfono non disponibile su questo dispositivo';
      });
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
      });
      return;
    }

    await _fermaLettura();

    setState(() {
      errore = '';
      _isListening = true;
    });

    await _speech.listen(
      localeId: 'it_IT',
      listenMode: stt.ListenMode.confirmation,
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _controller.text = result.recognizedWords;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
    );
  }

  Future<void> leggiRiassunto() async {
    if (riassunto.trim().isEmpty) return;

    if (_isSpeaking) {
      await _fermaLettura();
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
      });
    }

    final testoDaLeggere = '$titolo. $riassunto';
    await _tts.speak(testoDaLeggere);
  }

  Future<void> _fermaLettura() async {
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
    });
  }

  void apriSalvato(SavedItem item) async {
    await _fermaLettura();

    setState(() {
      titolo = item.titolo;
      riassunto = item.testo;
      errore = '';
      _controller.text = item.titolo;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _savedScrollController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(color: const Color(0xFFF1F5F9)),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool haRisultato = titolo.isNotEmpty && riassunto.isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Riassunti Smart'),
        actions: [
          if (salvati.isNotEmpty)
            IconButton(
              onPressed: cancellaTutto,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 110, 16, 32),
          children: [
            // Search Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cosa vuoi studiare?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    onSubmitted: (_) => cerca(),
                    decoration: InputDecoration(
                      hintText: 'Es. Napoleone, Roma antica...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6366F1)),
                      suffixIcon: _controller.text.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                          )
                        : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: cerca,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Cerca Ora',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _isListening ? Colors.redAccent.withOpacity(0.1) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: IconButton(
                          onPressed: toggleMicrofono,
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none_rounded,
                            color: _isListening ? Colors.redAccent : const Color(0xFF475569),
                          ),
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (loading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],

            if (errore.isNotEmpty) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                ),
                child: Text(
                  errore,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
              ),
            ],

            if (haRisultato) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: _cardDecoration().copyWith(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Colors.blue.withOpacity(0.02)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            titolo,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: salva,
                          icon: const Icon(Icons.bookmark_add_rounded, size: 28),
                          color: const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      riassunto,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.6,
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Approfondisci su:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                        textBaseline: TextBaseline.alphabetic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildActionButton(
                          onPressed: google,
                          icon: Icons.search_rounded,
                          label: 'Google',
                          color: Colors.blue,
                        ),
                        _buildActionButton(
                          onPressed: video,
                          icon: Icons.play_circle_fill_rounded,
                          label: 'YouTube',
                          color: Colors.red,
                        ),
                        _buildActionButton(
                          onPressed: chatgpt,
                          icon: Icons.auto_awesome_rounded,
                          label: 'ChatGPT',
                          color: const Color(0xFF10A37F),
                        ),
                        _buildActionButton(
                          onPressed: leggiRiassunto,
                          icon: _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                          label: _isSpeaking ? 'Ferma' : 'Ascolta',
                          color: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
            Row(
              children: [
                const Text(
                  'I tuoi riassunti',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                if (salvati.isNotEmpty)
                  const Text(
                    'Swipe per eliminare',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            if (salvati.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.bookmark_border_rounded, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    const Text(
                      'Ancora nulla di salvato',
                      style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: salvati.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = salvati[index];
                  return Dismissible(
                    key: ValueKey(item.titolo + index.toString()),
                    direction: DismissDirection.horizontal,
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 20),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.delete_rounded, color: Colors.white),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.delete_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) => eliminaSalvato(index),
                    child: Container(
                      decoration: _cardDecoration(),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        title: Text(
                          item.titolo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        subtitle: Text(
                          item.testo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
                        onTap: () => apriSalvato(item),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}