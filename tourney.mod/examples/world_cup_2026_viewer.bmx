SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import BRL.StandardIO

' The viewer reads engine snapshots and draws them; it never scores a match.
Type TWCViewTeam
	Field id:Int
	Field name:String
	Field group:String
	Field qualified:Int
End Type

Type TWCViewRow
	Field rank:Int
	Field teamId:Int
	Field played:Int
	Field wins:Int
	Field draws:Int
	Field losses:Int
	Field gf:Int
	Field ga:Int
	Field points:Int
End Type

Type TWCViewGroup
	Field rows:TWCViewRow[]

	Method Find:TWCViewRow(id:Int)
		For Local row:TWCViewRow = EachIn rows
			If row.teamId = id Then
				Return row
			End If
		Next

		Return Null
	End Method
End Type

Type TWCViewMatch
	Field index:Int
	Field date:String
	Field stage:String
	Field round:Int
	Field position:Int
	Field group:String
	Field homeId:Int
	Field awayId:Int
	Field homeScore:Int
	Field awayScore:Int
	Field homePenalties:Int
	Field awayPenalties:Int
	Field extraTime:Int
	Field winnerId:Int
End Type

Type TWCViewFrame
	Field match:TWCViewMatch
	Field groups:TWCViewGroup[]
End Type

Type TWCViewData
	Field teams:TWCViewTeam[]
	Field frames:TWCViewFrame[]

	Method Team:TWCViewTeam(id:Int)
		For Local team:TWCViewTeam = EachIn teams
			If team.id = id Then
				Return team
			End If
		Next

		Return Null
	End Method

	Method Name:String(id:Int)
		Local team:TWCViewTeam = Team(id)
		If team <> Null Then
			Return team.name
		End If

		Return "TBD"
	End Method

	Method Load(path:String)
		Local input:TStream = ReadStream(path)
		If input = Null Then
			Throw "Cannot read World Cup snapshots: " + path + " (run the exporter first)"
		End If

		frames = New TWCViewFrame[104]
		For Local i:Int = 0 Until frames.Length
			frames[i] = New TWCViewFrame
			frames[i].groups = New TWCViewGroup[12]
			For Local group:Int = 0 Until 12
				frames[i].groups[group] = New TWCViewGroup
			Next
		Next

		Local qualified:Int
		While Not input.Eof()
			Local line:String = input.ReadLine()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			Select fields[0]
				Case "T"
					If fields.Length <> 4 Then
						Throw "Invalid World Cup team snapshot"
					End If

					Local team:TWCViewTeam = New TWCViewTeam
					team.id = Int(fields[1])
					team.name = fields[2]
					team.group = fields[3]
					teams :+ [team]
				Case "Q"
					If fields.Length <> 2 Then
						Throw "Invalid World Cup qualifier snapshot"
					End If

					Local team:TWCViewTeam = Team(Int(fields[1]))
					If team = Null Or team.qualified Then
						Throw "Invalid World Cup qualifier"
					End If

					team.qualified = True
					qualified :+ 1
				Case "E"
					If fields.Length <> 15 Then
						Throw "Invalid World Cup match snapshot"
					End If

					Local index:Int = Int(fields[1]) - 1
					If index < 0 Or index >= frames.Length Or frames[index].match <> Null Then
						Throw "Invalid World Cup match index"
					End If

					Local match:TWCViewMatch = New TWCViewMatch
					match.index = index
					match.date = fields[2]
					match.stage = fields[3]
					match.round = Int(fields[4])
					match.position = Int(fields[5])
					match.group = fields[6]
					match.homeId = Int(fields[7])
					match.awayId = Int(fields[8])
					match.homeScore = Int(fields[9])
					match.awayScore = Int(fields[10])
					match.homePenalties = Int(fields[11])
					match.awayPenalties = Int(fields[12])
					match.extraTime = Int(fields[13])
					match.winnerId = Int(fields[14])
					frames[index].match = match
				Case "R"
					If fields.Length <> 12 Then
						Throw "Invalid World Cup table snapshot"
					End If

					Local index:Int = Int(fields[1]) - 1
					Local group:Int = fields[2][0] - 65
					If index < 0 Or index >= frames.Length Or group < 0 Or group >= 12 Then
						Throw "Invalid World Cup group snapshot"
					End If

					Local row:TWCViewRow = New TWCViewRow
					row.rank = Int(fields[3])
					row.teamId = Int(fields[4])
					row.played = Int(fields[5])
					row.wins = Int(fields[6])
					row.draws = Int(fields[7])
					row.losses = Int(fields[8])
					row.gf = Int(fields[9])
					row.ga = Int(fields[10])
					row.points = Int(fields[11])
					Local board:TWCViewGroup = frames[index].groups[group]
					If row.rank <> board.rows.Length + 1 Then
						Throw "Invalid World Cup table rank"
					End If

					board.rows :+ [row]
				Default
					Throw "Unknown World Cup snapshot row"
			End Select
		Wend

		input.Close()
		If teams.Length <> 48 Or qualified <> 32 Then
			Throw "Incomplete World Cup entrants"
		End If

		Local shootouts:Int
		For Local frame:TWCViewFrame = EachIn frames
			If frame.match = Null Then
				Throw "Missing World Cup match"
			End If

			If frame.match.homePenalties > 0 Or frame.match.awayPenalties > 0 Then
				shootouts :+ 1
			End If

			For Local group:TWCViewGroup = EachIn frame.groups
				If group.rows.Length <> 4 Then
					Throw "Incomplete World Cup group table"
				End If
			Next
		Next

		If shootouts <> 4 Or frames[71].match.stage <> "GROUPS" Or frames[72].match.stage <> "WORLD_CUP_W1" Then
			Throw "Incorrect World Cup phase transition"
		End If

		If Name(frames[103].match.winnerId) <> "Spain" Then
			Throw "Incorrect World Cup champion"
		End If
	End Method
End Type

Function WCPhase:String(stage:String)
	Select stage
		Case "GROUPS"; Return "GROUP STAGE"
		Case "WORLD_CUP_W1"; Return "ROUND OF 32"
		Case "WORLD_CUP_W2"; Return "ROUND OF 16"
		Case "WORLD_CUP_W3"; Return "QUARTER-FINAL"
		Case "WORLD_CUP_W4"; Return "SEMI-FINAL"
		Case "WORLD_CUP_W5"; Return "FINAL"
		Case "WORLD_CUP_THIRD"; Return "THIRD PLACE"
	End Select

	Return stage
End Function

Function WCScore:String(match:TWCViewMatch)
	Local result:String = match.homeScore + " - " + match.awayScore
	If match.homePenalties > 0 Or match.awayPenalties > 0 Then
		result :+ "  (pens " + match.homePenalties + "-" + match.awayPenalties + ")"
	ElseIf match.extraTime Then
		result :+ "  AET"
	End If

	Return result
End Function

Function WCShort:String(name:String, limit:Int = 10)
	If name.Length <= limit Then
		Return name
	End If

	Return name[..limit - 1] + "."
End Function

Function WCBracketLabel:String(data:TWCViewData, match:TWCViewMatch)
	Return WCShort(data.Name(match.homeId), 9) + " " + match.homeScore + "-" + match.awayScore + " " + WCShort(data.Name(match.awayId), 9)
End Function

Function WCDrawBracketCard(data:TWCViewData, match:TWCViewMatch, current:Int, selectedId:Int, x:Int, y:Int, width:Int)
	Local played:Int = match.index <= current
	If match.index = current Then
		SetColor 190, 155, 72
	ElseIf selectedId <> 0 And played And (match.homeId = selectedId Or match.awayId = selectedId) Then
		SetColor 59, 121, 119
	ElseIf played Then
		SetColor 42, 55, 70
	Else
		SetColor 31, 39, 52
	End If

	DrawRect x, y, width, 25
	If played Then
		SetColor 248, 247, 241
		DrawText WCBracketLabel(data, match), x + 5, y + 5
	ElseIf match.stage = "WORLD_CUP_W1" And current >= 71 Then
		SetColor 172, 184, 198
		DrawText WCShort(data.Name(match.homeId), 9) + " v " + WCShort(data.Name(match.awayId), 9), x + 5, y + 5
	Else
		SetColor 105, 123, 141
		DrawText "Awaiting teams", x + 5, y + 5
	End If
End Function

Local data:TWCViewData = New TWCViewData
data.Load(AppDir + "/world_cup_2026_snapshots.tsv")
For Local arg:String = EachIn AppArgs[1..]
	If arg = "--check" Then
		Local k:TWCViewGroup = data.frames[71].groups[10]
		If data.Name(k.rows[0].teamId) <> "Colombia" Or k.rows[0].points <> 7 Then
			Throw "Incorrect Group K table"
		End If

		If data.Name(data.frames[102].match.winnerId) <> "England" Then
			Throw "Incorrect bronze match"
		End If

		Print "World Cup viewer ready: 48 teams, 12 groups, 104 matches, 32 qualifiers and five knockout rounds"
		End
	End If
Next

AppTitle = "2026 World Cup replay"
Graphics 1280, 760
SetClsColor 18, 30, 43
Local current:Int, groupIndex:Int, mode:Int
Local selectedId:Int
Local playing:Int, nextPlay:Int = MilliSecs() + 1100
While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local wanted:Int = current
	Local click:Int = MouseHit(1)
	If KeyHit(KEY_RIGHT) Then wanted = Min(103, current + 1); playing = False

	If KeyHit(KEY_LEFT) Then wanted = Max(0, current - 1); playing = False

	If KeyHit(KEY_HOME) Then wanted = 0; playing = False

	If KeyHit(KEY_END) Then wanted = 103; playing = False

	If KeyHit(KEY_SPACE) Then playing = Not playing; nextPlay = MilliSecs() + 1100

	If KeyHit(KEY_G) Then
		mode = 0
	End If

	If KeyHit(KEY_B) Then
		mode = 1
	End If

	If KeyHit(KEY_C) Then
		selectedId = 0
	End If

	If KeyHit(KEY_UP) Then
		groupIndex = Max(0, groupIndex - 1)
	End If

	If KeyHit(KEY_DOWN) Then
		groupIndex = Min(11, groupIndex + 1)
	End If

	If playing And MilliSecs() >= nextPlay Then
		wanted = Min(103, current + 1)
		nextPlay = MilliSecs() + 1100
		If current = 103 Then
			playing = False
		End If
	End If

	If click And MouseY() >= 704 And MouseY() < 727 Then
		Local point:Int = (MouseX() - 36) / 11
		If point >= 0 And point < 104 Then wanted = point; playing = False
	End If

	If click And MouseY() >= 96 And MouseY() <= 127 Then
		If MouseX() >= 36 And MouseX() < 177 Then
			mode = 0
		End If

		If MouseX() >= 190 And MouseX() < 331 Then
			mode = 1
		End If
	End If

	If mode = 0 And click And MouseY() >= 139 And MouseY() <= 168 Then
		Local tab:Int = (MouseX() - 36) / 72
		If tab >= 0 And tab < 12 Then
			groupIndex = tab
		End If
	End If

	If wanted <> current Then
		current = wanted
		If current = 72 Then
			mode = 1
		End If
	End If

	Local frame:TWCViewFrame = data.frames[current]
	Local match:TWCViewMatch = frame.match
	Cls
	SetColor 206, 163, 73
	DrawRect 0, 0, 1280, 6
	DrawText "WORLD CUP 2026", 36, 24
	SetColor 240, 245, 248
	DrawText "Match " + (current + 1) + " / 104   " + WCPhase(match.stage), 36, 54
	SetColor 157, 179, 197
	DrawText match.date, 647, 55
	DrawText "LEFT/RIGHT match   SPACE play   G groups   B bracket", 36, 75
	For Local i:Int = 0 To 1
		Local x:Int = 36 + i * 154
		If i = mode Then SetColor 215, 173, 81 Else SetColor 73, 90, 107

		DrawRect x, 96, 141, 31
		SetColor 19, 31, 42
		If i = 0 Then DrawText "GROUPS", x + 14, 104 Else DrawText "BRACKET", x + 14, 104
	Next

	If mode = 0 Then
		For Local i:Int = 0 Until 12
			Local x:Int = 36 + i * 72
			If i = groupIndex Then SetColor 214, 173, 84 Else SetColor 63, 79, 96

			DrawRect x, 139, 64, 29
			SetColor 20, 30, 41
			DrawText "Group " + "ABCDEFGHIJKL"[i..i + 1], x + 5, 146
		Next

		Local code:String = "ABCDEFGHIJKL"[groupIndex..groupIndex + 1]
		SetColor 213, 174, 90
		DrawText "GROUP " + code + " STANDINGS", 36, 192
		SetColor 159, 177, 195
		DrawText "TEAM", 101, 225
		DrawText "P", 485, 225
		DrawText "W", 531, 225
		DrawText "D", 575, 225
		DrawText "L", 619, 225
		DrawText "GF", 662, 225
		DrawText "GA", 717, 225
		DrawText "PTS", 791, 225
		For Local i:Int = 0 Until 4
			Local row:TWCViewRow = frame.groups[groupIndex].rows[i]
			Local y:Int = 248 + i * 43
			If row.teamId = selectedId Then SetColor 81, 112, 111 ElseIf i < 2 Then SetColor 51, 72, 77 ElseIf i = 2 Then SetColor 55, 66, 73 Else SetColor 38, 50, 65

			DrawRect 36, y, 844, 39
			SetColor 220, 177, 88
			DrawText i + 1, 51, y + 10
			SetColor 241, 245, 247
			DrawText data.Name(row.teamId), 101, y + 10
			SetColor 170, 188, 204
			DrawText row.played, 485, y + 10
			DrawText row.wins, 531, y + 10
			DrawText row.draws, 575, y + 10
			DrawText row.losses, 619, y + 10
			DrawText row.gf, 662, y + 10
			DrawText row.ga, 717, y + 10
			SetColor 235, 200, 113
			DrawText row.points, 791, y + 10
			If current >= 71 Then
				Local team:TWCViewTeam = data.Team(row.teamId)
				If team.qualified Then SetColor 119, 216, 166; DrawText "Q", 841, y + 10
			End If

			If click And MouseX() >= 36 And MouseX() < 880 And MouseY() >= y And MouseY() < y + 39 Then
				If selectedId = row.teamId Then selectedId = 0 Else selectedId = row.teamId
			End If
		Next

		SetColor 213, 174, 90
		DrawText "GROUP MATCHES", 36, 438
		Local line:Int
		For Local candidate:TWCViewFrame = EachIn data.frames
			Local game:TWCViewMatch = candidate.match
			If game.group <> code Then
				Continue
			End If

			Local y:Int = 469 + line * 30
			If game.index = current Then SetColor 92, 87, 62 Else SetColor 35, 49, 64

			DrawRect 36, y, 844, 27
			SetColor 157, 178, 195
			DrawText game.date[..10], 49, y + 5
			SetColor 239, 243, 246
			DrawText data.Name(game.homeId), 189, y + 5
			If game.index <= current Then
				SetColor 231, 195, 110
				DrawText game.homeScore + " - " + game.awayScore, 475, y + 5
			Else
				SetColor 129, 149, 168
				DrawText "vs", 490, y + 5
			End If

			SetColor 239, 243, 246
			DrawText data.Name(game.awayId), 609, y + 5
			If click And MouseX() >= 36 And MouseX() < 880 And MouseY() >= y And MouseY() < y + 27 Then current = game.index; playing = False

			line :+ 1
		Next

		SetColor 40, 56, 70
		DrawRect 906, 139, 338, 509
		SetColor 217, 174, 83
		DrawText WCPhase(match.stage), 926, 159
		SetColor 156, 178, 198
		DrawText match.date, 926, 188
		SetColor 245, 247, 249
		DrawText data.Name(match.homeId), 926, 230
		DrawText data.Name(match.awayId), 926, 263
		SetColor 235, 200, 111
		DrawText WCScore(match), 926, 313
		If match.winnerId <> 0 Then
			SetColor 157, 178, 197
			DrawText "Winner", 926, 356
			SetColor 245, 247, 249
			DrawText data.Name(match.winnerId), 926, 380
		Else
			SetColor 157, 178, 197
			DrawText "Draw", 926, 367
		End If

		If selectedId <> 0 Then
			SetColor 218, 175, 89
			DrawText "FOLLOWING TEAM", 926, 451
			SetColor 243, 245, 248
			DrawText data.Name(selectedId), 926, 478
			Local selected:TWCViewTeam = data.Team(selectedId)
			Local selectedRow:TWCViewRow = frame.groups[selected.group[0] - 65].Find(selectedId)
			SetColor 158, 179, 197
			DrawText "Group " + selected.group + "   " + selectedRow.points + " points", 926, 507
			If current >= 71 Then
				If selected.qualified Then DrawText "Qualified for the last 32", 926, 533 Else DrawText "Eliminated in the groups", 926, 533
			End If

			DrawText "Click the row again or press C", 926, 596
		Else
			SetColor 157, 178, 197
			DrawText "Click a team to follow it", 926, 474
		End If
	Else
		Local headings:String[] = ["ROUND OF 32", "ROUND OF 16", "QUARTERS", "SEMIS", "FINAL"]
		For Local col:Int = 0 Until 5
			Local x:Int = 36 + col * 242
			SetColor 217, 174, 83
			DrawText headings[col], x, 144
		Next

		For Local candidate:TWCViewFrame = EachIn data.frames
			Local game:TWCViewMatch = candidate.match
			Local col:Int = -1
			Select game.stage
				Case "WORLD_CUP_W1"; col = 0
				Case "WORLD_CUP_W2"; col = 1
				Case "WORLD_CUP_W3"; col = 2
				Case "WORLD_CUP_W4"; col = 3
				Case "WORLD_CUP_W5"; col = 4
			End Select

			If col < 0 Then
				Continue
			End If

			Local y:Int = 177 + (game.position - 1) * (30 Shl col)
			If col > 0 Then
				y :+ ((30 Shl col) - 30) / 2
			End If

			WCDrawBracketCard(data, game, current, selectedId, 36 + col * 242, y, 226)
			If click And MouseX() >= 36 + col * 242 And MouseX() < 262 + col * 242 And MouseY() >= y And MouseY() < y + 25 And game.index <= current Then
				current = game.index; playing = False
				If selectedId = game.winnerId Then selectedId = 0 Else selectedId = game.winnerId
			End If
		Next

		SetColor 215, 174, 85
		DrawText "THIRD PLACE", 36, 658
		For Local candidate:TWCViewFrame = EachIn data.frames
			If candidate.match.stage = "WORLD_CUP_THIRD" Then
				WCDrawBracketCard(data, candidate.match, current, selectedId, 168, 654, 245)
				Exit
			End If
		Next

		If selectedId <> 0 Then
			SetColor 162, 184, 199
			DrawText "Following " + data.Name(selectedId) + "   (C to clear)", 546, 658
		End If
	End If

	SetColor 162, 184, 202
	DrawText "Select a match", 36, 681
	For Local i:Int = 0 Until 104
		Local game:TWCViewMatch = data.frames[i].match
		If i = current Then
			SetColor 238, 195, 98
		ElseIf game.stage = "GROUPS" Then
			SetColor 74, 119, 113
		Else
			SetColor 94, 117, 151
		End If

		DrawRect 36 + i * 11, 704, 9, 19
	Next

	SetColor 162, 184, 202
	DrawText "1", 36, 732
	DrawText "72  GROUPS", 776, 732
	DrawText "104  FINAL", 1125, 732
	Flip
Wend

EndGraphics
