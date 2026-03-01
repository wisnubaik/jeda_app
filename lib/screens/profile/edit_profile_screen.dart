import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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

  final List<String> _classes = ['Kelas 7', 'Kelas 8', 'Kelas 9'];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('user_name') ?? '';
      _selectedClass = prefs.getString('user_class') ?? 'Kelas 7';
      _motivationCtrl.text = prefs.getString('user_motivation') ?? '';
      _photoPath = prefs.getString('user_photo');
    });
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) setState(() => _photoPath = picked.path);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
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
    await prefs.setString('user_name', _nameCtrl.text.trim());
    await prefs.setString('user_class', _selectedClass);
    await prefs.setString('user_motivation', _motivationCtrl.text.trim());
    if (_photoPath != null) {
      await prefs.setString('user_photo', _photoPath!);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
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
            const SizedBox(height: 32),

            // Nama
            _label('Nama Panggilan'),
            const SizedBox(height: 8),
            _textField(controller: _nameCtrl, hint: 'Masukkan nama...'),
            const SizedBox(height: 20),

            // Kelas
            _label('Kelas'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedClass,
                  isExpanded: true,
                  style: GoogleFonts.poppins(
                      fontSize: 15, color: const Color(0xFF1A1A2E)),
                  items: _classes
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedClass = v!),
                ),
              ),
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

            // Tombol
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
                    ? const CircularProgressIndicator(color: Colors.white)
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