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
  the effort they were given, as Home does today (unset = focused).
- **Unknown events** (titles the local rules can't classify) are sent to
  Claude through a server function, which answers with one of the same
  five categories or "can't tell". It sends the title, duration and
  attendee count only, never notes. Answers are cached per title, and AI
  answers carry confidence 0.6. This replaces the dormant Gemini path in
  `calendar_cognitive_load_service.dart`. Whatever is still unknown
  ("Busy", "Hold", private events, offline) counts as 30 and lowers the
  day's confidence. Nothing is treated as free time.
- Pressure, as today: +10 while events overlap, and a continuous-run ramp
  of up to +5. Overlapping demand is not summed.
- **Back-to-back events** (next event starts < 15 min after one ends):
  +10 at any time of day, as the calculator does today. All events count,
  not only meetings. No time-of-day weighting: the cost is the missing
  buffer, after-hours time already has its own multiplier, and a fixed
  9–5 doesn't fit shift workers or students. Later, per-event costs
  learned from each person's stress reactions can capture time-of-day
  effects that are real for them.
- **After hours** (after the time the person usually wraps up their main
  work or classes; 5 PM if unanswered or "It varies"): the item's points
  × 1.25. The time comes from an onboarding question, "When do you
  usually wrap up your main work or classes for the day?", is editable in
  Settings, and existing users are asked once on My Day. There's no
  separate weekend rule. This is a separate signal from back-to-backs.

**Untimed priorities** have no slot, so they get flat points by effort:
light 2, focused 4, heavy 6.

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
the evening the card shows tomorrow's expected Demand. A workout logged
during the day doesn't change Demand: it already happened, so it is Effort.

**Morning comparison** (expected Demand at wake vs Capacity):
- Demand ≤ Capacity − 15: "Room to spare".
- Within ±15: "A full day".
- Demand > Capacity + 15: "More than you've got: protect a break".

## 3. Effort: what the day took

`Effort = mental points + physical points` (grows through the day; final
at local midnight). Both parts are stored.

**Mental:** points of what happened:
- the elapsed minutes of events (events you declined or that were
  cancelled don't count);
- timed priorities that were **completed**;
- untimed priorities completed today.

Priorities whose slot passed unfinished add no Effort. They are counted
as `unfinishedPriorities` for burnout.

**Physical:** first source that has data:
1. Heart-rate zones during workouts: minutes × zone weight (z1 1, z2 2,
   z3 3, z4 4, z5 5) ÷ 6. A 45-min run mostly in z3 ≈ 22 points.
2. Workouts without heart rate: minutes × intensity by type (light 0.1,
   moderate 0.2, vigorous 0.35 points per minute).
3. No workouts: active energy above your 90-day median ÷ 50 kcal
   (a heavy day on your feet still counts).

Physical points are capped at 40, and only one source counts per workout,
so nothing is counted twice.

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
  rate vs a fixed 60 bpm;
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
            hrv, hrvNormal, restingHr, restingHrNormal,
            checkInFeel, checkInSleep, yesterdayEffort, usualEffort }
effort:   { total, mental, physical, final, version,
            eventMinutes, backToBack, afterHoursMin,
            prioritiesDone, unfinishedPriorities, unknownMinutes }
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
