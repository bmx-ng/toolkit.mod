SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import BRL.StandardIO

' Rankings and point changes are exported from toolkit.tourney; this app only draws them.
Type TF1ViewRow
	Field id:Int
	Field rank:Int
	Field name:String
	Field team:String
	Field points:Int
	Field place:Int
	Field gained:Int
End Type

Type TF1ViewBoard
	Field rows:TF1ViewRow[]

	Method Find:TF1ViewRow(id:Int)
		For Local row:TF1ViewRow = EachIn rows
			If row.id = id Then
				Return row
			End If
		Next

		Return Null
	End Method
End Type

Type TF1ViewFrame
	Field round:Int
	Field eventName:String
	Field session:String
	Field fastestId:Int
	Field fastestName:String
	Field boards:TF1ViewBoard[]
End Type

Type TF1ViewData
	Field frames:TF1ViewFrame[]

	Method Load(path:String)
		Local source:TStream = ReadStream(path)
		If source = Null Then
			Throw "Cannot read F1 snapshots: " + path + " (run the exporter first)"
		End If

		frames = New TF1ViewFrame[25]
		For Local i:Int = 0 Until frames.Length
			frames[i] = New TF1ViewFrame
			frames[i].boards = [New TF1ViewBoard, New TF1ViewBoard]
		Next

		While Not source.Eof()
			Local line:String = source.ReadLine()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			If fields.Length <> 7 And fields.Length <> 10 Then
				Throw "Invalid F1 snapshot row"
			End If

			Local index:Int = Int(fields[1]) - 1
			If index < 0 Or index >= frames.Length Then
				Throw "Invalid F1 session index"
			End If

			Local frame:TF1ViewFrame = frames[index]
			If fields[0] = "E" Then
				If fields.Length <> 7 Or frame.eventName <> "" Then
					Throw "Invalid F1 event row"
				End If

				frame.round = Int(fields[2])
				frame.eventName = fields[3]
				frame.session = fields[4]
				frame.fastestId = Int(fields[5])
				frame.fastestName = fields[6]
			ElseIf fields[0] = "R" Then
				If fields.Length <> 10 Then
					Throw "Invalid F1 standings row"
				End If

				Local category:Int = Int(fields[2])
				If category < 0 Or category > 1 Then
					Throw "Invalid F1 championship"
				End If

				Local row:TF1ViewRow = New TF1ViewRow
				row.rank = Int(fields[3])
				row.id = Int(fields[4])
				row.name = fields[5]
				row.team = fields[6]
				row.points = Int(fields[7])
				row.place = Int(fields[8])
				row.gained = Int(fields[9])
				Local board:TF1ViewBoard = frame.boards[category]
				If row.rank <> board.rows.Length + 1 Or row.name = "" Then
					Throw "Invalid F1 rank"
				End If

				board.rows :+ [row]
			Else
				Throw "Unknown F1 snapshot row"
			End If
		Wend

		source.Close()
		Local sprintCount:Int
		For Local frame:TF1ViewFrame = EachIn frames
			If frame.eventName = "" Then
				Throw "Missing F1 event"
			End If

			If frame.session = "SPRINT" Then
				sprintCount :+ 1
			End If

			If frame.session <> "SPRINT" And frame.session <> "RACE" Then
				Throw "Invalid F1 session"
			End If

			If frame.boards[0].rows.Length <> 21 Or frame.boards[1].rows.Length <> 10 Then
				Throw "Incomplete F1 standings"
			End If
		Next

		If sprintCount <> 3 Or frames[24].round <> 22 Then
			Throw "Incomplete F1 season"
		End If
	End Method
End Type

Function F1Points:String(units:Int)
	Local sign:String = ""
	If units < 0 Then sign = "-"; units = -units

	Local value:String = String(units / 2)
	If units Mod 2 Then
		value :+ ".5"
	End If

	Return sign + value
End Function

Function F1Clamp:Int(value:Int, low:Int, high:Int)
	Return Max(low, Min(high, value))
End Function

Function F1First:Int(rank:Int, count:Int)
	Return F1Clamp(rank - 7, 1, Max(1, count - 14))
End Function

Function F1RowY:Float(rank:Int, first:Int)
	Return 169.0 + Float(rank - first) * 31.0
End Function

Function F1DrawRow(row:TF1ViewRow, old:TF1ViewRow, first:Int, t:Float, category:Int, selected:Int)
	Local y:Float = F1RowY(row.rank, first)
	If old <> Null Then
		y = F1RowY(F1Clamp(old.rank, first - 1, first + 15), first) * (1.0 - t) + y * t
	End If

	If y < 154 Or y > 625 Then
		Return
	End If

	If row.id = selected Then
		SetColor 96, 57, 59
	ElseIf row.rank = 1 Then
		SetColor 82, 61, 48
	ElseIf row.rank Mod 2 = 0 Then
		SetColor 37, 43, 56
	Else
		SetColor 30, 36, 49
	End If

	DrawRect 36, y, 907, 29
	If row.id = selected Then
		SetColor 255, 116, 104
		DrawRect 36, y, 4, 29
	End If

	SetColor 244, 116, 104
	DrawText row.rank, 50, y + 5
	SetColor 242, 245, 249
	DrawText row.name, 100, y + 5
	SetColor 158, 171, 189
	If category = 0 Then
		DrawText row.team, 370, y + 5
	End If

	If category = 0 And row.place > 0 Then
		SetColor 237, 187, 129
		DrawText "P" + row.place, 607, y + 5
	End If

	If row.gained > 0 Then
		SetColor 118, 219, 162
		DrawText "+" + F1Points(row.gained), 701, y + 5
	End If

	SetColor 242, 245, 249
	DrawText F1Points(row.points), 844, y + 5
	If old <> Null And old.rank <> row.rank Then
		Local move:Int = old.rank - row.rank
		If move > 0 Then SetColor 118, 219, 162 Else SetColor 255, 144, 135

		If move > 0 Then DrawText "+" + move, 777, y + 5 Else DrawText move, 777, y + 5
	End If
End Function

Local data:TF1ViewData = New TF1ViewData
data.Load(AppDir + "/f1_2021_snapshots.tsv")
For Local arg:String = EachIn AppArgs[1..]
	If arg = "--check" Then
		If data.frames[24].boards[0].rows[0].id <> 9 Or data.frames[24].boards[0].rows[0].points <> 791 Then
			Throw "Wrong final driver standing"
		End If

		If data.frames[24].boards[1].rows[0].id <> 108 Or data.frames[24].boards[1].rows[0].points <> 1227 Then
			Throw "Wrong final constructor standing"
		End If

		For Local frame:TF1ViewFrame = EachIn data.frames
			For Local board:TF1ViewBoard = EachIn frame.boards
				For Local row:TF1ViewRow = EachIn board.rows
					Local first:Int = F1First(row.rank, board.rows.Length)
					If row.rank < first Or row.rank > first + 14 Then
						Throw "F1 follow view missed a participant"
					End If
				Next
			Next
		Next

		Print "F1 viewer ready: 22 rounds, 25 sessions, 21 drivers and 10 constructors"
		End
	End If
Next

AppTitle = "2021 Formula One season replay"
Graphics 1280, 760
SetClsColor 21, 25, 34
Local session:Int, previous:Int, category:Int, first:Int = 1
Local selected:Int, selectedName:String
Local playing:Int, nextPlay:Int = MilliSecs() + 2000
Local changedAt:Int = MilliSecs() - 700
While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local wanted:Int = session
	Local click:Int = MouseHit(1)
	If KeyHit(KEY_RIGHT) Then wanted = Min(24, session + 1); playing = False

	If KeyHit(KEY_LEFT) Then wanted = Max(0, session - 1); playing = False

	If KeyHit(KEY_HOME) Then wanted = 0; playing = False

	If KeyHit(KEY_END) Then wanted = 24; playing = False

	If KeyHit(KEY_SPACE) Then playing = Not playing; nextPlay = MilliSecs() + 2000

	Local refocus:Int
	If KeyHit(KEY_1) Then category = 0; first = 1; refocus = True

	If KeyHit(KEY_2) Then category = 1; first = 1; refocus = True

	If KeyHit(KEY_F) Then
		refocus = True
	End If

	If KeyHit(KEY_C) Then selected = 0; selectedName = ""

	If KeyHit(KEY_DOWN) Then
		first :+ 1
	End If

	If KeyHit(KEY_UP) Then
		first :- 1
	End If

	Local wheel:Int = MouseZSpeed()
	If wheel <> 0 And MouseX() >= 36 And MouseX() < 944 And MouseY() >= 154 And MouseY() < 626 Then
		first :- wheel * 3
	End If

	If playing And MilliSecs() >= nextPlay Then
		wanted = Min(24, session + 1)
		nextPlay = MilliSecs() + 2000
		If session = 24 Then
			playing = False
		End If
	End If

	If click And MouseY() >= 686 And MouseY() <= 720 Then
		Local clicked:Int = Int(Float(MouseX() - 42) / 47.0)
		If clicked >= 0 And clicked < 25 Then wanted = clicked; playing = False
	End If

	If click And MouseY() >= 99 And MouseY() < 135 Then
		If MouseX() >= 36 And MouseX() < 203 Then category = 0; first = 1; refocus = True

		If MouseX() >= 215 And MouseX() < 382 Then category = 1; first = 1; refocus = True
	End If

	If wanted <> session Then
		previous = session
		session = wanted
		changedAt = MilliSecs()
		refocus = True
	End If

	Local frame:TF1ViewFrame = data.frames[session]
	Local board:TF1ViewBoard = frame.boards[category]
	Local oldBoard:TF1ViewBoard = data.frames[previous].boards[category]
	If refocus And selected <> 0 Then
		Local focused:TF1ViewRow = board.Find(selected)
		If focused <> Null Then
			first = F1First(focused.rank, board.rows.Length)
		End If
	End If

	first = F1Clamp(first, 1, Max(1, board.rows.Length - 14))
	Local t:Float = Min(1.0, Float(MilliSecs() - changedAt) / 650.0)
	If t = 1.0 Then
		previous = session
	End If

	If click And MouseX() >= 36 And MouseX() < 944 And MouseY() >= 154 And MouseY() < 626 Then
		For Local row:TF1ViewRow = EachIn board.rows
			If row.rank < first Or row.rank > first + 14 Then
				Continue
			End If

			Local y:Float = F1RowY(row.rank, first)
			Local old:TF1ViewRow = oldBoard.Find(row.id)
			If old <> Null Then
				y = F1RowY(F1Clamp(old.rank, first - 1, first + 15), first) * (1.0 - t) + y * t
			End If

			If MouseY() >= y And MouseY() < y + 29 Then
				If selected = row.id Then
					selected = 0; selectedName = ""
				Else
					selected = row.id; selectedName = row.name
				End If

				Exit
			End If
		Next
	End If

	Cls
	SetColor 220, 64, 65
	DrawRect 0, 0, 1280, 6
	DrawText "FORMULA ONE 2021", 36, 24
	SetColor 240, 243, 248
	DrawText "Round " + frame.round + " / 22   " + frame.eventName, 36, 54
	SetColor 172, 184, 201
	DrawText frame.session + "  |  Session " + (session + 1) + " / 25", 772, 55
	For Local i:Int = 0 To 1
		Local x:Int = 36 + i * 179
		If i = category Then SetColor 242, 115, 104 Else SetColor 86, 95, 109

		DrawRect x, 99, 167, 36
		SetColor 19, 24, 34
		If i = 0 Then DrawText "1  DRIVERS", x + 10, 110 Else DrawText "2  CONSTRUCTORS", x + 10, 110
	Next

	SetColor 151, 163, 184
	DrawText "RANK", 49, 145
	DrawText "PARTICIPANT", 100, 145
	If category = 0 Then
		DrawText "TEAM", 370, 145
	End If

	DrawText "FINISH", 607, 145
	DrawText "+POINTS", 701, 145
	DrawText "MOVE", 777, 145
	DrawText "POINTS", 844, 145
	For Local row:TF1ViewRow = EachIn board.rows
		If row.rank > first + 14 Then
			Exit
		End If

		If row.rank >= first Then
			F1DrawRow(row, oldBoard.Find(row.id), first, t, category, selected)
		End If
	Next

	SetColor 42, 48, 63
	DrawRect 964, 99, 280, 529
	SetColor 245, 130, 116
	DrawText "SESSION PODIUM", 984, 117
	For Local i:Int = 0 Until 3
		Local driverId:Int
		' Classification places are carried in the driver board.
		For Local row:TF1ViewRow = EachIn frame.boards[0].rows
			If row.place = i + 1 Then driverId = row.id; Exit
		Next

		Local driver:TF1ViewRow = frame.boards[0].Find(driverId)
		If driver <> Null Then
			SetColor 171, 182, 199
			DrawText (i + 1) + ".", 984, 153 + i * 38
			SetColor 243, 245, 249
			DrawText driver.name, 1012, 153 + i * 38
		End If
	Next

	SetColor 245, 130, 116
	DrawText "FASTEST LAP", 984, 286
	SetColor 242, 245, 249
	If frame.fastestId = 0 Then
		DrawText "No recorded award", 984, 315
	Else
		DrawText frame.fastestName, 984, 315
		Local lapDriver:TF1ViewRow = frame.boards[0].Find(frame.fastestId)
		SetColor 171, 182, 199
		If lapDriver <> Null And lapDriver.place <= 10 And frame.session = "RACE" Then
			DrawText "+1 point (top ten)", 984, 342
		Else
			DrawText "No bonus point", 984, 342
		End If
	End If

	SetColor 245, 130, 116
	DrawText "CHAMPIONSHIP LEADER", 984, 391
	SetColor 242, 245, 249
	DrawText board.rows[0].name, 984, 419
	SetColor 171, 182, 199
	DrawText F1Points(board.rows[0].points) + " points", 984, 446
	If selected <> 0 Then
		SetColor 245, 130, 116
		DrawText "FOLLOWING", 984, 482
		SetColor 242, 245, 249
		DrawText selectedName, 984, 506
		Local followed:TF1ViewRow = board.Find(selected)
		SetColor 171, 182, 199
		If followed <> Null Then DrawText "Rank " + followed.rank + "  |  " + F1Points(followed.points) + " pts", 984, 530 Else DrawText "Other championship", 984, 530
	Else
		SetColor 171, 182, 199
		DrawText "Click a row to follow", 984, 502
	End If

	SetColor 171, 182, 199
	DrawText "LEFT/RIGHT session  SPACE play", 984, 563
	DrawText "1/2 view  WHEEL scroll", 984, 585
	DrawText "CLICK again or C clear  F focus", 984, 607
	DrawText "Select a session (S = sprint, R = race)", 42, 650
	For Local i:Int = 0 Until 25
		If i = session Then SetColor 245, 130, 116 ElseIf i < session Then SetColor 117, 164, 152 Else SetColor 73, 83, 102

		DrawRect 42 + i * 47, 686, 41, 32
		SetColor 19, 24, 34
		Local label:String = "R"
		If data.frames[i].session = "SPRINT" Then
			label = "S"
		End If

		DrawText data.frames[i].round + label, 45 + i * 47, 694
	Next

	Flip
Wend

EndGraphics
