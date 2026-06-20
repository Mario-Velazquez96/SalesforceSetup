// Operational helper (NOT a deployed component) — schedules the sequence batch.
// Run as anonymous Apex once per org, as a user with edit FLS on the cadence
// fields (admin or Login_Sequence_User):
//   sf apex run --file scripts/apex/schedule_sequence_scheduler.apex --target-org BlueSkyProduction
//
// CRON: 3x/day during business hours = 08:00 / 12:00 / 16:00 MOUNTAIN time.
// IMPORTANT: scheduled Apex fires in the SCHEDULING USER'S timezone. The owner
// user (thomas@blueskyadvisory.com) is America/Los_Angeles (Pacific), and
// Mountain is 1 hour ahead of Pacific, so the Pacific-clock hours 7/11/15 fire
// at 8/12/16 Mountain. (Holds year-round for Denver-style Mountain, which
// observes DST in lockstep with Pacific. If the org is on Arizona MST — no DST —
// the summer alignment shifts by an hour; schedule as a Mountain-TZ user instead.)
// Seconds Minutes Hours Day-of-month Month Day-of-week
//    0       0    7,11,15    *         *        ?
System.schedule(
    'Sequence Scheduler - business hours (MT)',
    '0 0 7,11,15 * * ?',
    new SequenceSchedulerSchedulable()
);
