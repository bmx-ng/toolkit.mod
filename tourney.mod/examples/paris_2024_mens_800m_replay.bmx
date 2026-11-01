' Official Paris 2024 men's 800m replay: first round, repechage,
' semifinals, and final. Athlete bib numbers are stable participant IDs.
Type TParis800Record
	Field phase:String
	Field heat:Int
	Field bib:Int
	Field lane:Int
	Field time:String
End Type

Type TParis800Replay
	Function Millis:Long(mark:String)
		Local parts:String[] = mark.Split(":")
		If parts.Length <> 2 Then
			Throw "Invalid 800m time: " + mark
		End If

		Local seconds:String[] = parts[1].Split(".")
		If seconds.Length <> 2 Or seconds[1].Length <> 2 Then
			Throw "Invalid 800m time: " + mark
		End If

		Return (Long(parts[0]) * 60 + Long(seconds[0])) * 1000 + Long(seconds[1]) * 10
	End Function

	Function Lanes:THeatLanePolicy(records:TParis800Record[], phase:String)
		Local policy:THeatLanePolicy = New THeatLanePolicy
		policy.laneCount = 9
		For Local record:TParis800Record = EachIn records
			If record.phase <> phase Then
				Continue
			End If

			Local assignment:THeatLaneAssignment = New THeatLaneAssignment
			assignment.participantId = record.bib
			assignment.lane = record.lane
			policy.fixedAssignments :+ [assignment]
		Next

		Return policy
	End Function

	Function Groups:THeatGroup[](records:TParis800Record[], phase:String, count:Int)
		Local groups:THeatGroup[] = New THeatGroup[count]
		For Local i:Int = 0 Until count
			groups[i] = New THeatGroup
		Next

		For Local record:TParis800Record = EachIn records
			If record.phase = phase Then
				Local group:THeatGroup = groups[record.heat - 1]
				group.participantIds :+ [record.bib]
			End If
		Next

		Return groups
	End Function

	Function ReplayPhase(engine:TCompetitionEngine, comp:TCompetition, state:TCompetitionState, records:TParis800Record[], phase:String, expectedHeats:Int)
		Local fixtures:TFixtureState[]
		For Local fixture:TFixtureState = EachIn state.stages[0].fixtures
			If phase = "H" And fixture.round = 1 Then
				fixtures :+ [fixture]
			End If

			If phase = "R" And fixture.heatPhase = EHeatPhase.Repechage Then
				fixtures :+ [fixture]
			End If

			If phase = "S" And fixture.round = 3 And fixture.heatPhase = EHeatPhase.Main Then
				fixtures :+ [fixture]
			End If

			If phase = "F" And fixture.heatPhase = EHeatPhase.Final Then
				fixtures :+ [fixture]
			End If
		Next

		If fixtures.Length <> expectedHeats Then
			Throw "Incorrect number of Paris 800m " + phase + " heats"
		End If

		For Local h:Int = 0 Until fixtures.Length
			Local fixture:TFixtureState = fixtures[h]
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.TimeBased
			Local expectedCount:Int
			Local place:Int
			For Local record:TParis800Record = EachIn records
				If record.phase <> phase Or record.heat <> h + 1 Then
					Continue
				End If

				expectedCount :+ 1
				Local found:Int
				For Local id:Int = EachIn fixture.heatEntrants
					If id = record.bib Then found = True; Exit
				Next

				If Not found Then
					Throw "Incorrect Paris 800m " + phase + " assignment for bib " + record.bib
				End If

				Local laneFound:Int
				For Local assignment:THeatLaneAssignment = EachIn fixture.heatLanes
					If assignment.participantId = record.bib And assignment.lane = record.lane Then laneFound = True; Exit
				Next

				If Not laneFound Then
					Throw "Incorrect Paris 800m " + phase + " lane for bib " + record.bib
				End If

				Local time:TParticipantTime = New TParticipantTime
				time.participantId = record.bib
				If record.time = "DNS" Then
					time.status = ETimeStatus.DNS
				Else
					place :+ 1
					time.place = place
					time.millis = Millis(record.time)
				End If

				result.times :+ [time]
			Next

			If expectedCount <> fixture.heatEntrants.Length Then
				Throw "Paris 800m heat has unexpected entrants"
			End If

			engine.RecordResult(comp, state, "PARIS_800M", fixture.id, result)
		Next
	End Function

	Function Run:Int(path:String)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read Paris 800m results: " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "Paris 2024 men's 800 metres"
		Local records:TParis800Record[]
		Local phaseCount:Int[4]
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			If fields.Length <> 5 And fields.Length <> 6 Then
				Throw "Malformed Paris 800m result: " + line
			End If

			Local record:TParis800Record = New TParis800Record
			record.phase = fields[0]
			record.heat = Int(fields[1])
			record.bib = Int(fields[2])
			record.lane = Int(fields[fields.Length - 2])
			record.time = fields[fields.Length - 1]
			If record.bib <= 0 Or record.heat < 1 Or record.lane < 1 Or record.lane > 9 Then
				Throw "Invalid Paris 800m result: " + line
			End If

			If record.time <> "DNS" Then
				Millis(record.time)
			End If

			Select record.phase
				Case "H"
					If fields.Length <> 6 Or record.heat > 6 Then
						Throw "Invalid first-round entry: " + line
					End If

					For Local participant:TParticipant = EachIn comp.participants
						If participant.id = record.bib Then
							Throw "Duplicate Paris 800m entrant"
						End If
					Next

					Local athlete:TParticipant = New TParticipant
					athlete.id = record.bib
					athlete.name = fields[3]
					athlete.kind = EParticipantKind.Individual
					comp.participants :+ [athlete]
					phaseCount[0] :+ 1
				Case "R"
					If fields.Length <> 5 Or record.heat > 4 Then
						Throw "Invalid repechage entry: " + line
					End If

					phaseCount[1] :+ 1
				Case "S"
					If fields.Length <> 5 Or record.heat > 3 Then
						Throw "Invalid semifinal entry: " + line
					End If

					phaseCount[2] :+ 1
				Case "F"
					If fields.Length <> 5 Or record.heat <> 1 Then
						Throw "Invalid final entry: " + line
					End If

					phaseCount[3] :+ 1
				Default
					Throw "Unknown Paris 800m round: " + line
			End Select

			records :+ [record]
		Wend

		stream.Close()
		If phaseCount[0] <> 53 Or phaseCount[1] <> 35 Or phaseCount[2] <> 24 Or phaseCount[3] <> 8 Then
			Throw "Incomplete Paris 800m results"
		End If

		Local first:THeatRoundConfig = New THeatRoundConfig
		first.heatCount = 6
		first.automaticPlaces = 3
		first.fixedGroups = Groups(records, "H", 6)
		first.lanes = Lanes(records, "H")
		Local repechage:THeatRoundConfig = New THeatRoundConfig
		repechage.heatCount = 4
		repechage.automaticPlaces = 1
		repechage.fastestRemaining = 2
		repechage.fixedGroups = Groups(records, "R", 4)
		repechage.lanes = Lanes(records, "R")
		first.repechage = repechage
		Local semifinal:THeatRoundConfig = New THeatRoundConfig
		semifinal.heatCount = 3
		semifinal.automaticPlaces = 2
		semifinal.fastestRemaining = 2
		semifinal.fixedGroups = Groups(records, "S", 3)
		semifinal.lanes = Lanes(records, "S")
		Local cfg:THeatsConfig = New THeatsConfig
		cfg.qualifyingRounds = [first, semifinal]
		cfg.finalLanes = Lanes(records, "F")
		Local stage:TStage = New TStage
		stage.id = "PARIS_800M"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "timed-heats"
		stage.config = cfg
		comp.stages = [stage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("timed-heats", New THeatsScheduler, New THeatsScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		ReplayPhase(engine, comp, state, records, "H", 6)
		ReplayPhase(engine, comp, state, records, "R", 4)
		ReplayPhase(engine, comp, state, records, "S", 3)
		ReplayPhase(engine, comp, state, records, "F", 1)
		If state.stages[0].status <> EStageStatus.Complete Then
			Throw "Paris 800m event did not finish"
		End If

		If state.stages[0].leaderboard.rows.Length <> 53 Then
			Throw "Paris 800m leaderboard lost entrants"
		End If

		Local finalIds:Int[] = [987, 449, 307, 1315, 582, 675, 408, 691]
		For Local i:Int = 0 Until finalIds.Length
			If state.stages[0].leaderboard.rows[i].participantId <> finalIds[i] Then
				Throw "Incorrect Paris 800m final place " + (i + 1)
			End If
		Next

		Return state.stages[0].leaderboard.rows[0].participantId
	End Function
End Type
