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
Private Const MISSING_LABEL As String = "NOT IN SWITCH DATA"
Private Const MAX_MISSING_SHARE As Double = 0.1  ' more missing than this = filtered export, mark none

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

    mImportNote = vbNullString
    CopySheetValues wbSource.Worksheets("Raw Switch Data"), ThisWorkbook.Worksheets("Raw Switch Data")
    CopySheetValues wbSource.Worksheets("PROBLEM IN ATM"), ThisWorkbook.Worksheets("PROBLEM IN ATM")
    wbSource.Close SaveChanges:=False
    Set wbSource = Nothing

    MarkAtmsMissingFromExport
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

' An ATM deleted from the website is still on the TOTAL list, and the refresh
' keeps a TOTAL row's old values when its terminal is not in the new data - so
' it would stay in CASH LOW IN ATM / ATM NOT WORKING with stale figures. Mark
' such rows NOT IN SWITCH DATA (no cash / idle values) so the report skips
' them. Skipped when many ATMs are missing: that means a filtered export.
Private Sub MarkAtmsMissingFromExport()
    Dim wsRaw As Worksheet, wsTotal As Worksheet
    Dim present As Object
    Dim r As Long, tidCol As Long, headerRow As Long, lastRow As Long
    Dim terminal As String, missingList As String
    Dim totalCount As Long, missingCount As Long
    Dim data As Variant

    Set wsRaw = ThisWorkbook.Worksheets("Raw Switch Data")
    Set wsTotal = ThisWorkbook.Worksheets("TOTAL")

    For headerRow = 1 To 10
        tidCol = HeaderColumn(wsRaw, headerRow, "TID (PID)")
        If tidCol > 0 Then Exit For
    Next headerRow
    If tidCol = 0 Then Exit Sub

    Set present = CreateObject("Scripting.Dictionary")
    present.CompareMode = 1
    lastRow = wsRaw.Cells(wsRaw.Rows.Count, tidCol).End(xlUp).Row
    For r = headerRow + 1 To lastRow
        terminal = TerminalOf(wsRaw.Cells(r, tidCol).Value)
        If Len(terminal) > 0 Then present(terminal) = True
    Next r

    lastRow = wsTotal.Cells(wsTotal.Rows.Count, "B").End(xlUp).Row
    If lastRow < 2 Or present.Count = 0 Then Exit Sub
    data = wsTotal.Range("B2:H" & lastRow).Value  ' B terminal ... H remarks 2

    For r = 1 To UBound(data, 1)
        terminal = TerminalOf(data(r, 1))
        If Len(terminal) > 0 Then
            totalCount = totalCount + 1
            If Not present.Exists(terminal) Then
                missingCount = missingCount + 1
                missingList = missingList & vbCrLf & "    " & terminal & "  " & CStr(data(r, 2))
            End If
        End If
    Next r
    If missingCount = 0 Then Exit Sub

    If missingCount > totalCount * MAX_MISSING_SHARE Then
        mImportNote = missingCount & " of " & totalCount & " ATMs on the TOTAL list are not in this export. " & _
                      "That is too many to be deleted ATMs - was a filter on in the website?" & vbCrLf & _
                      "They were left unchanged."
        Exit Sub
    End If

    For r = 1 To UBound(data, 1)
        terminal = TerminalOf(data(r, 1))
        If Len(terminal) > 0 Then
            If Not present.Exists(terminal) Then
                data(r, 3) = Empty           ' D cash balance
                data(r, 4) = MISSING_LABEL   ' E last used
                data(r, 5) = MISSING_LABEL   ' F remarks 1
                data(r, 6) = Empty           ' G not working hours
                data(r, 7) = MISSING_LABEL   ' H remarks 2
            End If
        End If
    Next r
    On Error Resume Next
    wsTotal.Unprotect  ' the refresh protects it again
    On Error GoTo 0
    wsTotal.Range("B2:H" & lastRow).Value = data

    mImportNote = missingCount & " ATM(s) on the TOTAL list are not on the website any more, so they are " & _
                  "left out of CASH LOW IN ATM and ATM NOT WORKING:" & missingList & vbCrLf & vbCrLf & _
                  "If an ATM was removed for good, delete its row from the TOTAL sheet."
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
