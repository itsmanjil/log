# ATM Monitoring -> DAILY ATM STATUS

Replaces copy-pasting the ATM Monitoring website table into `DAILY_ATM_STATUS_V3.xlsm`.
Everything runs on the work PC: the script only reads the page that is open in Chrome and
saves a file to Downloads; the macro only reads that file. Nothing is sent anywhere.

| File | What it is |
|---|---|
| `atm_export.js` | Browser script: reads every page of the ATM Monitoring table and downloads `ATM_SWITCH_DATA_<date>_<time>.xlsx` with two sheets laid out like a copy-paste: **Raw Switch Data** (all ATMs) and **PROBLEM IN ATM** (ATMs whose status dot is red / offline) |
| `bookmarklet.txt` | The same script as a one-click bookmark (rebuild with `node make_bookmarklet.js` after editing `atm_export.js`) |
| `Module_WebImport.bas` | Macro module for `DAILY_ATM_STATUS_V3.xlsm`: copies both sheets of the newest export into **Raw Switch Data** / **PROBLEM IN ATM** and runs the normal 1 PM / 8 PM report |

## One-time setup

1. **Bookmark:** right-click the Chrome bookmarks bar -> *Add page* -> name `Export ATMs`, URL = the whole contents of `bookmarklet.txt`.
   (If you already made the bookmark, edit it and paste the new contents.)
2. **Macro module:** open `DAILY_ATM_STATUS_V3.xlsm` -> `Alt+F11` -> if `Module_WebImport` is already in the list on the left, right-click it -> *Remove Module_WebImport* -> *No* (don't export).
   Then *File* -> *Import File...* -> `Module_WebImport.bas` -> close the editor -> save.
3. **Buttons (optional):** on the CONTROL sheet right-click **Run 1 PM Report** -> *Assign Macro...* -> `ImportWebDataAndRun1PMReport`; same for **Run 8 PM Report** -> `ImportWebDataAndRun8PMReport`.

## Daily use

1. On the ATM Monitoring page, show **all ATMs** (no filter), go to page 1 and click **Export ATMs**.
   Wait until the message "Exported ... ATMs" appears (about 30 seconds; don't click the page meanwhile).
2. In `DAILY_ATM_STATUS_V3.xlsm` click **Run 1 PM Report** (or 8 PM). The report is built exactly as before.

An export made in the last 60 minutes is used without asking. An older one (or one not from today) asks first.
The macro looks in the Downloads folder of the PC you are working on (also when the workbook is opened from a
shared folder on another PC); if no export is there it lets you pick the file.

After importing, the file is moved to `Downloads\ATM SWITCH DATA`. That folder keeps only today's exports;
older ones are deleted at the next import. (A browser bookmark is not allowed to choose where Chrome saves
files, so the macro files them.)

ATMs on the website but not on TOTAL are not in the report; the import message lists them (add a TOTAL row for a new ATM).
Terminals typed on the **REMOVED ATMS** sheet (column A from row 4) are dropped from Raw Switch Data and PROBLEM IN ATM
at every import and their TOTAL rows are deleted (S.N renumbered).

ATMs deleted from the website are still on the TOTAL list. If 10% or fewer of the TOTAL ATMs are missing from the
export, they are marked `NOT IN SWITCH DATA` on TOTAL, left out of CASH LOW IN ATM / ATM NOT WORKING, and listed in
a message. Delete the row from TOTAL if the ATM was removed for good. If more are missing (a website filter was on)
nothing is marked.

## First real run: check these

1. The "Exported" message: the ATM count should match the website's own "FILTERED n ATM" number (the script reads that number every time; nothing is fixed) and the red count should match the red dots.
2. Open the downloaded file once: **Raw Switch Data** row 2 should show `NAME`, `TID (PID)`, `NPR`, `DISPENSER`, and the balance and idle-time values should sit under those headings.
3. After the report runs, compare CASH LOW IN ATM and ATM NOT WORKING with what your manual paste would give.

## If something goes wrong

- **The script stops** with a message and saves `ATM_EXPORT_DIAGNOSTIC_<date>_<time>.txt` in Downloads instead.
  It contains only the table layout (column headings, cell types, image names) and no ATM names, IDs, addresses or balances.
  Send a photo of it.
- **The macro shows an error:** take a photo of the message. Raw Switch Data and PROBLEM IN ATM are left unchanged if the file is not a valid export.
- You can always go back to copy-paste plus the original **Run 1 PM Report** / **Run 8 PM Report** macros; they are unchanged.

## Find "Dispenser down" ATMs (tick only, never sends)

`bookmarklet_dispenser_down.txt` (from `find_dispenser_down.js`) is a second bookmark, **Find Dispenser Down**.
On the ATM Monitoring page it first clicks the DEV column heading (device problems come to the top), then
reads each red DEV error icon's details (from the page, or by hovering it the way the mouse does), ticks the
checkbox of every ATM whose details say **Dispenser down** (one at a time, checking each tick stuck), outlines
those rows in orange and lists them. It never clicks Send commands / Group management: you check the list and
choose the command (e.g. Close and block) yourself. Only the page on screen is checked.

## Mail branches about ATMs that are down

`Module_DownAtmMail.bas` adds the **Mail Down ATMs (1 hr+)** button (CONTROL sheet, under Run 1 PM / Run 8 PM).

Click it after the report has run. It reads the **latest section** (8 PM if there is one, else 1 PM) of today's
open daily report, sheet ATM DOWN REPORT, and takes every ATM that
- has no ATM-UP date,
- is **not a red row** (red text = already with the vendor),
- is not `NO TRANSACTION IN ATM.` or `CHECK ATM` (only idle, not a fault),
- has been down at least 1 hour (Issue Identified Date + Down time), with **any** issue.

For each one it opens a filled-in new mail in Outlook on the web (Chrome): branch address, subject, message.
Check it and click **Send**. Nothing is sent automatically.

First click creates the **ATM EMAIL** sheet (every TOTAL terminal). Fill in once:
- column C: branch email, column D: extra CC, column E: phone (shown in the list when there is no email),
- B3: Outlook web address (already `https://outlook.office.com/mail/`); empty = the PC's default mail program,
- B4: address always copied (optional), B5: hours down before mailing (1),
- B6 / B7: subject and message, with `{TERMINAL} {BRANCH} {ISSUE} {DATE} {TIME} {DOWNFOR} {VENDOR} {REMARKS} {PHONE}`.

An ATM is mailed once per day (column F records when); clear that cell to mail it again. ATMs without an email
address are listed (with their phone) and skipped. A sheet made by the earlier dispenser-only version is
upgraded automatically, keeping the addresses already typed in.
## Daily ATM DOWN TIME REPORT mail

The same module adds **Mail Down Report (1-2 PM)** (macro `MailDownReport`) next to Mail Down ATMs. It saves a copy
of today's open daily report to `Downloads\ATM DOWN REPORT MAIL\dd.mm.yyyy.xlsx` without the rows whose issue
contains `NO TRANSACTION IN ATM` (S.N numbered again), opens a ready-filled Outlook on the web mail and a folder
window with the copy selected. Drag the copy into the mail and click **Send** (a compose link cannot attach files).
Settings on the **REPORT MAIL** sheet (made on first click): B3 To, B4 CC, B5 YES = also CC every branch mailed
today with Mail Down ATMs, B6 subject, B7 message (`{DATE}` = e.g. 28th October 2026, `{FILE}`), B8 issues to
leave out (separate with `;`). The daily report itself is not changed.
No mail opens while a row has no time or no Initiated by (ATM DOWN REPORT col E / L, except left-out rows;
CASH LOW col E / H): the rows are listed and OK goes to the first empty cell. Test helper: `ReportMailCheck(reportPath)`.
Outlook on the web ignores the `cc` of a compose link, so both mail buttons put the CC addresses on the
clipboard (Windows API, not MSForms) for pasting into the Cc box; when the per-ATM mails have different CCs they
open one at a time. Test helpers: `DownReportMailPreview(reportPath)`, `MailDryRun(True/False)` (log links instead of opening).

## USB ENABLE mail

**Mail USB Enable** (macro `MailUsbEnable`, same module) asks for a terminal ID (suggests the selected row's ATM),
takes the branch and the IP address from column G "IP address" of ATM EMAIL and opens a ready-filled Outlook on the
web mail. If column G is empty it suggests the ATM's REMOTE ADDRESS from Raw Switch Data; the address you confirm is
saved in column G. To / CC / subject / message (`{BRANCH}` `{TERMINAL}` `{IP}`) are on the **USB MAIL** sheet.
CC is copied for pasting, as for the other mails. Test helper: `UsbMailPreview(terminal)`.

Macros: `ImportWebDataAndRun1PMReport`, `ImportWebDataAndRun8PMReport`, `ImportWebDataOnly` (fills the two sheets without running the report).
