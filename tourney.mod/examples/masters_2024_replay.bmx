' Historical replay of all 89 entrants in the 2024 Masters Tournament.
' The published data contains 18-hole round totals. No hole scores are inferred.
Type TMasters2024Entry
	Field id:Int
	Field name:String
	Field position:String
	Field rounds:Int[]
	Field total:Int
End Type

Type TMasters2024Replay
	Function Entry:TMasters2024Entry(entries:TMasters2024Entry[], id:Int)
		If id < 1 Or id > entries.Length Then
			Throw "Unknown Masters entrant: " + id
		End If

		Return entries[id - 1]
	End Function

	Function Run:Int(path:String)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read Masters results: " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "2024 Masters Tournament"
		Local entries:TMasters2024Entry[]
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			If fields.Length <> 7 Then
				Throw "Malformed Masters results row: " + line
			End If

			Local entry:TMasters2024Entry = New TMasters2024Entry
			entry.id = entries.Length + 1
			entry.position = fields[0]
			entry.name = fields[1]
			entry.rounds = [Int(fields[2]), Int(fields[3])]
			If (fields[4] = "-") <> (fields[5] = "-") Then
				Throw "Incomplete Masters weekend scores: " + entry.name
			End If

			If fields[4] <> "-" Then
				entry.rounds :+ [Int(fields[4]), Int(fields[5])]
			End If

			entry.total = Int(fields[6])
			Local sum:Int
			For Local value:Int = EachIn entry.rounds
				If value < 1 Then
					Throw "Invalid Masters round score: " + entry.name
				End If

				sum :+ value
			Next

			If sum <> entry.total Then
				Throw "Masters round scores do not add up: " + entry.name
			End If

			If (entry.position = "CUT") <> (entry.rounds.Length = 2) Then
				Throw "Inconsistent Masters cut data: " + entry.name
			End If

			entries :+ [entry]
			Local player:TParticipant = New TParticipant
			player.id = entry.id
			player.name = entry.name
			player.kind = EParticipantKind.Individual
			comp.participants :+ [player]
		Wend

		stream.Close()
		If entries.Length <> 89 Then
			Throw "Incomplete Masters field"
		End If

		Local stage:TStage = New TStage
		stage.id = "MASTERS_2024"
		stage.stageType = EStageType.Qualifying
		stage.formatCode = "stroke-play"
		Local cfg:TStrokePlayConfig = New TStrokePlayConfig
		For Local round:Int = 1 To 4
			Local definition:TStrokePlayRoundConfig = New TStrokePlayRoundConfig
			definition.holeCount = 18
			cfg.rounds :+ [definition]
		Next

		cfg.cutAfterRound = 2
		cfg.cutPlaces = 50
		stage.config = cfg
		comp.stages = [stage]

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("stroke-play", New TStrokePlayScheduler, New TStrokePlayScorer)
		Local state:TCompetitionState = engine.Initialize(comp)
		For Local round:Int = 1 To 4
			Local fixture:TFixtureState = state.stages[0].fixtures[round - 1]
			Local result:TResultPayload = New TResultPayload
			result.kind = EResultKind.Custom
			result.customCode = "stroke-play-card"
			For Local id:Int = EachIn fixture.participantIds
				Local entry:TMasters2024Entry = Entry(entries, id)
				If entry.rounds.Length < round Then
					Throw "Cut player scheduled for Masters round " + round + ": " + entry.name
				End If

				Local card:TStrokeScorecard = New TStrokeScorecard
				card.participantId = id
				card.roundStrokes = entry.rounds[round - 1]
				result.strokeCards :+ [card]
			Next

			engine.RecordResult(comp, state, stage.id, fixture.id, result)
			If round = 2 Then
				If state.stages[0].fixtures.Length <> 3 Then
					Throw "Masters weekend fixture was not generated"
				End If

				If state.stages[0].fixtures[2].participantIds.Length <> 60 Then
					Throw "Masters cut did not retain 60 players"
				End If

				Local lowCutTotal:Int = 999
				Local highSurvivorTotal:Int
				For Local entry:TMasters2024Entry = EachIn entries
					Local survivor:Int = TStrokePlayRules.HasId(state.stages[0].fixtures[2].participantIds, entry.id)
					If survivor <> (entry.position <> "CUT") Then
						Throw "Incorrect Masters cut: " + entry.name
					End If

					If survivor And entry.rounds[0] + entry.rounds[1] > highSurvivorTotal Then
						highSurvivorTotal = entry.rounds[0] + entry.rounds[1]
					End If

					If Not survivor And entry.total < lowCutTotal Then
						lowCutTotal = entry.total
					End If
				Next

				If highSurvivorTotal <> 150 Or lowCutTotal <> 151 Then
					Throw "Incorrect Masters cut line"
				End If
			End If
		Next

		If state.stages[0].status <> EStageStatus.Complete Then
			Throw "Masters replay did not complete"
		End If

		If state.stages[0].strokeStandings.Length <> 89 Then
			Throw "Masters leaderboard lost entrants"
		End If

		Local finishers:Int
		Local previousTotal:Int
		Local reachedCut:Int
		For Local standing:TStrokeStanding = EachIn state.stages[0].strokeStandings
			Local entry:TMasters2024Entry = Entry(entries, standing.participantId)
			If standing.strokes <> entry.total Then
				Throw "Incorrect Masters total: " + entry.name
			End If

			If entry.position = "CUT" Then
				reachedCut = True
				If standing.status <> "cut" Or standing.roundsCompleted <> 2 Then
					Throw "Incorrect Masters cut status: " + entry.name
				End If
			Else
				If reachedCut Then
					Throw "Masters finalist ranked below a cut player"
				End If

				finishers :+ 1
				If standing.status <> "active" Or standing.roundsCompleted <> 4 Then
					Throw "Incorrect Masters final status: " + entry.name
				End If

				If finishers > 1 And standing.strokes < previousTotal Then
					Throw "Incorrect Masters leaderboard order"
				End If

				Local position:Int = 1
				Local tied:Int
				For Local other:TMasters2024Entry = EachIn entries
					If other.rounds.Length <> 4 Then
						Continue
					End If

					If other.total < entry.total Then
						position :+ 1
					End If

					If other.total = entry.total Then
						tied :+ 1
					End If
				Next

				Local expected:String = String(position)
				If tied > 1 Then
					expected = "T" + expected
				End If

				If entry.position <> expected Then
					Throw "Incorrect Masters finishing position: " + entry.name
				End If

				previousTotal = standing.strokes
			End If
		Next

		If finishers <> 60 Then
			Throw "Incorrect number of Masters finishers"
		End If

		If state.stages[0].leaderboard.rows[0].participantId <> 1 Then
			Throw "Incorrect Masters champion"
		End If

		Return finishers
	End Function
End Type
