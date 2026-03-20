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
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFFF3F6FB),
          elevation: 0,
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
      final url = Uri.parse(
        'https://it.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(query)}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final nuovoTitolo = data['title'] ?? query;
        final nuovoRiassunto = data['extract'] ?? '';

        if (nuovoRiassunto.toString().trim().isEmpty) {
          setState(() {
            errore = 'Nessun riassunto trovato';
          });
        } else {
          setState(() {
            titolo = nuovoTitolo;
            riassunto = nuovoRiassunto;
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
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color.fromARGB(18, 0, 0, 0),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool haRisultato = titolo.isNotEmpty && riassunto.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Riassunti Smart',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cerca un argomento',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scrivi o parla: Napoleone, Dante, Roma, Leonardo da Vinci...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  onSubmitted: (_) => cerca(),
                  decoration: InputDecoration(
                    hintText: 'Scrivi es. Napoleone',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: toggleMicrofono,
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening ? Colors.red : Colors.blue,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              titolo = '';
                              riassunto = '';
                              errore = '';
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isListening)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.mic, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Sto ascoltando...',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: cerca,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text(
                          'Trova riassunto',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: toggleMicrofono,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isListening ? Colors.red : Colors.black87,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: Icon(_isListening ? Icons.stop : Icons.mic),
                      label: Text(_isListening ? 'Stop' : 'Parla'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecoration(),
              child: const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Sto cercando il riassunto...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (errore.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecoration(),
              child: Text(
                errore,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (haRisultato) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titolo,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    riassunto,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: salva,
                          icon: const Icon(Icons.bookmark),
                          label: const Text('Salva'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: leggiRiassunto,
                          icon: Icon(
                            _isSpeaking ? Icons.stop_circle : Icons.volume_up,
                          ),
                          label: Text(_isSpeaking ? 'Stop voce' : 'Leggi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: video,
                          icon: const Icon(Icons.play_circle),
                          label: const Text('Video'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: google,
                          icon: const Icon(Icons.search),
                          label: const Text('Google'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: chatgpt,
                      icon: const Icon(Icons.smart_toy),
                      label: const Text('Apri ChatGPT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Salvati',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (salvati.isNotEmpty)
                      TextButton.icon(
                        onPressed: cancellaTutto,
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Cancella tutto',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Scorri la lista. Per eliminare un elemento, trascinalo a destra o sinistra.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 14),
                salvati.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Nessun riassunto salvato',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 340,
                        child: Scrollbar(
                          controller: _savedScrollController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _savedScrollController,
                            itemCount: salvati.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = salvati[index];

                              return Dismissible(
                                key: ValueKey('${item.titolo}-$index'),
                                direction: DismissDirection.horizontal,
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Elimina',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Elimina',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.delete, color: Colors.white),
                                    ],
                                  ),
                                ),
                                onDismissed: (_) {
                                  eliminaSalvato(index);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    title: Text(
                                      item.titolo,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        item.testo,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                    onTap: () => apriSalvato(item),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}