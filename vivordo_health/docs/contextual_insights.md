# Contextual insight bar

My Day, Fitness, Sleep detail and Stress detail publish small local summaries
from data already loaded for their UI. No new Firestore listeners, background
health syncs, or Claude calls are added by the bar.

The navigation-scoped controller selects the top route and active tab. Dialogs,
unrelated detail pages and other tabs cannot inherit advice from a covered page.
The preview appears after two seconds and stays wide during scrolling. It
collapses during keyboard use, chat and active workouts. Dismissal lasts for
the current screen visit; leaving and returning restores it. The normal robot
remains available to open chat.

Expand shows the full message and an Ask Vivordo AI action. On My Day, that
action opens a local planning introduction with prioritize, break and schedule
suggestions. It leaves the composer untouched (empty unless a draft exists)
and supplies the screen summary as contextual data on subsequent user sends.
A new My Day session skips automatic spike analysis. Existing conversations
are retained; starting a new chat clears the planning handoff. Other screens
still prefill their context. The existing consent/send flow controls requests.

Sleep comparisons require seven valid prior nights when available in the loaded
history. Missing data is disclosed. Stress drivers are described as recorded
contributions, not proven causes. These are deterministic wellness summaries,
not automatically generated model responses.

Device checks: switch tabs, open/pop detail pages and dialogs, scroll, open a
keyboard, expand and dismiss, start a workout, and continue an insight in Panda.
Confirm no advice appears over unrelated content and no network AI request is
made just by opening a screen. Check both themes and large text.
