Attribute VB_Name = "Module_WebImport"
Option Explicit

' ======================================================================
' IMPORT WEBSITE EXPORTS (atm_export.js) AND RUN THE DAILY REPORT
'
' The browser script saves the ATM Monitoring table as
'   ATM_RAW_SWITCH_DATA_<date>_<time>.xlsx   (all ATMs)
'   ATM_PROBLEM_IN_ATM_<date>_<time>.xlsx    (problem ATMs)
' in the same layout as copy-pasting the website table. These macros take
' the newest file of each kind from the Downloads folder (or ask for it),
' put them into Raw Switch Data / PROBLEM IN ATM, then run the normal
' 1 PM / 8 PM report (Run1PMReport / Run8PMReport in Module2).
' ======================================================================

Private Const RAW_FILE_PATTERN As String = "ATM_RAW_SWITCH_DATA_*.xlsx"
Private Const PROBLEM_FILE_PATTERN As String = "ATM_PROBLEM_IN_ATM_*.xlsx"

Public Sub ImportWebDataAndRun1PMReport()
    If ImportWebExports() Then Run1PMReport
End Sub

Public Sub ImportWebDataAndRun8PMReport()
    If ImportWebExports() Then Run8PMReport
End Sub

Public Sub ImportWebDataOnly()
    If ImportWebExports() Then
        MsgBox "Raw Switch Data and PROBLEM IN ATM updated from the website export files.", vbInformation
    End If
End Sub

Private Function ImportWebExports() As Boolean
    Dim oldScreenUpdating As Boolean
    Dim oldEnableEvents As Boolean
    Dim oldDisplayAlerts As Boolean
    Dim downloadsFolder As String
    Dim rawFile As String
    Dim problemFile As String
    Dim msg As String

    oldScreenUpdating = Application.ScreenUpdating
    oldEnableEvents = Application.EnableEvents
    oldDisplayAlerts = Application.DisplayAlerts

    On Error GoTo SafeFail

    downloadsFolder = Environ$("USERPROFILE") & "\Downloads\"

    rawFile = NewestFile(downloadsFolder, RAW_FILE_PATTERN)
    If Len(rawFile) = 0 Then rawFile = PickFile("Select the ALL ATMs export (" & RAW_FILE_PATTERN & ")")
    If Len(rawFile) = 0 Then Exit Function

    problemFile = NewestFile(downloadsFolder, PROBLEM_FILE_PATTERN)
    If Len(problemFile) = 0 Then problemFile = PickFile("Select the PROBLEM ATMs export (" & PROBLEM_FILE_PATTERN & ")")
    If Len(problemFile) = 0 Then Exit Function

    msg = "Import these website exports?" & vbCrLf & vbCrLf & _
          "Raw Switch Data:" & vbCrLf & "    " & FileLabel(rawFile) & vbCrLf & _
          "PROBLEM IN ATM:" & vbCrLf & "    " & FileLabel(problemFile)
    If Int(FileDateTime(rawFile)) < Date Or Int(FileDateTime(problemFile)) < Date Then
        msg = msg & vbCrLf & vbCrLf & "WARNING: at least one file is NOT from today."
    End If
    If MsgBox(msg, vbQuestion + vbYesNo, "Import Website Data") <> vbYes Then Exit Function

    Application.ScreenUpdating = False
    Application.EnableEvents = False
    Application.DisplayAlerts = False

    CopyExportIntoSheet rawFile, ThisWorkbook.Worksheets("Raw Switch Data")
    CopyExportIntoSheet problemFile, ThisWorkbook.Worksheets("PROBLEM IN ATM")

    Application.ScreenUpdating = oldScreenUpdating
    Application.EnableEvents = oldEnableEvents
    Application.DisplayAlerts = oldDisplayAlerts

    ImportWebExports = True
    Exit Function

SafeFail:
    Application.ScreenUpdating = oldScreenUpdating
    Application.EnableEvents = oldEnableEvents
    Application.DisplayAlerts = oldDisplayAlerts
    MsgBox "Error: " & Err.Description, vbExclamation, "Import Website Data"
End Function

' Same copy as ImportLastDispenseSwitchDataAndRefresh: values only, first sheet.
Private Sub CopyExportIntoSheet(ByVal filePath As String, ByVal wsTarget As Worksheet)
    Dim wbSource As Workbook
    Dim errNum As Long
    Dim errDesc As String

    On Error GoTo SafeFail

    Set wbSource = Workbooks.Open(filePath, UpdateLinks:=False, ReadOnly:=True)

    On Error Resume Next
    wsTarget.Unprotect
    On Error GoTo SafeFail

    wsTarget.Cells.Clear
    wbSource.Worksheets(1).UsedRange.Copy
    wsTarget.Range("A1").PasteSpecial Paste:=xlPasteValues
    Application.CutCopyMode = False

    wbSource.Close SaveChanges:=False
    Exit Sub

SafeFail:
    errNum = Err.Number
    errDesc = Err.Description
    Application.CutCopyMode = False
    If Not wbSource Is Nothing Then wbSource.Close SaveChanges:=False
    Err.Raise errNum, , wsTarget.Name & ": " & errDesc
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

Private Function FileLabel(ByVal filePath As String) As String
    FileLabel = Mid$(filePath, InStrRev(filePath, "\") + 1) & _
                "   (" & Format$(FileDateTime(filePath), "dd/mm/yyyy hh:nn") & ")"
End Function
