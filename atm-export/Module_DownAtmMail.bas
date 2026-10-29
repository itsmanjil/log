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
'
' MailDownReport (further down) opens the once-a-day "ATM DOWN TIME REPORT"
' mail with today's report to attach; its settings are on the "REPORT MAIL" sheet.
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
Private Const COL_INITIATED As Long = 12
Private Const COL_REMARKS As Long = 13

' CASH LOW sheet of the daily report
Private Const CASH_SHEET As String = "CASH LOW"
Private Const CL_TIME As Long = 5             ' CASH LOW ALERT TIME
Private Const CL_INITIATED As Long = 8
Private Const MAX_LISTED As Long = 10         ' rows listed in a message (message boxes cut off long text)

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

' Daily report mail (MailDownReport): REPORT MAIL sheet, settings in column B
Private Const REPORT_MAIL_SHEET As String = "REPORT MAIL"
Private Const RM_TO As Long = 3
Private Const RM_CC As Long = 4
Private Const RM_BRANCHES As Long = 5         ' YES = CC the branches mailed today
Private Const RM_SUBJECT As Long = 6
Private Const RM_BODY As Long = 7
Private Const RM_LEAVEOUT As Long = 8         ' issues left out of the mailed copy
Private Const RM_LAST As Long = 9             ' when the mail was last opened
' USB ENABLE mail (MailUsbEnable): USB MAIL sheet, settings in column B; IP addresses on ATM EMAIL
Private Const USB_SHEET As String = "USB MAIL"
Private Const U_TO As Long = 3
Private Const U_CC As Long = 4
Private Const U_SUBJECT As Long = 5
Private Const U_BODY As Long = 6
Private Const E_IP As Long = 7                ' ATM EMAIL column G
Private Const COPY_FOLDER As String = "ATM DOWN REPORT MAIL"
Private Const DOWNLOADS_GUID As String = "{374DE290-123F-4565-9164-39C4925E467B}"

' Outlook on the web ignores the CC of a compose link, so CC addresses are put on the
' clipboard to paste into the Cc box. Windows clipboard calls (32- and 64-bit Office):
' MSForms.DataObject can put "??" on the clipboard while a File Explorer window is open.
Private Declare PtrSafe Function OpenClipboard Lib "user32" (ByVal hwnd As LongPtr) As Long
Private Declare PtrSafe Function EmptyClipboard Lib "user32" () As Long
Private Declare PtrSafe Function CloseClipboard Lib "user32" () As Long
Private Declare PtrSafe Function SetClipboardData Lib "user32" (ByVal wFormat As Long, ByVal hMem As LongPtr) As LongPtr
Private Declare PtrSafe Function GlobalAlloc Lib "kernel32" (ByVal wFlags As Long, ByVal dwBytes As LongPtr) As LongPtr
Private Declare PtrSafe Function GlobalLock Lib "kernel32" (ByVal hMem As LongPtr) As LongPtr
Private Declare PtrSafe Function GlobalUnlock Lib "kernel32" (ByVal hMem As LongPtr) As Long
Private Declare PtrSafe Function GlobalFree Lib "kernel32" (ByVal hMem As LongPtr) As LongPtr
Private Declare PtrSafe Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (ByVal dest As LongPtr, ByVal src As LongPtr, ByVal bytes As LongPtr)

' For checking without opening anything (MailDryRun): links are logged instead of opened.
Private mDryRun As Boolean
Private mDryRunLog As String

Public Sub MailDownAtms()
    Dim wbReport As Workbook
    Dim mails As Collection
    Dim m As Variant
    Dim ready As Long, msg As String, notSent As String
    Dim wsMail As Worksheet
    Dim firstOk As Variant
    Dim sameCc As Boolean, cc As String, n As Long, howTo As String

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

    ' How-to and settings first: a message box shows only about 1000 characters.
    howTo = "Each mail opens in Chrome ready to send - check it and click Send."
    sameCc = SameCcForAll(mails, cc)
    If sameCc And Len(cc) > 0 Then
        howTo = howTo & vbCrLf & "Outlook does not take the CC from the link, so the CC addresses are copied:" & vbCrLf & _
                "in each mail click Cc (right end of the To line) and press Ctrl+V."
    ElseIf Not sameCc Then
        howTo = howTo & vbCrLf & "The mails have different CC addresses, so they open ONE AT A TIME:" & vbCrLf & _
                "in each mail click Cc (right end of the To line), press Ctrl+V, Send," & vbCrLf & _
                "then come back to Excel and click OK for the next mail."
    End If
    ' show what the ATM EMAIL settings produce, so changes there are visible before sending
    msg = "Open " & ready & " email(s) in Outlook for ATMs down " & HoursText() & " or more (" & wbReport.Name & ")." & _
          vbCrLf & howTo & vbCrLf & vbCrLf & _
          "First mail:" & vbCrLf & _
          "    To: " & firstOk(I_TO) & vbCrLf & _
          "    CC: " & IIf(Len(firstOk(I_CC)) > 0, CcForPaste(firstOk(I_CC)), "(none - cell B4 on " & EMAIL_SHEET & ")") & vbCrLf & _
          "    Subject: " & firstOk(I_SUBJECT) & vbCrLf & vbCrLf & _
          "ATMs:" & msg
    If Len(notSent) > 0 Then msg = msg & vbCrLf & vbCrLf & "Not mailed:" & notSent
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail Down ATMs") <> vbYes Then Exit Sub

    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)
    If sameCc And Len(cc) > 0 Then PutOnClipboard CcForPaste(cc)
    For Each m In mails
        If m(I_STATUS) = "OK" Then
            n = n + 1
            If Not sameCc Then
                If n > 1 Then
                    If MsgBox("Next mail (" & n & " of " & ready & "): " & m(I_TERMINAL) & "  " & m(I_BRANCH) & vbCrLf & _
                              "CC: " & IIf(Len(m(I_CC)) > 0, CcForPaste(m(I_CC)) & "  (copied - click Cc, Ctrl+V)", "none for this one") & _
                              vbCrLf & vbCrLf & "Click OK to open it, Cancel to stop.", vbOKCancel + vbInformation, "Mail Down ATMs") <> vbOK Then Exit For
                End If
                PutOnClipboard CcForPaste(m(I_CC))
            End If
            OpenLink CStr(m(I_LINK))
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).Value = Now
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).NumberFormat = "dd/mm/yyyy hh:mm"
            If sameCc Then Application.Wait Now + TimeSerial(0, 0, 1)
        End If
    Next m
End Sub

' True if every mail to open now has the same CC (returned in cc).
Private Function SameCcForAll(ByVal mails As Collection, ByRef cc As String) As Boolean
    Dim m As Variant, first As Boolean
    first = True
    SameCcForAll = True
    cc = vbNullString
    For Each m In mails
        If m(I_STATUS) = "OK" Then
            If first Then
                cc = m(I_CC): first = False
            ElseIf StrComp(m(I_CC), cc, vbTextCompare) <> 0 Then
                SameCcForAll = False
                Exit Function
            End If
        End If
    Next m
End Function

' "a@x.com,b@y.com" -> "a@x.com; b@y.com" (Outlook splits a pasted list on ;)
Private Function CcForPaste(ByVal cc As String) As String
    CcForPaste = Replace(cc, ",", "; ")
End Function

Private Sub OpenLink(ByVal link As String)
    If mDryRun Then
        mDryRunLog = mDryRunLog & link & vbLf
    Else
        CreateObject("Shell.Application").ShellExecute link
    End If
End Sub

' Test helper: MailDryRun(True) makes the mail buttons log their links instead of opening
' them (no folder window either); MailDryRun(False) switches back. Returns the log so far.
Public Function MailDryRun(ByVal enable As Boolean) As String
    MailDryRun = mDryRunLog
    mDryRun = enable
    mDryRunLog = vbNullString
End Function

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
    AddIpColumn ws
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
    If Len(cc) > 0 Then
        msg = msg & vbCrLf & "Outlook does not take the CC from the link, so the CC addresses are copied:" & vbCrLf & _
              "in the mail click Cc (right end of the To line) and press Ctrl+V."
    End If
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail Down ATMs") <> vbYes Then Exit Sub

    ' Very long links can be cut off: then open the mail without the text and put
    ' the text on the clipboard to paste.
    If Len(link) > 12000 Then
        pasted = PutOnClipboard(body)
        link = ComposeLink(Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(ROW_OWA, 2).Value)), toAddr, cc, subj, "")
    End If
    OpenLink link
    If pasted Then
        MsgBox "The list is long, so it was copied instead: click in the mail text in Outlook and press Ctrl+V." & _
               IIf(Len(cc) > 0, vbCrLf & vbCrLf & "Then click OK here to copy the CC addresses.", ""), _
               vbInformation, "Mail Down ATMs"
    End If
    If Len(cc) > 0 Then
        PutOnClipboard CcForPaste(cc)
        If pasted Then MsgBox "CC addresses copied: in the mail click Cc and press Ctrl+V.", vbInformation, "Mail Down ATMs"
    End If

    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)
    For Each m In mails
        If m(I_STATUS) <> "MAILED TODAY" And CLng(m(I_EMAILROW)) > 0 Then
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).Value = Now
            wsMail.Cells(CLng(m(I_EMAILROW)), E_LAST).NumberFormat = "dd/mm/yyyy hh:mm"
        End If
    Next m
End Sub

' Puts text on the Windows clipboard (empty text clears it).
Private Function PutOnClipboard(ByVal s As String) As Boolean
    Const CF_UNICODETEXT As Long = 13
    Const GHND As Long = &H42                    ' movable, zero-filled (ends with a null character)
    Dim hMem As LongPtr, p As LongPtr, tries As Long

    For tries = 1 To 5                           ' another program may hold the clipboard for a moment
        If OpenClipboard(0) <> 0 Then Exit For
        Application.Wait Now + TimeSerial(0, 0, 1)
    Next tries
    If tries > 5 Then Exit Function
    EmptyClipboard
    If Len(s) > 0 Then
        hMem = GlobalAlloc(GHND, (Len(s) + 1) * 2)
        If hMem <> 0 Then
            p = GlobalLock(hMem)
            If p <> 0 Then
                CopyMemory p, StrPtr(s), Len(s) * 2
                GlobalUnlock hMem
                If SetClipboardData(CF_UNICODETEXT, hMem) <> 0 Then PutOnClipboard = True Else GlobalFree hMem
            Else
                GlobalFree hMem
            End If
        End If
    Else
        PutOnClipboard = True
    End If
    CloseClipboard
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
        AddIpColumn ws
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
    AddIpColumn ws
End Sub

' Column G "IP address" (used by Mail USB Enable), added to sheets made before it.
Private Sub AddIpColumn(ByVal ws As Worksheet)
    Dim lastRow As Long
    If Len(Trim$(CStr(ws.Cells(FIRST_ROW - 1, E_IP).Value))) > 0 Then Exit Sub
    ws.Cells(FIRST_ROW - 1, E_IP).Value = "IP address"
    With ws.Cells(FIRST_ROW - 1, E_IP)
        .Font.Bold = True
        .Font.Color = RGB(255, 255, 255)
        .Interior.Color = RGB(31, 78, 120)
    End With
    lastRow = ws.Cells(ws.Rows.Count, E_TERMINAL).End(xlUp).Row
    If lastRow >= FIRST_ROW Then
        ws.Range(ws.Cells(FIRST_ROW, E_IP), ws.Cells(lastRow, E_IP)).Interior.Color = RGB(255, 242, 204)
        ws.Range(ws.Cells(FIRST_ROW, E_IP), ws.Cells(lastRow, E_IP)).NumberFormat = "@"
    End If
    ws.Columns(E_IP).ColumnWidth = 18
    ws.Columns(E_IP).VerticalAlignment = xlTop
End Sub

' ======================================================================
' DAILY "ATM DOWN TIME REPORT" MAIL (once a day, 1-2 PM)
'
' Makes a copy of today's daily report without the rows whose issue is
' NO TRANSACTION IN ATM (Downloads\ATM DOWN REPORT MAIL\dd.mm.yyyy.xlsx),
' opens a ready-filled mail in Outlook on the web (To / CC / subject /
' message from the REPORT MAIL sheet, plus every branch mailed today with
' Mail Down ATMs in CC) and shows the copy in a folder window. A web link
' cannot attach a file, so you drag the copy into the mail, check it and
' click Send. Nothing is sent automatically.
' ======================================================================

Public Sub MailDownReport()
    Dim wbReport As Workbook, wsSet As Worksheet
    Dim copyPath As String, link As String, msg As String, toAddr As String, cc As String, subj As String
    Dim removed As Long, kept As Long, branches As Long
    Dim missing As String, firstEmpty As Range, nMissing As Long

    If Not HasSheet(ThisWorkbook, REPORT_MAIL_SHEET) Then
        CreateReportMailSheet
        MsgBox "A new sheet '" & REPORT_MAIL_SHEET & "' was added." & vbCrLf & vbCrLf & _
               "Type the To and CC addresses of the daily report mail in B3 and B4 (separate several with ;), " & _
               "then click Mail Down Report again.", vbInformation, "Mail Down Report"
        ThisWorkbook.Worksheets(REPORT_MAIL_SHEET).Activate
        Exit Sub
    End If
    Set wsSet = ThisWorkbook.Worksheets(REPORT_MAIL_SHEET)
    If Len(CleanAddresses(CStr(wsSet.Cells(RM_TO, 2).Value))) = 0 Then
        MsgBox "Type the To addresses in cell B3 on the '" & REPORT_MAIL_SHEET & "' sheet first.", vbExclamation, "Mail Down Report"
        wsSet.Activate
        Exit Sub
    End If
    If IsDate(wsSet.Cells(RM_LAST, 2).Value) Then
        If Int(CDbl(CDate(wsSet.Cells(RM_LAST, 2).Value))) = CDbl(Date) Then
            If MsgBox("The report mail was already opened today at " & Format$(wsSet.Cells(RM_LAST, 2).Value, "h:mm AM/PM") & _
                      ". Open it again?", vbQuestion + vbYesNo, "Mail Down Report") <> vbYes Then Exit Sub
        End If
    End If

    Set wbReport = FindDailyReport()
    If wbReport Is Nothing Then Exit Sub

    ' no mail while a row has no time or no Initiated by
    missing = MissingEntries(wbReport, firstEmpty, nMissing)
    If nMissing > 0 Then
        If MsgBox("Not mailed yet: every row needs its time and Initiated by." & vbCrLf & _
                  "Fill these in " & wbReport.Name & ", save, and click Mail Down Report again." & vbCrLf & _
                  "Click OK to go to the first empty cell." & vbCrLf & vbCrLf & _
                  nMissing & " row(s):" & missing & _
                  IIf(nMissing > MAX_LISTED, vbCrLf & "    ... and " & (nMissing - MAX_LISTED) & " more", ""), _
                  vbExclamation + vbOKCancel, "Mail Down Report") = vbOK Then
            On Error Resume Next
            wbReport.Activate
            firstEmpty.Worksheet.Activate
            firstEmpty.Select
            On Error GoTo 0
        End If
        Exit Sub
    End If

    If Not wbReport.Saved And Not wbReport.ReadOnly Then
        Select Case MsgBox(wbReport.Name & " has changes that are not saved yet. Save it now?" & vbCrLf & _
                           "(The mailed copy contains what is on screen either way.)", vbQuestion + vbYesNoCancel, "Mail Down Report")
            Case vbYes: wbReport.Save
            Case vbCancel: Exit Sub
        End Select
    End If

    copyPath = MakeReportMailCopy(wbReport, removed, kept)
    If Len(copyPath) = 0 Then Exit Sub
    link = BuildReportMail(wbReport.Name, toAddr, cc, subj, branches)

    ' How-to first: a message box shows only about 1000 characters.
    msg = "Daily report mail for " & wbReport.Name & vbCrLf & vbCrLf & _
          "Click Yes: a folder window opens with the file selected, and the mail opens in Chrome." & vbCrLf & _
          "1. Drag " & wbReport.Name & " from the folder window into the mail." & vbCrLf & _
          IIf(Len(cc) > 0, "2. Outlook does not take the CC from the link, so the CC addresses are copied:" & vbCrLf & _
                           "    in the mail click Cc (right end of the To line) and press Ctrl+V." & vbCrLf, "") & _
          "Check it and click Send." & vbCrLf & vbCrLf & _
          "Copy to attach: " & copyPath & vbCrLf & _
          "    " & removed & " row(s) left out (" & LeaveOutText() & "), " & kept & " ATM row(s) in it." & vbCrLf & _
          "Subject: " & subj & vbCrLf & _
          "To: " & CcForPaste(toAddr) & vbCrLf & _
          IIf(branches > 0, "CC (" & branches & " branch address(es) mailed today included): ", "CC: ") & _
          IIf(Len(cc) > 0, CcForPaste(cc), "(none - cell B4 on " & REPORT_MAIL_SHEET & ")")
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail Down Report") <> vbYes Then Exit Sub

    If mDryRun Then
        mDryRunLog = mDryRunLog & "folder: " & copyPath & vbLf
    Else
        Shell "explorer.exe /select,""" & copyPath & """", vbNormalFocus
        Application.Wait Now + TimeSerial(0, 0, 1)
    End If
    OpenLink link
    If Len(cc) > 0 Then PutOnClipboard CcForPaste(cc)
    wsSet.Cells(RM_LAST, 2).Value = Now
    wsSet.Cells(RM_LAST, 2).NumberFormat = "dd/mm/yyyy hh:mm"
End Sub

' For checking without opening anything:
' "copy path <tab> rows left out <tab> rows kept <tab> branches in CC <tab> link".
Public Function DownReportMailPreview(ByVal reportPath As String) As String
    Dim wb As Workbook, opened As Boolean
    Dim copyPath As String, link As String, removed As Long, kept As Long, branches As Long
    Dim toAddr As String, cc As String, subj As String

    CreateReportMailSheet
    Set wb = OpenWorkbookByPath(reportPath, opened)
    copyPath = MakeReportMailCopy(wb, removed, kept)
    link = BuildReportMail(wb.Name, toAddr, cc, subj, branches)
    If opened Then wb.Close SaveChanges:=False
    DownReportMailPreview = copyPath & vbTab & removed & vbTab & kept & vbTab & branches & vbTab & link
End Function

' Compose link of the report mail; also returns To, CC (fixed CC + branches mailed
' today, without the To addresses), subject and the number of branch addresses added.
Private Function BuildReportMail(ByVal fileName As String, ByRef toAddr As String, ByRef cc As String, _
                                 ByRef subj As String, ByRef branches As Long) As String
    Dim wsSet As Worksheet, owa As String, a As Variant
    Dim inTo As Object, ccList As Object, branchList As Object

    Set wsSet = ThisWorkbook.Worksheets(REPORT_MAIL_SHEET)
    Set inTo = CreateObject("Scripting.Dictionary"): inTo.CompareMode = 1
    Set ccList = CreateObject("Scripting.Dictionary"): ccList.CompareMode = 1
    toAddr = CleanAddresses(CStr(wsSet.Cells(RM_TO, 2).Value))
    For Each a In Split(toAddr, ",")
        If Len(a) > 0 Then inTo(a) = True
    Next a
    For Each a In Split(CleanAddresses(CStr(wsSet.Cells(RM_CC, 2).Value)), ",")
        If Len(a) > 0 And Not inTo.Exists(a) Then ccList(a) = True
    Next a
    branches = 0
    If UCase$(Trim$(CStr(wsSet.Cells(RM_BRANCHES, 2).Value))) <> "NO" Then
        Set branchList = BranchesMailedToday()
        For Each a In branchList.Keys
            If Not inTo.Exists(a) And Not ccList.Exists(a) Then ccList(a) = True: branches = branches + 1
        Next a
    End If
    cc = Join(ccList.Keys, ",")

    subj = FillReportTemplate(CStr(wsSet.Cells(RM_SUBJECT, 2).Value), fileName)
    owa = DEFAULT_OWA
    If HasSheet(ThisWorkbook, EMAIL_SHEET) Then owa = Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(ROW_OWA, 2).Value))
    BuildReportMail = ComposeLink(owa, toAddr, cc, subj, FillReportTemplate(CStr(wsSet.Cells(RM_BODY, 2).Value), fileName))
End Function

' Branch addresses (column C of ATM EMAIL) of every ATM mailed today with Mail Down ATMs.
Private Function BranchesMailedToday() As Object
    Dim ws As Worksheet, r As Long, lastRow As Long, a As Variant
    Dim result As Object

    Set result = CreateObject("Scripting.Dictionary"): result.CompareMode = 1
    Set BranchesMailedToday = result
    If Not HasSheet(ThisWorkbook, EMAIL_SHEET) Then Exit Function
    Set ws = ThisWorkbook.Worksheets(EMAIL_SHEET)
    lastRow = ws.Cells(ws.Rows.Count, E_TERMINAL).End(xlUp).Row
    For r = FIRST_ROW To lastRow
        If IsDate(ws.Cells(r, E_LAST).Value) Then
            If Int(CDbl(CDate(ws.Cells(r, E_LAST).Value))) = CDbl(Date) Then
                For Each a In Split(CleanAddresses(CStr(ws.Cells(r, E_TO).Value)), ",")
                    If Len(a) > 0 Then result(a) = True
                Next a
            End If
        End If
    Next r
End Function

' {DATE} = date of the report file, e.g. "28th October 2026"; {FILE} = file name; {NL} = new line.
Private Function FillReportTemplate(ByVal tpl As String, ByVal fileName As String) As String
    Dim s As String
    s = Replace(Replace(tpl, vbCrLf, vbLf), vbLf, vbCrLf)
    s = Replace(s, "{NL}", vbCrLf, , , vbTextCompare)
    s = Replace(s, "{DATE}", LongDateText(ReportDateOf(fileName)), , , vbTextCompare)
    s = Replace(s, "{FILE}", fileName, , , vbTextCompare)
    FillReportTemplate = s
End Function

' "28.10.2026.xlsx" -> 28/10/2026 (today if the name is not a date)
Private Function ReportDateOf(ByVal fileName As String) As Date
    Dim parts() As String
    ReportDateOf = Date
    If InStrRev(fileName, ".") > 0 Then fileName = Left$(fileName, InStrRev(fileName, ".") - 1)
    parts = Split(fileName, ".")
    If UBound(parts) <> 2 Then Exit Function
    If Not (IsNumeric(parts(0)) And IsNumeric(parts(1)) And IsNumeric(parts(2))) Then Exit Function
    On Error Resume Next
    ReportDateOf = DateSerial(CInt(parts(2)), CInt(parts(1)), CInt(parts(0)))
End Function

' 28/10/2026 -> "28th October 2026" (English month names whatever the PC's language)
Private Function LongDateText(ByVal d As Date) As String
    Dim suffix As String
    Select Case Day(d)
        Case 1, 21, 31: suffix = "st"
        Case 2, 22: suffix = "nd"
        Case 3, 23: suffix = "rd"
        Case Else: suffix = "th"
    End Select
    LongDateText = Day(d) & suffix & " " & _
        Split("January February March April May June July August September October November December")(Month(d) - 1) & _
        " " & Year(d)
End Function

Private Function LeaveOutText() As String
    LeaveOutText = Trim$(CStr(ThisWorkbook.Worksheets(REPORT_MAIL_SHEET).Cells(RM_LEAVEOUT, 2).Value))
    If Len(LeaveOutText) = 0 Then LeaveOutText = "nothing left out"
End Function

' Saves a copy of the report (as it is on screen) to Downloads\ATM DOWN REPORT MAIL under
' the same file name and removes the left-out rows from its ATM DOWN REPORT sheet.
' Older copies in that folder are deleted. Returns the path, or "" after telling why not.
Private Function MakeReportMailCopy(ByVal wbReport As Workbook, ByRef removed As Long, ByRef kept As Long) As String
    Dim folder As String, finalPath As String, workPath As String, f As String
    Dim old As New Collection, oldFile As Variant
    Dim wb As Workbook, ws As Worksheet
    Dim screenWas As Boolean, alertsWas As Boolean

    folder = DownloadsDir()
    If Len(folder) = 0 Then MsgBox "The Downloads folder was not found.", vbExclamation, "Mail Down Report": Exit Function
    folder = folder & "\" & COPY_FOLDER
    If Len(Dir$(folder, vbDirectory)) = 0 Then MkDir folder
    finalPath = folder & "\" & wbReport.Name
    workPath = folder & "\making copy - " & wbReport.Name   ' Excel cannot open two files with the same name

    For Each wb In Application.Workbooks
        If StrComp(wb.FullName, finalPath, vbTextCompare) = 0 Or StrComp(wb.FullName, workPath, vbTextCompare) = 0 Then
            wb.Close SaveChanges:=False
            Exit For
        End If
    Next wb
    f = Dir$(folder & "\*.xls*")
    Do While Len(f) > 0
        old.Add folder & "\" & f
        f = Dir$()
    Loop
    On Error Resume Next
    For Each oldFile In old
        Kill CStr(oldFile)
    Next oldFile
    On Error GoTo 0
    If Len(Dir$(finalPath)) > 0 Then
        MsgBox "Close " & finalPath & " (it is open somewhere) and click Mail Down Report again.", vbExclamation, "Mail Down Report"
        Exit Function
    End If

    screenWas = Application.ScreenUpdating: alertsWas = Application.DisplayAlerts
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False
    Set wb = Nothing
    On Error GoTo Failed
    wbReport.SaveCopyAs workPath
    Set wb = Workbooks.Open(workPath, UpdateLinks:=False)
    Set ws = FindSheetTrim(wb, REPORT_SHEET)
    If Not ws Is Nothing Then RemoveLeftOutRows ws, removed, kept
    wb.Close SaveChanges:=True
    Set wb = Nothing
    Name workPath As finalPath
    MakeReportMailCopy = finalPath
Failed:
    If Err.Number <> 0 Then
        MsgBox "Could not make the copy to attach: " & Err.Description, vbExclamation, "Mail Down Report"
        If Not wb Is Nothing Then wb.Close SaveChanges:=False
    End If
    Application.DisplayAlerts = alertsWas
    Application.ScreenUpdating = screenWas
End Function

' Deletes the rows whose Issue in ATM contains a left-out text, then numbers S.N again
' (1 on the first row of each section, then =previous+1 as in the report).
Private Sub RemoveLeftOutRows(ByVal ws As Worksheet, ByRef removed As Long, ByRef kept As Long)
    Dim leaveOut() As String
    Dim r As Long, lastRow As Long

    leaveOut = LeaveOutItems()
    removed = 0: kept = 0
    lastRow = ws.Cells(ws.Rows.Count, COL_TERMINAL).End(xlUp).Row
    For r = lastRow To 1 Step -1
        If UCase$(Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value))) Like "PRV#*" Then
            If IsLeftOut(ws.Cells(r, COL_ISSUE).Value, leaveOut) Then
                ws.Rows(r).Delete
                removed = removed + 1
            End If
        End If
    Next r

    lastRow = ws.Cells(ws.Rows.Count, COL_TERMINAL).End(xlUp).Row
    For r = 1 To lastRow
        If UCase$(Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value))) Like "PRV#*" Then
            kept = kept + 1
            If r > 1 And UCase$(Trim$(CStr(ws.Cells(r - 1, COL_TERMINAL).Value))) Like "PRV#*" Then
                ws.Cells(r, 1).Formula = "=A" & (r - 1) & "+1"
            Else
                ws.Cells(r, 1).Value = 1
            End If
        End If
    Next r
End Sub

' Issues left out of the mailed copy (REPORT MAIL B8), upper case.
Private Function LeaveOutItems() As String()
    LeaveOutItems = Split(UCase$(CleanList(CStr(ThisWorkbook.Worksheets(REPORT_MAIL_SHEET).Cells(RM_LEAVEOUT, 2).Value))), ";")
End Function

Private Function IsLeftOut(ByVal issue As Variant, ByRef leaveOut() As String) As Boolean
    Dim part As Variant, s As String
    If IsError(issue) Then Exit Function
    s = UCase$(Trim$(CStr(issue)))
    For Each part In leaveOut
        If Len(part) > 0 And InStr(s, part) > 0 Then IsLeftOut = True: Exit Function
    Next part
End Function

' Rows the report mail must not go out with: no time or no Initiated by, on ATM DOWN REPORT
' (rows left out of the mailed copy are skipped) and CASH LOW. Returns the first MAX_LISTED
' as lines; n = number of rows, firstEmpty = the first empty cell.
Private Function MissingEntries(ByVal wb As Workbook, ByRef firstEmpty As Range, ByRef n As Long) As String
    Dim ws As Worksheet, out As String
    n = 0
    Set firstEmpty = Nothing
    Set ws = FindSheetTrim(wb, REPORT_SHEET)
    If Not ws Is Nothing Then out = MissingInSheet(ws, COL_TIME, "Down time", COL_INITIATED, True, firstEmpty, n)
    Set ws = FindSheetTrim(wb, CASH_SHEET)
    If Not ws Is Nothing Then out = out & MissingInSheet(ws, CL_TIME, "Cash low alert time", CL_INITIATED, False, firstEmpty, n)
    MissingEntries = out
End Function

Private Function MissingInSheet(ByVal ws As Worksheet, ByVal timeCol As Long, ByVal timeName As String, _
                                ByVal initCol As Long, ByVal skipLeftOut As Boolean, _
                                ByRef firstEmpty As Range, ByRef n As Long) As String
    Dim leaveOut() As String
    Dim r As Long, lastRow As Long, what As String, out As String

    leaveOut = LeaveOutItems()
    lastRow = ws.Cells(ws.Rows.Count, COL_TERMINAL).End(xlUp).Row
    For r = 1 To lastRow
        If UCase$(Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value))) Like "PRV#*" Then
            If Not (skipLeftOut And IsLeftOut(ws.Cells(r, COL_ISSUE).Value, leaveOut)) Then
                what = vbNullString
                If IsEmptyEntry(ws.Cells(r, timeCol).Value) Then
                    what = timeName
                    If firstEmpty Is Nothing Then Set firstEmpty = ws.Cells(r, timeCol)
                End If
                If IsEmptyEntry(ws.Cells(r, initCol).Value) Then
                    what = what & IIf(Len(what) > 0, ", ", "") & "Initiated by"
                    If firstEmpty Is Nothing Then Set firstEmpty = ws.Cells(r, initCol)
                End If
                If Len(what) > 0 Then
                    n = n + 1
                    If n <= MAX_LISTED Then
                        out = out & vbCrLf & "    " & Trim$(ws.Name) & " row " & r & ": " & _
                              Trim$(CStr(ws.Cells(r, COL_TERMINAL).Value)) & "  " & Trim$(CStr(ws.Cells(r, COL_BRANCH).Value)) & _
                              " - no " & what
                    End If
                End If
            End If
        End If
    Next r
    MissingInSheet = out
End Function

' Empty, spaces only, or an Excel error such as #N/A.
Private Function IsEmptyEntry(ByVal v As Variant) As Boolean
    If IsError(v) Then IsEmptyEntry = True Else IsEmptyEntry = (Len(Trim$(CStr(v))) = 0)
End Function

' For checking without opening anything: "rows <tab> lines" of MissingEntries for a report file.
Public Function ReportMailCheck(ByVal reportPath As String) As String
    Dim wb As Workbook, opened As Boolean, firstEmpty As Range, n As Long, lines As String
    CreateReportMailSheet
    Set wb = OpenWorkbookByPath(reportPath, opened)
    lines = MissingEntries(wb, firstEmpty, n)
    If n > 0 Then lines = lines & vbCrLf & "    first empty cell: " & Trim$(firstEmpty.Worksheet.Name) & "!" & firstEmpty.Address(False, False)
    If opened Then wb.Close SaveChanges:=False
    ReportMailCheck = n & vbTab & lines
End Function

' "a; b , c" -> "a;b;c" (items may contain spaces, e.g. NO TRANSACTION IN ATM)
Private Function CleanList(ByVal s As String) As String
    Dim part As Variant, out As String
    For Each part In Split(Replace(Replace(Replace(s, ",", ";"), vbCr, ";"), vbLf, ";"), ";")
        If Len(Trim$(part)) > 0 Then out = out & ";" & Trim$(part)
    Next part
    If Len(out) > 0 Then CleanList = Mid$(out, 2)
End Function

Private Function DownloadsDir() As String
    On Error Resume Next
    With CreateObject("WScript.Shell")
        DownloadsDir = .ExpandEnvironmentStrings(.RegRead( _
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\" & DOWNLOADS_GUID))
    End With
    On Error GoTo 0
    If Len(DownloadsDir) = 0 Then DownloadsDir = Environ$("USERPROFILE") & "\Downloads"
    If Right$(DownloadsDir, 1) = "\" Then DownloadsDir = Left$(DownloadsDir, Len(DownloadsDir) - 1)
    If Len(Dir$(DownloadsDir, vbDirectory)) = 0 Then DownloadsDir = vbNullString
End Function

' Settings of the daily report mail (addresses are typed in by you).
Public Sub CreateReportMailSheet()
    Dim ws As Worksheet

    If HasSheet(ThisWorkbook, REPORT_MAIL_SHEET) Then Exit Sub
    Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    ws.Name = REPORT_MAIL_SHEET
    ws.Range("A1").Value = "DAILY ATM DOWN TIME REPORT MAIL - used by Mail Down Report"
    ws.Range("A1").Font.Bold = True
    ws.Range("A1").Font.Size = 13

    ws.Cells(RM_TO, 1).Value = "To"
    ws.Cells(RM_TO, 3).Value = "Addresses, separate several with ;"
    ws.Cells(RM_CC, 1).Value = "CC"
    ws.Cells(RM_CC, 3).Value = "Always copied, separate several with ;"
    ws.Cells(RM_BRANCHES, 1).Value = "CC branches mailed today"
    ws.Cells(RM_BRANCHES, 2).Value = "YES"
    ws.Cells(RM_BRANCHES, 3).Value = "YES = also CC every branch mailed today with Mail Down ATMs (email in column C of ATM EMAIL)"
    ws.Cells(RM_SUBJECT, 1).Value = "Subject"
    ws.Cells(RM_SUBJECT, 2).Value = "ATM DOWN TIME REPORT"
    ws.Cells(RM_SUBJECT, 3).Value = "Placeholders: {DATE} (e.g. 28th October 2026) {FILE} (e.g. 28.10.2026.xlsx)"
    ws.Cells(RM_BODY, 1).Value = "Message"
    ws.Cells(RM_BODY, 2).Value = "Dear Sir/Madam," & vbLf & _
        "Please find the attached ATM downtime report date {DATE} here with this formal mail."
    ws.Cells(RM_BODY, 3).Value = "Same placeholders. Alt+Enter = new line. Outlook adds your signature if it is set to add it to new mails."
    ws.Cells(RM_LEAVEOUT, 1).Value = "Leave out issues"
    ws.Cells(RM_LEAVEOUT, 2).Value = "NO TRANSACTION IN ATM"
    ws.Cells(RM_LEAVEOUT, 3).Value = "Rows whose 'Issue in ATM' contains this are removed from the mailed copy. Several: separate with ;"
    ws.Cells(RM_LAST, 1).Value = "Last opened"
    ws.Cells(RM_LAST, 3).Value = "Filled in by the macro"

    ws.Range(ws.Cells(RM_TO, 1), ws.Cells(RM_LAST, 1)).Font.Bold = True
    ws.Range(ws.Cells(RM_TO, 3), ws.Cells(RM_LAST, 3)).Font.Italic = True
    ws.Range(ws.Cells(RM_TO, 3), ws.Cells(RM_LAST, 3)).Font.Color = RGB(89, 89, 89)
    ws.Range(ws.Cells(RM_TO, 2), ws.Cells(RM_LEAVEOUT, 2)).Interior.Color = RGB(255, 242, 204)
    ws.Range(ws.Cells(RM_TO, 2), ws.Cells(RM_BODY, 2)).WrapText = True
    ws.Rows(RM_BODY).RowHeight = 48
    ws.Columns(1).ColumnWidth = 26
    ws.Columns(2).ColumnWidth = 80
    ws.Columns(3).ColumnWidth = 60
    ws.Range("A:C").VerticalAlignment = xlTop
End Sub

' ======================================================================
' "USB ENABLE" MAIL (MailUsbEnable)
'
' Asks for the terminal ID (suggests the ATM of the selected row), takes the
' branch and IP address from the ATM EMAIL sheet (column G) and opens a
' ready-filled Outlook on the web mail. With no IP stored yet it suggests the
' REMOTE ADDRESS of that ATM from Raw Switch Data; what you confirm is saved
' in column G. To / CC / subject / message are on the USB MAIL sheet.
' Nothing is sent automatically.
' ======================================================================

Public Sub MailUsbEnable()
    Dim wsSet As Worksheet, wsMail As Worksheet
    Dim t As String, branch As String, ip As String, suggested As String, prompt As String
    Dim toAddr As String, cc As String, subj As String, link As String, msg As String
    Dim r As Long

    If Not HasSheet(ThisWorkbook, USB_SHEET) Then
        CreateUsbMailSheet
        MsgBox "A new sheet '" & USB_SHEET & "' was added." & vbCrLf & vbCrLf & _
               "Type the To and CC addresses of the USB ENABLE mail in B3 and B4 (separate several with ;), " & _
               "then click Mail USB Enable again.", vbInformation, "Mail USB Enable"
        ThisWorkbook.Worksheets(USB_SHEET).Activate
        Exit Sub
    End If
    Set wsSet = ThisWorkbook.Worksheets(USB_SHEET)
    toAddr = CleanAddresses(CStr(wsSet.Cells(U_TO, 2).Value))
    If Len(toAddr) = 0 Then
        MsgBox "Type the To addresses in cell B3 on the '" & USB_SHEET & "' sheet first.", vbExclamation, "Mail USB Enable"
        wsSet.Activate
        Exit Sub
    End If
    If Not HasSheet(ThisWorkbook, EMAIL_SHEET) Then CreateEmailSheet
    UpgradeEmailSheet
    Set wsMail = ThisWorkbook.Worksheets(EMAIL_SHEET)

    t = UCase$(Trim$(InputBox("Terminal ID of the ATM (e.g. PRV20701):", "Mail USB Enable", SelectedTerminal())))
    If Len(t) = 0 Then Exit Sub
    r = EmailRowOf(t)
    If r = 0 Then
        MsgBox t & " is not on the '" & EMAIL_SHEET & "' sheet. Check the terminal ID.", vbExclamation, "Mail USB Enable"
        Exit Sub
    End If
    branch = Trim$(CStr(wsMail.Cells(r, E_BRANCH).Value))

    ip = Trim$(CStr(wsMail.Cells(r, E_IP).Value))
    If Len(ip) = 0 Then
        suggested = SwitchIpOf(t)
        prompt = "IP address of " & t & "  " & branch & ":"
        If Len(suggested) > 0 Then prompt = prompt & vbCrLf & vbCrLf & _
            "Filled in from the REMOTE ADDRESS column of Raw Switch Data - check it is the ATM's IP."
        prompt = prompt & vbCrLf & vbCrLf & "It is saved in column G of " & EMAIL_SHEET & " for next time."
        ip = Trim$(InputBox(prompt, "Mail USB Enable", suggested))
        If Len(ip) = 0 Then Exit Sub
        If Not IsIpAddress(ip) Then
            MsgBox "'" & ip & "' is not an IP address (like 10.20.30.40).", vbExclamation, "Mail USB Enable"
            Exit Sub
        End If
        wsMail.Cells(r, E_IP).NumberFormat = "@"
        wsMail.Cells(r, E_IP).Value = ip
    End If

    link = BuildUsbMail(t, branch, ip, toAddr, cc, subj)
    msg = "Open the USB ENABLE mail for " & t & "  " & branch & "?" & vbCrLf & vbCrLf & _
          "It opens in Chrome ready to send - check it and click Send." & vbCrLf & _
          IIf(Len(cc) > 0, "Outlook does not take the CC from the link, so the CC addresses are copied:" & vbCrLf & _
                           "in the mail click Cc (right end of the To line) and press Ctrl+V." & vbCrLf, "") & vbCrLf & _
          "IP address: " & ip & "   (column G of " & EMAIL_SHEET & ")" & vbCrLf & _
          "Subject: " & subj & vbCrLf & _
          "To: " & CcForPaste(toAddr) & vbCrLf & _
          "CC: " & IIf(Len(cc) > 0, CcForPaste(cc), "(none - cell B4 on " & USB_SHEET & ")")
    If MsgBox(msg, vbQuestion + vbYesNo, "Mail USB Enable") <> vbYes Then Exit Sub
    OpenLink link
    If Len(cc) > 0 Then PutOnClipboard CcForPaste(cc)
End Sub

' For checking without opening anything: "IP <tab> link" for a terminal (IP from column G
' of ATM EMAIL, else the Raw Switch Data suggestion; nothing is saved).
Public Function UsbMailPreview(ByVal terminal As String) As String
    Dim r As Long, ip As String, branch As String, toAddr As String, cc As String, subj As String
    CreateUsbMailSheet
    terminal = UCase$(Trim$(terminal))
    r = EmailRowOf(terminal)
    If r = 0 Then Exit Function
    branch = Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(r, E_BRANCH).Value))
    ip = Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(r, E_IP).Value))
    If Len(ip) = 0 Then ip = SwitchIpOf(terminal)
    UsbMailPreview = ip & vbTab & BuildUsbMail(terminal, branch, ip, toAddr, cc, subj)
End Function

Private Function BuildUsbMail(ByVal t As String, ByVal branch As String, ByVal ip As String, _
                              ByRef toAddr As String, ByRef cc As String, ByRef subj As String) As String
    Dim wsSet As Worksheet, owa As String
    Set wsSet = ThisWorkbook.Worksheets(USB_SHEET)
    toAddr = CleanAddresses(CStr(wsSet.Cells(U_TO, 2).Value))
    cc = CleanAddresses(CStr(wsSet.Cells(U_CC, 2).Value))
    subj = FillUsbTemplate(CStr(wsSet.Cells(U_SUBJECT, 2).Value), t, branch, ip)
    owa = DEFAULT_OWA
    If HasSheet(ThisWorkbook, EMAIL_SHEET) Then owa = Trim$(CStr(ThisWorkbook.Worksheets(EMAIL_SHEET).Cells(ROW_OWA, 2).Value))
    BuildUsbMail = ComposeLink(owa, toAddr, cc, subj, FillUsbTemplate(CStr(wsSet.Cells(U_BODY, 2).Value), t, branch, ip))
End Function

' {TERMINAL} {BRANCH} {IP} {NL}
Private Function FillUsbTemplate(ByVal tpl As String, ByVal t As String, ByVal branch As String, ByVal ip As String) As String
    Dim s As String
    s = Replace(Replace(tpl, vbCrLf, vbLf), vbLf, vbCrLf)
    s = Replace(s, "{NL}", vbCrLf, , , vbTextCompare)
    s = Replace(s, "{TERMINAL}", t, , , vbTextCompare)
    s = Replace(s, "{BRANCH}", branch, , , vbTextCompare)
    s = Replace(s, "{IP}", ip, , , vbTextCompare)
    FillUsbTemplate = s
End Function

' Row of a terminal on ATM EMAIL, 0 if it is not there.
Private Function EmailRowOf(ByVal t As String) As Long
    Dim ws As Worksheet, r As Long, lastRow As Long
    If Not HasSheet(ThisWorkbook, EMAIL_SHEET) Then Exit Function
    Set ws = ThisWorkbook.Worksheets(EMAIL_SHEET)
    lastRow = ws.Cells(ws.Rows.Count, E_TERMINAL).End(xlUp).Row
    For r = FIRST_ROW To lastRow
        If StrComp(Trim$(CStr(ws.Cells(r, E_TERMINAL).Value)), t, vbTextCompare) = 0 Then EmailRowOf = r: Exit Function
    Next r
End Function

' Terminal of the selected row (any of columns A-D, e.g. ATM EMAIL or a report), else "".
Private Function SelectedTerminal() As String
    Dim c As Long, v As String
    On Error Resume Next
    For c = 1 To 4
        v = UCase$(Trim$(CStr(ActiveCell.EntireRow.Cells(1, c).Value)))
        If v Like "PRV#*" Then
            If InStr(v, " ") > 0 Then v = Left$(v, InStr(v, " ") - 1)
            SelectedTerminal = v
            Exit Function
        End If
    Next c
End Function

' REMOTE ADDRESS of a terminal in Raw Switch Data (the website export), "" if not found.
Private Function SwitchIpOf(ByVal t As String) As String
    Dim ws As Worksheet, r As Long, c As Long, hdr As Long, tidCol As Long, ipCol As Long, lastRow As Long
    Dim v As String
    If Not HasSheet(ThisWorkbook, "Raw Switch Data") Then Exit Function
    Set ws = ThisWorkbook.Worksheets("Raw Switch Data")
    For hdr = 1 To 10
        tidCol = 0: ipCol = 0
        For c = 1 To 30
            v = UCase$(Trim$(CStr(ws.Cells(hdr, c).Value)))
            If v = "TID (PID)" Then tidCol = c
            If v = "REMOTE ADDRESS" Then ipCol = c
        Next c
        If tidCol > 0 And ipCol > 0 Then Exit For
    Next hdr
    If tidCol = 0 Or ipCol = 0 Then Exit Function
    lastRow = ws.Cells(ws.Rows.Count, tidCol).End(xlUp).Row
    For r = hdr + 1 To lastRow
        v = UCase$(Trim$(CStr(ws.Cells(r, tidCol).Value)))
        If InStr(v, "(") > 0 Then v = Left$(v, InStr(v, "(") - 1)
        v = Trim$(v)
        If v = t Then
            v = Trim$(CStr(ws.Cells(r, ipCol).Value))
            If IsIpAddress(v) Then SwitchIpOf = v
            Exit Function
        End If
    Next r
End Function

Private Function IsIpAddress(ByVal s As String) As Boolean
    Dim parts() As String, i As Long
    parts = Split(Trim$(s), ".")
    If UBound(parts) <> 3 Then Exit Function
    For i = 0 To 3
        If Len(parts(i)) = 0 Or Len(parts(i)) > 3 Then Exit Function
        If Not parts(i) Like String$(Len(parts(i)), "#") Then Exit Function
        If CLng(parts(i)) > 255 Then Exit Function
    Next i
    IsIpAddress = True
End Function

' Settings of the USB ENABLE mail (addresses are typed in by you).
Public Sub CreateUsbMailSheet()
    Dim ws As Worksheet

    If HasSheet(ThisWorkbook, USB_SHEET) Then Exit Sub
    Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    ws.Name = USB_SHEET
    ws.Range("A1").Value = "USB ENABLE MAIL - used by Mail USB Enable (IP addresses: column G of " & EMAIL_SHEET & ")"
    ws.Range("A1").Font.Bold = True
    ws.Range("A1").Font.Size = 13

    ws.Cells(U_TO, 1).Value = "To"
    ws.Cells(U_TO, 3).Value = "Addresses, separate several with ;"
    ws.Cells(U_CC, 1).Value = "CC"
    ws.Cells(U_CC, 3).Value = "Separate several with ; (copied for you to paste into the Cc box)"
    ws.Cells(U_SUBJECT, 1).Value = "Subject"
    ws.Cells(U_SUBJECT, 2).Value = "USB ENABLE"
    ws.Cells(U_SUBJECT, 3).Value = "Placeholders: {TERMINAL} {BRANCH} {IP}"
    ws.Cells(U_BODY, 1).Value = "Message"
    ws.Cells(U_BODY, 2).Value = "Dear Sir/Madam," & vbLf & vbLf & _
        "Please enable USB access for the ATM at {BRANCH} ({TERMINAL}) with the following IP address:" & vbLf & vbLf & _
        "IP Address: {IP}" & vbLf & vbLf & _
        "Note for Branch: If USB access is not enabled, kindly contact the Cyber Cell Department for further assistance."
    ws.Cells(U_BODY, 3).Value = "Same placeholders. Alt+Enter = new line. Outlook adds your signature if it is set to add it to new mails."

    ws.Range(ws.Cells(U_TO, 1), ws.Cells(U_BODY, 1)).Font.Bold = True
    ws.Range(ws.Cells(U_TO, 3), ws.Cells(U_BODY, 3)).Font.Italic = True
    ws.Range(ws.Cells(U_TO, 3), ws.Cells(U_BODY, 3)).Font.Color = RGB(89, 89, 89)
    ws.Range(ws.Cells(U_TO, 2), ws.Cells(U_BODY, 2)).Interior.Color = RGB(255, 242, 204)
    ws.Range(ws.Cells(U_TO, 2), ws.Cells(U_BODY, 2)).WrapText = True
    ws.Rows(U_BODY).RowHeight = 110
    ws.Columns(1).ColumnWidth = 16
    ws.Columns(2).ColumnWidth = 90
    ws.Columns(3).ColumnWidth = 50
    ws.Range("A:C").VerticalAlignment = xlTop
End Sub
