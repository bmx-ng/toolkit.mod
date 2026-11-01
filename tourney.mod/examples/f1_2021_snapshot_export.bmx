' Export a chronological, display-ready view of the engine's immutable snapshots.
Type TF12021SnapshotExport
	Function Place:Int(order:Int[], id:Int)
		For Local i:Int = 0 Until order.Length
			If order[i] = id Then
				Return i + 1
			End If
		Next

		Return 0
	End Function

	Function PreviousPoints:Int(timeline:TCompetitionTimeline, index:Int, code:String, id:Int)
		If index = 0 Then
			Return 0
		End If

		Local board:TLeaderboard = timeline.frames[index - 1].Board(code)
		For Local row:TLeaderboardRow = EachIn board.rows
			If row.participantId = id Then
				Return row.points
			End If
		Next

		Return 0
	End Function

	Function Export:Int(inputPath:String, outputPath:String)
		Local timeline:TCompetitionTimeline = New TCompetitionTimeline
		TF12021Replay.Run(inputPath, timeline)
		If timeline.frames.Length <> 25 Then
			Throw "Expected 25 F1 sessions"
		End If

		Local names:TStringMap = New TStringMap
		Local input:TStream = ReadStream(inputPath)
		If input = Null Then
			Throw "Cannot read " + inputPath
		End If

		While Not input.Eof()
			Local line:String = input.ReadLine()
			If line.StartsWith("R|") Then
				Local fields:String[] = line.Split("|")
				names.Insert(fields[1], fields[2])
			End If
		Wend

		input.Close()
		Local output:TStream = WriteStream(outputPath)
		If output = Null Then
			Throw "Cannot write " + outputPath
		End If

		output.WriteLine("# 2021 F1 engine snapshots; points are stored as half-point units")
		output.WriteLine("# E|session|round|event|session code|fastest lap driver|fastest lap name")
		output.WriteLine("# R|session|championship|rank|id|name|team|points units|session place|points gained units")
		For Local index:Int = 0 Until timeline.frames.Length
			Local frame:TStandingsFrame = timeline.frames[index]
			Local round:Int = Int(frame.eventId[1..])
			Local eventName:String = String(names.ValueForKey(String(round)))
			If eventName = "" Then
				Throw "Missing F1 event name"
			End If

			Local fastestId:Int
			Local fastestName:String = ""
			For Local award:TResultAward = EachIn frame.awards
				If award.code = "FASTEST_LAP" Then
					fastestId = award.participantId
				End If
			Next

			If fastestId <> 0 Then
				fastestName = timeline.Participant(fastestId).name
			End If

			output.WriteLine("E|" + (index + 1) + "|" + round + "|" + eventName + "|" + frame.sessionCode + "|" + fastestId + "|" + fastestName)
			For Local championship:Int = 0 To 1
				Local code:String = "DRIVERS"
				If championship = 1 Then
					code = "CONSTRUCTORS"
				End If

				Local board:TLeaderboard = frame.Board(code)
				If board = Null Then
					Throw "Missing F1 championship " + code
				End If

				For Local rank:Int = 0 Until board.rows.Length
					Local row:TLeaderboardRow = board.rows[rank]
					Local participant:TTimelineParticipant = timeline.Participant(row.participantId)
					If participant = Null Then
						Throw "Missing F1 participant"
					End If

					Local team:String = ""
					Local sessionPlace:Int
					If championship = 0 Then
						Local parent:TTimelineParticipant = timeline.Participant(participant.parentTeamId)
						If parent <> Null Then
							team = parent.name
						End If

						sessionPlace = Place(frame.classificationOrder, row.participantId)
					End If

					Local gained:Int = row.points - PreviousPoints(timeline, index, code, row.participantId)
					output.WriteLine("R|" + (index + 1) + "|" + championship + "|" + (rank + 1) + "|" + row.participantId + "|" + participant.name + "|" + team + "|" + row.points + "|" + sessionPlace + "|" + gained)
				Next
			Next
		Next

		output.Close()
		Return timeline.frames.Length
	End Function
End Type
