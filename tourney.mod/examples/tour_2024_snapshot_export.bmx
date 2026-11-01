' Export immutable daily standings from the actual engine replay. The Max2D
' viewer reads this tab-separated file. Include this file after
' tour_2024_replay.bmx in a program that imports toolkit.tourney.
Type TTourSnapshotExport Implements ITour2024StageObserver
	Field stream:TStream

	Function Export:Int(inputPath:String, outputPath:String)
		Local exporter:TTourSnapshotExport = New TTourSnapshotExport
		exporter.stream = WriteStream(outputPath)
		If exporter.stream = Null Then
			Throw "Cannot create Tour snapshots: " + outputPath
		End If

		exporter.stream.WriteLine("# Engine standings from the official 2024 Tour replay; regenerate with tour_2024_export_app.bmx")
		exporter.stream.WriteLine("# W: stage, place, rider name; R: stage, category (G/P/M/Y/T/S = 0/1/2/3/4/5), rank, ID, name, team, value, stage place")
		Local finishers:Int = TTour2024Replay.Run(inputPath, exporter)
		exporter.stream.Close()
		Return finishers
	End Function

	Method Name:String(comp:TCompetition, id:Int)
		For Local participant:TParticipant = EachIn comp.participants
			If participant.id = id Then
				Return participant.name
			End If
		Next

		Throw "Unknown Tour participant: " + id
	End Method

	Method Team:String(comp:TCompetition, id:Int)
		For Local participant:TParticipant = EachIn comp.participants
			If participant.id = id Then
				Return Name(comp, participant.parentTeamId)
			End If
		Next

		Return ""
	End Method

	Method StagePlace:Int(fixture:TFixtureState, id:Int)
		For Local result:TCyclingRiderResult = EachIn fixture.cyclingResults
			If result.participantId = id Then
				Return result.place
			End If
		Next

		Return 0
	End Method

	Method OnStage(comp:TCompetition, state:TCompetitionState, stageNumber:Int)
		Local fixture:TFixtureState = state.stages[0].fixtures[stageNumber - 1]
		For Local place:Int = 1 To 3
			For Local result:TCyclingRiderResult = EachIn fixture.cyclingResults
				If result.place = place Then stream.WriteLine("W~t" + stageNumber + "~t" + place + "~t" + Name(comp, result.participantId)); Exit
			Next
		Next

		Local codes:String[] = ["G", "P", "M", "Y", "T"]
		For Local category:Int = 0 Until 5
			Local board:TLeaderboard = TTour2024Replay.Board(state.stages[0], codes[category])
			For Local i:Int = 0 Until board.rows.Length
				Local row:TLeaderboardRow = board.rows[i]
				Local value:Long = row.points
				If category = 0 Or category = 3 Or category = 4 Then
					value = row.timeSeconds
				End If

				Local teamName:String
				If category <> 4 Then
					teamName = Team(comp, row.participantId)
				End If

				stream.WriteLine("R~t" + stageNumber + "~t" + category + "~t" + (i + 1) + "~t" + row.participantId + "~t" + Name(comp, row.participantId) + "~t" + teamName + "~t" + value + "~t" + StagePlace(fixture, row.participantId))
			Next
		Next

		For Local place:Int = 1 To fixture.cyclingResults.Length
			For Local result:TCyclingRiderResult = EachIn fixture.cyclingResults
				If result.place = place Then
					stream.WriteLine("R~t" + stageNumber + "~t5~t" + place + "~t" + result.participantId + "~t" + Name(comp, result.participantId) + "~t" + Team(comp, result.participantId) + "~t" + result.elapsedSeconds + "~t" + place)
					Exit
				End If
			Next
		Next
	End Method
End Type
