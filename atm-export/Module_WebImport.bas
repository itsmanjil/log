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
' 1 PM / 8 PM report (Run1PMReport / Run8PMReport in Module2).
' ======================================================================

Private Const EXPORT_FILE_PATTERN As String = "ATM_SWITCH_DATA_*.xlsx"

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
    Dim oldScreenUpdating As Boolean
    Dim oldEnableEvents As Boolean
    Dim oldDisplayAlerts As Boolean
    Dim exportFile As String
    Dim msg As String
    Dim wbSource As Workbook

    oldScreenUpdating = Application.ScreenUpdating
    oldEnableEvents = Application.EnableEvents
    oldDisplayAlerts = Application.DisplayAlerts

    On Error GoTo SafeFail

    exportFile = NewestFile(Environ$("USERPROFILE") & "\Downloads\", EXPORT_FILE_PATTERN)
    If Len(exportFile) = 0 Then exportFile = PickFile("Select the website export (" & EXPORT_FILE_PATTERN & ")")
    If Len(exportFile) = 0 Then Exit Function

    msg = "Import this website export into Raw Switch Data and PROBLEM IN ATM?" & vbCrLf & vbCrLf & _
          "    " & Mid$(exportFile, InStrRev(exportFile, "\") + 1) & vbCrLf & _
          "    saved " & Format$(FileDateTime(exportFile), "dd/mm/yyyy hh:nn")
    If Int(FileDateTime(exportFile)) < Date Then
        msg = msg & vbCrLf & vbCrLf & "WARNING: this file is NOT from today."
    End If
    If MsgBox(msg, vbQuestion + vbYesNo, "Import Website Data") <> vbYes Then Exit Function

    Application.ScreenUpdating = False
    Application.EnableEvents = False
    Application.DisplayAlerts = False

    Set wbSource = Workbooks.Open(exportFile, UpdateLinks:=False, ReadOnly:=True)
    CopySheetValues wbSource.Worksheets("Raw Switch Data"), ThisWorkbook.Worksheets("Raw Switch Data")
    CopySheetValues wbSource.Worksheets("PROBLEM IN ATM"), ThisWorkbook.Worksheets("PROBLEM IN ATM")
    wbSource.Close SaveChanges:=False
    Set wbSource = Nothing

    Application.ScreenUpdating = oldScreenUpdating
    Application.EnableEvents = oldEnableEvents
    Application.DisplayAlerts = oldDisplayAlerts

    ImportWebExport = True
    Exit Function

SafeFail:
    msg = Err.Description
    Application.CutCopyMode = False
    If Not wbSource Is Nothing Then wbSource.Close SaveChanges:=False
    Application.ScreenUpdating = oldScreenUpdating
    Application.EnableEvents = oldEnableEvents
    Application.DisplayAlerts = oldDisplayAlerts
    MsgBox "Error: " & msg, vbExclamation, "Import Website Data"
End Function

' Same copy as ImportLastDispenseSwitchDataAndRefresh: clear, then paste values.
Private Sub CopySheetValues(ByVal wsSource As Worksheet, ByVal wsTarget As Worksheet)
    On Error Resume Next
    wsTarget.Unprotect
    On Error GoTo 0

    wsTarget.Cells.Clear
    wsSource.UsedRange.Copy
    wsTarget.Range("A1").PasteSpecial Paste:=xlPasteValues
    Application.CutCopyMode = False
End Sub

Private Function NewestFile(ByVal folderPath As String, ByVal pattern As String) As String
    Dim f As String
    Dim best As String
    Dim bestTime As Date

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
