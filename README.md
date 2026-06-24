# Privacy Policy

> **Last updated:** June 23, 2026

Vivordo (“we”, “us”, or “our”) is a wellness app focusing on stress, recovery, and performance. This Privacy Policy explains what personal data we collect, why we collect it, how we use and share it, and how you can control it.

---

## Table of Contents

- [Introduction](#introduction)
- [Data We Collect](#data-we-collect)
- [Purposes of Use](#purposes-of-use)
- [Legal Basis for Processing](#legal-basis-for-processing)
- [Data Storage and Retention](#data-storage-and-retention)
- [Security Measures](#security-measures)
- [Data Sharing and Third Parties](#data-sharing-and-third-parties)
- [User Rights](#user-rights)
- [Children and Minors](#children-and-minors)
- [Not Covered by HIPAA/PHIPA](#not-covered-by-hipaaphipa)
- [Cross-Border Data Transfers](#cross-border-data-transfers)
- [Updates to This Policy](#updates-to-this-policy)
- [Contact](#contact)

---

## Introduction

This policy applies to Vivordo users in the U.S., Canada, and other jurisdictions. By downloading or using Vivordo, you consent to the practices described here and in the app, as required by Apple’s App Store guidelines.

We are **not** a covered health-care provider or insurer, so this policy is not governed by HIPAA or PHIPA, but we treat all health data with strict confidentiality.

📧 **Contact:** vivordoexternal@gmail.com — if you have privacy concerns, please reach out; we will respond promptly.

---

## Data We Collect

Vivordo collects data only to provide and improve the service. We strive for minimal collection and explicit user consent. Our data categories include:

### Account Info
- **Name** and **email address** — used to create your account and authenticate via Firebase Authentication.
- **Password** — stored securely as a hash.
- Email is used for account login, support, and optionally account recovery or notifications (with user consent for marketing emails; you may opt out at any time).

### Device and Usage Data
- Device identifiers (e.g. app-specific user ID, advertising ID if applicable).
- App usage logs (features used, session length, crash reports).
- We use **Firebase Analytics** to improve our app; we only collect aggregated/non-identifiable usage statistics. Firebase may collect device model, OS version, and anonymous analytics data.
- Crash reports and performance metrics help us fix bugs and improve stability.

### Health & Fitness Data
Data from **Apple HealthKit** (only with your explicit permission), including:
- Heart rate (resting/active)
- Heart rate variability (HRV)
- Sleep duration and stages
- Steps and activity
- Recovery scores
- Any derived data (e.g. stress scores)

**Camera/PPG scan data:** If you use our 60-second fingertip scan, Vivordo captures your pulse waveform via the camera’s PPG (photoplethysmography) and computes metrics (heart rate, HRV).

> ⚠️ These measurements are estimates and **not medical-grade**. We do **not** record or store raw camera images — only the calculated metrics. The camera is only used during scanning; we do not video record.

### Behavioral & Context Data
- Data you input in check-ins or journals: mood, stress level, notes on what caused stress, energy level.
- **Calendar events or tasks** (if you sync calendars for availability). Vivordo can connect to your Google or Outlook calendar (with permission) to read event times and titles for generating availability insights. We do **not** write to or modify your calendar.
- **Contacts** (optional, with permission) — used to suggest messaging others. Vivordo never sends messages without your explicit action. If you allow it, we parse your contacts to offer personalized, context-aware conversation prompts, but we do **not** upload your contacts to our servers or share them with third parties.

### AI Interaction Data
- Any text or voice you submit to the AI conversational assistant, and the assistant’s responses (for personalization and memory).
- These interactions are used to improve your insights and may be logged on our servers to train the AI model and improve the service.

### Other Data
- Push notification tokens (to send you alerts/reminders).
- Data from third-party integration APIs (e.g. Garmin, Oura, Whoop) if connected in the future.

> Any additional data requests will be transparently disclosed and optional.

---

## Purposes of Use

We use your data for core app functionality and personalization. Key uses include:

| Purpose | Description |
| --- | --- |
| **App Functionality & UX** | Authenticate you, maintain your account, enable features (dashboard, check-ins), and personalize content. Your name/email is only used for account management and communication. |
| **Stress & Recovery Analysis** | Process physiological and behavioral data to compute stress scores, availability predictions, and recovery insights — e.g. correlating HRV and sleep data with self-reported stress to generate a **Personal Stress Fingerprint**. This is the core value proposition of Vivordo. |
| **Communications & Reminders** | Generate suggested messages (e.g. to reschedule a meeting when stressed) if you enable messaging integration. Calendar events are read-only and used solely to estimate workload and availability. Notifications are only sent if you’ve opted in. |
| **AI Assistant** | Uses your data (stress history, journals, etc.) to generate advice and prompts. The model is third-party (e.g. an LLM) hosted via secure APIs. We never share personal health data with the AI beyond what’s needed for each prompt. |
| **Improvement & Research** | Use anonymized or aggregated data (direct identifiers removed) to analyze performance, improve algorithms, and develop features. |
| **Legal Compliance & Safety** | Retain minimal data for security, fraud prevention, legal requests, or to defend against legal claims, in accordance with the law. |

> We do **not** sell or trade personal data for marketing. Interest-based communications (e.g. new feature emails) are sent only with consent, and you can opt out of all marketing.

---

## Legal Basis for Processing

Although Vivordo is targeted at U.S. and Canadian users, for best practices we treat processing of health and personal data as requiring user consent.

- **Consent** — We obtain clear consent before collecting sensitive data (health metrics, contacts, calendars, etc.). You can revoke this consent at any time in app settings. Push notifications and analytics are requested separately with opt-out options.
- **Contract (Performance)** — Once you sign up, we rely on fulfilling our service agreement to process necessary data (email for account, physiological data for stress analysis).
- **Legitimate Interest** — For non-sensitive data (analytics, security logging), we rely on our legitimate interest in maintaining and securing the app, ensuring use is proportionate and not detrimental to you.

We comply with **GDPR / CCPA / CPRA** principles: we do not sell data. California residents have rights to access or delete data, and we honor those. Canadian users fall under **PIPEDA** (and applicable provincial laws), which require limited collection, clear purpose, accuracy, safeguards, openness, and individual access.

---

## Data Storage and Retention

We store user data in secure, encrypted databases on servers located in the U.S. (via Google Firebase/Cloud and Apple Cloud for HealthKit if used). Data is encrypted in transit (TLS) and at rest. Only authorized personnel and automated systems have access.

### Retention Periods
We retain your personal and health data only as long as needed for service, compliance, or legal reasons. By default, we keep active user data until you delete your account. After account deletion, we may retain residual data (for fraud prevention or legal defense).

#### Retention Schedule

| Data Category | Retention Period |
| --- | --- |
| Security / fraud logs | 1–3 years _(recommended)_ |
| Account & health data | Until account deletion |
| Residual post-deletion data | Up to **X** years _(to be finalized)_ |

> 📝 _Placeholder values above (`X` years) should be confirmed before publishing._

### Deletion
You can request immediate deletion of your account and all personal data via the app or by contacting **vivordo-support@vivordo.com**. We will delete it promptly from our servers and inform you when complete.

> Note: any data you have shared with connected services (e.g. forwarded messages) may not be retractable.

---

## Security Measures

Vivordo uses industry-standard security:

- HTTPS for all communication
- Encryption of sensitive data (health metrics) at rest
- Secure authentication (Firebase Auth with hashed passwords or OAuth tokens)
- Regular security audits and patching

While no system is 100% secure, we use best practices (SSL/TLS, secure coding, restricted access) to protect user data.

---

## Data Sharing and Third Parties

**Vivordo does not sell your data.** We share personal data only as follows:

- **With Your Consent** — For connected integrations (Apple HealthKit, Google Calendar), we read data only with your permission. We never write back to HealthKit or other apps except with explicit opt-in. For third-party integrations (Garmin, Oura, etc.), we only import data; we do not send your data to them.
- **Service Providers** — We use vendors like Google (Firebase) for authentication, database, and analytics, and secure AI (LLM) services for chat responses. Providers handle data under confidentiality agreements and only for the specified purpose.
- **Legal Requirements** — We may disclose data if required by law (court order, legal process) or to protect rights (fraud investigation, etc.).
- **Aggregate / Anonymized Data** — We may share aggregate statistics (e.g. average stress levels across users) for research or marketing; this data has no identifiers.

---

## User Rights

We follow **PIPEDA / CCPA** principles on user rights. Vivordo users can:

- **Access** — Request a copy of all personal information we hold.
- **Correction** — Request corrections of inaccurate data.
- **Deletion** — Delete their account and personal data (right to be forgotten).
- **Data Portability** — Export health and journal data (CSV/JSON) via the app.
- **Opt-out** — Object to future processing (revoke Apple Health permissions, disable AI insights) or opt out of marketing emails.

To exercise these rights, contact **vivordo-support@vivordo.com**. We will respond as required by law (typically within 30 days).

---

## Children and Minors

Vivordo is not intended for children under 13 (or the age of digital consent in your jurisdiction). We do not knowingly collect personal data from anyone under 13. If we become aware of such data, we will delete it. Minors (13–17) should use the app with parental consent.

---

## Not Covered by HIPAA/PHIPA

Vivordo is not a healthcare provider, clinic, or insurance company. We are not subject to **HIPAA** (U.S.) or **PHIPA** (Ontario) regulations. Nevertheless, we protect health data with similar care.

> Vivordo’s content (AI insights, stress metrics) is **not medical advice** and should not replace professional medical or mental-health consultation.

---

## Cross-Border Data Transfers

Your data may be transferred to and stored in the United States (where our servers and Apple/Google cloud are located). We comply with legal safeguards for international transfers (e.g. standard contractual clauses as needed). Canadian users should note their data crosses borders but is protected by the same privacy principles.

---

## Updates to This Policy

We may update this policy as Vivordo evolves or laws change. Material changes will be posted here with a new “last updated” date and notified in-app or via email.

---

## Contact

| Purpose | Email |
| --- | --- |
| General / privacy concerns | vivordoexternal@gmail.com |
| Support, deletion & data requests | vivordo-support@vivordo.com |
