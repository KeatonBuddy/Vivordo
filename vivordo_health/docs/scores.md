# Daily scores: Capacity, Demand, Effort (design, v1)

Status: proposed, not implemented. All numbers are starting values to tune
against real histories. These are wellness estimates, not medical scores.

Lineup: **Capacity** (the energy you have today), **Demand** (what's still
ahead), **Effort** (what the day took), **Stress** (live, unchanged) and
**Heart** (long-term, unchanged). Wellness is retired. Sleep has no separate
score: it is Capacity's main ingredient.

## 1. Item points (shared by Demand and Effort)

Demand and Effort price every item the same way, so they always agree.
Items are calendar events and timed priorities, priced by the existing
hourly calculator (`docs/calendar_load.md`, classifier v3 + hourly v1):

- Base demand per minute from the category: routine 15, social 20,
  collaboration 40, focused work 55, high-consequence 75. Priorities use
  the effort they were given, as Home does today: light 20, moderate 45,
  demanding 75 (unset = moderate).
- **Unknown events** (titles the local rules can't classify) are sent to
  Claude Opus 5.5 (low effort, structured JSON) through the
  `classifyPlanItems` function, which answers with one of the same five
  categories or "can't tell". It sends the title, duration and attendee
  count only, never notes, at most 20 events per call, with its own daily
  budget of 50 calls per account. Answers (including "can't tell") are
  cached on the device per title, and AI answers carry confidence 0.6.
  It needs the user's AI consent (version 2, which added this use).
  Whatever is still unknown
  ("Busy", "Hold", private events, offline) counts as 30 and lowers the
  day's confidence. Nothing is treated as free time.
- Pressure: +10 while events overlap (overlapping demand is not summed),
  and a continuous-run ramp: nothing for the first 60 min, rising to +5
  at 120 min. **Gaps under 15 min don't reset the run**, so a chain of
  back-to-backs builds up like one long block; a gap of 15 min or more
  does.
- **Back-to-back events** (next event starts < 15 min after one ends): a
  flat **+0.5 points each**, whatever the event's length: +10 on the
  rating for its first 30 minutes, or packed into a shorter event (+20
  for 15 min, +30 for 10 min). Today's calculator adds +10 for the whole
  event; that changes. All events count, not only meetings. No
  time-of-day weighting: the cost is the missing buffer, after-hours time
  already has its own multiplier, and a fixed 9–5 doesn't fit shift
  workers or students. Harder transitions (straight out of a
  presentation) are left to per-event costs learned from each person's
  stress reactions.
- **After hours** (after the time the person usually wraps up their main
  work or classes; 5 PM if unanswered or "It varies"): the item's points
  × 1.25. The time comes from an onboarding question, "When do you
  usually wrap up your main work or classes for the day?", is editable in
  Settings, and existing users are asked once on My Day. There's no
  separate weekend rule. This is a separate signal from back-to-backs.

**Untimed priorities** have no slot, so they get flat points by effort:
light 2, moderate 4, demanding 6.

**Blank priority estimates** are filled in by Claude. When a priority is
saved without an effort or a duration, the same server function that
classifies unknown events estimates the missing ones from the title only
(never notes). It only fills blanks: a value the user entered is never
changed. Estimated fields are listed in `planning.estimated`, show with
"≈" in the priority editor, and become the user's own value when
changed there. It runs after saving, in the background, and only with AI
consent; without it, the defaults apply (moderate, no duration).
Recurring priorities' templates aren't estimated (each occurrence is,
when edited). Later, the person's own past durations for
similar titles replace Claude's guess.

**Points scale:** the hourly calendar load (0–100 per hour) summed over
the day, ÷ 10. One fully booked hour of collaboration (40) = 4 points, and
an 8-hour workday of mostly collaboration and focused work ≈ 40–50. 100
means an extremely heavy day. The scale is fixed rather than personal: a
person who is always overloaded should see big numbers. Personal context
comes from Capacity and from burnout's own baselines.

## 2. Demand: what's still ahead

`Demand = points of items not yet finished`:
- the remaining minutes of events in progress and of later events;
- timed priorities not yet done;
- open untimed priorities;
- workouts **planned in the calendar** (moderate intensity unless the
  title says otherwise: 0.2 points per minute).

Demand updates live and reaches ~0 once the last item is behind you. In
the evening (past the end-of-day time, with nothing timed left) the card
shows tomorrow's expected Demand; open untimed priorities carry over, so
they count there rather than holding off the evening view. A workout
logged during the day doesn't change Demand: it already happened, so it
is Effort.

**Implemented** on the phone in `buildDayEffort`
(`lib/src/utils/day_effort.dart`), the same calculation as Home's Effort
bars, so "still ahead" on Home and Demand on My Day always agree. My
Day's brief shows it in place of the old schedule score
(`analyzeBriefPlan`, removed). It isn't stored on the server yet; store
it when burnout or trends need it.

**Morning comparison** (expected Demand at wake vs Capacity):
- Demand ≤ Capacity − 15: "Room to spare".
- Within ±15: "A full day".
- Demand > Capacity + 15: "More than you've got: protect a break".

## 3. Effort: what the day took

`Effort = mental points + physical points` (grows through the day). Both
parts are stored. Because the phone's day record can arrive late (the
nightly push may be dropped, and the next open may be the next
afternoon), the server keeps recalculating a day's Effort for 2 days
after it ends, then locks it.

**Mental:** points of what happened:
- the elapsed minutes of events (events you declined or that were
  cancelled don't count);
- timed priorities that were **completed**;
- untimed priorities completed today.

Priorities whose slot passed unfinished add no Effort. They are counted
as `unfinishedPriorities` for burnout.

**Physical:** first source that has data (v1; heart-rate zones aren't
stored, so they're a later upgrade):
1. Exercise: in-app workouts' minutes × intensity by type (light 0.1 for
   walks, yoga and stretching; vigorous 0.35 for runs, HIIT, cycling,
   rowing, swimming and boxing; moderate 0.2 for strength, sports and
   everything else), plus Health exercise minutes outside in-app
   workouts (`exercise_time.healthSum`) × 0.2. A 45-min run ≈ 16 points.
2. No exercise: active calories above your 90-day median (from 7 days of
   history) ÷ 50 kcal (a heavy day on your feet still counts).

Physical points are capped at 25. In-app workouts and Health minutes
don't overlap (the app already subtracts one from the other), so nothing
is counted twice.

**Implemented** in `functions/effort.js` (`computeDailyEffort` on day
records, `computeEffortFromWorkout` on workouts, and the existing
`computeDailyCapacity` trigger when exercise minutes or active calories
change). `finishDailyEffort` recalculates every day about an hour after it
ends, so the final Effort counts the whole day even if the phone's
record wasn't rewritten after the last event. Its hourly loads match the
phone's calculator through shared cases in
`test/fixtures/calendar_load_cases.json`.

**Recovery from yesterday** (in Capacity) starts once there are 7 days of
Effort; until then it's left out.

**Shown on Home** as "Your Day" (replacing "Your Day's Load"),
never as a headline number. Hourly bars before now are Effort (solid,
workouts in their own colour) and after now are Demand (outlined). A
summary shows **So far** as a word only: "Heavier than usual", "About
usual" or "Lighter than usual" against your usual Effort by this time of
day, or "Still learning your usual" until there are 14 days of Effort.
**Still ahead** shows the planned time and how heavy it is, switching to
**Tomorrow** after the last item. Implemented in `lib/src/utils/day_effort.dart`
and Home's card: "usual by this time of day" is the median of the last 28
days' `effort.byHour` at the current hour (from 14 days), and Home rates
events with the same Claude sorting as the day records. Tapping a bar and the "Open" row stay as
they are.

Priorities on the chart:
- **Untimed priorities** have no hour, so they don't get a bar. Their
  points count towards "So far", and a small tick marks the hour they
  were completed.
- **Timed priorities finished early** count as soon as they're ticked
  off and are drawn as done in their planned slot, so the chart keeps the
  plan's shape.
- Unticking a priority removes its points.

## 4. Capacity: the energy you have today

Calculated each morning, 0–100. Each ingredient becomes a 0–100 sub-score
against **your own** 90-day normal: a long memory, so a slow decline isn't
absorbed into "normal". Missing ingredients are left out and the rest are
re-weighted, except overnight body data (see below).

| Ingredient | Weight | Sub-score |
|---|---|---|
| Sleep | 45 | 100 × min(1, hours ÷ your need); below 5 h, × 0.7. −10 if bedtime is > 60 min off your 14-day median |
| Overnight body | 35 | Average of the available parts: HRV 70 + 100 × (HRV ÷ your 90-day HRV − 1); resting HR 70 − 6 × (bpm above your 90-day RHR) |
| Recovery from yesterday | 20 | 100 if yesterday's Effort was at or below your usual; otherwise 100 − (yesterday's Effort − your usual Effort), floored at 0. Higher = less to recover from (a very heavy yesterday gives a low value) |
| Morning check-in (optional) | +15 | Average of the parts answered: "How do you feel?" as a mood score (0–100, the same scale as mood check-ins) and "How did you sleep?" (Awful 0, Poor 25, Okay 50, Good 75, Great 100) |

`Capacity = Σ(weight × sub-score) ÷ Σ(weights of the ingredients present)`

Note the two meanings of "100": an Effort of 100 is an extremely heavy
day, but a Recovery-from-yesterday sub-score of 100 means yesterday was no
heavier than usual.

Without a check-in the weights are exactly 45 / 35 / 20. With one, they
work out to about 39 / 30 / 17 / 13. Each sub-score is clamped to 0–100.

**Missing overnight body data counts as 70** (a normal night) instead of
being left out. Leaving it out inflated scores without a wearable: an
ordinary day scored 99 without one and 89 with one, because the body
sub-score sits at 70 on a normal night. With a neutral 70, the same day
scores the same either way. The day is still flagged as having no body
data (`hrv` and `restingHr` stay null), so trends and burnout know it was
assumed, not measured.

**Why there is no morning stress:** the stress score is already built from
sleep, HRV and resting heart rate, so including it counted last night
twice (and, without a wearable, it adds little beyond sleep and mood).
Stress stays its own live number. The check-in replaces it as the one
signal sensors can't measure. It is left out on days it isn't answered.

**The morning check-in card** sits at the top of My Day until noon (local),
until answered or dismissed. "How do you feel?" uses the mood labels
(Awful 10, Down 30, Okay 50, Good 75, Great 95) and is also saved as the
day's mood check-in. "How did you sleep?" is asked even when sleep was
recorded, with the recorded duration shown beside it. Answers are saved to
`metrics_daily/{day}.morning_check_in` as `{feel, sleep, dismissed}`
(scores), which the Capacity trigger reads. Once both are answered the card
collapses to a confirmation with Edit.

- **Your sleep need** is your 90-day median sleep, kept between 7 and 9 h.
  With fewer than 14 nights it is 8 h.
- **Your usual Effort** is the 90-day median.
- **Without a wearable:** sleep from Health, recovery from yesterday, the
  morning check-in, and a morning camera heart scan (resting HR) if one was
  done.
- **Not enough data:** with no sleep, no overnight body data and no
  check-in, Capacity is shown as unavailable. It is never guessed.
- **One reading never decides it:** a resting HR more than 12 bpm from your
  normal is treated as a bad reading and left out (`restingHrIgnored`), and
  with no sleep and no check-in, the body part needs both HRV and resting
  HR. Otherwise the day is unavailable. (A lone resting HR of 67 against a
  normal of 49 used to score 0.)
- **Check-in only** (no sleep or body data yet): Capacity is the check-in
  (plus recovery from yesterday, once built), without the assumed neutral
  body, and is labelled "Based on your check-in" until sleep syncs.
- **Provisional until last night's sleep syncs.** There's no time cutoff,
  because there's no way to know when someone woke up. Capacity
  recalculates whenever last night's sleep arrives, and locks at local
  midnight. If sleep never arrives, it stays provisional on the other
  ingredients.
- **Labels:** High ≥ 80, Moderate 50–79, Low < 50. These are raised from
  70 / 40, because an ordinary day scores about 85–90 with this formula and
  the old bands called nearly every day High.

Changes from the current Capacity:
- sleep is compared with your own need, not 8 h;
- HRV and resting HR are compared with your own normal, instead of heart
  rate vs a fixed 60 bpm. HRV uses one kind only (WHOOP or Fitbit overnight
  RMSSD, else Apple SDNN; `functions/hrv.js`), since the kinds can't be
  compared; `hrvKind` records which;
- recovery from yesterday's Effort carries over;
- morning stress is dropped (it double-counted sleep and the body);
- an optional morning check-in adds a self-reported signal;
- missing body data counts as a neutral 70, so scores with and without a
  wearable are comparable;
- the label bands are raised to 80 / 50;
- the score recalculates when sleep arrives and locks at midnight.

## 5. Daily record

One record per day in `users/{uid}/scores_daily/{day}` (server-written,
owner-readable). It is not stored in `metrics_daily`, where writing back
would re-trigger the function, nor in the summary documents, which are
replaced whole on every projection. Capacity is implemented in
`functions/capacity.js`: the `computeDailyCapacity` trigger recalculates
only when a day's sleep, HRV, resting heart rate or check-in changes, reads just
those fields for 90 days, and never rewrites a day once it is over in
every time zone (`final`). `scripts/backfill_capacity.js` fills past days.
Field names below are the planned shape; see `capacity.js` for the exact
Capacity record.

```
capacity: { score, final, version, provisional,
            sleepHours, sleepNeed, bedtimeOffsetMin,
            hrv, hrvKind, hrvNormal, restingHr, restingHrNormal,
            checkInFeel, checkInSleep, yesterdayEffort, usualEffort }
effort:   { total, mental, physical, physicalSource, final, version,
            busyMinutes, backToBack, afterHoursMinutes,
            prioritiesDone, unfinishedPriorities, unknownMinutes,
            byHour }   // running total at the end of each hour
demand:   { expectedAtWake, version }
```

- Missing values are null, never 0.
- Each score carries a formula version; trends and burnout only compare
  days from the same version.
- Capacity and Effort are calculated on the server.
- The phone writes the day's calendar facts (event intervals with
  category and demand, no titles), because calendar data only exists on
  the device.
- Live Demand is calculated in the app with the same formulas, kept in
  sync with the server by shared test cases.

## 6. Burnout uses

Groups:
- **Capacity:** the daily score, plus raw sleep, HRV and resting HR for
  the reasons.
- **Effort:** the daily total, plus back-to-backs, after-hours time and
  unfinished priorities.
- **Mood.**

The check in `functions/burnout.js` is unchanged: only its signal list
changes.

## Open questions

None. Decided (2026-10-01):
- Ticking off any priority, timed or untimed, adds Effort.
- Late sleep updates Capacity, with no time cutoff.
- Unknown events are classified by Claude Opus 5.5 at low effort. Revisit
  with a Haiku 4.5 comparison on real titles once there are thousands of
  users.
- The privacy policy needs a line about event titles being processed by
  an AI provider.
- After hours = after the user's own wrap-up time (default 5 PM).
