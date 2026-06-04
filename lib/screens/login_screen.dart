import 'package:docs_clone_flutter/colors.dart';
import 'package:docs_clone_flutter/repository/auth_repository.dart';
import 'package:docs_clone_flutter/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:routemaster/routemaster.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;

  void signInWithGoogle(BuildContext context) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    final sMessenger = ScaffoldMessenger.of(context);
    final navigator = Routemaster.of(context);
    final authRepository = ref.read(authRepositoryProvider);
    final userNotifier = ref.read(userProvider.notifier);

    final errorModel = await authRepository.signInWithGoogle();
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    if (errorModel.error == null) {
      userNotifier.update((state) => errorModel.data);
      navigator.replace('/');
    } else {
      sMessenger.showSnackBar(
        SnackBar(
          content: Text(errorModel.error!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : () => signInWithGoogle(context),
          icon: _isLoading 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Image.asset(
                  'assets/images/g-logo-2.png',
                  height: 20,
                ),
          label: Text(
            _isLoading ? 'Signing in...' : 'Sign in with Google',
            style: const TextStyle(
              color: kBlackColor,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: kWhiteColor,
            minimumSize: const Size(150, 50),
          ),
        ),
      ),
    );
  }
}
