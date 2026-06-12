import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _motivationCtrl = TextEditingController();
  String _selectedClass = 'Kelas 7';
  String? _photoPath;
  bool _isLoading = false;

  // STEP 0: Snapshot nilai awal saat halaman dibuka.
  // Dipakai untuk membandingkan apakah user mengubah sesuatu (_hasChanges()).
  String _initialName = '';
  String _initialClass = 'Kelas 7';
  String _initialMotivation = '';
  String? _initialPhoto;

  final List<String> _classes = ['Kelas 7', 'Kelas 8', 'Kelas 9'];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  // STEP 1: Load data dari SharedPreferences, lalu simpan juga
  // sebagai "snapshot awal" untuk deteksi perubahan nanti.
  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('user_name') ?? '';
      _selectedClass = prefs.getString('user_class') ?? 'Kelas 7';
      _motivationCtrl.text = prefs.getString('user_motivation') ?? '';
      _photoPath = prefs.getString('user_photo');

      _initialName = _nameCtrl.text;
      _initialClass = _selectedClass;
      _initialMotivation = _motivationCtrl.text;
      _initialPhoto = _photoPath;
    });
  }

  /// Ubah "  budi   santoso " -> "Budi Santoso"
  String _toTitleCase(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return trimmed;
    return trimmed.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  // STEP 2: Bandingkan kondisi sekarang vs snapshot awal.
  // Dipakai oleh tombol back untuk memutuskan perlu dialog konfirmasi atau tidak.
  bool _hasChanges() {
    return _nameCtrl.text.trim() != _initialName.trim() ||
        _selectedClass != _initialClass ||
        _motivationCtrl.text.trim() != _initialMotivation.trim() ||
        _photoPath != _initialPhoto;
  }

  // STEP 3: Dipanggil saat tombol back (arrow / fisik) ditekan.
  // - Jika tidak ada perubahan -> langsung keluar.
  // - Jika ada perubahan -> tampilkan dialog konfirmasi "Buang Perubahan?".
  Future<void> _onBackPressed() async {
    if (!_hasChanges()) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Column(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.redAccent, size: 40),
            const SizedBox(height: 8),
            Text(
              'Perubahan Belum Disimpan',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Kamu mengubah data profil tapi belum menyimpannya. Yakin ingin keluar tanpa menyimpan?',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Lanjut Edit',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Buang',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.pop(context);
    }
  }

  /// Copy file foto ke direktori permanen aplikasi supaya tidak hilang
  /// saat cache dibersihkan oleh OS.
  Future<String> _persistPhoto(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.split('.').last;
    final fileName = 'profile_photo.$ext';
    final newPath = '${appDir.path}/$fileName';

    final dir = Directory(appDir.path);
    final existing = dir
        .listSync()
        .where((f) => f.path.contains('profile_photo'))
        .toList();
    for (final f in existing) {
      try {
        await File(f.path).delete();
      } catch (_) {}
    }

    final newFile = await File(sourcePath).copy(newPath);
    return newFile.path;
  }

  Future<void> _pickPhoto() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFFFFC107)),
              title: Text('Ambil Foto', style: GoogleFonts.poppins()),
              onTap: () async {
                Navigator.pop(context);
                final picked = await ImagePicker().pickImage(
                  source: ImageSource.camera,
                  imageQuality: 80,
                );
                if (picked != null) {
                  setState(() => _photoPath = picked.path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFFFFC107)),
              title: Text('Pilih dari Galeri', style: GoogleFonts.poppins()),
              onTap: () async {
                Navigator.pop(context);
                final picked = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                );
                if (picked != null) {
                  setState(() => _photoPath = picked.path);
                }
              },
            ),
            if (_photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: Text('Hapus Foto',
                    style: GoogleFonts.poppins(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _photoPath = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final nameInput = _nameCtrl.text.trim();
    if (nameInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nama tidak boleh kosong!',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('user_name', _toTitleCase(nameInput));
    await prefs.setString('user_class', _selectedClass);
    await prefs.setString('user_motivation', _motivationCtrl.text.trim());

    if (_photoPath != null) {
      String finalPath = _photoPath!;
      if (!finalPath.contains('profile_photo')) {
        finalPath = await _persistPhoto(finalPath);
      }
      await prefs.setString('user_photo', finalPath);
    } else {
      await prefs.remove('user_photo');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profil berhasil disimpan!',
            style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFFFFC107),
      ),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _motivationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // STEP 4: Bungkus Scaffold dengan PopScope agar tombol back fisik
    // (Android) juga memicu _onBackPressed, bukan langsung keluar tanpa cek.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            // STEP 5: Tombol back di AppBar memicu pengecekan perubahan juga.
            onPressed: _onBackPressed,
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Color(0xFF1A1A2E)),
          ),
          title: Text(
            'Edit Profil',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Foto
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: const Color(0xFFFFF3CD),
                        backgroundImage: _photoPath != null
                            ? FileImage(File(_photoPath!))
                            : null,
                        child: _photoPath == null
                            ? const Icon(Icons.person_rounded,
                                size: 52, color: Color(0xFFFFC107))
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFC107),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Ketuk untuk ubah foto',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[400],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Nama
              _label('Nama Panggilan'),
              const SizedBox(height: 8),
              _textField(controller: _nameCtrl, hint: 'Masukkan nama...'),
              const SizedBox(height: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _nameCtrl,
                builder: (_, value, __) {
                  final preview = _toTitleCase(value.text);
                  if (preview.isEmpty) return const SizedBox.shrink();
                  return Text(
                    'Akan tersimpan sebagai: $preview',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Kelas — STEP 6: diganti dari DropdownButton menjadi
              // chip/segmented selector karena cuma 3 pilihan dan
              // lebih sesuai tema kuning-rounded + target usia SMP.
              _label('Kelas'),
              const SizedBox(height: 8),
              Row(
                children: _classes.map((c) {
                  final isSelected = c == _selectedClass;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: c == _classes.last ? 0 : 8,
                      ),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedClass = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFFFC107)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFFFC107)
                                  : Colors.grey[200]!,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            c,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Motivasi
              _label('Motivasi Diri'),
              const SizedBox(height: 8),
              _textField(
                controller: _motivationCtrl,
                hint: 'Kurangi Game, Fokus Sekolah!',
                maxLines: 2,
              ),
              const SizedBox(height: 6),
              Text(
                '*Akan muncul di halaman profil sebagai pengingat.',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 40),

              // Tombol Simpan (tombol Batal sengaja tidak ada —
              // back arrow sudah menangani pembatalan via dialog konfirmasi)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Simpan Perubahan',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF1A1A2E),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.poppins(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}