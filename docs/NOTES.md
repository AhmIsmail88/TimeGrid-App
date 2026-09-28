# Engineering notes

Details that do not belong in the README but that are expensive to rediscover.
Everything here was measured on this project, not assumed.

---

## 1. The earlier Android build (`com.aistudio.timegrid.krqzyb`)

An earlier version of the same idea was installed on the phone: a Kotlin/Room
app built outside this repository, with its own database and its own signing
key. It **cannot be updated in place from here** — the applicationId and the
signing key both differ, and Android refuses an update when either does.

Its data is still recoverable, because that build is `DEBUGGABLE`, which lets
adb read its private files:

```bash
adb exec-out run-as com.aistudio.timegrid.krqzyb cat databases/timegrid_database     > legacy.db
adb exec-out run-as com.aistudio.timegrid.krqzyb cat databases/timegrid_database-wal > legacy.db-wal
adb exec-out run-as com.aistudio.timegrid.krqzyb cat databases/timegrid_database-shm > legacy.db-shm
```

Copy all three: the main file was only 24 KB while the write-ahead log held
412 KB, so reading the `.db` alone would have shown an almost empty table.

The legacy schema is one flat table:

```
time_logs(id, taskName, projectName, hours, dateString, category, description, timestamp, company)
```

`test/convert_legacy_db_test.dart` turns those files into this app's backup
format and then proves the result by restoring it into a fresh database and
checking the row counts and total hours. Mapping decisions:

| Legacy | Here | Why |
| --- | --- | --- |
| `projectName` / `taskName` (free text) | rows in `projects` / `tasks` | the new schema separates them; distinct names become rows |
| `description` | `notes` | direct |
| `category` | kept inside `notes` | there is no category column |
| `company` | dropped | a constant in the source; the company name lives in the Excel template |

Restoring through the app itself is what `integration_test/legacy_restore_test.dart`
covers on a device. That test reads the file from the app's **own external
files directory**, because Android's scoped storage stops the app reading
`/sdcard/Download` directly.

---

## 2. The real company template

It is **SpreadsheetML 2003 XML** — an `<?xml …?>` document with
`<?mso-application progid="Excel.Sheet"?>` — usually saved with a `.xls`
extension. `package:excel` cannot read it, because that package only
understands OOXML (ZIP) packages.

Its layout, read from the file itself rather than assumed:

* row 1: company banner; row 2: the period sentence; row 3: `الاسم :` and the
  employee name; row 4: the day headers; rows 5+: one row per project/task.
* the columns are **رقم | المهمة | المشروع | days… | الإجمالي** — the *task*
  column comes before the *project* column.
* the day columns run **backwards**: the last day of the period is the first
  day column, counting down to day 1, then the previous month's last day down
  to the period's first day. A 21st-to-20th period therefore reads
  `20 19 … 1 31 30 … 21`.
* below the data there is a totals row, then `عمل بالمنزل` and
  `إجمالي عدد الساعات`.

The exporter discovers all of this from the document: the day columns are the
run of numeric cells in the header row, and the task/project columns are found
by their labels. `test/spreadsheetml_exporter_test.dart` re-exports the
template's **own** data and asserts the result is identical cell for cell.

---

## 3. The PDF, and a measured dead end

A PDF text library emits glyphs one at a time and does no Arabic shaping, so
`مشروع` comes out as isolated letters in the wrong order.

The obvious fix — rendering HTML through the platform's web engine with
`Printing.convertHtml` — was **tried on a real device and never returned**.
The export simply hung; the test was killed after eight minutes. A timeout was
added so the button could at least fail honestly.

The approach that works: paint the page with Flutter (whose text engine does
shape Arabic correctly, because it is the same one drawing the app) and embed
that image in the PDF. The trade-off is a PDF whose text is not selectable.

The page is 2105x1489 px (A4 landscape at 180 dpi) and the PDF page is
`841.89 x 595.28` points.

---

## 4. Dates inside Arabic text need a bidi isolate

`21 Sep – 20 Oct` is a left-to-right run inside an Arabic paragraph. Without
isolation the bidi algorithm reorders the pieces and the day and the month
swap on screen, so the dashboard appeared to show the wrong period even though
the stored value was correct.

`ltrRun()` in `lib/core/utils/bidi.dart` wraps such runs in U+2066 … U+2069.
It is applied wherever a date is concatenated into Arabic text — the dashboard
period and its chart axis, the entry form's date field, the past-period
warning, the work-log cards, the reports header, the export history, and the
period text written into the PDF.

Symptom worth remembering: if a date ever looks "wrong" again, check for a
missing isolate before suspecting the arithmetic.

---

## 5. Data-safety contract

`AppDatabase` is the only place allowed to change the schema.

* Migrations are **additive only**. `fallbackToDestructiveMigration` must
  never appear.
* Before an existing database file is opened at a higher version, it is
  byte-copied to `timegrid.db.pre-v<old>.bak`.
* A downgrade throws instead of deleting data.
* Each version has a test that builds a database exactly as the previous
  release left it and asserts every row survived:

| Step | Test |
| --- | --- |
| 1 → 2 (offices) | `test/migration_v1_to_v2_test.dart` |
| 2 → 3 (locked periods) | `test/period_lock_test.dart` |
| 3 → 4 (export log) | `test/export_history_test.dart` |
| fresh install | `test/app_database_safety_test.dart` |

Restoring a backup writes a `TimeGrid_PreRestore_Backup_*.json` first, so a
restore is itself reversible.

---

## 6. Widget tests and the fake clock

`flutter test` runs on a fake clock, where a real SQLite read never completes —
the first attempt at a dashboard test hung for exactly that reason. Anything
that would touch the database is therefore injected: `periodLogsProvider` and
`recentEntriesProvider` are overridden with in-memory data, and the lock
repository and repositories are replaced with fakes.

The default test window is 800x600, much shorter than a phone, so the smoke
test sets a realistic surface (`1080x3000` at DPR 3) before pumping — otherwise
the lower half of the dashboard is never laid out and the assertions fail for
the wrong reason.

---

## 7. Building and the versionCode trap

```bash
flutter build apk --release
flutter build apk --release --split-per-abi -P force-version-code-ignoring-abi=true
```

Without `-P force-version-code-ignoring-abi=true`, Flutter offsets
`versionCode` per ABI for split builds. Switching between a split and a
universal APK afterwards then looks like a downgrade and is refused — with the
installed app's data hostage. Both were built with that flag forced so the
two flavours stay interchangeable.

The APK is signed with the machine's **debug** keystore on purpose: the app
already on the phone is debug-signed, and a different key cannot update it.
That keystore is the app's identity — losing it means the installed app can
never be updated again without an uninstall, which takes the database with it.
Keep a copy of `~/.android/debug.keystore` somewhere safe.

`tool/install_to_phone.ps1` reads the device ABI, prefers the matching split
APK, verifies the signing key matches what is installed, refuses anything that
would need an uninstall, and then proves the data survived by checking that
`firstInstallTime` did not change.

---

## 8. Integration tests uninstall the app

`flutter test integration_test/... -d <serial>` **removes the app when it
finishes**, and its storage with it — the database, exports, everything. Run
it on a phone whose data you can restore, and reinstall afterwards with
`tool/install_to_phone.ps1`.

---

## 9. Working with this repository's files

The Dart sources contain non-ASCII characters in comments and strings (`§`,
`—`, `–`, `·`, `…`, Arabic). A Windows console renders some of them as `?` or
mojibake; that is a display artifact, never a reason to "fix" the file. When
scripting edits, anchor on ASCII-only text and preserve UTF-8 without a BOM.
