SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import BRL.StandardIO

' A Max2D view of snapshots produced by the tournament engine. No ranking is
' calculated here: the animation only moves the engine's published rows.
Type TTourViewRow
	Field id:Int
	Field rank:Int
	Field name:String
	Field team:String
	Field value:Long
	Field stagePlace:Int
End Type

Type TTourViewBoard
	Field rows:TTourViewRow[]

	Method Find:TTourViewRow(id:Int)
		For Local row:TTourViewRow = EachIn rows
			If row.id = id Then
				Return row
			End If
		Next

		Return Null
	End Method
End Type

Type TTourViewFrame
	Field boards:TTourViewBoard[]
	Field podium:String[]
End Type

Type TTourViewData
	Field frames:TTourViewFrame[]

	Method Load(path:String)
		Local source:TStream = ReadStream(path)
		If source = Null Then
			Throw "Cannot read Tour snapshots: " + path + " (run the snapshot exporter first)"
		End If

		frames = New TTourViewFrame[21]
		For Local day:Int = 0 Until 21
			frames[day] = New TTourViewFrame
			frames[day].boards = New TTourViewBoard[6]
			For Local category:Int = 0 Until 6
				frames[day].boards[category] = New TTourViewBoard
			Next
		Next

		While Not source.Eof()
			Local line:String = source.ReadLine()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("~t")
			If fields.Length < 4 Then
				Throw "Invalid Tour snapshot row: " + line
			End If

			Local day:Int = Int(fields[1]) - 1
			If day < 0 Or day >= 21 Then
				Throw "Invalid Tour snapshot stage"
			End If

			If fields[0] = "W" Then
				Local frame:TTourViewFrame = frames[day]
				If Int(fields[2]) <> frame.podium.Length + 1 Then
					Throw "Invalid Tour podium order"
				End If

				frame.podium :+ [fields[3]]
			ElseIf fields[0] = "R" Then
				If fields.Length <> 9 Then
					Throw "Invalid Tour ranking row"
				End If

				Local category:Int = Int(fields[2])
				If category < 0 Or category > 5 Then
					Throw "Invalid Tour classification"
				End If

				Local board:TTourViewBoard = frames[day].boards[category]
				Local row:TTourViewRow = New TTourViewRow
				row.rank = Int(fields[3])
				row.id = Int(fields[4])
				row.name = fields[5]
				row.team = fields[6]
				row.value = Long(fields[7])
				row.stagePlace = Int(fields[8])
				If row.rank <> board.rows.Length + 1 Or row.name = "" Then
					Throw "Invalid Tour rank or rider name"
				End If

				board.rows :+ [row]
			Else
				Throw "Unknown Tour snapshot row"
			End If
		Wend

		source.Close()
		For Local frame:TTourViewFrame = EachIn frames
			If frame.podium.Length <> 3 Then
				Throw "Incomplete Tour podium"
			End If

			For Local board:TTourViewBoard = EachIn frame.boards
				If board.rows.Length = 0 Then
					Throw "Incomplete Tour standings"
				End If
			Next
		Next
	End Method
End Type

Function TwoDigits:String(value:Int)
	If value < 10 Then
		Return "0" + value
	End If

	Return String(value)
End Function

Function RaceTime:String(value:Long)
	Local hours:Int = Int(value / 3600)
	Local minutes:Int = Int((value Mod 3600) / 60)
	Local seconds:Int = Int(value Mod 60)
	Return hours + ":" + TwoDigits(minutes) + ":" + TwoDigits(seconds)
End Function

Function Points:String(units:Long)
	Local whole:Long = units / 2
	If units Mod 2 Then
		Return whole + ".5"
	End If

	Return String(whole)
End Function

Function Value:String(category:Int, row:TTourViewRow, leader:TTourViewRow)
	If category = 1 Or category = 2 Then
		Return Points(row.value) + " pts"
	End If

	If row.rank = 1 Then
		Return RaceTime(row.value)
	End If

	Return "+" + RaceTime(row.value - leader.value)
End Function

Function Limit:Int(value:Int, low:Int, high:Int)
	If value < low Then
		Return low
	End If

	If value > high Then
		Return high
	End If

	Return value
End Function

Function RowY:Float(rank:Int, firstRank:Int)
	Return 161.0 + Float(rank - firstRank) * 31.0
End Function

Function RowScreenY:Float(row:TTourViewRow, prior:TTourViewRow, firstRank:Int, t:Float)
	Local y:Float = RowY(row.rank, firstRank)
	If prior <> Null Then
		Local oldRank:Int = Limit(prior.rank, firstRank - 1, firstRank + 15)
		y = RowY(oldRank, firstRank) + (y - RowY(oldRank, firstRank)) * t
	End If

	Return y
End Function

Function FocusFirst:Int(rank:Int, count:Int)
	Return Limit(rank - 7, 1, Max(1, count - 14))
End Function

Function DrawRow(row:TTourViewRow, prior:TTourViewRow, category:Int, firstRank:Int, t:Float, leader:TTourViewRow, selectedId:Int, leaving:Int = False)
	Local y:Float = RowScreenY(row, prior, firstRank, t)
	Local alpha:Float = 1.0
	If prior = Null Then
		alpha = t
	End If

	If leaving Then
		alpha = 1.0 - t
	End If

	If y < 145 Or y > 625 Or alpha <= 0 Then
		Return
	End If

	SetAlpha alpha
	If row.id = selectedId And Not leaving Then
		SetColor 61, 82, 96
	ElseIf row.rank = 1 Then
		SetColor 58, 79, 70
	ElseIf row.rank Mod 2 = 0 Then
		SetColor 37, 48, 65
	Else
		SetColor 31, 41, 57
	End If

	DrawRect 36, y, 908, 29
	If row.id = selectedId And Not leaving Then
		SetColor 249, 210, 111
		DrawRect 36, y, 4, 29
	End If

	SetColor 252, 212, 109
	DrawText row.rank, 49, y + 5
	SetColor 241, 244, 249
	DrawText row.name, 103, y + 5
	SetColor 150, 170, 192
	If category <> 4 Then
		DrawText row.team, 402, y + 5
	End If

	SetColor 249, 210, 111
	If row.stagePlace > 0 Then
		DrawText "#" + row.stagePlace, 664, y + 5
	End If

	SetColor 245, 246, 247
	DrawText Value(category, row, leader), 806, y + 5
	If prior <> Null And prior.rank <> row.rank And Not leaving Then
		Local moved:Int = prior.rank - row.rank
		If moved > 0 Then
			SetColor 101, 230, 159
			DrawText "+" + moved, 738, y + 5
		Else
			SetColor 255, 147, 139
			DrawText moved, 738, y + 5
		End If
	End If

	SetAlpha 1.0
End Function

Local data:TTourViewData = New TTourViewData
data.Load(AppDir + "/tour_2024_snapshots.tsv")
For Local arg:String = EachIn AppArgs[1..]
	If arg = "--check" Then
		For Local frame:TTourViewFrame = EachIn data.frames
			Local board:TTourViewBoard = frame.boards[0]
			Local rider:TTourViewRow = board.Find(11)
			If rider = Null Then
				Throw "Tour follow check cannot find rider 11"
			End If

			Local first:Int = FocusFirst(rider.rank, board.rows.Length)
			If rider.rank < first Or rider.rank > first + 14 Then
				Throw "Tour follow check did not keep rider visible"
			End If
		Next

		Print "Tour viewer ready: " + data.frames.Length + " stages, " + data.frames[20].boards[0].rows.Length + " finishers, five classifications and stage results"
		End
	End If
Next

AppTitle = "2024 Tour de France — stage race replay"
Graphics 1280, 760
SetClsColor 19, 27, 40
Local labels:String[] = ["GENERAL", "POINTS", "MOUNTAINS", "YOUTH", "TEAMS", "STAGE"]
Local category:Int, day:Int, previousDay:Int, firstRank:Int = 1
Local changedAt:Int = MilliSecs() - 700
Local playing:Int, nextPlay:Int = MilliSecs() + 2200
Local selectedId:Int, selectedName:String

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local wanted:Int = day
	Local click:Int = MouseHit(1)
	If KeyHit(KEY_RIGHT) Then wanted = Min(20, day + 1); playing = False

	If KeyHit(KEY_LEFT) Then wanted = Max(0, day - 1); playing = False

	If KeyHit(KEY_HOME) Then wanted = 0; playing = False

	If KeyHit(KEY_END) Then wanted = 20; playing = False

	If KeyHit(KEY_SPACE) Then playing = Not playing; nextPlay = MilliSecs() + 2200

	Local focusRequested:Int
	If KeyHit(KEY_1) Then category = 0; firstRank = 1; focusRequested = True

	If KeyHit(KEY_2) Then category = 1; firstRank = 1; focusRequested = True

	If KeyHit(KEY_3) Then category = 2; firstRank = 1; focusRequested = True

	If KeyHit(KEY_4) Then category = 3; firstRank = 1; focusRequested = True

	If KeyHit(KEY_5) Then category = 4; firstRank = 1; focusRequested = True

	If KeyHit(KEY_6) Then category = 5; firstRank = 1; focusRequested = True

	If KeyHit(KEY_F) Then
		focusRequested = True
	End If

	If KeyHit(KEY_C) Then selectedId = 0; selectedName = ""

	If KeyHit(KEY_DOWN) Then
		firstRank :+ 1
	End If

	If KeyHit(KEY_UP) Then
		firstRank :- 1
	End If

	Local wheel:Int = MouseZSpeed()
	If wheel <> 0 And MouseX() >= 36 And MouseX() < 944 And MouseY() >= 145 And MouseY() < 626 Then
		firstRank :- wheel * 3
	End If

	If playing And MilliSecs() >= nextPlay Then
		wanted = Min(20, day + 1)
		nextPlay = MilliSecs() + 2200
		If day = 20 Then
			playing = False
		End If
	End If

	If click And MouseY() >= 687 And MouseY() <= 719 Then
		Local clicked:Int = Int(Float(MouseX() - 42) / 57.0)
		If clicked >= 0 And clicked < 21 Then wanted = clicked; playing = False
	End If

	If wanted <> day Then
		previousDay = day
		day = wanted
		changedAt = MilliSecs()
		focusRequested = True
	End If

	Local board:TTourViewBoard = data.frames[day].boards[category]
	Local oldBoard:TTourViewBoard = data.frames[previousDay].boards[category]
	If focusRequested And selectedId <> 0 Then
		Local focused:TTourViewRow = board.Find(selectedId)
		If focused <> Null Then
			firstRank = FocusFirst(focused.rank, board.rows.Length)
		End If
	End If

	firstRank = Limit(firstRank, 1, Max(1, board.rows.Length - 14))
	Local t:Float = Min(1.0, Float(MilliSecs() - changedAt) / 650.0)
	If t = 1.0 Then
		previousDay = day
	End If

	If category <> 4 And click And MouseX() >= 36 And MouseX() < 944 And MouseY() >= 145 And MouseY() < 626 Then
		Local clickedRow:TTourViewRow
		For Local row:TTourViewRow = EachIn board.rows
			If row.rank < firstRank Or row.rank > firstRank + 14 Then
				Continue
			End If

			Local y:Float = RowScreenY(row, oldBoard.Find(row.id), firstRank, t)
			If MouseY() >= y And MouseY() < y + 29 Then
				clickedRow = row
			End If
		Next

		If clickedRow <> Null Then
			If selectedId = clickedRow.id Then
				selectedId = 0
				selectedName = ""
			Else
				selectedId = clickedRow.id
				selectedName = clickedRow.name
			End If
		End If
	End If

	Cls
	SetColor 249, 210, 111
	DrawRect 0, 0, 1280, 6
	DrawText "TOUR DE FRANCE 2024", 36, 26
	SetColor 238, 243, 249
	DrawText "Stage " + (day + 1) + " / 21", 36, 56
	SetColor 151, 172, 199
	DrawText "Engine standings after the stage", 177, 56
	DrawText "Click a rider to follow", 523, 56
	For Local i:Int = 0 Until 6
		Local x:Int = 36 + i * 151
		If i = category Then
			SetColor 222, 181, 86
		Else
			SetColor 74, 87, 109
		End If

		DrawRect x, 91, 142, 35
		SetColor 18, 27, 40
		DrawText (i + 1) + "  " + labels[i], x + 9, 101
	Next

	SetColor 144, 163, 185
	DrawText "RANK", 48, 139
	DrawText "RIDER / TEAM", 103, 139
	If category <> 4 Then
		DrawText "TEAM", 402, 139
	End If

	DrawText "STAGE", 664, 139
	DrawText "MOVE", 738, 139
	DrawText "TIME / POINTS", 806, 139
	If t < 1.0 Then
		For Local old:TTourViewRow = EachIn oldBoard.rows
			If old.rank < firstRank Or old.rank > firstRank + 14 Then
				Continue
			End If

			Local updated:TTourViewRow = board.Find(old.id)
			If updated = Null Or updated.rank < firstRank Or updated.rank > firstRank + 14 Then
				DrawRow(old, old, category, firstRank, t, oldBoard.rows[0], selectedId, True)
			End If
		Next
	End If

	For Local row:TTourViewRow = EachIn board.rows
		If row.rank > firstRank + 14 Then
			Exit
		End If

		If row.rank >= firstRank Then
			DrawRow(row, oldBoard.Find(row.id), category, firstRank, t, board.rows[0], selectedId)
		End If
	Next

	SetColor 39, 52, 70
	DrawRect 964, 91, 279, 537
	SetColor 248, 211, 120
	DrawText "STAGE PODIUM", 984, 110
	For Local i:Int = 0 Until data.frames[day].podium.Length
		SetColor 142, 160, 184
		DrawText (i + 1) + ".", 984, 146 + i * 38
		SetColor 245, 247, 250
		DrawText data.frames[day].podium[i], 1012, 146 + i * 38
	Next

	SetColor 248, 211, 120
	If category = 5 Then
		DrawText "STAGE WINNER", 984, 304
	Else
		DrawText labels[category] + " LEADER", 984, 304
	End If

	SetColor 245, 247, 250
	DrawText board.rows[0].name, 984, 337
	SetColor 158, 177, 197
	DrawText Value(category, board.rows[0], board.rows[0]), 984, 365
	DrawText board.rows.Length + " classified", 984, 400
	If day > 0 Then
		Local lastBoard:TTourViewBoard = data.frames[day - 1].boards[category]
		Local moves:Int
		For Local row:TTourViewRow = EachIn board.rows
			Local last:TTourViewRow = lastBoard.Find(row.id)
			If last <> Null And last.rank <> row.rank Then
				moves :+ 1
			End If
		Next

		DrawText moves + " rank changes today", 984, 426
	End If

	If selectedId <> 0 Then
		SetColor 249, 210, 111
		DrawText "FOLLOWING RIDER", 984, 451
		SetColor 245, 247, 250
		DrawText selectedName, 984, 475
		SetColor 158, 177, 197
		Local selected:TTourViewRow = board.Find(selectedId)
		If selected <> Null Then
			Local status:String = "Rank #" + selected.rank
			If selected.stagePlace > 0 Then
				status :+ "   Stage #" + selected.stagePlace
			End If

			DrawText status, 984, 498
		ElseIf category = 4 Then
			DrawText "Team view has no rider rows", 984, 498
		Else
			DrawText "No result in this view", 984, 498
		End If
	Else
		SetColor 158, 177, 197
		DrawText "Click a rider to follow", 984, 468
	End If

	SetColor 158, 177, 197
	DrawText "LEFT/RIGHT stage  SPACE play", 984, 541
	DrawText "1–6 view  WHEEL scroll", 984, 563
	DrawText "CLICK again or C to clear", 984, 585
	DrawText "F refocus  UP/DOWN scroll", 984, 607
	SetColor 151, 172, 199
	DrawText "Select a stage", 42, 649
	For Local i:Int = 0 Until 21
		If i = day Then
			SetColor 249, 211, 111
		ElseIf i < day Then
			SetColor 90, 164, 158
		Else
			SetColor 66, 82, 105
		End If

		DrawRect 42 + i * 57, 689, 43, 25
		SetColor 18, 27, 40
		DrawText i + 1, 53 + i * 57, 694
	Next

	Flip
Wend

EndGraphics
