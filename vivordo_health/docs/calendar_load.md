# Calendar demand and hourly load

Implemented in the app, including calendar_context in scoring requests.
BaaS weighting changes, deployment and user demand overrides remain separate.

## Event classifier v3

`CalendarCognitiveLoadService.scoreEvents` uses local rules by default. AI is
optional (`allowAi: true`) and is not invoked by Home. Categories have fixed
starting demand: routine 15, social 20, collaboration 40, focused-work 55,
high-consequence 75. Unknown has a numeric placeholder of 0 and confidence 0;
consumers must use `isKnown` rather than interpret it as low demand.

Title matches take precedence over notes. More specific (longer) matching
phrases take precedence over generic matches. Equal-length conflicting
categories remain unknown. Matching uses word boundaries, normalized case,
whitespace and hyphens. Rule confidence is 0.85 for titles and 0.6 for notes;
these are heuristic evidence levels, not calibrated probabilities. Duration,
attendees, organizer status and transitions do not alter intrinsic demand.
Version 3 expands routine errands, personal care, transport, leisure, social
plans and workplace coordination phrases. Category scores are unchanged.
For example, hotel check-in is routine and team check-in is collaboration.

AI is restricted to the same categories/scores, with 0.6 confidence for known
categories. Its cache namespace and signatures include classifier version 3.

## Hourly calculator v1

`HourlyCalendarLoadCalculator.calculate` accepts classified events and a time
range. Pass an hour-aligned `from`; windows advance by one elapsed hour.
Pass `asOf` for live/historical use. Omit it only for schedule forecasts.
The last window may be partial but is always normalized against 60 minutes,
so a 15-minute presentation contributes 18.75 demand points, not 75.

For each interval between event boundaries:

- Occupied minutes are the union of eligible event intervals.
- Use the highest known active event demand; overlapping demand is not summed.
- Add 10 pressure points while two or more distinct events overlap.
- Add 10 pressure points during an event that starts less than 15 minutes
  after a preceding event ends. Only transitions already reached are used.
- Add a continuous-run pressure ramp: zero through 60 uninterrupted minutes,
  rising linearly to 5 at 120 minutes, then capped at 5. A gap resets the run.

`demand = integral(active demand) / 60 minutes`

`schedule_pressure = integral(pressure) / occupied minutes`

`calendar_load = clamp(demand + integral(pressure) / 60 minutes, 0, 100)`

This caps pressure's contribution at 25 points per fully occupied hour.
These are experimental product defaults requiring evaluation before BaaS use.

Cancelled, declined, all-day, free and invalid-duration events are excluded.
Optional events remain eligible unless declined or marked free. Deduplicate
by provider occurrence ID. Include earlier events in the input for run/transition
context; an event that began before the window can contribute within it.

Unknown events occupy time and contribute schedule pressure, but no assumed
demand. An hour containing only unknown events returns null load. In mixed
hours, confidence is reduced by unknown occupied time. Empty connected hours
return zero load; unavailable calendar returns null with availability false.
Do not infer availability from an empty list or convert fetch failures to
confirmed empty hours in a BaaS integration.

## Consumers and BaaS boundary

Home's existing reachable-window card now shows high forecast calendar-load
hours (60+) within its existing 9 AM–5 PM range. Tapping one retains event
summary navigation to the highest-demand contributor. Open recovery windows
remain free gaps of at least 30 minutes. Forecasts are not sent as live strain.

`CalendarBaasContext` fetches the preceding three days of UTC hourly windows,
plus three hours of preceding event context for schedule pressure. Fetches run
alongside health input collection with a five-second timeout, without prompting
for authorization. Missing permission, fetch errors or partial-calendar failures
produce unavailable/null-load windows, not confirmed empty time. Calendar and
event pagination are exhausted before treating a fetch as complete.

The request uses one as_of captured before input collection. Windows are clipped
to that instant. The background feedback path shares this payload but does not
use calendar for training. Only Google Calendar is connected in this step.

`HourlyCalendarLoad.toJson()` provides versioned UTC window bounds,
evaluated-until time, availability, demand, pressure, occupied/known minutes,
confidence and nullable load. It excludes IDs, titles, descriptions and
attendees. StressScoreService includes these DTOs as calendar_context.

Before connecting it to BaaS, agree which side computes hourly load and its
score-time alignment. Keep one implementation authoritative. Handle absent
calendar separately from confirmed free time, account for confidence, and
trial the proposed 5% channel before enabling it in users' live scores.
