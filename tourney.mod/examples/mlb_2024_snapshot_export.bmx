' Renderer-neutral standings after every recorded game. The viewer performs no
' result scoring; it reads these snapshots produced by the engine replay.
Type TMLBExportEntry
	Field id:Int
	Field wins:Int
	Field losses:Int
	Field runsFor:Int
	Field runsAgainst:Int
End Type

Type TMLB2024SnapshotExport Implements ICompetitionResultObserver
	Field output:TStream
	Field frameCount:Int
	Field wroteTeams:Int

	Method Line(value:String)
		output.WriteString(value + "~n")
	End Method

	Function Export:Int(inputPath:String, outputPath:String)
		Local exporter:TMLB2024SnapshotExport = New TMLB2024SnapshotExport
		exporter.output = WriteStream(outputPath)
		If exporter.output = Null Then
			Throw "Cannot create MLB snapshots: " + outputPath
		End If

		exporter.Line("# 2024 MLB engine snapshots; 2429 regular games and 43 postseason games")
		exporter.Line("# T|team id|name|division")
		exporter.Line("# E|game index|stage|round or series game|home id|away id|home runs|away runs")
		exporter.Line("# R|game index|division|rank by winning percentage|team id|wins|losses|runs for|runs against|percentage x1000")
		Local games:Int = TMLB2024Replay.Run(inputPath, exporter, 1215)
		exporter.output.Close()
		If games <> 2472 Or exporter.frameCount <> games Then
			Throw "Incomplete MLB snapshot export"
		End If

		Return games
	End Function

	Function Row:TLeaderboardRow(board:TLeaderboard, id:Int)
		For Local row:TLeaderboardRow = EachIn board.rows
			If row.participantId = id Then
				Return row
			End If
		Next

		Throw "Missing MLB standing for team " + id
	End Function

	Function Percentage:Int(entry:TMLBExportEntry)
		Local games:Int = entry.wins + entry.losses
		If games = 0 Then
			Return 0
		End If

		Return (entry.wins * 1000 + games / 2) / games
	End Function

	Function Better:Int(left:TMLBExportEntry, right:TMLBExportEntry)
		Local leftGames:Int = left.wins + left.losses
		Local rightGames:Int = right.wins + right.losses
		Local leftCross:Int = left.wins * Max(1, rightGames)
		Local rightCross:Int = right.wins * Max(1, leftGames)
		If leftCross <> rightCross Then
			Return leftCross > rightCross
		End If

		If left.wins <> right.wins Then
			Return left.wins > right.wins
		End If

		Return left.id < right.id
	End Function

	Method OnResultRecorded(comp:TCompetition, state:TCompetitionState, stageId:String, fixtureId:String, result:TResultPayload)
		If Not wroteTeams Then
			For Local team:TParticipant = EachIn comp.participants
				Line("T|" + team.id + "|" + team.name + "|" + team.divisionId)
			Next

			wroteTeams = True
		End If

		frameCount :+ 1
		Local played:TFixtureState
		For Local fixture:TFixtureState = EachIn TMLB2024Replay.Stage(state, stageId).fixtures
			If fixture.id = fixtureId Then played = fixture; Exit
		Next

		If played = Null Then
			Throw "Missing recorded MLB fixture: " + fixtureId
		End If

		Line("E|" + frameCount + "|" + stageId + "|" + played.round + "|" + played.homeTeamId + "|" + played.awayTeamId + "|" + played.scoreHome + "|" + played.scoreAway)
		Local board:TLeaderboard = state.stages[0].leaderboard
		If board = Null Or board.rows.Length <> 30 Then
			Throw "Incomplete MLB regular-season table"
		End If

		For Local division:String = EachIn ["ALE", "ALC", "ALW", "NLE", "NLC", "NLW"]
			Local entries:TMLBExportEntry[]
			For Local team:TParticipant = EachIn comp.participants
				If team.divisionId <> division Then
					Continue
				End If

				Local standing:TLeaderboardRow = Row(board, team.id)
				Local entry:TMLBExportEntry = New TMLBExportEntry
				entry.id = team.id
				entry.wins = standing.wins
				entry.losses = standing.losses
				entry.runsFor = standing.gf
				entry.runsAgainst = standing.ga
				entries :+ [entry]
			Next

			If entries.Length <> 5 Then
				Throw "Incomplete MLB division " + division
			End If

			For Local i:Int = 0 Until entries.Length - 1
				For Local j:Int = i + 1 Until entries.Length
					If Better(entries[j], entries[i]) Then
						Local swap:TMLBExportEntry = entries[i]
						entries[i] = entries[j]
						entries[j] = swap
					End If
				Next
			Next

			For Local rank:Int = 0 Until entries.Length
				Local entry:TMLBExportEntry = entries[rank]
				Line("R|" + frameCount + "|" + division + "|" + (rank + 1) + "|" + entry.id + "|" + entry.wins + "|" + entry.losses + "|" + entry.runsFor + "|" + entry.runsAgainst + "|" + Percentage(entry))
			Next
		Next
	End Method
End Type
