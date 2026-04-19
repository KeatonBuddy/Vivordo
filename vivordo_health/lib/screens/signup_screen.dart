import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/services/user_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final PageController _pageController = PageController();
  final _formKey = GlobalKey<FormState>();

  int _currentPage = 0;
  final int _totalQuestions = 15;
  bool _isLoading = false; // prevents double-tap triggering emailSignup twice

  // Centralized data map for future database integration
  final Map<String, dynamic> _userData = {'responses': <String, dynamic>{}};

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  // For show/hide password
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _isCurrentQuestionAnswered() {
    if (_currentPage == 0) return true; // Handled by Form validation
    if (_currentPage > _totalQuestions) return true; // Thank you slide

    String key = "q$_currentPage";
    return _userData['responses'].containsKey(key) &&
        _userData['responses'][key] != null;
  }

  Future<void> _nextPage() async {
    //TODO: Consider case where user signs up but exists before questionare is completed
    if (_currentPage == 0) {
      if (_formKey.currentState!.validate()) {
        if (_passController.text != _confirmPassController.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Passwords do not match"),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        // Guard against double-tap: if already loading, do nothing.
        // Without this, tapping the button twice calls createUserWithEmailAndPassword
        // twice with the same email — the second call returns email-already-in-use
        // even though the email is brand new.
        if (_isLoading) return;
        setState(() => _isLoading = true);
        await AuthService.emailSignup(
          emailAddress: _emailController.text,
          password: _passController.text,
          displayName: _nameController.text,
          context: context,
          pageController: _pageController,
        );
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (_currentPage == _totalQuestions) {
        _submitQuestionnaire().then((_) {
          if (mounted) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubicEmphasized,
            );
          }
        });
      } else {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubicEmphasized, // Smoother animation
        );
      }
    }
  }

  Future<void> _submitQuestionnaire() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await UserService.submitQuestionnaire(
          user: user,
          userdata: _userData,
        );
      }
    } catch (e) {
      debugPrint("Error submitting questionnaire: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to submit assessment: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double progress = _currentPage == 0 
        ? 0.5 
        : (_currentPage > _totalQuestions ? 1.0 : _currentPage / _totalQuestions);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F7FF),
      appBar: AppBar(
        leading: _currentPage > 0
            ? BackButton(
                color: const Color(0xFF6B4EFF),
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                ),
              )
            : const BackButton(color: Color(0xFF6B4EFF)),
        title: Text(
          _currentPage == 0 ? "Create Account" : "Well-Being Assessment",
          style: const TextStyle(
            color: Color(0xFF333333),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Progress Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _currentPage == 0 
                        ? "Step 1 of 2" 
                        : (_currentPage > _totalQuestions ? "Assessment Complete" : "Question $_currentPage of 15"), 
                      style: const TextStyle(color: Colors.grey)
                    ),
                    Text(
                      _currentPage == 0 
                        ? "Account Setup" 
                        : (_currentPage > _totalQuestions ? "100% Complete" : "${(progress * 100).toInt()}% Complete"), 
                      style: const TextStyle(color: Color(0xFF9E8DFF), fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFFE0E0E0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.black,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _currentPage = page),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAccountSetup(), // Page 0
                _buildSliderQuestion(
                  "How would you rate your current work stress level?",
                  "q1",
                ),
                _buildMultipleChoiceQuestion(
                  "How many hours of sleep do you typically get per night?",
                  ["Less than 5", "5-6", "6-7", "7-8", "More than 8"],
                  "q2",
                ),
                _buildMultipleChoiceQuestion(
                  "How active are you on a typical day?",
                  [
                    "Sedentary",
                    "Lightly active",
                    "Moderately active",
                    "Very active",
                    "Extremely active",
                  ],
                  "q3",
                ),
                _buildSliderQuestion(
                  "How would you describe your emotional state lately?",
                  "q4",
                ),
                _buildSliderQuestion(
                  "How connected do you feel to your social circle?",
                  "q5",
                ),
                _buildSliderQuestion(
                  "How would you rate your ability to focus?",
                  "q6",
                ),
                _buildMultipleChoiceQuestion(
                  "How often do you take breaks during work?",
                  [
                    "Rarely",
                    "Once per day",
                    "Few times per day",
                    "Every hour",
                    "Very frequently",
                  ],
                  "q7",
                ),
                _buildMultipleChoiceQuestion(
                  "Do you have a regular meditation or mindfulness practice?",
                  ["Never", "Rarely", "Sometimes", "Often", "Daily"],
                  "q8",
                ),
                _buildSliderQuestion("How balanced does your diet feel?", "q9"),
                _buildMultipleChoiceQuestion(
                  "How often do you exercise per week?",
                  ["Never", "1-2 times", "3-4 times", "5-6 times", "Daily"],
                  "q10",
                ),
                _buildSliderQuestion(
                  "How would you rate your overall energy levels?",
                  "q11",
                ),
                _buildSliderQuestion(
                  "Do you feel overwhelmed by daily responsibilities?",
                  "q12",
                ),
                _buildMultipleChoiceQuestion(
                  "How much time do you spend on screens daily?",
                  ["Less than 2h", "2-4h", "4-6h", "6-8h", "8h+"],
                  "q13",
                ),
                _buildSliderQuestion(
                  "How supported do you feel by friends and family?",
                  "q14",
                ),
                _buildSliderQuestion(
                  "How would you rate your overall life satisfaction?",
                  "q15",
                ),
                _buildThankYouSlide(),
              ],
            ),
          ),

          // Action Button
          if (_currentPage <= _totalQuestions)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isCurrentQuestionAnswered() && !_isLoading) ? _nextPage : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C69EF),
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _currentPage == 0
                              ? "Continue to Stress Questionnaire"
                              : "Next",
                          style: TextStyle(
                            color: _isCurrentQuestionAnswered()
                                ? Colors.white
                                : Colors.grey.shade500,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Widgets ---

  Widget _buildAccountSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
            ],
          ),
          child: Column(
            children: [
              _buildField(
                "Full Name",
                _nameController,
                Icons.person_outline,
                "First Last",
              ),
              _buildField(
                "Email",
                _emailController,
                Icons.email_outlined,
                "you@example.com",
              ),
              _buildField(
                "Password",
                _passController,
                Icons.lock_outline,
                "********",
                isPass: true,
              ),
              _buildField(
                "Confirm Password",
                _confirmPassController,
                Icons.lock_outline,
                "********",
                isPass: true,
              ),
              const SizedBox(height: 10),
              _buildSecurityNotice(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    bool isPass = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Color(0xFF444444),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrl,
            obscureText: isPass
                ? (label == "Password" ? !_showPassword : !_showConfirmPassword)
                : false,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              // Show/hide password toggle
              suffixIcon: isPass
                  ? IconButton(
                      icon: Icon(
                        (label == "Password"
                                ? _showPassword
                                : _showConfirmPassword)
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          if (label == "Password") {
                            _showPassword = !_showPassword;
                          } else {
                            _showConfirmPassword = !_showConfirmPassword;
                          }
                        });
                      },
                    )
                  : null,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return "Field required";
              if (label == "Email" &&
                  !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                return "Invalid email";
              }
              if (isPass && v.length < 6) return "Min 6 characters";
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_reset_outlined, color: Color(0xFF9E8DFF)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Your data is secure. We encrypt all information using industry-standard protocols.",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderQuestion(String title, String key) {
    double? val = _userData['responses'][key];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 50),
          Slider(
            value: val ?? 5.0,
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: val == null ? Colors.grey : const Color(0xFF7C69EF),
            onChanged: (newVal) =>
                setState(() => _userData['responses'][key] = newVal),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text("1 (Low)"), Text("10 (High)")],
          ),
          if (val != null)
            Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.all(15),
              decoration: const BoxDecoration(
                color: Color(0xFFF3EFFF),
                shape: BoxShape.circle,
              ),
              child: Text(
                val.toInt().toString(),
                style: const TextStyle(
                  fontSize: 20,
                  color: Color(0xFF7C69EF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceQuestion(
    String title,
    List<String> options,
    String key,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 30),
          ...options.map(
            (opt) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _userData['responses'][key] == opt
                      ? const Color(0xFF7C69EF)
                      : Colors.transparent,
                ),
              ),
              child: RadioListTile(
                title: Text(opt),
                value: opt,
                groupValue: _userData['responses'][key],
                onChanged: (val) =>
                    setState(() => _userData['responses'][key] = val),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThankYouSlide() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 80,
          color: Color(0xFF7C69EF),
        ),
        const SizedBox(height: 20),
        const Text(
          "Thank