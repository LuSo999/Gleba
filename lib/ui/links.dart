import 'package:url_launcher/url_launcher.dart';

const privacyUrl = 'https://gleba-e9a60.web.app/privacy.html';
const supportEmail = 'lubomirsoustruznik@email.cz';

Future<void> openPrivacyPolicy() => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication);

/// Google Play's AI-generated content policy: let people flag a bad answer.
Future<void> reportAiAnswer(String answer) => launchUrl(Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=${Uri.encodeComponent('Gleba – nahlášení odpovědi AI')}'
          '&body=${Uri.encodeComponent('Co je na odpovědi špatně:\n\n\n---\n${answer.length > 1500 ? answer.substring(0, 1500) : answer}')}',
    ));
