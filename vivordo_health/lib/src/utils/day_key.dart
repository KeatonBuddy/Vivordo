/// Local-date key (YYYY-MM-DD) used for Firestore day documents and day-keyed
/// maps. Built from the date parts rather than DateFormat so the key is always
/// ASCII, independent of the active locale's numbering system.
String localDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
