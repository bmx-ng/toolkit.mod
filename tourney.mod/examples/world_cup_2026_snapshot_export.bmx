' Presentable, renderer-neutral snapshots from the played engine timeline.
Type TWorldCup2026SnapshotExport
	Function FindGroup:TGroupTable(groups:TGroupTable[], code:String)
		For Local group:TGroupTable = EachIn groups
			If group.key = code Then
				Return group
			End If
		Next

		Return Null
	End Function

	Function HasRow:Int(group:TGroupTable, id:Int)
		If group = Null Then
			Return False
		End If

		For Local row:TLeaderboardRow = EachIn group.rows
			If row.participantId = id Then
				Return True
			End If
		Next

		Return False
	End Function

	Function Winner:Int(frame:TStandingsFrame)
		If frame.scoreHome > frame.scoreAway Then
			Return frame.homeTeamId
		End If

		If frame.scoreAway > frame.scoreHome Then
			Return frame.awayTeamId
		End If

		If frame.penaltiesHome > frame.penaltiesAway Then
			Return frame.homeTeamId
		End If

		If frame.penaltiesAway > frame.penaltiesHome Then
			Return frame.awayTeamId
		End If

		Return 0
	End Function

	Function Export:Int(inputPath:String, outputPath:String)
		Local timeline:TCompetitionTimeline = New TCompetitionTimeline
		TWorldCup2026Replay.Run(inputPath, timeline)
		Local dates:String[]
		Local qualifiers:Int[]
		Local input:TStream = ReadStream(inputPath)
		If input = Null Then
			Throw "Cannot read World Cup source"
		End If

		While Not input.Eof()
			Local line:String = input.ReadLine()
			If line.StartsWith("M|") Then
				Local fields:String[] = line.Split("|")
				dates :+ [fields[3]]
			ElseIf line.StartsWith("Q|") Then
				Local fields:String[] = line.Split("|")
				qualifiers :+ [Int(fields[2])]
			End If
		Wend

		input.Close()
		If dates.Length <> timeline.frames.Length Or qualifiers.Length <> 32 Then
			Throw "Incomplete World Cup snapshot source"
		End If

		Local output:TStream = WriteStream(outputPath)
		If output = Null Then
			Throw "Cannot write World Cup snapshots"
		End If

		output.WriteLine("# 2026 World Cup engine snapshots; no viewer-specific scoring calculations")
		output.WriteLine("# T|id|name|group; Q|qualified id")
		output.WriteLine("# E|index|date UTC|stage|round|bracket position|group|home id|away id|home score|away score|home penalties|away penalties|extra time|winner id")
		output.WriteLine("# R|index|group|rank|team id|played|wins|draws|losses|goals for|goals against|points")
		For Local team:TTimelineParticipant = EachIn timeline.participants
			output.WriteLine("T|" + team.id + "|" + team.name + "|" + team.divisionId)
		Next

		For Local id:Int = EachIn qualifiers
			output.WriteLine("Q|" + id)
		Next

		Local latestGroups:TGroupTable[]
		For Local i:Int = 0 Until timeline.frames.Length
			Local frame:TStandingsFrame = timeline.frames[i]
			If frame.groups <> Null And frame.groups.Length > 0 Then
				latestGroups = frame.groups
			End If

			output.WriteLine("E|" + (i + 1) + "|" + dates[i] + "|" + frame.stageId + "|" + frame.round + "|" + frame.bracketPosition + "|" + frame.groupKey + "|" + frame.homeTeamId + "|" + frame.awayTeamId + "|" + frame.scoreHome + "|" + frame.scoreAway + "|" + frame.penaltiesHome + "|" + frame.penaltiesAway + "|" + frame.afterExtraTime + "|" + Winner(frame))
			For Local groupIndex:Int = 0 Until 12
				Local code:String = "ABCDEFGHIJKL"[groupIndex..groupIndex + 1]
				Local group:TGroupTable = FindGroup(latestGroups, code)
				Local rank:Int
				If group <> Null Then
					For Local row:TLeaderboardRow = EachIn group.rows
						rank :+ 1
						output.WriteLine("R|" + (i + 1) + "|" + code + "|" + rank + "|" + row.participantId + "|" + (row.wins + row.draws + row.losses) + "|" + row.wins + "|" + row.draws + "|" + row.losses + "|" + row.gf + "|" + row.ga + "|" + row.points)
					Next
				End If

				For Local team:TTimelineParticipant = EachIn timeline.participants
					If team.divisionId <> code Or HasRow(group, team.id) Then
						Continue
					End If

					rank :+ 1
					output.WriteLine("R|" + (i + 1) + "|" + code + "|" + rank + "|" + team.id + "|0|0|0|0|0|0|0")
				Next

				If rank <> 4 Then
					Throw "World Cup snapshot group is incomplete: " + code
				End If
			Next
		Next

		output.Close()
		Return timeline.frames.Length
	End Function
End Type
