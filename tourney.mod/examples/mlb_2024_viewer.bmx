SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import BRL.StandardIO

' A display-only reader of snapshots exported by Toolkit.Tourney.
Type TMLBViewTeam
	Field id:Int
	Field name:String
	Field division:String
End Type

Type TMLBViewRow
	Field rank:Int
	Field id:Int
	Field wins:Int
	Field losses:Int
	Field runsFor:Int
	Field runsAgainst:Int
	Field pct:Int
End Type

Type TMLBViewDivision
	Field rows:TMLBViewRow[]

	Method Find:TMLBViewRow(id:Int)
		For Local row:TMLBViewRow = EachIn rows
			If row.id = id Then
				Return row
			End If
		Next

		Return Null
	End Method
End Type

Type TMLBViewFrame
	Field stage:String
	Field round:Int
	Field homeId:Int
	Field awayId:Int
	Field homeRuns:Int
	Field awayRuns:Int
	Field divisions:TMLBViewDivision[]

	Method Row:TMLBViewRow(id:Int)
		For Local division:TMLBViewDivision = EachIn divisions
			Local row:TMLBViewRow = division.Find(id)
			If row <> Null Then
				Return row
			End If
		Next

		Return Null
	End Method
End Type

Type TMLBViewSeries
	Field stage:String
	Field first:Int
	Field last:Int
	Field teamA:Int
	Field teamB:Int

	Method HasTeams:Int(a:Int, b:Int)
		Return (teamA = a And teamB = b) Or (teamA = b And teamB = a)
	End Method

	Method HasTeam:Int(id:Int)
		Return teamA = id Or teamB = id
	End Method

	Method Wins:Int(data:TMLBViewData, current:Int, id:Int)
		Local wins:Int
		For Local i:Int = first To Min(current, last)
			Local game:TMLBViewFrame = data.frames[i]
			If game.stage <> stage Or Not HasTeams(game.homeId, game.awayId) Then
				Continue
			End If

			If game.homeRuns > game.awayRuns And game.homeId = id Then
				wins :+ 1
			End If

			If game.awayRuns > game.homeRuns And game.awayId = id Then
				wins :+ 1
			End If
		Next

		Return wins
	End Method

	Method Winner:Int(data:TMLBViewData, current:Int)
		If current < last Then
			Return 0
		End If

		If Wins(data, current, teamA) > Wins(data, current, teamB) Then
			Return teamA
		End If

		Return teamB
	End Method
End Type

Type TMLBViewData
	Field teams:TMLBViewTeam[]
	Field frames:TMLBViewFrame[]
	Field postseasonSeries:TMLBViewSeries[]

	Function DivisionIndex:Int(code:String)
		Local codes:String[] = ["ALE", "ALC", "ALW", "NLE", "NLC", "NLW"]
		For Local i:Int = 0 Until codes.Length
			If codes[i] = code Then
				Return i
			End If
		Next

		Return -1
	End Function

	Method Team:TMLBViewTeam(id:Int)
		For Local team:TMLBViewTeam = EachIn teams
			If team.id = id Then
				Return team
			End If
		Next

		Return Null
	End Method

	Method Name:String(id:Int)
		Local team:TMLBViewTeam = Team(id)
		If team <> Null Then
			Return team.name
		End If

		Return "Unknown team"
	End Method

	Method ShortName:String(id:Int)
		Local words:String[] = Name(id).Split(" ")
		Return words[words.Length - 1]
	End Method

	Method Series:TMLBViewSeries(stage:String, ordinal:Int)
		For Local item:TMLBViewSeries = EachIn postseasonSeries
			If item.stage <> stage Then
				Continue
			End If

			If ordinal = 0 Then
				Return item
			End If

			ordinal :- 1
		Next

		Throw "Missing MLB postseason series: " + stage
	End Method

	Method Load(path:String)
		Local input:TStream = ReadStream(path)
		If input = Null Then
			Throw "Cannot read MLB snapshots: " + path + " (run the exporter first)"
		End If

		frames = New TMLBViewFrame[2472]
		For Local i:Int = 0 Until frames.Length
			frames[i] = New TMLBViewFrame
			frames[i].divisions = New TMLBViewDivision[6]
			For Local d:Int = 0 Until 6
				frames[i].divisions[d] = New TMLBViewDivision
			Next
		Next

		While Not input.Eof()
			Local line:String = input.ReadLine()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			Select fields[0]
				Case "T"
					If fields.Length <> 4 Or DivisionIndex(fields[3]) < 0 Then
						Throw "Invalid MLB team row"
					End If

					Local team:TMLBViewTeam = New TMLBViewTeam
					team.id = Int(fields[1]); team.name = fields[2]; team.division = fields[3]
					If team.id <= 0 Or team.name = "" Or Team(team.id) <> Null Then
						Throw "Duplicate or incomplete MLB team"
					End If

					teams :+ [team]
				Case "E"
					If fields.Length <> 8 Then
						Throw "Invalid MLB game row"
					End If

					Local index:Int = Int(fields[1]) - 1
					If index < 0 Or index >= frames.Length Or frames[index].stage <> "" Then
						Throw "Invalid MLB game index"
					End If

					Local frame:TMLBViewFrame = frames[index]
					frame.stage = fields[2]
					frame.round = Int(fields[3])
					frame.homeId = Int(fields[4]); frame.awayId = Int(fields[5])
					frame.homeRuns = Int(fields[6]); frame.awayRuns = Int(fields[7])
				Case "R"
					If fields.Length <> 10 Then
						Throw "Invalid MLB standing row"
					End If

					Local index:Int = Int(fields[1]) - 1
					Local division:Int = DivisionIndex(fields[2])
					If index < 0 Or index >= frames.Length Or division < 0 Then
						Throw "Invalid MLB standing index"
					End If

					Local row:TMLBViewRow = New TMLBViewRow
					row.rank = Int(fields[3]); row.id = Int(fields[4])
					row.wins = Int(fields[5]); row.losses = Int(fields[6])
					row.runsFor = Int(fields[7]); row.runsAgainst = Int(fields[8]); row.pct = Int(fields[9])
					Local board:TMLBViewDivision = frames[index].divisions[division]
					If row.rank <> board.rows.Length + 1 Or row.id <= 0 Or row.wins < 0 Or row.losses < 0 Or row.pct < 0 Or row.pct > 1000 Then
						Throw "Invalid MLB standing"
					End If

					board.rows :+ [row]
				Default
					Throw "Unknown MLB snapshot row"
			End Select
		Wend

		input.Close()
		If teams.Length <> 30 Then
			Throw "Expected 30 MLB teams"
		End If

		For Local i:Int = 0 Until frames.Length
			Local frame:TMLBViewFrame = frames[i]
			If frame.stage = "" Or Team(frame.homeId) = Null Or Team(frame.awayId) = Null Then
				Throw "Incomplete MLB game"
			End If

			If i < 2429 And frame.stage <> "REG" Then
				Throw "Unexpected MLB regular-season stage"
			End If

			If i >= 2429 And frame.stage = "REG" Then
				Throw "Unexpected MLB postseason stage"
			End If

			For Local d:Int = 0 Until 6
				If frame.divisions[d].rows.Length <> 5 Then
					Throw "Incomplete MLB division standings"
				End If

				For Local row:TMLBViewRow = EachIn frame.divisions[d].rows
					Local team:TMLBViewTeam = Team(row.id)
					If team = Null Or DivisionIndex(team.division) <> d Then
						Throw "MLB standing in wrong division"
					End If
				Next
			Next
		Next

		For Local i:Int = 2429 Until frames.Length
			Local frame:TMLBViewFrame = frames[i]
			Local found:TMLBViewSeries
			For Local item:TMLBViewSeries = EachIn postseasonSeries
				If item.stage = frame.stage And item.HasTeams(frame.homeId, frame.awayId) Then found = item; Exit
			Next

			If found = Null Then
				found = New TMLBViewSeries
				found.stage = frame.stage
				found.first = i
				found.teamA = frame.homeId
				found.teamB = frame.awayId
				postseasonSeries :+ [found]
			End If

			found.last = i
		Next

		If postseasonSeries.Length <> 11 Then
			Throw "Incomplete MLB postseason bracket"
		End If

		Series("AL_W1", 1); Series("NL_W1", 1)
		Series("AL_W2", 1); Series("NL_W2", 1)
		Series("AL_W3", 0); Series("NL_W3", 0)
		For Local league:String = EachIn ["AL", "NL"]
			For Local slot:Int = 0 To 1
				If Not Series(league + "_W2", slot).HasTeam(Series(league + "_W1", slot).Winner(Self, 2471)) Then
					Throw "Wrong MLB Wild Card route"
				End If
			Next

			If Not Series(league + "_W3", 0).HasTeams(Series(league + "_W2", 0).Winner(Self, 2471), Series(league + "_W2", 1).Winner(Self, 2471)) Then
				Throw "Wrong MLB Championship Series route"
			End If
		Next

		If Not Series("WORLD_SERIES", 0).HasTeams(Series("AL_W3", 0).Winner(Self, 2471), Series("NL_W3", 0).Winner(Self, 2471)) Then
			Throw "Wrong MLB World Series route"
		End If

		If Series("WORLD_SERIES", 0).Winner(Self, 2471) <> 119 Then
			Throw "Wrong MLB champion"
		End If

		Local dodgers:TMLBViewRow = frames[2471].Row(119)
		If frames[2471].stage <> "WORLD_SERIES" Or frames[2471].awayId <> 119 Or frames[2471].awayRuns <= frames[2471].homeRuns Or dodgers.wins <> 98 Or dodgers.losses <> 64 Then
			Throw "Wrong MLB finish"
		End If
	End Method
End Type

Function MLBClamp:Int(value:Int, low:Int, high:Int)
	Return Max(low, Min(high, value))
End Function

Function MLBPct:String(value:Int)
	If value = 1000 Then
		Return "1.000"
	End If

	Local padded:String = "000" + value
	Return "." + padded[padded.Length - 3..]
End Function

Function MLBTimelineX:Float(index:Int)
	If index < 2429 Then
		Return 42.0 + 884.0 * Float(index) / 2428.0
	End If

	Return 946.0 + 288.0 * Float(index - 2429) / 42.0
End Function

Function MLBTimelineIndex:Int(x:Int)
	If x < 936 Then
		Return MLBClamp(Int(Float(x - 42) * 2428.0 / 884.0), 0, 2428)
	End If

	Return MLBClamp(2429 + Int(Float(x - 946) * 42.0 / 288.0), 2429, 2471)
End Function

Function MLBStageName:String(stage:String)
	Select stage
		Case "REG" Return "REGULAR SEASON"
		Case "AL_W1", "NL_W1" Return "WILD CARD SERIES"
		Case "AL_W2", "NL_W2" Return "DIVISION SERIES"
		Case "AL_W3", "NL_W3" Return "LEAGUE CHAMPIONSHIP"
		Case "WORLD_SERIES" Return "WORLD SERIES"
	End Select

	Return stage
End Function

Function MLBSeriesWins:Int(data:TMLBViewData, current:Int, id:Int)
	Local frame:TMLBViewFrame = data.frames[current]
	Local wins:Int
	For Local i:Int = 2429 To current
		Local game:TMLBViewFrame = data.frames[i]
		If game.stage <> frame.stage Then
			Continue
		End If

		If Not ((game.homeId = frame.homeId And game.awayId = frame.awayId) Or (game.homeId = frame.awayId And game.awayId = frame.homeId)) Then
			Continue
		End If

		If game.homeRuns > game.awayRuns And game.homeId = id Then
			wins :+ 1
		End If

		If game.awayRuns > game.homeRuns And game.awayId = id Then
			wins :+ 1
		End If
	Next

	Return wins
End Function

Function MLBDrawSeriesCard(data:TMLBViewData, current:Int, item:TMLBViewSeries, x:Int, y:Int, width:Int)
	Local visible:Int = current >= item.first
	Local winner:Int = item.Winner(data, current)
	SetColor 35, 52, 76
	DrawRect x, y, width, 80
	If winner <> 0 Then
		SetColor 242, 163, 91
		DrawRect x, y, 4, 80
	End If

	SetColor 130, 157, 187
	Local format:String = "BEST OF 7"
	If item.stage.EndsWith("W1") Then
		format = "BEST OF 3"
	End If

	If item.stage.EndsWith("W2") Then
		format = "BEST OF 5"
	End If

	DrawText format, x + 12, y + 7
	If Not visible Then
		SetColor 156, 177, 201
		DrawText "Awaiting matchup", x + 12, y + 36
		Return
	End If

	Local aWins:Int = item.Wins(data, current, item.teamA)
	Local bWins:Int = item.Wins(data, current, item.teamB)
	If winner = item.teamA Then SetColor 251, 187, 113 Else SetColor 236, 242, 248

	DrawText data.ShortName(item.teamA), x + 12, y + 29
	DrawText aWins, x + width - 26, y + 29
	If winner = item.teamB Then SetColor 251, 187, 113 Else SetColor 236, 242, 248

	DrawText data.ShortName(item.teamB), x + 12, y + 53
	DrawText bWins, x + width - 26, y + 53
End Function

Function MLBDrawBracket(data:TMLBViewData, current:Int)
	SetColor 144, 165, 190
	DrawText "WILD CARD", 40, 111
	DrawText "DIVISION SERIES", 320, 111
	DrawText "LEAGUE CHAMPIONSHIP", 600, 111
	DrawText "WORLD SERIES", 930, 295
	SetColor 235, 151, 91
	DrawText "AMERICAN LEAGUE", 40, 135
	DrawText "NATIONAL LEAGUE", 40, 405

	SetColor 65, 91, 119
	DrawLine 250, 196, 320, 196
	DrawLine 250, 296, 320, 296
	DrawLine 530, 196, 565, 196
	DrawLine 530, 296, 565, 296
	DrawLine 565, 196, 565, 246
	DrawLine 565, 296, 565, 246
	DrawLine 565, 246, 600, 246
	DrawLine 250, 466, 320, 466
	DrawLine 250, 566, 320, 566
	DrawLine 530, 466, 565, 466
	DrawLine 530, 566, 565, 566
	DrawLine 565, 466, 565, 516
	DrawLine 565, 566, 565, 516
	DrawLine 565, 516, 600, 516
	DrawLine 810, 246, 860, 246
	DrawLine 810, 516, 860, 516
	DrawLine 860, 246, 860, 381
	DrawLine 860, 516, 860, 381
	DrawLine 860, 381, 930, 381

	MLBDrawSeriesCard(data, current, data.Series("AL_W1", 0), 40, 156, 210)
	MLBDrawSeriesCard(data, current, data.Series("AL_W1", 1), 40, 256, 210)
	MLBDrawSeriesCard(data, current, data.Series("AL_W2", 0), 320, 156, 210)
	MLBDrawSeriesCard(data, current, data.Series("AL_W2", 1), 320, 256, 210)
	MLBDrawSeriesCard(data, current, data.Series("AL_W3", 0), 600, 206, 210)
	MLBDrawSeriesCard(data, current, data.Series("NL_W1", 0), 40, 426, 210)
	MLBDrawSeriesCard(data, current, data.Series("NL_W1", 1), 40, 526, 210)
	MLBDrawSeriesCard(data, current, data.Series("NL_W2", 0), 320, 426, 210)
	MLBDrawSeriesCard(data, current, data.Series("NL_W2", 1), 320, 526, 210)
	MLBDrawSeriesCard(data, current, data.Series("NL_W3", 0), 600, 476, 210)
	MLBDrawSeriesCard(data, current, data.Series("WORLD_SERIES", 0), 930, 341, 300)
	If current < 2429 Then
		SetColor 165, 185, 209
		DrawText "Press P to jump to the postseason", 930, 443
	Else
		Local game:TMLBViewFrame = data.frames[current]
		SetColor 165, 185, 209
		DrawText "Game " + (current - 2428) + " of 43", 930, 443
		SetColor 241, 245, 250
		DrawText data.Name(game.awayId) + " " + game.awayRuns, 930, 470
		DrawText data.Name(game.homeId) + " " + game.homeRuns, 930, 494
		Local champion:Int = data.Series("WORLD_SERIES", 0).Winner(data, current)
		If champion <> 0 Then
			SetColor 242, 163, 91
			DrawText "CHAMPION: " + data.Name(champion), 930, 544
		End If
	End If
End Function

Function MLBRowY:Float(rank:Int)
	Return 203.0 + Float(rank - 1) * 58.0
End Function

Local data:TMLBViewData = New TMLBViewData
data.Load(AppDir + "/mlb_2024_snapshots.tsv")
For Local arg:String = EachIn AppArgs[1..]
	If arg = "--check" Then
		Print "MLB viewer ready: 30 teams, 2429 regular games, 43 postseason games"
		End
	End If
Next

AppTitle = "2024 MLB season replay"
Graphics 1280, 760
SetClsColor 14, 25, 43
Local current:Int, previous:Int, division:Int = 0
Local selected:Int, playing:Int, postseasonView:Int, changedAt:Int = MilliSecs() - 500
Local nextPlay:Int = MilliSecs() + 500
While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local wanted:Int = current
	Local click:Int = MouseHit(1)
	If KeyHit(KEY_RIGHT) Then wanted = Min(2471, current + 1); playing = False

	If KeyHit(KEY_LEFT) Then wanted = Max(0, current - 1); playing = False

	If KeyHit(KEY_UP) Then wanted = Min(2471, current + 25); playing = False

	If KeyHit(KEY_DOWN) Then wanted = Max(0, current - 25); playing = False

	If KeyHit(KEY_HOME) Then wanted = 0; playing = False

	If KeyHit(KEY_END) Then wanted = 2471; playing = False

	If KeyHit(KEY_P) Then wanted = 2429; playing = False; postseasonView = True

	If KeyHit(KEY_B) Then
		postseasonView = Not postseasonView
	End If

	If KeyHit(KEY_SPACE) Then playing = Not playing; nextPlay = MilliSecs() + 500

	If KeyHit(KEY_C) Then
		selected = 0
	End If

	If KeyHit(KEY_F) And selected <> 0 Then
		division = TMLBViewData.DivisionIndex(data.Team(selected).division)
	End If

	If KeyHit(KEY_1) Then
		division = 0
	End If

	If KeyHit(KEY_2) Then
		division = 1
	End If

	If KeyHit(KEY_3) Then
		division = 2
	End If

	If KeyHit(KEY_4) Then
		division = 3
	End If

	If KeyHit(KEY_5) Then
		division = 4
	End If

	If KeyHit(KEY_6) Then
		division = 5
	End If

	Local wheel:Int = MouseZSpeed()
	If wheel <> 0 Then
		Local stepSize:Int = 10
		If current >= 2429 Then
			stepSize = 1
		End If

		wanted = MLBClamp(current + wheel * stepSize, 0, 2471)
		playing = False
	End If

	If playing And MilliSecs() >= nextPlay Then
		Local stepSize:Int = 10
		If current >= 2429 Then
			stepSize = 1
		End If

		wanted = Min(2471, current + stepSize)
		nextPlay = MilliSecs() + 450
		If current = 2471 Then
			playing = False
		End If
	End If

	If click And MouseY() >= 687 And MouseY() <= 723 Then wanted = MLBTimelineIndex(MouseX()); playing = False

	If click And MouseY() >= 26 And MouseY() <= 56 Then
		If MouseX() >= 918 And MouseX() < 1035 Then
			postseasonView = False
		End If

		If MouseX() >= 1045 And MouseX() < 1227 Then
			postseasonView = True
		End If
	End If

	If click And MouseY() >= 111 And MouseY() <= 146 Then
		For Local d:Int = 0 Until 6
			Local x:Int = 38 + d * 137
			If MouseX() >= x And MouseX() < x + 126 Then
				division = d
			End If
		Next
	End If

	If wanted <> current Then previous = current; current = wanted; changedAt = MilliSecs()

	Local frame:TMLBViewFrame = data.frames[current]
	Local oldFrame:TMLBViewFrame = data.frames[previous]
	Local board:TMLBViewDivision = frame.divisions[division]
	Local oldBoard:TMLBViewDivision = oldFrame.divisions[division]
	Local t:Float = Min(1.0, Float(MilliSecs() - changedAt) / 340.0)
	If t >= 1.0 Then
		previous = current
	End If

	If Not postseasonView And click And MouseX() >= 40 And MouseX() < 844 And MouseY() >= 203 And MouseY() < 493 Then
		For Local row:TMLBViewRow = EachIn board.rows
			Local old:TMLBViewRow = oldBoard.Find(row.id)
			Local y:Float = MLBRowY(row.rank)
			If old <> Null Then
				y = MLBRowY(old.rank) * (1.0 - t) + y * t
			End If

			If MouseY() >= y And MouseY() < y + 52 Then
				If selected = row.id Then selected = 0 Else selected = row.id

				Exit
			End If
		Next
	End If

	Cls
	SetColor 232, 91, 61
	DrawRect 0, 0, 1280, 6
	SetColor 241, 245, 250
	DrawText "MAJOR LEAGUE BASEBALL  /  2024", 39, 27
	SetColor 156, 177, 203
	DrawText "Game " + (current + 1) + " of 2472  |  " + MLBStageName(frame.stage), 40, 63
	If postseasonView Then SetColor 52, 72, 98 Else SetColor 230, 103, 71

	DrawRect 918, 26, 117, 31
	If postseasonView Then SetColor 230, 103, 71 Else SetColor 52, 72, 98

	DrawRect 1045, 26, 182, 31
	SetColor 245, 247, 251
	DrawText "STANDINGS", 929, 34
	DrawText "POSTSEASON BRACKET", 1054, 34

	If Not postseasonView Then

		Local codes:String[] = ["AL EAST", "AL CENTRAL", "AL WEST", "NL EAST", "NL CENTRAL", "NL WEST"]
		For Local d:Int = 0 Until 6
			Local x:Int = 38 + d * 137
			If d = division Then SetColor 230, 103, 71 Else SetColor 52, 72, 98

			DrawRect x, 111, 126, 36
			SetColor 245, 247, 251
			DrawText (d + 1) + " " + codes[d], x + 8, 121
		Next

		SetColor 164, 184, 206
		DrawText "RANK", 53, 170
		DrawText "CLUB", 108, 170
		DrawText "W-L", 475, 170
		DrawText "PCT", 604, 170
		DrawText "RUN DIFF", 715, 170
		For Local row:TMLBViewRow = EachIn board.rows
			Local old:TMLBViewRow = oldBoard.Find(row.id)
			Local y:Float = MLBRowY(row.rank)
			If old <> Null Then
				y = MLBRowY(old.rank) * (1.0 - t) + y * t
			End If

			If row.id = selected Then SetColor 72, 83, 110 ElseIf row.rank Mod 2 = 0 Then SetColor 27, 43, 65 Else SetColor 32, 49, 72

			DrawRect 40, y, 804, 52
			If row.id = selected Then SetColor 242, 164, 91; DrawRect 40, y, 5, 52

			SetColor 237, 156, 103
			DrawText row.rank, 58, y + 17
			SetColor 243, 246, 250
			DrawText data.Name(row.id), 108, y + 17
			SetColor 177, 194, 214
			DrawText row.wins + "-" + row.losses, 475, y + 17
			DrawText MLBPct(row.pct), 604, y + 17
			Local diff:Int = row.runsFor - row.runsAgainst
			If diff > 0 Then SetColor 112, 219, 163 ElseIf diff < 0 Then SetColor 247, 138, 121

			If diff > 0 Then DrawText "+" + diff, 715, y + 17 Else DrawText diff, 715, y + 17
		Next

		SetColor 35, 52, 76
		DrawRect 873, 112, 369, 235
		SetColor 242, 163, 91
		DrawText MLBStageName(frame.stage), 894, 131
		SetColor 173, 191, 213
		If frame.stage = "REG" Then DrawText "Regular game " + (current + 1) + " / 2429", 894, 157 Else DrawText "Postseason game " + (current - 2428) + " / 43", 894, 157

		SetColor 242, 246, 250
		DrawText data.Name(frame.awayId), 894, 194
		DrawText data.Name(frame.homeId), 894, 239
		SetColor 246, 182, 112
		DrawText frame.awayRuns, 1195, 194
		DrawText frame.homeRuns, 1195, 239
		SetColor 138, 161, 190
		DrawText "AWAY", 894, 218
		DrawText "HOME", 894, 263
		If frame.stage <> "REG" Then
			SetColor 114, 218, 162
			DrawText "Series  " + MLBSeriesWins(data, current, frame.awayId) + " - " + MLBSeriesWins(data, current, frame.homeId), 894, 302
		End If

		SetColor 35, 52, 76
		DrawRect 873, 364, 369, 260
		If selected <> 0 Then
			Local team:TMLBViewTeam = data.Team(selected)
			Local standing:TMLBViewRow = frame.Row(selected)
			SetColor 242, 163, 91
			DrawText "FOLLOWING  " + team.division, 894, 383
			SetColor 242, 246, 250
			DrawText team.name, 894, 411
			SetColor 170, 191, 213
			DrawText "Rank " + standing.rank + "   " + standing.wins + "-" + standing.losses + "   " + MLBPct(standing.pct), 894, 438
			Local last:TMLBViewFrame
			For Local i:Int = current To 0 Step -1
				If data.frames[i].homeId = selected Or data.frames[i].awayId = selected Then last = data.frames[i]; Exit
			Next

			If last <> Null Then
				Local opponent:Int = last.homeId
				Local forRuns:Int = last.awayRuns
				Local against:Int = last.homeRuns
				If last.homeId = selected Then opponent = last.awayId; forRuns = last.homeRuns; against = last.awayRuns

				DrawText "Last: " + forRuns + "-" + against + " vs " + data.Name(opponent), 894, 466
			End If

			SetColor 81, 102, 127
			DrawRect 894, 520, 322, 1
			Local start:Int = Max(0, current - 220)
			For Local i:Int = start To current Step 4
				Local prior:TMLBViewRow = data.frames[i].Row(selected)
				Local x:Float = 894.0 + 322.0 * Float(i - start) / Max(1, current - start)
				Local y:Float = 595.0 - 65.0 * Float(prior.pct) / 1000.0
				SetColor 235, 151, 91
				DrawRect x, y, 3, 3
			Next

			SetColor 144, 164, 190
			DrawText "Winning percentage, recent 220 games", 894, 601
		Else
			SetColor 242, 163, 91
			DrawText "FOLLOW A CLUB", 894, 387
			SetColor 176, 194, 214
			DrawText "Click a team in the table.", 894, 419
			DrawText "Click it again to clear selection.", 894, 446
			DrawText "F returns to its division.", 894, 473
		End If
	Else
		MLBDrawBracket(data, current)
	End If

	SetColor 144, 165, 190
	DrawText "SEASON TIMELINE", 42, 648
	DrawText "Mar - Sep", 42, 666
	DrawText "October", 952, 666
	SetColor 55, 76, 104
	DrawRect 42, 699, 884, 8
	DrawRect 946, 699, 288, 8
	SetColor 234, 111, 76
	DrawRect 42, 699, Min(884, Max(2, MLBTimelineX(current) - 42)), 8
	DrawRect MLBTimelineX(current) - 4, 691, 8, 24
	SetColor 122, 199, 237
	DrawRect 946, 699, Max(0, MLBTimelineX(current) - 946), 8
	SetColor 164, 184, 207
	DrawText "Left/Right: game   Up/Down: 25   Wheel: scrub   Space: play   P: playoffs   B: view   Home/End: jump   1-6: division   Esc: exit", 42, 731
	Flip
Wend

End
