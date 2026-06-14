// Operational helper (NOT a deployed component) — schedules the sequence batch.
// Run as anonymous Apex once per org:
//   sf apex run --file scripts/apex/schedule_sequence_scheduler.apex --target-org BlueSky
//
// CRON: every 8 hours, runs at 00:00 / 08:00 / 16:00 (R4).
// Seconds Minutes Hours Day-of-month Month Day-of-week
//    0       0    0,8,16     *         *        ?
System.schedule(
    'Sequence Scheduler - every 8 hours',
    '0 0 0,8,16 * * ?',
    new SequenceSchedulerSchedulable()
);
