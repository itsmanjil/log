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

ATMs deleted from the website are still on the TOTAL list. If 10% or fewer of the TOTAL ATMs are missing from the
export, they are marked `NOT IN SWITCH DATA` on TOTAL, left out of CASH LOW IN ATM / ATM NOT WORKING, and listed in
a message. Delete the row from TOTAL if the ATM was removed for good. If more are missing (a website filter was on)
nothing is marked.

## First real run: check these

1. The "Exported" message: the ATM count should match the website (about 264) and the red count should match the red dots.
2. Open the downloaded file once: **Raw Switch Data** row 2 should show `NAME`, `TID (PID)`, `NPR`, `DISPENSER`, and the balance and idle-time values should sit under those headings.
3. After the report runs, compare CASH LOW IN ATM and ATM NOT WORKING with what your manual paste would give.

## If something goes wrong

- **The script stops** with a message and saves `ATM_EXPORT_DIAGNOSTIC_<date>_<time>.txt` in Downloads instead.
  It contains only the table layout (column headings, cell types, image names) and no ATM names, IDs, addresses or balances.
  Send a photo of it.
- **The macro shows an error:** take a photo of the message. Raw Switch Data and PROBLEM IN ATM are left unchanged if the file is not a valid export.
- You can always go back to copy-paste plus the original **Run 1 PM Report** / **Run 8 PM Report** macros; they are unchanged.

## Mail branches about cash dispenser problems

`Module_DispenserMail.bas` adds the **Mail Dispenser Problems** button (CONTROL sheet, under Run 1 PM / Run 8 PM).

1. After the report runs, staff set **Issue in ATM** to `PROBLEM IN CASH DISPENSER.` as usual.
2. Click **Mail Dispenser Problems**. It reads today's open daily report and takes every ATM whose latest row
   has that issue and no ATM-UP date.
3. For each one it opens a filled-in new mail in Outlook on the web (Chrome): branch address, subject, message.
   Check it and click **Send**. Nothing is sent automatically.

First click creates the **ATM EMAIL** sheet (every TOTAL terminal). Fill in once:
- column C: the branch email for each terminal (column D: extra CC),
- B3: the Outlook web address from Chrome's address bar (e.g. `https://outlook.office.com/mail/`; for a bank
  server something like `https://mail.<bank>/owa/`). Empty = the PC's default mail program,
- B4: an address always copied (optional); B5 / B6: subject and message, with `{TERMINAL} {BRANCH} {DATE} {TIME}
  {VENDOR} {REMARKS}`.

An ATM is mailed once per day (column E records when); clear that cell to mail it again. ATMs without an email
address are listed and skipped.

Macros: `ImportWebDataAndRun1PMReport`, `ImportWebDataAndRun8PMReport`, `ImportWebDataOnly` (fills the two sheets without running the report).
