# Contextual insight bar

My Day, Fitness, Sleep detail and Stress detail publish small local summaries
from data already loaded for their UI. No new Firestore listeners, background
health syncs, or Claude calls are added by the bar.

The navigation-scoped controller selects the top route and active tab. Dialogs,
unrelated detail pages and other tabs cannot inherit advice from a covered page.
The preview appears after two quiet seconds and collapses during scrolling,
keyboard use, chat and active workouts. Dismissal lasts for the current navigation
session, per screen. The normal robot remains available to open chat.

Expand shows the full message and an Ask Vivordo AI action. That action appends
the context to Panda's composer (preserving any existing draft), rather than
sending it. The existing consent/send flow still controls model requests.

Sleep comparisons require seven valid prior nights when available in the loaded
history. Missing data is disclosed. Stress drivers are described as recorded
contributions, not proven causes. These are deterministic wellness summaries,
not automatically generated model responses.

Device checks: switch tabs, open/pop detail pages and dialogs, scroll, open a
keyboard, expand and dismiss, start a workout, and continue an insight in Panda.
Confirm no advice appears over unrelated content and no network AI request is
made just by opening a screen. Check both themes and large text.
