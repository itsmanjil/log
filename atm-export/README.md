# ATM Monitoring -> DAILY ATM STATUS

Replaces copy-pasting the ATM Monitoring website table into `DAILY_ATM_STATUS_V3.xlsm`.

| File | What it is |
|---|---|
| `atm_export.js` | Browser script: reads every page of the ATM Monitoring table and downloads it as `.xlsx` in the same 16-column layout as copy-paste |
| `bookmarklet.txt` | The same script as a one-click bookmark |
| `Module_WebImport.bas` | Macro module for `DAILY_ATM_STATUS_V3.xlsm`: loads the newest downloads into **Raw Switch Data** / **PROBLEM IN ATM** and runs the 1 PM / 8 PM report |

## One-time setup

1. **Bookmark:** right-click the Chrome bookmarks bar -> *Add page* -> name `Export ATMs`, URL = the whole contents of `bookmarklet.txt`.
2. **Macro module:** open `DAILY_ATM_STATUS_V3.xlsm` -> `Alt+F11` -> *File* -> *Import File...* -> `Module_WebImport.bas` -> close the editor -> save.
3. **Buttons (optional):** on the CONTROL sheet right-click **Run 1 PM Report** -> *Assign Macro...* -> `ImportWebDataAndRun1PMReport`; same for **Run 8 PM Report** -> `ImportWebDataAndRun8PMReport`.

## Daily use

1. On the ATM Monitoring page, show **all ATMs**, go to page 1, click **Export ATMs**, answer `1`.
2. Set the website filter you use for **problem ATMs**, go to page 1, click **Export ATMs**, answer `2`.
3. In `DAILY_ATM_STATUS_V3.xlsm` click **Run 1 PM Report** (or 8 PM). Confirm the two file names it shows; the report is built as before.

Macros: `ImportWebDataAndRun1PMReport`, `ImportWebDataAndRun8PMReport`, `ImportWebDataOnly` (fills the two sheets without running the report).
Files are taken from `%USERPROFILE%\Downloads`; if none are found you are asked to pick them.
