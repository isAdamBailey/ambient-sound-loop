/// The privacy policy link. App Store guideline 5.1.1(i) wants it reachable
/// in the app; the policy itself lives on the site (`site/privacy/`).
library;

import 'package:url_launcher/url_launcher.dart';

final privacyPolicyUrl = Uri.parse('https://humspan.adambailey.io/privacy/');

/// Opens the policy in the system browser. The app makes no request itself.
Future<void> openPrivacyPolicy() async {
  await launchUrl(privacyPolicyUrl, mode: LaunchMode.externalApplication);
}
