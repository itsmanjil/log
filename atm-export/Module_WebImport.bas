Attribute VB_Name = "Module_WebImport"
Option Explicit

' ======================================================================
' IMPORT WEBSITE EXPORT (atm_export.js) AND RUN THE DAILY REPORT
'
' The browser script saves the ATM Monitoring table as
'   ATM_SWITCH_DATA_<date>_<time>.xlsx
' with two sheets in the same layout as copy-pasting the website table:
'   Raw Switch Data  - every ATM
'   PROBLEM IN ATM   - ATMs whose status dot is red / offline
' These macros take the newest such file from the Downloads folder (or ask
' for it), copy both sheets into this workbook, then run the normal
' 1 PM / 8 PM report (Run1PMReport / Run8PMReport in Module2). The report
' logic itself is untouched - this only replaces the manual copy-paste.
' ======================================================================

Private Const EXPORT_FILE_PATTERN As String = "ATM_SWITCH_DATA_*.xlsx"
Private Const FRESH_MINUTES As Long = 60   ' newer files are imported without asking
Private Const DOWNLOADS_GUID As String = "{374DE290-123F-4565-9164-39C4925E467B}"
Private Const ARCHIVE_FOLDER As String = "ATM SWITCH DATA"  ' inside Downloads, today's files only
Private Const MAX_MISSING_SHARE As Double = 0.1  ' more TOTAL ATMs missing than this = filtered export, not imported
Private Const REMOVED_SHEET As String = "REMOVED ATMS"  ' terminals left out of every import (column A from row 4)
Private Const REMOVED_FIRST_ROW As Long = 4

Private mImportNote As String  ' what the last import did, shown to the user

Public Sub ImportWebDataAndRun1PMReport()
    If ImportWebExport() Then Run1PMReport
End Sub

Public Sub ImportWebDataAndRun8PMReport()
    If ImportWebExport() Then Run8PMReport
End Sub

Public Sub ImportWebDataOnly()
    If ImportWebExport() Then
        MsgBox "Raw Switch Data and PROBLEM IN ATM updated from the website export file.", vbInformation
    End If
End Sub

' For checking: what the last import did (the message shown after it).
Public Function LastImportNote() As String
    LastImportNote = mImportNote
End Function

Private Function ImportWebExport() As Boolean
    Dim exportFile As String
    Dim msg As String
    Dim ageMinutes As Double

    exportFile = NewestExportFile()
    If Len(exportFile) = 0 Then exportFile = PickFile("Select the website export (" & EXPORT_FILE_PATTERN & ")")
    If Len(exportFile) = 0 Then Exit Function

    ' Ask only when the file is not a fresh export from today.
    ageMinutes = (Now - FileDateTime(exportFile)) * 1440
    If Int(FileDateTime(exportFile)) < Date Or ageMinutes > FRESH_MINUTES Then
        msg = "Import this website export into Raw Switch Data and PROBLEM IN ATM?" & vbCrLf & vbCrLf & _
              "    " & Mid$(exportFile, InStrRev(exportFile, "\") + 1) & vbCrLf & _
              "    saved " & Format$(FileDateTime(exportFile), "dd/mm/yyyy hh:nn") & vbCrLf & vbCrLf
        If Int(FileDateTime(exportFile)) < Date Then
            msg = msg & "WARNING: this file is NOT from today."
        Else
            msg = msg & "WARNING: this file is " & CLng(ageMinutes) & " minutes old. Export again for current data?"
        End If
        If MsgBox(msg, vbQuestion + vbYesNo + vbDefaultButton2, "Import Website Data") <> vbYes Then Exit Function
    End If

    ImportWebExport = ImportWebExportFile(exportFile)
    If ImportWebExport And Len(mImportNote) > 0 Then MsgBox mImportNote, vbInformation, "Import Website Data"
End Function

' Copies both sheets of exportFile into this workbook. No questions asked;
' returns False (after showing the reason) if the file is not a valid export.
Public Function ImportWebExportFile(ByVal exportFile As String) As Boolean
    Dim oldScreenUpdating As Boolean
    Dim oldEnableEvents As Boolean
    Dim oldDisplayAlerts As Boolean
    Dim msg As String
    Dim wbSource As Workbook
    Dim removed As Object

    oldScreenUpdating = Application.ScreenUpdating
    oldEnableEvents = Application.EnableEvents
    oldDisplayAlerts = Application.DisplayAlerts

    On Error GoTo SafeFail

    Application.ScreenUpdating = False
    Application.EnableEvents = False
    Application.DisplayAlerts = False

    Set wbSource = Workbooks.Open(exportFile, UpdateLinks:=False, ReadOnly:=True)

    ' Check the file before anything in this workbook is overwritten.
    msg = ExportProblem(wbSource)
    If Len(msg) > 0 Then Err.Raise vbObjectError + 701, , msg
    Set removed = RemovedAtms()
    msg = FilteredExportProblem(wbSource, removed)
    If Len(msg) > 0 Then Err.Raise vbObjectError + 702, , msg

    mImportNote = vbNullString
    CopySheetValues wbSource.Worksheets("Raw Switch Data"), ThisWorkbook.Worksheets("Raw Switch Data")
    CopySheetValues wbSource.Worksheets("PROBLEM IN ATM"), ThisWorkbook.Worksheets("PROBLEM IN ATM")
    wbSource.Close SaveChanges:=False
    Set wbSource = Nothing

    DropRemovedAtms ThisWorkbook.Worksheets("Raw Switch Data"), removed
    DropRemovedAtms ThisWorkbook.Worksheets("PROBLEM IN ATM"), removed
    RemoveFromTotal removed
    SyncTotalWithExport
    ArchiveExport exportFile

    Application.ScreenUpdating = oldScreenUpdating
    Application.EnableEvents = oldEnableEvents
    Application.DisplayAlerts = oldDisplayAlerts

    ImportWebExportFile = True
    Exit Function

SafeFail:
    msg = Err.Description
    Application.CutCopyMode = False
    If Not wbSource Is Nothing Then wbSource.Close SaveChanges:=False
    Application.ScreenUpdating = oldScreenUpdating
    Application.EnableEvents = oldEnableEvents
    Application.DisplayAlerts = oldDisplayAlerts
    MsgBox "Error: " & msg & vbCrLf & vbCrLf & "Raw Switch Data and PROBLEM IN ATM were not changed.", _
           vbExclamation, "Import Website Data"
End Function

' TOTAL follows the website: ATMs on the website but not on TOTAL are added (terminal +
' name; the refresh fills the figures), ATMs on TOTAL but no longer on the website are
' deleted, S.N is numbered again. New ATMs are also added to ATM EMAIL if that sheet exists.
' (A filtered export never gets this far: ImportWebExportFile stops when too many are missing.)
Private Sub SyncTotalWithExport()
    Dim wsTotal As Worksheet
    Dim present As Object, onTotal As Object, key As Variant
    Dim r As Long, lastRow As Long, sn As Long, added As Long, deleted As Long
    Dim terminal As String, addedList As String, deletedList As String

    Set present = WebsiteAtms()
    If present.Count = 0 Then Exit Sub
    Set wsTotal = ThisWorkbook.Worksheets("TOTAL")
    On Error Resume Next
    wsTotal.Unprotect  ' the refresh protects it again
    On Error GoTo 0

    ' delete ATMs that are no longer on the website
    Set onTotal = CreateObject("Scripting.Dictionary")
    onTotal.CompareMode = 1
    lastRow = wsTotal.Cells(wsTotal.Rows.Count, "B").End(xlUp).Row
    For r = lastRow To 2 Step -1
        terminal = TerminalOf(wsTotal.Cells(r, 2).Value)
        If Len(terminal) > 0 Then
            If present.Exists(terminal) And Not onTotal.Exists(terminal) Then
                onTotal(terminal) = True
            Else  ' gone from the website, or a second row for the same ATM
                deleted = deleted + 1
                If deleted <= 10 Then deletedList = vbCrLf & "    " & terminal & "  " & CStr(wsTotal.Cells(r, 3).Value) & deletedList
                wsTotal.Rows(r).Delete
            End If
        End If
    Next r

    ' add ATMs that are new on the website, at the end (formatted like the row above)
    lastRow = wsTotal.Cells(wsTotal.Rows.Count, "B").End(xlUp).Row
    For Each key In present.Keys
        If Not onTotal.Exists(key) Then
            If lastRow >= 2 Then wsTotal.Rows(lastRow).Copy Destination:=wsTotal.Rows(lastRow + 1)
            lastRow = lastRow + 1
            wsTotal.Range(wsTotal.Cells(lastRow, 1), wsTotal.Cells(lastRow, 8)).ClearContents
            wsTotal.Cells(lastRow, 2).Value = CStr(key)
            wsTotal.Cells(lastRow, 3).Value = present(key)
            added = added + 1
            If added <= 10 Then addedList = addedList & vbCrLf & "    " & key & "  " & present(key)
            AddToEmailSheet CStr(key), CStr(present(key))
        End If
    Next key

    If added = 0 And deleted = 0 Then Exit Sub
    For r = 2 To lastRow
        If Len(TerminalOf(wsTotal.Cells(r, 2).Value)) > 0 Then
            sn = sn + 1
            wsTotal.Cells(r, 1).Value = sn
        End If
    Next r
    If added > 0 Then mImportNote = mImportNote & "TOTAL list updated - " & added & " new ATM(s) from the website added:" & _
        addedList & IIf(added > 10, vbCrLf & "    ... and " & (added - 10) & " more", "") & vbCrLf & vbCrLf
    If deleted > 0 Then mImportNote = mImportNote & "TOTAL list updated - " & deleted & " ATM(s) no longer on the website deleted:" & _
        deletedList & IIf(deleted > 10, vbCrLf & "    ... and " & (deleted - 10) & " more", "") & vbCrLf & _
        "(If one was deleted by mistake it comes back by itself once it is on the website again.)" & vbCrLf & vbCrLf
    mImportNote = mImportNote & "TOTAL now has " & sn & " ATMs."
End Sub

' Terminal -> ATM name of every ATM in Raw Switch Data.
Private Function WebsiteAtms() As Object
    Dim ws As Worksheet, result As Object
    Dim headerRow As Long, tidCol As Long, nameCol As Long, r As Long
    Dim terminal As String

    Set result = CreateObject("Scripting.Dictionary")
    result.CompareMode = 1
    Set WebsiteAtms = result
    Set ws = ThisWorkbook.Worksheets("Raw Switch Data")
    For headerRow = 1 To 10
        tidCol = HeaderColumn(ws, headerRow, "TID (PID)")
        If tidCol > 0 Then Exit For
    Next headerRow
    If tidCol = 0 Then Exit Function
    nameCol = HeaderColumn(ws, headerRow, "NAME")
    For r = headerRow + 1 To ws.Cells(ws.Rows.Count, tidCol).End(xlUp).Row
        terminal = TerminalOf(ws.Cells(r, tidCol).Value)
        If Len(terminal) > 0 Then
            If nameCol > 0 Then result(terminal) = Trim$(CStr(ws.Cells(r, nameCol).Value)) Else result(terminal) = ""
        End If
    Next r
End Function

' A new ATM also gets a row on ATM EMAIL (used by the mail buttons), if that sheet exists.
Private Sub AddToEmailSheet(ByVal terminal As String, ByVal branch As String)
    Const FIRST_ROW As Long = 12
    Dim ws As Worksheet, r As Long, lastRow As Long
    If Not HasSheet(ThisWorkbook, "ATM EMAIL") Then Exit Sub
    Set ws = ThisWorkbook.Worksheets("ATM EMAIL")
    If StrComp(Trim$(CStr(ws.Cells(FIRST_ROW - 1, 1).Value)), "Terminal", vbTextCompare) <> 0 Then Exit Sub
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    For r = FIRST_ROW To lastRow
        If StrComp(Trim$(CStr(ws.Cells(r, 1).Value)), terminal, vbTextCompare) = 0 Then Exit Sub
    Next r
    If lastRow >= FIRST_ROW Then
        ws.Rows(lastRow).Copy Destination:=ws.Rows(lastRow + 1)
        ws.Rows(lastRow + 1).ClearContents
    End If
    ws.Cells(lastRow + 1, 1).Value = terminal
    ws.Cells(lastRow + 1, 2).Value = branch
End Sub

' Empty string, or why the export looks filtered: more than MAX_MISSING_SHARE of the TOTAL
' ATMs (not counting REMOVED ATMS) are not in it. Importing it would delete them from TOTAL.
Private Function FilteredExportProblem(ByVal wb As Workbook, ByVal removed As Object) As String
    Dim ws As Worksheet, wsTotal As Worksheet, inExport As Object
    Dim headerRow As Long, tidCol As Long, r As Long, totalCount As Long, missing As Long
    Dim terminal As String

    Set ws = wb.Worksheets("Raw Switch Data")
    For headerRow = 1 To 10
        tidCol = HeaderColumn(ws, headerRow, "TID (PID)")
        If tidCol > 0 Then Exit For
    Next headerRow
    If tidCol = 0 Then Exit Function
    Set inExport = CreateObject("Scripting.Dictionary")
    inExport.CompareMode = 1
    For r = headerRow + 1 To ws.Cells(ws.Rows.Count, tidCol).End(xlUp).Row
        terminal = TerminalOf(ws.Cells(r, tidCol).Value)
        If Len(terminal) > 0 Then inExport(terminal) = True
    Next r

    Set wsTotal = ThisWorkbook.Worksheets("TOTAL")
    For r = 2 To wsTotal.Cells(wsTotal.Rows.Count, "B").End(xlUp).Row
        terminal = TerminalOf(wsTotal.Cells(r, 2).Value)
        If Len(terminal) > 0 And Not removed.Exists(terminal) Then
            totalCount = totalCount + 1
            If Not inExport.Exists(terminal) Then missing = missing + 1
        End If
    Next r
    If missing > totalCount * MAX_MISSING_SHARE Then
        FilteredExportProblem = "This export has " & inExport.Count & " ATMs, but " & missing & " of the " & totalCount & _
            " ATMs on the TOTAL list are not in it - a filter was probably on in the website." & vbCrLf & _
            "On the ATM Monitoring page remove every filter (show ALL ATMs) and click Export ATMs again." & vbCrLf & _
            "(If that many ATMs really were removed, delete them from TOTAL yourself: Review > Unprotect Sheet.)"
    End If
End Function

' Terminals typed on the REMOVED ATMS sheet (made empty on first use).
Private Function RemovedAtms() As Object
    Dim ws As Worksheet, r As Long, t As String
    Dim result As Object

    Set result = CreateObject("Scripting.Dictionary")
    result.CompareMode = 1
    Set RemovedAtms = result
    If Not HasSheet(ThisWorkbook, REMOVED_SHEET) Then CreateRemovedSheet
    Set ws = ThisWorkbook.Worksheets(REMOVED_SHEET)
    For r = REMOVED_FIRST_ROW To ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
        t = TerminalOf(ws.Cells(r, 1).Value)
        If Len(t) > 0 Then result(t) = True
    Next r
End Function

Public Sub CreateRemovedSheet()
    Dim ws As Worksheet, wasActive As Object
    If HasSheet(ThisWorkbook, REMOVED_SHEET) Then Exit Sub
    Set wasActive = ActiveSheet
    Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    On Error Resume Next
    wasActive.Activate          ' Add makes the new sheet active
    On Error GoTo 0
    ws.Name = REMOVED_SHEET
    ws.Range("A1").Value = "REMOVED ATMS - left out of every website import and report"
    ws.Range("A1").Font.Bold = True
    ws.Range("A1").Font.Size = 13
    ws.Range("A2").Value = "Type the terminal in column A (e.g. PRV12345). At each import its rows are dropped from " & _
                           "Raw Switch Data and PROBLEM IN ATM and its TOTAL row is deleted. To bring it back: " & _
                           "delete the line here and add the ATM to TOTAL again."
    ws.Range("A2").Font.Italic = True
    ws.Range("A3:C3").Value = Array("Terminal", "Branch / ATM", "Note (e.g. date removed, reason)")
    With ws.Range("A3:C3")
        .Font.Bold = True
        .Font.Color = RGB(255, 255, 255)
        .Interior.Color = RGB(31, 78, 120)
    End With
    ws.Range("A" & REMOVED_FIRST_ROW & ":C" & REMOVED_FIRST_ROW + 30).Interior.Color = RGB(255, 242, 204)
    ws.Columns(1).ColumnWidth = 16
    ws.Columns(2).ColumnWidth = 40
    ws.Columns(3).ColumnWidth = 50
End Sub

' Deletes the rows of removed terminals from a sheet in the website-table layout.
Private Sub DropRemovedAtms(ByVal ws As Worksheet, ByVal removed As Object)
    Dim headerRow As Long, tidCol As Long, r As Long
    If removed.Count = 0 Then Exit Sub
    For headerRow = 1 To 10
        tidCol = HeaderColumn(ws, headerRow, "TID (PID)")
        If tidCol > 0 Then Exit For
    Next headerRow
    If tidCol = 0 Then Exit Sub
    For r = ws.Cells(ws.Rows.Count, tidCol).End(xlUp).Row To headerRow + 1 Step -1
        If removed.Exists(TerminalOf(ws.Cells(r, tidCol).Value)) Then ws.Rows(r).Delete
    Next r
End Sub

' Deletes the TOTAL rows of removed terminals and numbers S.N (column A) again.
Private Sub RemoveFromTotal(ByVal removed As Object)
    Dim ws As Worksheet, r As Long, lastRow As Long, n As Long, sn As Long
    Dim names As String, t As String

    If removed.Count = 0 Then Exit Sub
    Set ws = ThisWorkbook.Worksheets("TOTAL")
    lastRow = ws.Cells(ws.Rows.Count, "B").End(xlUp).Row
    For r = lastRow To 2 Step -1
        t = TerminalOf(ws.Cells(r, 2).Value)
        If removed.Exists(t) Then
            If n = 0 Then
                On Error Resume Next
                ws.Unprotect  ' the refresh protects it again
                On Error GoTo 0
            End If
            names = vbCrLf & "    " & t & "  " & CStr(ws.Cells(r, 3).Value) & names
            ws.Rows(r).Delete
            n = n + 1
        End If
    Next r
    If n = 0 Then Exit Sub

    lastRow = ws.Cells(ws.Rows.Count, "B").End(xlUp).Row
    For r = 2 To lastRow
        If Len(TerminalOf(ws.Cells(r, 2).Value)) > 0 Then
            sn = sn + 1
            ws.Cells(r, 1).Value = sn
        End If
    Next r
    mImportNote = mImportNote & n & " ATM(s) on the '" & REMOVED_SHEET & "' sheet were deleted from TOTAL:" & names & vbCrLf & vbCrLf
End Sub

' "PRV12345 (100001)" -> "PRV12345"; empty if not a PRV terminal.
Private Function TerminalOf(ByVal v As Variant) As String
    Dim t As String
    If IsError(v) Then Exit Function
    t = UCase$(Trim$(CStr(v)))
    If InStr(t, "(") > 0 Then t = Trim$(Left$(t, InStr(t, "(") - 1))
    If InStr(t, " ") > 0 Then t = Left$(t, InStr(t, " ") - 1)
    If t Like "PRV#*" Then TerminalOf = t
End Function

' Move the imported file into Downloads\ATM SWITCH DATA, so Downloads stays clean and
' the same file is never imported twice. That folder keeps only today's exports:
' older ATM_SWITCH_DATA files in it are deleted.
Private Sub ArchiveExport(ByVal exportFile As String)
    Dim folder As String, target As String, baseName As String, f As String
    Dim n As Long
    Dim old As New Collection
    Dim item As Variant

    On Error GoTo Done
    folder = DownloadsFolder()
    If Len(folder) = 0 Then Exit Sub
    folder = folder & "\" & ARCHIVE_FOLDER
    If Len(Dir$(folder, vbDirectory)) = 0 Then MkDir folder

    baseName = Mid$(exportFile, InStrRev(exportFile, "\") + 1)
    If StrComp(Left$(exportFile, InStrRev(exportFile, "\") - 1), folder, vbTextCompare) <> 0 Then
        target = folder & "\" & baseName
        Do While Len(Dir$(target)) > 0
            n = n + 1
            target = folder & "\" & Left$(baseName, Len(baseName) - 5) & " (" & n & ").xlsx"
        Loop
        CreateObject("Scripting.FileSystemObject").MoveFile exportFile, target
    End If

    f = Dir$(folder & "\" & EXPORT_FILE_PATTERN)
    Do While Len(f) > 0
        If Int(FileDateTime(folder & "\" & f)) < Date Then old.Add folder & "\" & f
        f = Dir$()
    Loop
    For Each item In old
        Kill item
    Next item
Done:
    ' Could not move or delete (e.g. file open): leave it where it is.
End Sub

' The Windows Downloads folder (it can be moved, e.g. to another drive).
Private Function DownloadsFolder() As String
    On Error Resume Next
    With CreateObject("WScript.Shell")
        DownloadsFolder = .ExpandEnvironmentStrings(.RegRead( _
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\" & DOWNLOADS_GUID))
    End With
    On Error GoTo 0
    If Len(DownloadsFolder) = 0 Then DownloadsFolder = Environ$("USERPROFILE") & "\Downloads"
    If Right$(DownloadsFolder, 1) = "\" Then DownloadsFolder = Left$(DownloadsFolder, Len(DownloadsFolder) - 1)
    If Len(Dir$(DownloadsFolder, vbDirectory)) = 0 Then DownloadsFolder = vbNullString
End Function

' Empty string if wb looks like an atm_export.js file, otherwise the reason.
Private Function ExportProblem(ByVal wb As Workbook) As String
    Dim ws As Worksheet
    Dim r As Long, tidCol As Long, atmRows As Long

    If Not HasSheet(wb, "Raw Switch Data") Then ExportProblem = "The file has no 'Raw Switch Data' sheet.": Exit Function
    If Not HasSheet(wb, "PROBLEM IN ATM") Then ExportProblem = "The file has no 'PROBLEM IN ATM' sheet.": Exit Function
    Set ws = wb.Worksheets("Raw Switch Data")

    For r = 1 To 10
        tidCol = HeaderColumn(ws, r, "TID (PID)")
        If tidCol > 0 And HeaderColumn(ws, r, "NAME") > 0 And HeaderColumn(ws, r, "NPR") > 0 And _
           HeaderColumn(ws, r, "DISPENSER") > 0 Then Exit For
        tidCol = 0
    Next r
    If tidCol = 0 Then
        ExportProblem = "Header row with NAME, TID (PID), NPR and DISPENSER not found in 'Raw Switch Data'."
        Exit Function
    End If

    atmRows = Application.WorksheetFunction.CountIf(ws.Columns(tidCol), "PRV*")
    If atmRows < 10 Then ExportProblem = "Only " & atmRows & " ATM rows found in 'Raw Switch Data'."
End Function

Private Function HasSheet(ByVal wb As Workbook, ByVal sheetName As String) As Boolean
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = wb.Worksheets(sheetName)
    On Error GoTo 0
    HasSheet = Not ws Is Nothing
End Function

Private Function HeaderColumn(ByVal ws As Worksheet, ByVal headerRow As Long, ByVal headerText As String) As Long
    Dim c As Long, lastCol As Long

    lastCol = ws.Cells(headerRow, ws.Columns.Count).End(xlToLeft).Column
    For c = 1 To lastCol
        If UCase$(Trim$(CStr(ws.Cells(headerRow, c).Value))) = headerText Then
            HeaderColumn = c
            Exit Function
        End If
    Next c
End Function

' Clear, then copy the values without the Windows clipboard (Copy/PasteSpecial can
' fail or hang when other programs use the clipboard). The cells are text-formatted
' while the values go in, so every value stays text exactly as on the website
' (e.g. 1`065`000.00, 10.0.69.35), the same as a manual paste.
Private Sub CopySheetValues(ByVal wsSource As Worksheet, ByVal wsTarget As Worksheet)
    Dim src As Range, dest As Range

    On Error Resume Next
    wsTarget.Unprotect
    On Error GoTo 0

    wsTarget.Cells.Clear
    Set src = wsSource.UsedRange
    Set dest = wsTarget.Range("A1").Resize(src.Rows.Count, src.Columns.Count)
    dest.NumberFormat = "@"
    dest.Value = src.Value
    dest.NumberFormat = "General"
End Sub

' Newest export in the Windows Downloads folder (which can be moved, e.g. to
' another drive) or in %USERPROFILE%\Downloads.
Private Function NewestExportFile() As String
    Dim folders(1) As String
    Dim i As Long
    Dim f As String, best As String

    On Error Resume Next
    With CreateObject("WScript.Shell")
        folders(0) = .ExpandEnvironmentStrings(.RegRead( _
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\" & DOWNLOADS_GUID))
    End With
    On Error GoTo 0
    folders(1) = Environ$("USERPROFILE") & "\Downloads"

    For i = 0 To 1
        f = NewestFile(folders(i), EXPORT_FILE_PATTERN)
        If Len(f) > 0 Then
            If Len(best) = 0 Then
                best = f
            ElseIf FileDateTime(f) > FileDateTime(best) Then
                best = f
            End If
        End If
    Next i

    NewestExportFile = best
End Function

Private Function NewestFile(ByVal folderPath As String, ByVal pattern As String) As String
    Dim f As String
    Dim best As String
    Dim bestTime As Date

    If Len(folderPath) = 0 Then Exit Function
    If Right$(folderPath, 1) <> "\" Then folderPath = folderPath & "\"
    If Len(Dir$(folderPath, vbDirectory)) = 0 Then Exit Function

    f = Dir$(folderPath & pattern)
    Do While Len(f) > 0
        If Len(best) = 0 Or FileDateTime(folderPath & f) > bestTime Then
            best = folderPath & f
            bestTime = FileDateTime(best)
        End If
        f = Dir$()
    Loop

    NewestFile = best
End Function

Private Function PickFile(ByVal dialogTitle As String) As String
    With Application.FileDialog(3) ' msoFileDialogFilePicker
        .Title = dialogTitle
        .AllowMultiSelect = False
        .Filters.Clear
        .Filters.Add "Excel Files", "*.xlsx; *.xls"
        If .Show = -1 Then PickFile = CStr(.SelectedItems(1))
    End With
End Function
