Attribute VB_Name = "Module_DownAtmMail"
Option Explicit

' ======================================================================
' MAIL BRANCHES ABOUT ATMS THAT ARE DOWN
'
' Reads the latest section (8 PM if present, else 1 PM) of today's daily
' report, sheet ATM DOWN REPORT, and takes every ATM that
'   - has no ATM-UP date,
'   - is not a red row (red text = already with the vendor),
'   - is not NO TRANSACTION IN ATM. / CHECK ATM (only idle, not a fault),
'   - has been down at least the hours set on ATM EMAIL (default 1),
' whatever the issue. For each one it opens a ready-filled new mail in
' Outlook on the web (Chrome). Nothing is sent automatically: you check each
' mail and click Send.
'
' Branch email, phone, the Outlook web address and the mail text are kept on
' the "ATM EMAIL" sheet of this workbook (created on first use).
' ======================================================================

Private Const EMAIL_SHEET As String = "ATM EMAIL"
Private Const REPORT_SHEET As String = "ATM DOWN REPORT"
Private Const FIRST_ROW As Long = 12          ' first terminal row on ATM EMAIL (headers on row 11)
Private Const ROW_OWA As Long = 3             ' settings rows (value in column B)
Private Const ROW_CC As Long = 4
Private Const ROW_HOURS As Long = 5
Private Const ROW_SUBJECT As Long = 6
Private Const ROW_BODY As Long = 7
Private Const ROW_ONEMAIL As Long = 8          ' YES = all ATMs in one mail
Private Const ROW_ONESUBJECT As Long = 9      ' subject of that one mail
Private Const ROW_LINE As Long = 10           ' one line per ATM in that mail
Private Const DEFAULT_OWA As String = "https://outlook.office.com/mail/"

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
Private Const E_PHONE As Long = 5
Private Const E_LAST As Long = 6

' Item fields
Private Const I_TERMINAL = 0, I_BRANCH = 1, I_TO = 2, I_LINK = 3, I_EMAILROW = 4, I_STATUS = 5, _
              I_ISSUE = 6, I_DOWNFOR = 7, I_PHONE = 8, I_SUBJECT = 9, I_CC = 10, I_LINE = 11

Public Sub MailDownAtms()
    Dim wbReport As Workbook
    Dim mails As Collection
    Dim m As Variant
    Dim ready As Long, msg As String, notSent As String
    Dim wsMail As Worksheet
    Dim firstOk As Variant

    If Not HasSheet(ThisWorkbook, EMAIL_SHEET) Then
        CreateEmailSheet
        MsgBox "A new sheet '" & EMAIL_SHEET & "' was added." & vbCrLf & vbCrLf & _
               "Type each branch's email in column C (column D for CC) and phone number in column E, " & _
               "then click Mail Down ATMs again.", vbInformation, "Mail Down ATMs"
        ThisWorkbook.Worksheets(EMAIL_SHEET).Activate
        Exit Sub
    End If
    UpgradeEmailSheet

    Set wbReport = FindDailyReport()
    If wbReport Is Nothing Then Exit Sub

    Set mails = BuildMails(wbReport)
    For Each m In mails
        If m(I_STATUS) = "OK" Then
            ready = ready + 1
            If ready = 1 Then firstOk = m
            msg = msg & vbCrLf & "    " & m(I_TERMINAL) & "  " & m(I_BRANCH) & "  (" & m(I_ISSUE) & ", down " & m(I_DOWNFOR) & ")"
        Else
            notSent = notSent & vbCrLf & "    " & m(I_TERMINAL) & "  " & m(I_BRANCH) & "  - " & m(I_STATUS) & _
                      IIf(Len(m(I_PHONE)) > 0, "  phone " & m(I_PHONE), "")
        End If
    Next m

    If mails.Count = 0 Then
        MsgBox "No ATM in the latest section of " & wbReport.Name & " has been down " & HoursText() & _
               " or more (red rows, ATMs already up and no-transaction / CHECK ATM rows are not counted).", vbInformation, "Mail Down ATMs"
        Exit Sub
    End If
    If OneMailMode() Then
        MailAllInOne mails, wbReport
        Exit Sub
    End If
    If ready = 0 Then
        MsgBox "Nothing to mail from " & wbReport.Name & ":" & notSent & vbCrLf & vbCrLf & _
               "Add missing emails on the '" & EMAIL_SHEET & "' sheet. To mail an ATM again today, clear its 'Last mailed' cell.", _
               vbInformation, "Mail Down ATMs"
        Exit Sub
    End If

    msg = "Open " & ready & " email(s) in Outlook for ATMs down " & HoursText() & " or more (" & wbReport.Name & "):" & msg
    If Len(notSent) > 0 Then msg = msg & vbCrLf & vbCrLf & "Not mailed:" & notSent
    ' show what the ATM EMAIL settings produce, so changes there are visible before sending
    msg = msg & vbCrLf & vbCrLf & "First mail:" & vbCrLf & _
          "    To: " & firstOk(I_TO) & vbCrLf & _
          "    CC: " & IIf(Len(firstOk(I_CC)) > 0, firstOk(I_CC), "(none - cell B4 on " & EMAIL_SHEET & ")") & vbCrLf & _
          "    Subject: " & firstOk(I_SUBJECT)
    msg = msg & vbCrLf & vbCrLf & "Each mail opens in Chrome ready to send - check it and click Send." & vbCrLf & _
          "If Outlook leaves the CC box empty, add the CC address in Outlook before sending."
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail Down ATMs") <> vbYes Then Exit Sub

    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)
    For Each m In mails
        If m(I_STATUS) = "OK" Then
            CreateObject("Shell.Application").ShellExecute CStr(m(I_LINK))
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).Value = Now
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).NumberFormat = "dd/mm/yyyy hh:mm"
            Application.Wait Now + TimeSerial(0, 0, 1)
        End If
    Next m
End Sub

' For checking without opening anything: one line per ATM,
' "terminal <tab> status <tab> to <tab> issue <tab> down for <tab> link".
Public Function DownAtmMailList(ByVal reportPath As String) As String
    Dim wb As Workbook, m As Variant, out As String, opened As Boolean

    UpgradeEmailSheet
    Set wb = OpenWorkbookByPath(reportPath, opened)
    Dim mails As Collection, toAddr As String, cc As String, subj As String, body As String, n As Long, skipped As String
    Set mails = BuildMails(wb)
    If OneMailMode() Then
        out = "ONE MAIL" & vbTab & BuildOneMail(mails, toAddr, cc, subj, body, n, skipped) & vbTab & toAddr & vbTab & cc & vbTab & n & vbLf
    End If
    For Each m In mails
        out = out & m(I_TERMINAL) & vbTab & m(I_STATUS) & vbTab & m(I_TO) & vbTab & m(I_ISSUE) & vbTab & _
              m(I_DOWNFOR) & vbTab & m(I_LINK) & vbLf
    Next m
    If opened Then wb.Close SaveChanges:=False
    DownAtmMailList = out
End Function

' Each item: see the I_ constants. Status: OK / NO EMAIL / MAILED TODAY
Private Function BuildMails(ByVal wbReport As Workbook) As Collection
    Dim ws As Worksheet, wsMail As Worksheet
    Dim emailRow As Object, seen As Object
    Dim r As Long, lastRow As Long, row As Long, startRow As Long
    Dim t As String, toAddr As String, cc As String, status As String, phone As String, subj As String
    Dim owa As String, ccAll As String, subjTpl As String, bodyTpl As String, lineTpl As String
    Dim downSince As Date, minHours As Double, hoursDown As Double
    Dim result As New Collection

    Set BuildMails = result
    Set ws = FindSheetTrim(wbReport, REPORT_SHEET)
    If ws Is Nothing Then Exit Function
    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)

    Set emailRow = CreateObject("Scripting.Dictionary")
    lastRow = wsMail.Cells(wsMail.Rows.Count, E_TERMINAL).End(xlUp).Row
    For r = FIRST_ROW To lastRow
        t = UCase$(Trim$(CStr(wsMail.Cells(r, E_TERMINAL).Value)))
        If Len(t) > 0 And Not emailRow.Exists(t) Then emailRow(t) = r
    Next r

    owa = Trim$(CStr(wsMail.Cells(ROW_OWA, 2).Value))
    ccAll = CleanAddresses(CStr(wsMail.Cells(ROW_CC, 2).Value))
    minHours = MinDownHours()
    subjTpl = CStr(wsMail.Cells(ROW_SUBJECT, 2).Value)
    bodyTpl = CStr(wsMail.Cells(ROW_BODY, 2).Value)
    lineTpl = CStr(wsMail.Cells(ROW_LINE, 2).Value)
    If Len(Trim$(lineTpl)) = 0 Then lineTpl = DefaultLine()

    ' only the latest section: rows after the last "ATM DOWN REPORT ..." title
    lastRow = ws.Cells(ws.Rows.Count, COL_TERMINAL).End(xlUp).Row
    startRow = 1
    For r = 1 To lastRow
        If InStr(1, CStr(ws.Cells(r, 1).Value), REPORT_SHEET, vbTextCompare) > 0 Then startRow = r + 1
    Next r

    Set seen = CreateObject("Scripting.Dictionary")
    For r = startRow To lastRow
        t = UCase$(Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value)))
        If t Like "PRV#*" And Not seen.Exists(t) Then
            seen(t) = True
            If Len(Trim$(CStr(ws.Cells(r, COL_UP).Value))) = 0 And Not RowHasRedText(ws, r) And _
               Not IsNoTransactionIssue(ws, r) And DownSinceOf(ws, r, downSince) Then
                hoursDown = (Now - downSince) * 24
                If hoursDown >= minHours Then
                    row = 0: toAddr = "": cc = ccAll: phone = ""
                    If emailRow.Exists(t) Then
                        row = emailRow(t)
                        toAddr = CleanAddresses(CStr(wsMail.Cells(row, E_TO).Value))
                        cc = JoinAddresses(CStr(wsMail.Cells(row, E_CC).Value), ccAll)
                        phone = Trim$(CStr(wsMail.Cells(row, E_PHONE).Value))
                    End If

                    If Len(toAddr) = 0 Then
                        status = "NO EMAIL"
                    ElseIf IsDate(wsMail.Cells(row, E_LAST).Value) And _
                           Int(CDbl(CDate(wsMail.Cells(row, E_LAST).Value))) = CDbl(Date) Then
                        status = "MAILED TODAY"
                    Else
                        status = "OK"
                    End If

                    subj = FillTemplate(subjTpl, ws, r, downSince, hoursDown, phone)
                    result.Add Array(t, Trim$(CStr(ws.Cells(r, COL_BRANCH).Value)), toAddr, _
                        ComposeLink(owa, toAddr, cc, subj, FillTemplate(bodyTpl, ws, r, downSince, hoursDown, phone)), _
                        row, status, IssueOf(ws, r), DurationText(hoursDown), phone, subj, cc, _
                        FillTemplate(lineTpl, ws, r, downSince, hoursDown, phone))
                End If
            End If
        End If
    Next r
End Function

' Issue Identified Date + Down time of a report row; False if the date is missing.
Private Function DownSinceOf(ByVal ws As Worksheet, ByVal r As Long, ByRef downSince As Date) As Boolean
    Dim d As Variant, tm As Variant, timePart As Double

    d = ws.Cells(r, COL_DATE).Value
    If Not IsDate(d) Then Exit Function
    tm = ws.Cells(r, COL_TIME).Value
    If IsDate(tm) Then
        timePart = CDbl(TimeValue(tm))
    ElseIf IsNumeric(tm) And Not IsEmpty(tm) Then
        timePart = CDbl(tm) - Int(CDbl(tm))
    End If
    downSince = CDate(Int(CDbl(CDate(d))) + timePart)
    DownSinceOf = True
End Function

' Same rule as the report macros (IsCellFontRed): any non-empty cell with red text.
Private Function RowHasRedText(ByVal ws As Worksheet, ByVal r As Long) As Boolean
    Dim c As Long, colorValue As Long
    On Error Resume Next
    For c = 1 To COL_REMARKS
        If Len(Trim$(CStr(ws.Cells(r, c).Text))) > 0 Then
            If ws.Cells(r, c).Font.ColorIndex = 3 Then RowHasRedText = True: Exit Function
            colorValue = CLng(ws.Cells(r, c).Font.Color)
            If (colorValue Mod 256) >= 180 And ((colorValue \ 256) Mod 256) <= 100 And _
               ((colorValue \ 65536) Mod 256) <= 100 Then RowHasRedText = True: Exit Function
        End If
    Next c
End Function

' Not a fault, only no transactions: "NO TRANSACTION IN ATM." chosen by staff, or the
' "CHECK ATM" rows the report writes for ATMs idle 2+ hours. These are never mailed.
Private Function IsNoTransactionIssue(ByVal ws As Worksheet, ByVal r As Long) As Boolean
    Dim issue As String
    issue = UCase$(Trim$(CStr(ws.Cells(r, COL_ISSUE).Value)))
    IsNoTransactionIssue = InStr(issue, "NO TRANSACTION") > 0 Or issue = "CHECK ATM"
End Function

Private Function IssueOf(ByVal ws As Worksheet, ByVal r As Long) As String
    IssueOf = Trim$(CStr(ws.Cells(r, COL_ISSUE).Value))
    If Right$(IssueOf, 1) = "." Then IssueOf = Left$(IssueOf, Len(IssueOf) - 1)
    If Len(IssueOf) = 0 Then IssueOf = "issue not entered yet"
End Function

Private Function DurationText(ByVal hours As Double) As String
    Dim d As Long, h As Long, mins As Long
    mins = Int(hours * 60)
    d = mins \ 1440: h = (mins Mod 1440) \ 60: mins = mins Mod 60
    If d > 0 Then DurationText = d & IIf(d = 1, " day ", " days ")
    If h > 0 Or d > 0 Then DurationText = DurationText & h & IIf(h = 1, " hour ", " hours ")
    If d = 0 And (mins > 0 Or h = 0) Then DurationText = DurationText & mins & " mins"
    DurationText = Trim$(DurationText)
End Function

Private Function MinDownHours() As Double
    Dim v As Variant
    v = ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(ROW_HOURS, 2).Value
    If IsNumeric(v) And Not IsEmpty(v) Then MinDownHours = CDbl(v) Else MinDownHours = 1
End Function

Private Function HoursText() As String
    HoursText = MinDownHours() & IIf(MinDownHours() = 1, " hour", " hours")
End Function

' {TERMINAL} {BRANCH} {ISSUE} {DATE} {TIME} {DOWNFOR} {VENDOR} {REMARKS} {PHONE} {NL}; Alt+Enter works too.
Private Function FillTemplate(ByVal tpl As String, ByVal ws As Worksheet, ByVal r As Long, _
                              ByVal downSince As Date, ByVal hoursDown As Double, ByVal phone As String) As String
    Dim s As String

    s = Replace(Replace(tpl, vbCrLf, vbLf), vbLf, vbCrLf)
    s = Replace(s, "{NL}", vbCrLf, , , vbTextCompare)
    s = Replace(s, "{TERMINAL}", Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value)), , , vbTextCompare)
    s = Replace(s, "{BRANCH}", Trim$(CStr(ws.Cells(r, COL_BRANCH).Value)), , , vbTextCompare)
    s = Replace(s, "{ISSUE}", IssueOf(ws, r), , , vbTextCompare)
    s = Replace(s, "{DATE}", Format$(downSince, "dd/mm/yyyy"), , , vbTextCompare)
    s = Replace(s, "{TIME}", Format$(downSince, "h:mm AM/PM"), , , vbTextCompare)
    s = Replace(s, "{DOWNFOR}", DurationText(hoursDown), , , vbTextCompare)
    s = Replace(s, "{VENDOR}", Trim$(CStr(ws.Cells(r, COL_VENDOR).Value)), , , vbTextCompare)
    s = Replace(s, "{REMARKS}", Trim$(CStr(ws.Cells(r, COL_REMARKS).Value)), , , vbTextCompare)
    s = Replace(s, "{PHONE}", phone, , , vbTextCompare)
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
    JoinAddresses = CleanAddresses(a & "," & b)
End Function

' "a@x.com; b@y.com" (any mix of ; , spaces or line breaks) -> "a@x.com,b@y.com",
' the separator Outlook on the web expects in the To / CC of a compose link.
Private Function CleanAddresses(ByVal s As String) As String
    s = Replace(Replace(Replace(Replace(s, ";", ","), vbCr, ","), vbLf, ","), " ", ",")
    Do While InStr(s, ",,") > 0
        s = Replace(s, ",,", ",")
    Loop
    If Left$(s, 1) = "," Then s = Mid$(s, 2)
    If Right$(s, 1) = "," Then s = Left$(s, Len(s) - 1)
    CleanAddresses = s
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
        MsgBox "That file has no '" & REPORT_SHEET & "' sheet.", vbExclamation, "Mail Down ATMs"
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

Private Function DefaultSubject() As String
    DefaultSubject = "ATM Down - {BRANCH} ({TERMINAL}) - {ISSUE}"
End Function

Private Function DefaultBody() As String
    DefaultBody = "ATM {BRANCH} ({TERMINAL}) has been down since {DATE} {TIME} ({DOWNFOR}). " & _
        "Issue: {ISSUE}. Please check the ATM and update us as soon as possible."
End Function

' Builds the ATM EMAIL sheet: settings on top, then every terminal on the TOTAL list.
Public Sub CreateEmailSheet()
    Dim ws As Worksheet, wsTotal As Worksheet
    Dim lastRow As Long, r As Long, n As Long
    Dim t As String

    If HasSheet(ThisWorkbook, EMAIL_SHEET) Then Exit Sub
    Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    ws.Name = EMAIL_SHEET

    ws.Range("A1").Value = "ATM EMAIL & PHONE LIST - used by Mail Down ATMs"
    ws.Range("A1").Font.Bold = True
    ws.Range("A1").Font.Size = 13
    WriteSettings ws, True

    ws.Cells(FIRST_ROW - 1, E_TERMINAL).Value = "Terminal"
    ws.Cells(FIRST_ROW - 1, E_BRANCH).Value = "Branch / ATM"
    ws.Cells(FIRST_ROW - 1, E_TO).Value = "Email (To)"
    ws.Cells(FIRST_ROW - 1, E_CC).Value = "CC"
    ws.Cells(FIRST_ROW - 1, E_PHONE).Value = "Phone"
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
    ws.Range(ws.Cells(FIRST_ROW, E_TO), ws.Cells(r - 1, E_PHONE)).Interior.Color = RGB(255, 242, 204)
    ws.Range(ws.Cells(FIRST_ROW, E_PHONE), ws.Cells(r - 1, E_PHONE)).NumberFormat = "@"

    ws.Columns(1).ColumnWidth = 22
    ws.Columns(2).ColumnWidth = 60
    ws.Columns(3).ColumnWidth = 34
    ws.Columns(4).ColumnWidth = 30
    ws.Columns(5).ColumnWidth = 22
    ws.Columns(6).ColumnWidth = 17
    ws.Range("A:F").VerticalAlignment = xlTop
    On Error Resume Next  ' freezing needs a visible window
    ws.Activate
    ws.Range("A" & FIRST_ROW).Select
    ActiveWindow.FreezePanes = True
    ws.Range("C" & FIRST_ROW).Select
    On Error GoTo 0
End Sub

Private Sub WriteSettings(ByVal ws As Worksheet, ByVal isNew As Boolean)
    ws.Cells(ROW_OWA, 1).Value = "Outlook web address"
    If isNew Or Len(Trim$(CStr(ws.Cells(ROW_OWA, 2).Value))) = 0 Then ws.Cells(ROW_OWA, 2).Value = DEFAULT_OWA
    ws.Cells(ROW_OWA, 3).Value = "Outlook in Chrome (empty = the PC's default mail program)"
    ws.Cells(ROW_CC, 1).Value = "Always CC"
    ws.Cells(ROW_CC, 3).Value = "Optional, e.g. your team's address. Separate several with ;"
    ws.Cells(ROW_HOURS, 1).Value = "Down for at least (hours)"
    If isNew Or Len(Trim$(CStr(ws.Cells(ROW_HOURS, 2).Value))) = 0 Then ws.Cells(ROW_HOURS, 2).Value = 1
    ws.Cells(ROW_HOURS, 3).Value = "Only ATMs down this long are mailed (red rows, ATMs already up and no-transaction / CHECK ATM rows never are)"
    ws.Cells(ROW_SUBJECT, 1).Value = "Subject"
    If isNew Then ws.Cells(ROW_SUBJECT, 2).Value = DefaultSubject()
    ws.Cells(ROW_BODY, 1).Value = "Message"
    If isNew Then ws.Cells(ROW_BODY, 2).Value = DefaultBody()
    ws.Cells(ROW_BODY, 3).Value = "Used when B8 = NO (one mail per ATM). Placeholders: {TERMINAL} {BRANCH} {ISSUE} {DATE} {TIME} {DOWNFOR} {VENDOR} {REMARKS} {PHONE}. Alt+Enter = new line."
    ws.Cells(ROW_ONEMAIL, 1).Value = "All ATMs in one mail"
    If isNew Or Len(Trim$(CStr(ws.Cells(ROW_ONEMAIL, 2).Value))) = 0 Then ws.Cells(ROW_ONEMAIL, 2).Value = "NO"
    ws.Cells(ROW_ONEMAIL, 3).Value = "NO = one mail per ATM (default). YES = one mail listing every ATM (To = all their branches)."
    ws.Cells(ROW_ONESUBJECT, 1).Value = "Subject (one mail)"
    If isNew Or Len(Trim$(CStr(ws.Cells(ROW_ONESUBJECT, 2).Value))) = 0 Then ws.Cells(ROW_ONESUBJECT, 2).Value = DefaultOneSubject()
    ws.Cells(ROW_ONESUBJECT, 3).Value = "Placeholders: {COUNT} {DATE} {TIME}"
    ws.Cells(ROW_LINE, 1).Value = "Line per ATM (one mail)"
    If isNew Or Len(Trim$(CStr(ws.Cells(ROW_LINE, 2).Value))) = 0 Then ws.Cells(ROW_LINE, 2).Value = DefaultLine()
    ws.Cells(ROW_LINE, 3).Value = "Same placeholders as the Message"
    ws.Range(ws.Cells(ROW_OWA, 1), ws.Cells(ROW_LINE, 1)).Font.Bold = True
    ws.Range(ws.Cells(ROW_OWA, 3), ws.Cells(ROW_LINE, 3)).Font.Italic = True
    ws.Range(ws.Cells(ROW_OWA, 3), ws.Cells(ROW_LINE, 3)).Font.Color = RGB(89, 89, 89)
    ws.Range(ws.Cells(ROW_OWA, 2), ws.Cells(ROW_LINE, 2)).Interior.Color = RGB(255, 242, 204)
    ws.Cells(ROW_BODY, 2).WrapText = True
    ws.Rows(ROW_BODY).RowHeight = 60
End Sub

Private Function DefaultOneSubject() As String
    DefaultOneSubject = "ATM Down - {COUNT} ATM(s) - {DATE} {TIME}"
End Function

Private Function DefaultLine() As String
    DefaultLine = "{TERMINAL} - {BRANCH} - {ISSUE} - down since {DATE} {TIME} ({DOWNFOR})"
End Function

Private Function OneMailMode() As Boolean
    OneMailMode = UCase$(Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(ROW_ONEMAIL, 2).Value))) = "YES"
End Function

' One mail for every ATM to mail now (skips ATMs already mailed today): To = all their
' branch addresses, CC = their CCs + Always CC, body = one line per ATM. Returns the link.
Private Function BuildOneMail(ByVal mails As Collection, ByRef toAddr As String, ByRef cc As String, _
                              ByRef subj As String, ByRef body As String, ByRef n As Long, _
                              ByRef skipped As String) As String
    Dim m As Variant, a As Variant
    Dim toList As Object, ccList As Object
    Dim lines As String
    Dim wsMail As Worksheet

    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)
    Set toList = CreateObject("Scripting.Dictionary"): toList.CompareMode = 1
    Set ccList = CreateObject("Scripting.Dictionary"): ccList.CompareMode = 1
    n = 0: skipped = vbNullString
    For Each m In mails
        If m(I_STATUS) = "MAILED TODAY" Then
            skipped = skipped & vbCrLf & "    " & m(I_TERMINAL) & "  " & m(I_BRANCH)
        Else
            n = n + 1
            lines = lines & vbCrLf & m(I_LINE)
            For Each a In Split(CStr(m(I_TO)), ",")
                If Len(a) > 0 Then toList(a) = True
            Next a
            For Each a In Split(CStr(m(I_CC)), ",")
                If Len(a) > 0 And Not toList.Exists(a) Then ccList(a) = True
            Next a
        End If
    Next m
    toAddr = Join(toList.Keys, ",")
    cc = Join(ccList.Keys, ",")
    subj = CStr(wsMail.Cells(ROW_ONESUBJECT, 2).Value)
    If Len(Trim$(subj)) = 0 Then subj = DefaultOneSubject()
    subj = Replace(subj, "{COUNT}", CStr(n), , , vbTextCompare)
    subj = Replace(subj, "{DATE}", Format$(Date, "dd/mm/yyyy"), , , vbTextCompare)
    subj = Replace(subj, "{TIME}", Format$(Now, "h:mm AM/PM"), , , vbTextCompare)
    body = "The following ATM(s) have been down for " & HoursText() & " or more:" & vbCrLf & lines & vbCrLf & vbCrLf & _
           "Please check your ATM and update us as soon as possible."
    BuildOneMail = ComposeLink(Trim$(CStr(wsMail.Cells(ROW_OWA, 2).Value)), toAddr, cc, subj, body)
End Function

Private Sub MailAllInOne(ByVal mails As Collection, ByVal wbReport As Workbook)
    Dim toAddr As String, cc As String, subj As String, body As String, skipped As String
    Dim link As String, msg As String, noEmail As String, listText As String
    Dim n As Long, pasted As Boolean
    Dim m As Variant
    Dim wsMail As Worksheet

    link = BuildOneMail(mails, toAddr, cc, subj, body, n, skipped)
    If n = 0 Then
        MsgBox "All these ATMs were already mailed today:" & skipped & vbCrLf & vbCrLf & _
               "To mail them again, clear their 'Last mailed' cells on the '" & EMAIL_SHEET & "' sheet.", _
               vbInformation, "Mail Down ATMs"
        Exit Sub
    End If
    For Each m In mails
        If m(I_STATUS) <> "MAILED TODAY" Then listText = listText & vbCrLf & "    " & m(I_LINE)
        If m(I_STATUS) = "NO EMAIL" Then
            noEmail = noEmail & vbCrLf & "    " & m(I_TERMINAL) & "  " & m(I_BRANCH) & _
                      IIf(Len(m(I_PHONE)) > 0, "  phone " & m(I_PHONE), "")
        End If
    Next m

    msg = "Open ONE email in Outlook listing " & n & " ATM(s) down " & HoursText() & " or more (" & wbReport.Name & "):" & _
          listText & vbCrLf & vbCrLf & _
          "To: " & IIf(Len(toAddr) > 0, toAddr, "(no branch emails - add them on " & EMAIL_SHEET & " or in Outlook)") & vbCrLf & _
          "CC: " & IIf(Len(cc) > 0, cc, "(none)") & vbCrLf & _
          "Subject: " & subj
    If Len(noEmail) > 0 Then msg = msg & vbCrLf & vbCrLf & "Listed in the mail but no email address:" & noEmail
    If Len(skipped) > 0 Then msg = msg & vbCrLf & vbCrLf & "Left out (already mailed today):" & skipped
    msg = msg & vbCrLf & vbCrLf & "Check it and click Send - or close the Outlook window to keep it in Drafts and send it later."
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail Down ATMs") <> vbYes Then Exit Sub

    ' Very long links can be cut off: then open the mail without the text and put
    ' the text on the clipboard to paste.
    If Len(link) > 12000 Then
        pasted = PutOnClipboard(body)
        link = ComposeLink(Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(ROW_OWA, 2).Value)), toAddr, cc, subj, "")
    End If
    CreateObject("Shell.Application").ShellExecute link
    If pasted Then
        MsgBox "The list is long, so it was copied instead: click in the mail text in Outlook and press Ctrl+V.", _
               vbInformation, "Mail Down ATMs"
    End If

    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)
    For Each m In mails
        If m(I_STATUS) <> "MAILED TODAY" And CLng(m(I_EMAILROW)) > 0 Then
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).Value = Now
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).NumberFormat = "dd/mm/yyyy hh:mm"
        End If
    Next m
End Sub

Private Function PutOnClipboard(ByVal s As String) As Boolean
    On Error Resume Next
    With CreateObject("new:{1C3B4210-F441-11CE-B9EA-00AA006B1A69}")  ' MSForms.DataObject
        .SetText s
        .PutInClipboard
    End With
    PutOnClipboard = (Err.Number = 0)
End Function

' An ATM EMAIL sheet made by the first (dispenser-only) version has no Hours row
' and no Phone column: add them, keeping every address already typed in.
Private Sub UpgradeEmailSheet()
    Dim ws As Worksheet
    If Not HasSheet(ThisWorkbook, EMAIL_SHEET) Then Exit Sub
    Set ws = ThisWorkbook.Worksheets(EMAIL_SHEET)
    If StrComp(Trim$(CStr(ws.Cells(FIRST_ROW - 1, E_TERMINAL).Value)), "Terminal", vbTextCompare) = 0 And _
       StrComp(Trim$(CStr(ws.Cells(FIRST_ROW - 1, E_PHONE).Value)), "Phone", vbTextCompare) = 0 Then
        ' message still the earlier default (Dear Sir/Madam ... Regards): switch to the current one
        If InStr(1, CStr(ws.Cells(ROW_BODY, 2).Value), "Your ATM {BRANCH} ({TERMINAL}) has been down since", vbTextCompare) > 0 Then
            ws.Cells(ROW_BODY, 2).Value = DefaultBody()
        End If
        ' sheets made before the one-mail option: add its settings (rows 8-10)
        If Len(Trim$(CStr(ws.Cells(ROW_ONEMAIL, 1).Value))) = 0 Then WriteSettings ws, False
        Exit Sub
    End If
    If StrComp(Trim$(CStr(ws.Cells(10, 1).Value)), "Terminal", vbTextCompare) <> 0 Then Exit Sub

    ' old layout: settings rows 3-6 (address, CC, subject, message), headers on row 10, Last mailed in E
    ws.Rows(ROW_HOURS).Insert                     ' headers move to row 11
    ws.Columns(E_PHONE).Insert                    ' Last mailed moves to F
    ws.Cells(FIRST_ROW - 1, E_PHONE).Value = "Phone"
    ws.Cells(FIRST_ROW - 1, E_PHONE).Font.Bold = True
    ws.Cells(FIRST_ROW - 1, E_PHONE).Font.Color = RGB(255, 255, 255)
    ws.Cells(FIRST_ROW - 1, E_PHONE).Interior.Color = RGB(31, 78, 120)
    ws.Columns(E_PHONE).ColumnWidth = 22
    If InStr(1, CStr(ws.Cells(ROW_SUBJECT, 2).Value), "Dispenser", vbTextCompare) > 0 Then ws.Cells(ROW_SUBJECT, 2).Value = DefaultSubject()
    If InStr(1, CStr(ws.Cells(ROW_BODY, 2).Value), "cash dispenser problem", vbTextCompare) > 0 Then ws.Cells(ROW_BODY, 2).Value = DefaultBody()
    WriteSettings ws, False
End Sub
