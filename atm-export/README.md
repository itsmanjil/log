# ATM Monitoring -> DAILY ATM STATUS

Replaces copy-pasting the ATM Monitoring website table into `DAILY_ATM_STATUS_V3.xlsm`.

| File | What it is |
|---|---|
| `atm_export.js` | Browser script: reads every page of the ATM Monitoring table and downloads `ATM_SWITCH_DATA_<date>_<time>.xlsx` with two sheets in the same 16-column layout as copy-paste: **Raw Switch Data** (all ATMs) and **PROBLEM IN ATM** (ATMs whose status dot is red / offline) |
| `bookmarklet.txt` | The same script as a one-click bookmark |
| `Module_WebImport.bas` | Macro module for `DAILY_ATM_STATUS_V3.xlsm`: copies both sheets of the newest export into **Raw Switch Data** / **PROBLEM IN ATM** and runs the 1 PM / 8 PM report |

## One-time setup

1. **Bookmark:** right-click the Chrome bookmarks bar -> *Add page* -> name `Export ATMs`, URL = the whole contents of `bookmarklet.txt`.
2. **Macro module:** open `DAILY_ATM_STATUS_V3.xlsm` -> `Alt+F11` -> *File* -> *Import File...* -> `Module_WebImport.bas` -> close the editor -> save.
3. **Buttons (optional):** on the CONTROL sheet right-click **Run 1 PM Report** -> *Assign Macro...* -> `ImportWebDataAndRun1PMReport`; same for **Run 8 PM Report** -> `ImportWebDataAndRun8PMReport`.

## Daily use

1. On the ATM Monitoring page, show **all ATMs** (no filter), go to page 1 and click **Export ATMs**.
2. In `DAILY_ATM_STATUS_V3.xlsm` click **Run 1 PM Report** (or 8 PM). Confirm the file name it shows; the report is built as before.

Macros: `ImportWebDataAndRun1PMReport`, `ImportWebDataAndRun8PMReport`, `ImportWebDataOnly` (fills the two sheets without running the report).
The newest `ATM_SWITCH_DATA_*.xlsx` in `%USERPROFILE%\Downloads` is used; if none is found you are asked to pick it.
If the script cannot tell red from green for every ATM it downloads nothing and says so, rather than produce a wrong PROBLEM IN ATM list.
