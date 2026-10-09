# Daily Brief v1

This is local My Day planning logic. It does not write BaaS scores or call AI.

## Baselines and freshness

My Day listens to at most 29 date-keyed metric documents (today plus 28 prior
calendar days). Sleep comparison uses the median of at least seven valid nights;
differences below 45 minutes are described as close to usual. Missing nights are
not zeroes. Capacity uses the existing calculator with sleep and stress only:
raw BPM is excluded because a fixed BPM reference is not personalized recovery.
Capacity comparisons require seven matching-input historical days, matching BaaS
algorithm versions, and stress samples within two hours before the corresponding
local time. Current stale stress suppresses comparisons. These are estimates.

The freshness panel distinguishes calendar **loaded** time (which can use the
existing short-lived cache) from stress computation and heart-rate measurement
timestamps. Missing/stale data is labelled limited; this is not a clinical
coverage measure. Local Firestore cache use is disclosed.

## Remaining demand

Timed calendar commitments plus unfinished timed priorities use real intervals.
Untimed priorities count only on an explicitly selected planned day, independently
of the original stored date. Scheduled time takes precedence over planned day.
Unplanned backlog does not count. Completed priorities stop contributing, but
their linked calendar events are not deleted or assumed free.

Flexible work contributes only to occupancy workload. Effort uses neutral 1.0,
light 0.8, and demanding 1.2 factors. These are product heuristics, not medical
weights. Missing duration/link data is disclosed instead of inventing time.
Existing calendar overlap/gap/fragmentation scoring is retained; priorities do
not feed the BaaS stress calculation. The scale is capped at 100.

Openings use a fixed, explicitly labelled 9 AM–5 PM window and require 30 minutes.
Busy afternoon means at least three remaining occupied afternoon hours.
Consecutive/overlapping sequences use gaps under ten minutes. Unscheduled work
does not erase calendar openings. The planning window is not yet user-configurable.

## Persistence

Priority `planning` stores optional `minutes`, `effort`, and `plannedDay` (local
YYYY-MM-DD). Existing documents need no migration. `priorityPlanSources` on the
user indexes source days for planned tasks, including tasks stored under future
dates. Existing carry-forward and completion logic otherwise remains intact.
Recurring templates copy estimates and plan each materialized occurrence on its
own day when the template opts into planning.

New Google links store `sourceEventKey` and `linkedCalendarId`; event private
metadata also includes the priority reference for reconciliation. Recurring
instances resolve through their series ID. Existing unlinked calendar exports
are not automatically migrated. A linked event outside the loaded range cannot
be edited from the priority flow; the UI reports that limitation.

## Manual release checks

- Create a priority due later but planned today; verify it appears today.
- Complete/uncomplete it and confirm remaining load changes.
- Create and edit a Google-linked timed priority; verify one event and one load.
- Verify recurring instances resolve to the series and remain date-specific.
- Disable connectivity and check freshness/error messaging.
- Test midnight rollover and device timezone changes.

No Firebase function deployment is required. Existing owner-only priority rules
apply. Google/Firebase end-to-end testing is still required before release.
