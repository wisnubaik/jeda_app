import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class GatekeeperScreen extends StatefulWidget {
  const GatekeeperScreen({super.key});

  @override
  State<GatekeeperScreen> createState() => _GatekeeperScreenState();
}

class _GatekeeperScreenState extends State<GatekeeperScreen> {
  final _nameCtrl = TextEditingController();
  String? _photoPath;
  bool _isLoading = false;

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _photoPath = picked.path);
    }
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
    await prefs.setBool('is_onboarded', true);
    if (_photoPath != null) {
      await prefs.setString('user_photo', _photoPath!);
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/permission');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Sun icon kecil di atas
              const Icon(
                Icons.wb_sunny_rounded,
                color: Color(0xFFFFC107),
                size: 32,
              ),
              const SizedBox(height: 48),

              // Foto
              GestureDetector(
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
                          ? const Icon(
                              Icons.person_rounded,
                              size: 52,
                              color: Color(0xFFFFC107),
                            )
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
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Label
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Siapa nama panggilanmu?',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Input nama
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.poppins(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Ketik namamu...',
                  hintStyle:
                      GoogleFonts.poppins(color: Colors.grey[400]),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 80),

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
                      ? const CircularProgressIndicator(
                          color: Colors.white)
                      : Text(
                          'Simpan Profil',
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
}