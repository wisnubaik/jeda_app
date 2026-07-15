import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

class JedaOverlayWidget extends StatefulWidget {
  const JedaOverlayWidget({super.key});

  @override
  State<JedaOverlayWidget> createState() => _JedaOverlayWidgetState();
}

class _JedaOverlayWidgetState extends State<JedaOverlayWidget> {
  final AudioPlayer _player = AudioPlayer();

  // Pesan default; akan ditimpa oleh nilai dari shareData (pilihan pengguna
  // di halaman Pengaturan).
  String _message = 'Pola penggunaanmu sudah berlebihan.\nWaktunya istirahat sejenak.';

  // Logo & warna per pesan — HARUS sama urutannya dengan _motivationIcons /
  // _motivationColors di halaman Pengaturan (settings_screen.dart).
  static const List<IconData> _icons = [
    Icons.wb_sunny_rounded,
    Icons.self_improvement_rounded,
    Icons.directions_walk_rounded,
    Icons.air_rounded,
  ];
  static const List<Color> _colors = [
    Color(0xFFF97316),
    Color(0xFF06B6D4),
    Color(0xFF22C55E),
    Color(0xFF6366F1),
  ];

  IconData _icon = Icons.wb_sunny_rounded;
  Color _color = const Color(0xFFF97316);

  @override
  void initState() {
    super.initState();
    // Alarm & konfigurasi diterima via shareData dari isolate utama (nilai
    // selalu terbaru). Overlay yang re-attach saat startup tidak menerima
    // sinyal ini sehingga tidak berbunyi.
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && event['action'] == 'alarm') {
        // Perbarui pesan sesuai pilihan pengguna di Pengaturan.
        final msg = event['message'];
        final idx = event['variant_index'];
        debugPrint('💬 [OVERLAY] pesan diterima: "$msg" (index=$idx)');
        if (mounted) {
          setState(() {
            if (msg is String && msg.isNotEmpty) _message = msg;
            if (idx is int && idx >= 0 && idx < _icons.length) {
              _icon = _icons[idx];
              _color = _colors[idx];
            }
          });
        }
        _playAlarm(
          soundOn: event['sound_enabled'] as bool? ?? true,
          alarm: event['alarm_sound'] as String? ?? 'alarm',
          vibMode: event['vibration_mode'] as String? ?? 'pendek',
        );
      }
    });
  }

  Future<void> _playAlarm({
    required bool soundOn,
    required String alarm,
    required String vibMode,
  }) async {
    debugPrint('🔊 [OVERLAY] _playAlarm (nyata): sound=$soundOn alarm=$alarm vib=$vibMode');
    try {
      if (soundOn) {
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.play(AssetSource('sounds/$alarm.mp3'));
      }
      if (vibMode != 'off') {
        final hasVib = await Vibration.hasVibrator() ?? false;
        if (hasVib) {
          if (vibMode == 'panjang') {
            Vibration.vibrate(pattern: [0, 1000, 500, 1000, 500, 1000]);
          } else {
            Vibration.vibrate(pattern: [0, 200, 100, 200]);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [OVERLAY] gagal play alarm: $e');
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _snooze(int seconds) async {
    await _stopAlarm();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (seconds >= 600) {
        await prefs.setBool('overlay_snoozeLong', true);
      } else {
        await prefs.setBool('overlay_snoozeShort', true);
      }
      await prefs.reload();
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _disableMonitoring() async {
    await _stopAlarm();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('overlay_disableMonitoring', true);
      await prefs.reload();
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    // ═══ TAMBAHAN: shortestSide adalah sisi TERPENDEK device secara fisik,
    // nilainya SELALU SAMA baik device dalam mode portrait maupun landscape
    // (misal device 720x1600 di portrait, shortestSide=720; setelah diputar
    // ke landscape jadi 1600x720, shortestSide TETAP 720). Dengan mematok
    // maxWidth berdasar shortestSide (bukan lebar layar aktual saat itu),
    // kartu overlay selalu berukuran SAMA PERSIS di kedua orientasi —
    // tidak lagi melebar mengikuti lebar landscape yang jauh lebih besar
    // dari lebar portrait. ═══
    final mediaSize = MediaQuery.of(context).size;
    final referenceWidth = mediaSize.shortestSide;
    final isLandscape = mediaSize.width > mediaSize.height;

    // ═══ TAMBAHAN: batas TINGGI pop-up di mode lanskap ═══
    // mediaSize.height saat lanskap SEHARUSNYA sama dengan lebar layar saat
    // potret (referenceWidth), tapi di sebagian ROM window overlay tidak
    // melaporkan tinggi sepenuhnya akurat (terpotong status bar/insets dsb),
    // sehingga kartu bisa "nembus" ke luar batas layar (lihat kasus overflow
    // sebelumnya). Untuk menjamin kartu TIDAK PERNAH melebihi tinggi layar
    // asli device, batas tinggi di mode lanskap dipatok LANGSUNG dari
    // referenceWidth (bukan dari mediaSize.height), dikurangi margin yang
    // sama seperti margin horizontal pada mode potret. Di mode potret,
    // tinggi layar aktual jauh lebih besar dari lebar sehingga tetap aman
    // memakai mediaSize.height * 0.9 seperti sebelumnya.
    final maxCardHeight =
        isLandscape ? referenceWidth - 64 : mediaSize.height * 0.9;

    // Lebar konten di dalam kartu (di luar padding horizontal 24 kiri+kanan).
    // Dipakai untuk tombol menggantikan `double.infinity`, karena FittedBox
    // di bawah butuh constraint yang bounded (tidak boleh infinity).
    const double cardPaddingH = 24.0;
    const double cardPaddingV = 32.0;
    final contentWidth = (referenceWidth - 64) - (cardPaddingH * 2);

    // Posisi kartu digeser sedikit ke bawah dari tengah (faktor 0.3) untuk
    // mengimbangi window overlay yang pada sebagian ROM tidak setinggi layar
    // penuh sehingga Center murni tampak agak ke atas. Nilai 0.3 dipilih agar
    // pop-up berada di area tengah yang nyaman dilihat.
    //
    // ConstrainedBox dengan maxWidth (berbasis shortestSide) + maxHeight
    // (maxCardHeight, lihat penjelasan di atas) + SingleChildScrollView di
    // dalamnya: lebar kartu selalu konsisten kedua orientasi, dan tinggi
    // dijamin tidak pernah melebihi layar di kedua orientasi — kalau konten
    // tak muat, otomatis bisa di-scroll, bukan overflow/cacat.
    // ═══ TAMBAHAN: posisi vertikal ═══
    // Digeser ke bawah tengah (0.5) baik potret maupun lanskap — kalibrasi
    // lama untuk kompensasi window overlay yang di sebagian ROM tidak
    // menutupi layar penuh (lihat solusi MethodChannel status bar height).
    final verticalAlign = 0.5;

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Align(
          alignment: Alignment(0, verticalAlign),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: referenceWidth - 64,
              maxHeight: maxCardHeight,
            ),
            child: (() {
              // ═══ TAMBAHAN: konten kartu dipisah jadi widget tersendiri
              // supaya bisa dirender dengan 2 cara berbeda tergantung
              // orientasi (lihat di bawah). ═══
              final cardContent = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _color, shape: BoxShape.circle),
                      child: Icon(_icon, color: Colors.white, size: 48),
                    ),
                    const SizedBox(height: 24),
                    Text('SAATNYA JEDA!',
                        style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _color,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: Colors.grey[600], height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: contentWidth,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24))),
                        onPressed: () => _snooze(10),
                        child: Text('Ingatkan 10 Detik Lagi',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: contentWidth,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1A1A2E),
                            side: BorderSide(
                                color: Colors.grey[300]!, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24))),
                        onPressed: () => _snooze(600),
                        child: Text('Ingatkan 10 Menit Lagi',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: _disableMonitoring,
                      behavior: HitTestBehavior.opaque,
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey[500]),
                          children: [
                            const TextSpan(text: 'Saya sedang produktif. '),
                            TextSpan(
                                text: 'Matikan\nmonitoring hari ini!',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                    decoration: TextDecoration.underline)),
                          ],
                        ),
                      ),
                    ),
                ],
              );

              // ═══ TAMBAHAN: cara render konten beda per orientasi ═══
              // Potret: ruang vertikal sudah cukup luas → tetap pakai
              // SingleChildScrollView (natural size, scroll cuma jaring
              // pengaman untuk kasus ekstrem).
              // Lanskap: ruang vertikal terbatas (maxCardHeight = lebar
              // potret device) → kartu dipatok ke ukuran PASTI
              // (referenceWidth-64 x maxCardHeight), lalu seluruh konten
              // di-scale proporsional pakai FittedBox(scaleDown) supaya
              // MUAT PENUH dan TERLIHAT SEKALIGUS tanpa perlu scroll —
              // ikon, judul, teks, dan tombol ikut mengecil bersama secara
              // proporsional, bukan terpotong.
              if (isLandscape) {
                // Batas ruang di DALAM padding kartu (24 kiri+kanan,
                // 32 atas+bawah), tempat cardContent akan di-scale.
                final innerMaxWidth =
                    (referenceWidth - 64) - (cardPaddingH * 2);
                final innerMaxHeight = maxCardHeight - (cardPaddingV * 2);
                return Container(
                  // ═══ TAMBAHAN: TIDAK ada width/height tetap di sini lagi.
                  // Sebelumnya Container dipaksa selebar referenceWidth-64,
                  // padahal FittedBox men-scale konten secara UNIFORM
                  // berdasarkan sisi paling ketat (tinggi, karena konten
                  // aslinya tinggi/portrait-shaped). Hasilnya lebar konten
                  // yang sudah di-scale jadi LEBIH SEMPIT dari kotak yang
                  // dipaksa lebar itu → muncul spasi putih kosong di
                  // kiri-kanan. Dengan menghilangkan width/height tetap,
                  // Container membungkus (shrink-wrap) PERSIS sebesar hasil
                  // scale konten + padding — tidak ada sisa ruang lagi. ═══
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: cardPaddingH, vertical: cardPaddingV),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: innerMaxWidth,
                      maxHeight: innerMaxHeight,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: cardContent,
                    ),
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: cardPaddingH, vertical: cardPaddingV),
                  child: cardContent,
                ),
              );
            })(),
          ),
        ),
      ),
    );
  }
}