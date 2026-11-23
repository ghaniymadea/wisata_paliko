import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthGate extends StatelessWidget {
  const SupabaseAuthGate({
    required this.configured,
    required this.authenticatedBuilder,
    super.key,
  });

  final bool configured;
  final WidgetBuilder authenticatedBuilder;

  @override
  Widget build(BuildContext context) {
    if (!configured) return const SupabaseSetupPage();

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessagePage(
            title: 'Autentikasi gagal',
            message: snapshot.error.toString(),
          );
        }
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return const SignInPage();
        return KeyedSubtree(
          key: ValueKey(user.id),
          child: authenticatedBuilder(context),
        );
      },
    );
  }
}

class SupabaseSetupPage extends StatelessWidget {
  const SupabaseSetupPage({super.key});

  @override
  Widget build(BuildContext context) => const _MessagePage(
    title: 'Hubungkan Supabase',
    message: 'Konfigurasi belum tersedia. Jalankan aplikasi dengan --dart-define=SUPABASE_URL=... dan --dart-define=SUPABASE_PUBLISHABLE_KEY=... (atau SUPABASE_ANON_KEY), lalu jalankan supabase/schema.sql di SQL Editor proyek Supabase.',
  );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  bool _passwordVisible = false;
  bool _noticeIsSuccess = false;
  bool _awaitingOtp = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _notice = null;
      _noticeIsSuccess = false;
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (_awaitingOtp) {
        final response = await auth.verifyOTP(
          email: _email.text.trim(),
          token: _otp.text.trim(),
          type: OtpType.signup,
        );
        if (response.session != null && mounted) {
          setState(() {
            _awaitingOtp = false;
            _notice = null;
          });
        }
        return;
      }
      if (_isSignUp) {
        final response = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'nama': _name.text.trim(), 'username': _username.text.trim()},
        );
        if (response.session == null && mounted) {
          setState(() {
            _awaitingOtp = true;
            _noticeIsSuccess = true;
            _notice = 'Kode OTP sudah dikirim ke email Anda. Masukkan kode tersebut untuk mengaktifkan akun.';
          });
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _notice = _friendlyAuthMessage(error));
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } catch (error) {
      // Flutter Web dapat mengembalikan ClientException dari browser_client.dart
      // saat jaringan/Supabase tidak dapat dijangkau. Tampilkan pesan di UI
      // agar exception tidak menjadi unhandled error dan membuat aplikasi crash.
      if (mounted) {
        setState(
          () => _notice =
              'Tidak dapat terhubung ke server. Periksa koneksi internet lalu coba lagi.\n$error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendVerification() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _busy = true;
      _notice = null;
    });

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (mounted) {
        setState(() {
          _noticeIsSuccess = true;
          _notice = 'Kode OTP sudah dikirim ulang. Periksa kotak masuk atau folder Spam.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _notice = _friendlyAuthMessage(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Email verifikasi belum dapat dikirim. Coba lagi beberapa saat.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthMessage(AuthException error) {
    final message = error.message.toLowerCase();
    final code = (error.code ?? '').toLowerCase();

    if (!_isSignUp &&
        (code == 'invalid_credentials' ||
            message.contains('invalid login credentials') ||
            message.contains('invalid credentials'))) {
      return 'Akun belum terdaftar atau email dan kata sandi tidak cocok. Silakan daftar terlebih dahulu jika belum memiliki akun.';
    }

    if (message.contains('email not confirmed') ||
        message.contains('email belum dikonfirmasi')) {
      return 'Email belum dikonfirmasi. Buka email verifikasi dari Luak Explorer, lalu coba masuk kembali.';
    }

    if (message.contains('invalid') &&
        (message.contains('token') || message.contains('otp'))) {
      return 'Kode OTP salah atau sudah kedaluwarsa. Periksa kembali atau kirim ulang kode.';
    }

    if (_isSignUp &&
        (message.contains('already registered') ||
            message.contains('user already exists') ||
            code == 'user_already_exists')) {
      return 'Email ini sudah terdaftar. Silakan masuk menggunakan akun tersebut.';
    }

    if (message.contains('password should be at least') ||
        message.contains('password') && message.contains('weak')) {
      return 'Kata sandi terlalu lemah. Gunakan minimal 8 karakter.';
    }

    return 'Autentikasi gagal. Periksa email dan kata sandi, lalu coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWelcomeBanner(),
                  const SizedBox(height: 18),
                  _buildAuthCard(),
                  const SizedBox(height: 18),
                  const Text(
                    'Jelajahi Payakumbuh & Lima Puluh Kota bersama Luak Explorer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF174B2A), Color(0xFF2E7D4F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -54,
          right: -44,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(15),
              ),
              padding: const EdgeInsets.all(5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/luak_explorer_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'LUAK EXPLORER',
              style: TextStyle(
                color: Color(0xFFD8E9D8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Temukan cerita di setiap perjalanan.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Jelajahi sudut terbaik Ranah Luak.',
              style: TextStyle(color: Color(0xFFE4EEE4), fontSize: 13),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildAuthCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xFFE9EDE5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x101E3A28),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isSignUp ? 'Buat akun penjelajah' : 'Selamat datang kembali',
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _isSignUp
                ? 'Daftar untuk menyimpan tempat dan berbagi cerita.'
                : 'Masuk untuk melanjutkan petualangan Anda.',
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          _buildModeSelector(),
          const SizedBox(height: 20),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_awaitingOtp) ...[
                  _input(
                    controller: _otp,
                    label: 'Kode OTP',
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.password_rounded,
                    validator: (value) {
                      final code = value?.trim() ?? '';
                      if (code.length < 6) return 'Masukkan 6 digit kode OTP';
                      return null;
                    },
                  ),
                ] else ...[
                  if (_isSignUp) ...[
                    _input(
                      controller: _name,
                      label: 'Nama lengkap',
                      autofillHints: const [AutofillHints.name],
                      prefixIcon: Icons.person_outline_rounded,
                      validator: (value) => _required(value, 'Nama'),
                    ),
                    const SizedBox(height: 13),
                    _input(
                      controller: _username,
                      label: 'Username',
                      autofillHints: const [AutofillHints.newUsername],
                      prefixIcon: Icons.alternate_email_rounded,
                      validator: (value) => _required(value, 'Username'),
                    ),
                    const SizedBox(height: 13),
                  ],
                  _input(
                    controller: _email,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    prefixIcon: Icons.mail_outline_rounded,
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty || !email.contains('@')) {
                        return 'Masukkan email yang valid';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 13),
                  _input(
                    controller: _password,
                    label: 'Kata sandi',
                    autofillHints: [
                      _isSignUp
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: !_passwordVisible,
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible
                          ? 'Sembunyikan kata sandi'
                          : 'Tampilkan kata sandi',
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF718096),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').length < 8) {
                        return 'Kata sandi minimal 8 karakter';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _noticeIsSuccess
                    ? const Color(0xFFEAF5EC)
                    : const Color(0xFFFFEFED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _noticeIsSuccess
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _noticeIsSuccess
                        ? const Color(0xFF267344)
                        : const Color(0xFFB42318),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _notice!,
                      style: TextStyle(
                        color: _noticeIsSuccess
                            ? const Color(0xFF205D37)
                            : const Color(0xFFB42318),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_noticeIsSuccess && _isSignUp) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _resendVerification,
                child: const Text('Kirim ulang kode OTP'),
              ),
            ],
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _awaitingOtp
                            ? 'Verifikasi OTP'
                            : (_isSignUp ? 'Buat akun' : 'Masuk'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy || _awaitingOtp
                ? null
                : () => setState(() {
                    _isSignUp = !_isSignUp;
                    _notice = null;
                    _passwordVisible = false;
                  }),
            child: Text(
              _isSignUp
                  ? 'Sudah punya akun? Masuk'
                  : 'Belum punya akun? Daftar',
              style: const TextStyle(
                color: Color(0xFF28613B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildModeSelector() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4EF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        _modeButton('Masuk', isSignUp: false),
        _modeButton('Daftar', isSignUp: true),
      ],
    ),
  );

  Widget _modeButton(String label, {required bool isSignUp}) {
    final selected = _isSignUp == isSignUp;
    return Expanded(
      child: TextButton(
        onPressed: _busy || _awaitingOtp
            ? null
            : () {
                if (_isSignUp == isSignUp) return;
                setState(() {
                  _isSignUp = isSignUp;
                  _notice = null;
                  _passwordVisible = false;
                });
              },
        style: TextButton.styleFrom(
          backgroundColor: selected ? Colors.white : Colors.transparent,
          foregroundColor: selected
              ? const Color(0xFF1B5E20)
              : const Color(0xFF718096),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    IconData? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFFAFBF9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E7DE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E7DE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
        ),
      ),
    );
  }

  String? _required(String? value, String label) =>
      (value?.trim().isEmpty ?? true) ? '$label wajib diisi' : null;
}

class _MessagePage extends StatelessWidget {
  const _MessagePage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Color(0xFF1B5E20),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
