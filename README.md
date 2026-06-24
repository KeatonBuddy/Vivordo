Privacy Policy
Last updated: June 23, 2026
Introduction
Vivordo (“we”, “us”, or “our”) is a wellness app focusing on stress, recovery, and performance.
This Privacy Policy explains what personal data we collect, why we collect it, how we use and
share it, and how you can control it. It applies to Vivordo users in the U.S., Canada, and other
jurisdictions. By downloading or using Vivordo, you consent to the practices described here and
in the app, as required by Apple’s App Store guidelines. We are not a covered health-care
provider or insurer, so this policy is not governed by HIPAA or PHIPA, but we treat all health
data with strict confidentiality.
Contact us: vivordoexternal@gmail.com. If you have privacy concerns, please reach out; we will
respond promptly.
Data We Collect
Vivordo collects data only to provide and improve the service. We strive for minimal collection
and explicit user consent. Our data categories include:
Account Info: Name, email address (used to create your account and authenticate via Firebase
Authentication), password (stored securely as a hash). Email is used for account login, support,
and optionally account recovery or notifications (with user consent for marketing emails; you
may opt out at any time).
Device and Usage Data: Device identifiers (e.g. app-specific user ID, advertising ID if
applicable) and app usage logs (features used, session length, crash reports). We use Firebase
Analytics to improve our app; we only collect aggregated/non-identifiable usage statistics.
Firebase may collect device model, OS version, and anonymous analytics data. Crash reports
and performance metrics help us fix bugs and improve stability.
Health & Fitness Data: Data from Apple HealthKit (only with your explicit permission). This
includes heart rate (resting/active), heart rate variability (HRV), sleep duration and stages, steps
and activity, and recovery scores. It also includes any data derived from these (e.g. stress
scores). Camera/PPG scan data: If you use our 60-second fingertip scan, Vivordo captures your
pulse waveform via the camera’s PPG (photoplethysmography) and computes metrics (heart
rate, HRV). These measurements are estimates and not medical-grade. We do not record or
store raw camera images; only the calculated metrics. The camera is only used during
scanning; we do not video record.
Behavioral & Context Data: Data you input in check-ins or journals, such as mood, stress level,
notes on what caused stress, energy level, and your calendar events or tasks (if you sync
calendars for availability). Vivordo can connect to your Google or Outlook calendar (with
permission) to read event times and titles for generating availability insights (we do not write to
or modify your calendar). We may optionally use your contacts (with permission) to suggest
messaging others (Vivordo never sends messages without your explicit action). If you allow it,
we parse your contacts to offer personalized, context-aware conversation prompts or
communication suggestions, but we do not upload your contacts to our servers or share them
with third parties.
AI Interaction Data: Any text or voice you submit to the AI conversational assistant, and the
assistant’s responses (for personalization and memory). These interactions are used to improve
your insights and may be logged on our servers to train the AI model and improve the service.
Other Data: Push notification tokens (to send you alerts/reminders), and any data from third-
party integration APIs (e.g. Garmin, Oura, Whoop) if connected in the future. Any additional data
requests will be transparently disclosed and optional.
Purposes of Use
We use your data for core app functionality and personalization. Key uses include:
App Functionality & User Experience: To authenticate you, maintain your account, enable
features (e.g. dashboard, check-ins), and personalize content (e.g. showing your own stress
trends, providing targeted tips). Your name/email is only used for account management and
communication (e.g. service updates or support responses).
Stress and Recovery Analysis: We process your physiological and behavioral data to compute
stress scores, availability predictions, and recovery insights. For example, we correlate your
HRV and sleep data with self-reported stress to generate a Personal Stress Fingerprint. This is
the core value proposition of Vivordo. All processing happens on our servers: we translate
signals into actionable guidance.
Communications & Reminders: If you enable messaging integration, we generate suggested
messages (e.g. to reschedule a meeting when you’re stressed). If you allow it, we will parse
your email/calendar/text to contextually suggest phrasing, but only with your consent and
always locally on device or through secure cloud processing with minimal data. We use your
calendar events (read-only) solely to estimate workload and availability; we do not upload
calendar details to third parties. Notifications (for check-ins or reminders) are only sent if you’ve
opted in.
AI Assistant: Vivordo’s AI assistant uses your data (stress history, journals, etc.) to generate
advice and prompts. You can choose to ask it questions or let it proactively check in with you.
The AI model itself is third-party (e.g. an LLM) but hosted via secure APIs. We never share your
personal health data with the AI beyond what’s needed for each prompt. Responses are meant
for informational use only; see Disclaimers below.
Improvement and Research: We use anonymized or aggregated data (with direct identifiers
removed) to analyze app performance, improve algorithms, and develop new features. For
example, we might use aggregate HRV and sleep data trends to refine our stress detection
models. We do not sell or trade personal data for marketing. We may use some data for
interest-based communications (e.g. emailing you about new Vivordo features) only if you
consent, but you can opt out of all marketing.
Legal Compliance and Safety: To comply with laws and protect users (e.g., storing some logs
for security, fraud prevention, or legal requests). We may retain minimal data to defend against
legal claims or law enforcement requests, in accordance with the law.
Legal Basis for Processing (Consent, Legitimate Interest)
Although Vivordo is targeted at U.S. and Canadian users (where GDPR-like law doesn’t strictly
apply), for best practices we treat processing health and personal data as requiring user
consent.
Consent: We obtain clear consent before collecting sensitive data (health metrics, contacts,
calendars, etc.). You can revoke this consent at any time in app settings (for example,
disconnect Apple HealthKit or calendar access). For push notifications and analytics, we ask
separately and give opt-out options.
Contract (Performance): Once you sign up, we rely on fulfilling our service agreement as a
contractual basis to process necessary data (email for account, physiological data for stress
analysis).
Legitimate Interest: For non-sensitive data (e.g. analytics for app improvements, security
logging), we rely on our legitimate interest in maintaining and securing the app. We ensure such
use is proportionate and not detrimental to you.
We comply with GDPR/CCPA/CPRA principles for users concerned with privacy: we do not sell
data (no “sale” of personal info). California residents have rights to access or delete data, and
we honor those. Canadian users fall under PIPEDA (and applicable provincial laws) which
require limited collection, clear purpose, accuracy, safeguards, openness, and individual
access. Vivordo’s practices are designed to meet these principles.
Data Storage and Retention
We store user data in secure, encrypted databases on servers located in the U.S. (via Google
Firebase/Cloud and Apple Cloud for HealthKit if used). Data is encrypted in transit (TLS) and at
rest. Only authorized personnel and the automated systems have access.
Retention Periods: We retain your personal and health data only as long as needed for service,
compliance, or legal reasons. By default, we keep active user data until you delete your
account. After account deletion, we may retain residual data (for fraud prevention or legal
defense) for up to X years (we suggest typically 1–3 years for security logs, otherwise delete
fully). See the Retention Schedule table below for recommended durations.
Deletion: You can request immediate deletion of your account and all personal data via the app
or by contacting us (vivordo-support@vivordo.com). We will delete it promptly from our servers
and inform you when complete. Note that any data you have shared with connected services
(e.g. forwarded messages) may not be retractable.
Security Measures
Vivordo uses industry-standard security: HTTPS for all communication, encryption of sensitive
data (health metrics) at rest, and secure authentication (Firebase Auth with hashed passwords
or OAuth tokens). We regularly audit our security and apply patches. While no system is 100%
secure, we use best practices (SSL/TLS, secure coding, restricted access) to protect user data.
Data Sharing and Third Parties
Vivordo does not sell your data. We share personal data only as follows:
With Your Consent: For connected integrations, such as Apple HealthKit or Google Calendar,
we read data from these sources only with your permission. We never write back to HealthKit or
other apps except with explicit opt-in. If you enable any third-party integration (Garmin, Oura,
etc.), we only import data from those services; we do not send your data to them (except
possibly email if you choose to export).
Service Providers: We use third-party vendors like Google (Firebase) for authentication,
database, and analytics. These providers handle data on our behalf under confidentiality
agreements. We also use secure AI (LLM) services for chat responses, but we feed only the
data you consent to provide for each session. Any such provider abides by our privacy
standards and only processes the data for the specified purpose.
Legal Requirements: We may disclose data if required by law (court order, legal process) or to
protect rights (investigation of fraud, etc.).
Aggregate/Anonymized Data: We may share aggregate statistics (e.g. average stress levels
across users) for research or marketing, but this data has no identifiers.
User Rights (Access, Correction, Deletion)
We follow PIPEDA/CCPA principles on user rights. Vivordo users can:
Access: Request a copy of all personal information we hold about them.
Correction: Request corrections of any inaccurate data in their profile or collected data.
Deletion: Delete their account and personal data (right to be forgotten).
Data Portability: Export their health and journal data (in CSV/JSON format) via the app.
Opt-out: Object to future processing (e.g. revoke Apple Health permissions, disable AI insights),
or opt-out of marketing emails (unsubscribe link).
To exercise these rights, contact vivordo-support@vivordo.com. We will respond as required by
law (typically within 30 days).
Children and Minors
Vivordo is not intended for children under 13 (or the age of digital consent in your jurisdiction).
We do not knowingly collect personal data from anyone under 13. If we become aware of such
data, we will delete it. Minors (13-17) should use the app with parental consent.
Not Covered by HIPAA/PHIPA
Vivordo is not a healthcare provider, clinic, or insurance company. We are not subject to HIPAA
(U.S.) or PHIPA (Ontario) regulations. Nevertheless, we protect health data with similar care.
Vivordo’s content (AI insights, stress metrics) is not medical advice and should not replace
professional medical or mental-health consultation.
Cross-Border Data Transfers
Your data may be transferred to and stored in the United States (where our servers and
Apple/Google cloud are located). We comply with legal safeguards for international transfers
(e.g. standard contractual clauses as needed). Canadian users should note their data crosses
borders but is protected by the same privacy principles.
Updates to This Policy
We may update this policy as Vivordo evolves or laws change. Material changes will be posted
here with a new “last updated” date and notified in-app or via email.
