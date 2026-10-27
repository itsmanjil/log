Attribute VB_Name = "Module_DispenserMail"
Option Explicit

' ======================================================================
' MAIL BRANCHES ABOUT CASH DISPENSER PROBLEMS
'
' Reads today's daily report (ATM DOWN REPORT sheet), takes every ATM whose
' latest row has Issue in ATM = PROBLEM IN CASH DISPENSER. and no ATM-UP
' date, and opens one ready-filled email per ATM in Outlook on the web
' (Chrome). Nothing is sent automatically: you check each mail and click Send.
'
' Branch email addresses, the Outlook web address and the mail text are kept
' on the "ATM EMAIL" sheet of this workbook (created on first use).
' ======================================================================

Private Const EMAIL_SHEET As String = "ATM EMAIL"
Private Const REPORT_SHEET As String = "ATM DOWN REPORT"
Private Const FIRST_ROW As Long = 11          ' first terminal row on ATM EMAIL
Private Const ROW_OWA As Long = 3             ' settings rows (value in column B)
Private Const ROW_CC As Long = 4
Private Const ROW_SUBJECT As Long = 5
Private Const ROW_BODY As Long = 6

' Daily report columns
Private Const COL_TERMINAL As Long = 2
Private Const COL_BRANCH As Long = 3
Private Const COL_DATE As Long = 4
Private Const COL_TIME As Long = 5
Private Const COL_UP As Long = 6
Private Const COL_ISSUE As Long = 7
Private Const COL_VENDOR As Long = 10
Private Const COL_REMARKS As Long = 13

' ATM EMAIL columns
Private Const E_TERMINAL As Long = 1
Private Const E_BRANCH As Long = 2
Private Const E_TO As Long = 3
Private Const E_CC As Long = 4
Private Const E_LAST As Long = 5

Public Sub MailDispenserProblems()
    Dim wbReport As Workbook
    Dim mails As Collection
    Dim m As Variant
    Dim ready As Long, msg As String, notSent As String
    Dim wsMail As Worksheet

    If Not HasSheet(ThisWorkbook, EMAIL_SHEET) Then
        CreateEmailSheet
        MsgBox "A new sheet '" & EMAIL_SHEET & "' was added." & vbCrLf & vbCrLf & _
               "1. Type each branch's email address in column C (column D for CC)." & vbCrLf & _
               "2. In cell B3 paste your Outlook web address from Chrome (e.g. https://outlook.office.com/mail/)." & vbCrLf & vbCrLf & _
               "Then click Mail Dispenser Problems again.", vbInformation, "Mail Dispenser Problems"
        ThisWorkbook.Worksheets(EMAIL_SHEET).Activate
        Exit Sub
    End If

    Set wbReport = FindDailyReport()
    If wbReport Is Nothing Then Exit Sub

    Set mails = BuildMails(wbReport)
    For Each m In mails
        If m(8) = "OK" Then
            ready = ready + 1
            msg = msg & vbCrLf & "    " & m(0) & "  " & m(1) & "  ->  " & m(2)
        Else
            notSent = notSent & vbCrLf & "    " & m(0) & "  " & m(1) & "  (" & m(8) & ")"
        End If
    Next m

    If mails.Count = 0 Then
        MsgBox "No open PROBLEM IN CASH DISPENSER. rows in " & wbReport.Name & ".", vbInformation, "Mail Dispenser Problems"
        Exit Sub
    End If
    If ready = 0 Then
        MsgBox "Nothing to mail from " & wbReport.Name & ":" & notSent & vbCrLf & vbCrLf & _
               "Add missing emails on the '" & EMAIL_SHEET & "' sheet. To mail an ATM again today, clear its 'Last mailed' cell.", _
               vbInformation, "Mail Dispenser Problems"
        Exit Sub
    End If

    msg = "Open " & ready & " email(s) in Outlook for PROBLEM IN CASH DISPENSER. (" & wbReport.Name & "):" & msg
    If Len(notSent) > 0 Then msg = msg & vbCrLf & vbCrLf & "Not mailed:" & notSent
    msg = msg & vbCrLf & vbCrLf & "Each mail opens in Chrome ready to send - check it and click Send."
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail Dispenser Problems") <> vbYes Then Exit Sub

    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)
    For Each m In mails
        If m(8) = "OK" Then
            CreateObject("Shell.Application").ShellExecute CStr(m(6))
            wsMail.Cells(CLng(m(7)), E_LAST).Value = Now
            wsMail.Cells(CLng(m(7)), E_LAST).NumberFormat = "dd/mm/yyyy hh:mm"
            Application.Wait Now + TimeSerial(0, 0, 1)
        End If
    Next m
End Sub

' For checking without opening anything: one line per ATM,
' "terminal <tab> status <tab> to <tab> link".
Public Function DispenserMailList(ByVal reportPath As String) As String
    Dim wb As Workbook, m As Variant, out As String, opened As Boolean

    Set wb = OpenWorkbookByPath(reportPath, opened)
    For Each m In BuildMails(wb)
        out = out & m(0) & vbTab & m(8) & vbTab & m(2) & vbTab & m(6) & vbLf
    Next m
    If opened Then wb.Close SaveChanges:=False
    DispenserMailList = out
End Function

' Each item: Array(terminal, branch, to, cc, subject, body, link, emailRow, status)
' status: OK / NO EMAIL / MAILED TODAY
Private Function BuildMails(ByVal wbReport As Workbook) As Collection
    Dim ws As Worksheet, wsMail As Worksheet
    Dim latest As Object, emailRow As Object
    Dim r As Long, lastRow As Long, row As Long
    Dim terminal As Variant, t As String
    Dim toAddr As String, cc As String, subj As String, body As String, status As String
    Dim owa As String, ccAll As String, subjTpl As String, bodyTpl As String
    Dim result As New Collection

    Set BuildMails = result
    Set ws = FindSheetTrim(wbReport, REPORT_SHEET)
    If ws Is Nothing Then Exit Function
    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)

    ' latest row per terminal (the 8 PM section comes after the 1 PM one)
    Set latest = CreateObject("Scripting.Dictionary")
    lastRow = ws.Cells(ws.Rows.Count, COL_TERMINAL).End(xlUp).Row
    For r = 1 To lastRow
        t = UCase$(Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value)))
        If t Like "PRV#*" Then latest(t) = r
    Next r

    Set emailRow = CreateObject("Scripting.Dictionary")
    lastRow = wsMail.Cells(wsMail.Rows.Count, E_TERMINAL).End(xlUp).Row
    For r = FIRST_ROW To lastRow
        t = UCase$(Trim$(CStr(wsMail.Cells(r, E_TERMINAL).Value)))
        If Len(t) > 0 And Not emailRow.Exists(t) Then emailRow(t) = r
    Next r

    owa = Trim$(CStr(wsMail.Cells(ROW_OWA, 2).Value))
    ccAll = Trim$(CStr(wsMail.Cells(ROW_CC, 2).Value))
    subjTpl = CStr(wsMail.Cells(ROW_SUBJECT, 2).Value)
    bodyTpl = CStr(wsMail.Cells(ROW_BODY, 2).Value)

    For Each terminal In latest.Keys
        r = latest(terminal)
        If InStr(1, CStr(ws.Cells(r, COL_ISSUE).Value), "CASH DISPENSER", vbTextCompare) > 0 And _
           Len(Trim$(CStr(ws.Cells(r, COL_UP).Value))) = 0 Then
            row = 0: toAddr = "": cc = ccAll
            If emailRow.Exists(terminal) Then
                row = emailRow(terminal)
                toAddr = Trim$(CStr(wsMail.Cells(row, E_TO).Value))
                cc = JoinAddresses(Trim$(CStr(wsMail.Cells(row, E_CC).Value)), ccAll)
            End If

            If Len(toAddr) = 0 Then
                status = "NO EMAIL"
            ElseIf IsDate(wsMail.Cells(row, E_LAST).Value) And Int(CDbl(CDate(wsMail.Cells(row, E_LAST).Value))) = CDbl(Date) Then
                status = "MAILED TODAY"
            Else
                status = "OK"
            End If

            subj = FillTemplate(subjTpl, ws, r)
            body = FillTemplate(bodyTpl, ws, r)
            result.Add Array(CStr(terminal), Trim$(CStr(ws.Cells(r, COL_BRANCH).Value)), toAddr, cc, subj, body, _
                             ComposeLink(owa, toAddr, cc, subj, body), row, status)
        End If
    Next terminal
End Function

' {TERMINAL} {BRANCH} {DATE} {TIME} {VENDOR} {REMARKS} {NL}; Alt+Enter line breaks work too.
Private Function FillTemplate(ByVal tpl As String, ByVal ws As Worksheet, ByVal r As Long) As String
    Dim s As String, v As Variant, dateText As String, timeText As String

    v = ws.Cells(r, COL_DATE).Value
    If IsDate(v) Then dateText = Format$(v, "dd/mm/yyyy") Else dateText = Trim$(CStr(v))
    v = ws.Cells(r, COL_TIME).Value
    If IsNumeric(v) And Not IsEmpty(v) Then
        timeText = Format$(CDbl(v), "h:mm AM/PM")
    ElseIf IsDate(v) Then
        timeText = Format$(v, "h:mm AM/PM")
    Else
        timeText = Trim$(CStr(v))
    End If

    s = Replace(Replace(tpl, vbCrLf, vbLf), vbLf, vbCrLf)
    s = Replace(s, "{NL}", vbCrLf, , , vbTextCompare)
    s = Replace(s, "{TERMINAL}", Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value)), , , vbTextCompare)
    s = Replace(s, "{BRANCH}", Trim$(CStr(ws.Cells(r, COL_BRANCH).Value)), , , vbTextCompare)
    s = Replace(s, "{DATE}", dateText, , , vbTextCompare)
    s = Replace(s, "{TIME}", timeText, , , vbTextCompare)
    s = Replace(s, "{VENDOR}", Trim$(CStr(ws.Cells(r, COL_VENDOR).Value)), , , vbTextCompare)
    s = Replace(s, "{REMARKS}", Trim$(CStr(ws.Cells(r, COL_REMARKS).Value)), , , vbTextCompare)
    FillTemplate = s
End Function

' Link that opens a filled-in new mail:
'   Outlook on the web (Microsoft 365)  https://outlook.office.com/mail/deeplink/compose?...
'   Outlook on the web (bank server)    https://<server>/owa/?path=/mail/action/compose&...
'   no address in B3                    mailto:... (opens the PC's default mail program)
Private Function ComposeLink(ByVal owa As String, ByVal toAddr As String, ByVal cc As String, _
                             ByVal subj As String, ByVal body As String) As String
    Dim q As String, host As String, lowerOwa As String

    q = "to=" & Enc(toAddr)
    If Len(cc) > 0 Then q = q & "&cc=" & Enc(cc)
    q = q & "&subject=" & Enc(subj) & "&body=" & Enc(body)

    lowerOwa = LCase$(owa)
    If Len(owa) = 0 Then
        ComposeLink = "mailto:" & Replace(toAddr, " ", "") & "?" & Mid$(q, InStr(q, "&") + 1)
    ElseIf InStr(lowerOwa, "outlook.office") > 0 Or InStr(lowerOwa, "office365.com") > 0 Then
        ComposeLink = "https://outlook.office.com/mail/deeplink/compose?" & q
    ElseIf InStr(lowerOwa, "outlook.live.com") > 0 Then
        ComposeLink = "https://outlook.live.com/mail/0/deeplink/compose?" & q
    Else
        host = owa
        If InStr(host, "#") > 0 Then host = Left$(host, InStr(host, "#") - 1)
        If InStr(host, "?") > 0 Then host = Left$(host, InStr(host, "?") - 1)
        If InStr(1, host, "/owa", vbTextCompare) > 0 Then host = Left$(host, InStr(1, host, "/owa", vbTextCompare) + 3)
        If Right$(host, 1) <> "/" Then host = host & "/"
        ComposeLink = host & "?path=/mail/action/compose&" & q
    End If
End Function

Private Function Enc(ByVal s As String) As String
    Enc = Application.WorksheetFunction.EncodeURL(s)
End Function

Private Function JoinAddresses(ByVal a As String, ByVal b As String) As String
    If Len(a) > 0 And Len(b) > 0 Then
        JoinAddresses = a & ";" & b
    Else
        JoinAddresses = a & b
    End If
End Function

' Today's daily report if it is open, else the only open daily report, else ask.
Private Function FindDailyReport() As Workbook
    Dim wb As Workbook, found As Workbook, n As Long
    Dim picked As Variant
    Dim opened As Boolean

    For Each wb In Application.Workbooks
        If Not FindSheetTrim(wb, REPORT_SHEET) Is Nothing Then
            If StrComp(wb.Name, Format$(Date, "dd.mm.yyyy") & ".xlsx", vbTextCompare) = 0 Then
                Set FindDailyReport = wb
                Exit Function
            End If
            Set found = wb
            n = n + 1
        End If
    Next wb
    If n = 1 Then Set FindDailyReport = found: Exit Function

    picked = Application.GetOpenFilename("Excel Files (*.xlsx),*.xlsx", , "Select today's daily report (" & Format$(Date, "dd.mm.yyyy") & ".xlsx)")
    If VarType(picked) = vbBoolean Then Exit Function
    Set FindDailyReport = OpenWorkbookByPath(CStr(picked), opened)
    If FindSheetTrim(FindDailyReport, REPORT_SHEET) Is Nothing Then
        MsgBox "That file has no '" & REPORT_SHEET & "' sheet.", vbExclamation, "Mail Dispenser Problems"
        Set FindDailyReport = Nothing
    End If
End Function

Private Function OpenWorkbookByPath(ByVal path As String, ByRef opened As Boolean) As Workbook
    Dim wb As Workbook
    For Each wb In Application.Workbooks
        If StrComp(wb.FullName, path, vbTextCompare) = 0 Then Set OpenWorkbookByPath = wb: Exit Function
    Next wb
    Set OpenWorkbookByPath = Workbooks.Open(path, UpdateLinks:=False, ReadOnly:=True)
    opened = True
End Function

Private Function FindSheetTrim(ByVal wb As Workbook, ByVal sheetName As String) As Worksheet
    Dim ws As Worksheet
    For Each ws In wb.Worksheets
        If StrComp(Trim$(ws.Name), sheetName, vbTextCompare) = 0 Then Set FindSheetTrim = ws: Exit Function
    Next ws
End Function

Private Function HasSheet(ByVal wb As Workbook, ByVal sheetName As String) As Boolean
    HasSheet = Not FindSheetTrim(wb, sheetName) Is Nothing
End Function

' Builds the ATM EMAIL sheet: settings on top, then every terminal on the TOTAL list.
Public Sub CreateEmailSheet()
    Dim ws As Worksheet, wsTotal As Worksheet
    Dim lastRow As Long, r As Long, n As Long
    Dim t As String

    If HasSheet(ThisWorkbook, EMAIL_SHEET) Then Exit Sub
    Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    ws.Name = EMAIL_SHEET

    ws.Range("A1").Value = "ATM EMAIL LIST - used by Mail Dispenser Problems"
    ws.Range("A1").Font.Bold = True
    ws.Range("A1").Font.Size = 13
    ws.Cells(ROW_OWA, 1).Value = "Outlook web address"
    ws.Cells(ROW_OWA, 3).Value = "Copy from Chrome's address bar while Outlook is open, e.g. https://outlook.office.com/mail/ (empty = default mail program)"
    ws.Cells(ROW_CC, 1).Value = "Always CC"
    ws.Cells(ROW_CC, 3).Value = "Optional, e.g. your team's address. Separate several with ;"
    ws.Cells(ROW_SUBJECT, 1).Value = "Subject"
    ws.Cells(ROW_SUBJECT, 2).Value = "ATM Cash Dispenser Problem - {BRANCH} ({TERMINAL})"
    ws.Cells(ROW_BODY, 1).Value = "Message"
    ws.Cells(ROW_BODY, 2).Value = "Dear Sir/Madam," & vbLf & vbLf & _
        "Your ATM {BRANCH} ({TERMINAL}) has a cash dispenser problem since {DATE} {TIME}." & vbLf & _
        "Please check the ATM and coordinate with the vendor to resolve it as soon as possible." & vbLf & vbLf & _
        "Regards," & vbLf & "ATM Monitoring"
    ws.Cells(ROW_BODY, 3).Value = "Placeholders: {TERMINAL} {BRANCH} {DATE} {TIME} {VENDOR} {REMARKS}. Alt+Enter for a new line."
    ws.Range(ws.Cells(ROW_OWA, 1), ws.Cells(ROW_BODY, 1)).Font.Bold = True
    ws.Range(ws.Cells(ROW_OWA, 3), ws.Cells(ROW_BODY, 3)).Font.Italic = True
    ws.Range(ws.Cells(ROW_OWA, 3), ws.Cells(ROW_BODY, 3)).Font.Color = RGB(89, 89, 89)
    ws.Range(ws.Cells(ROW_OWA, 2), ws.Cells(ROW_BODY, 2)).Interior.Color = RGB(255, 242, 204)
    ws.Cells(ROW_BODY, 2).WrapText = True
    ws.Rows(ROW_BODY).RowHeight = 105

    ws.Cells(FIRST_ROW - 1, E_TERMINAL).Value = "Terminal"
    ws.Cells(FIRST_ROW - 1, E_BRANCH).Value = "Branch / ATM"
    ws.Cells(FIRST_ROW - 1, E_TO).Value = "Email (To)"
    ws.Cells(FIRST_ROW - 1, E_CC).Value = "CC"
    ws.Cells(FIRST_ROW - 1, E_LAST).Value = "Last mailed"
    With ws.Range(ws.Cells(FIRST_ROW - 1, 1), ws.Cells(FIRST_ROW - 1, E_LAST))
        .Font.Bold = True
        .Font.Color = RGB(255, 255, 255)
        .Interior.Color = RGB(31, 78, 120)
    End With

    Set wsTotal = ThisWorkbook.Worksheets("TOTAL")
    lastRow = wsTotal.Cells(wsTotal.Rows.Count, 2).End(xlUp).Row
    r = FIRST_ROW
    For n = 2 To lastRow
        t = UCase$(Trim$(CStr(wsTotal.Cells(n, 2).Value)))
        If t Like "PRV#*" Then
            ws.Cells(r, E_TERMINAL).Value = t
            ws.Cells(r, E_BRANCH).Value = Trim$(CStr(wsTotal.Cells(n, 3).Value))
            r = r + 1
        End If
    Next n
    If r > FIRST_ROW + 1 Then
        ws.Range(ws.Cells(FIRST_ROW, 1), ws.Cells(r - 1, E_LAST)).Sort Key1:=ws.Cells(FIRST_ROW, 1), Order1:=xlAscending, Header:=xlNo
    End If
    ws.Range(ws.Cells(FIRST_ROW, E_TO), ws.Cells(r - 1, E_CC)).Interior.Color = RGB(255, 242, 204)

    ws.Columns(1).ColumnWidth = 22
    ws.Columns(2).ColumnWidth = 60
    ws.Columns(3).ColumnWidth = 34
    ws.Columns(4).ColumnWidth = 30
    ws.Columns(5).ColumnWidth = 17
    ws.Range("A:E").VerticalAlignment = xlTop
    On Error Resume Next  ' freezing needs a visible window
    ws.Activate
    ws.Range("A" & FIRST_ROW).Select
    ActiveWindow.FreezePanes = True
    ws.Range("C" & FIRST_ROW).Select
    On Error GoTo 0
End Sub
