' Replay the official 2025 Wimbledon gentlemen's singles draw.
Type TWimbledon2025Replay
	Function Replay:Int(path:String)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "Wimbledon 2025 Gentlemen's Singles"
		Local resultLines:String[]
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			If fields[0] = "P" Then
				Local participant:TParticipant = New TParticipant
				participant.id = Int(fields[1]) ' official draw position
				participant.name = fields[2]
				participant.kind = EParticipantKind.Individual
				comp.participants :+ [participant]
			ElseIf fields[0] = "R" Then
				resultLines :+ [line]
			End If
		Wend

		stream.Close()
		If comp.participants.Length <> 128 Or resultLines.Length <> 127 Then
			Throw "Incomplete historical draw"
		End If

		' Rank entrants so the scheduler's seeded slot permutation recreates the
		' published draw exactly. Later stages preserve those bracket lanes.
		Local slots:Int[] = New TBracketScheduler.SeededBracketOrder(128)
		For Local i:Int = 0 Until 128
			comp.participants[i].seedRank = slots[i]
		Next

		Local format:TMatchFormat = New TMatchFormat
		format.setRules = New TSetRules
		format.setRules.usesSets = True
		format.setRules.setsBestOf = 5
		format.setRules.gamesPerSetTarget = 6
		format.setRules.gamesMargin = 2
		format.setRules.tiebreakAtGames = 6
		Local options:TEliminationTreeOptions = New TEliminationTreeOptions
		options.idPrefix = "WIMBLEDON_2025"
		options.size = 128
		options.kind = EEliminationTreeKind.SingleElimination
		options.matchFormat = format
		options.seeding = New TSeedingPolicy
		options.seeding.seedingMethod = ESeedingMethod.Ranking
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, options)

		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local recorded:Int
		For Local line:String = EachIn resultLines
			Local fields:String[] = line.Split("|")
			Local round:Int = Int(fields[1])
			Local position:Int = Int(fields[2])
			Local winnerId:Int = Int(fields[3])
			Local retiredId:Int = Int(fields[4])
			Local stageId:String = tree.winnerRounds[round - 1]
			Local fixture:TFixtureState = Null
			For Local stageState:TStageState = EachIn state.stages
				If stageState.stageId <> stageId Then
					Continue
				End If

				For Local candidate:TFixtureState = EachIn stageState.fixtures
					If candidate.bracketPosition = position Then fixture = candidate; Exit
				Next

				Exit
			Next

			If fixture = Null Then
				Throw "Missing historical fixture " + stageId + " position " + position
			End If

			If winnerId <> fixture.homeTeamId And winnerId <> fixture.awayTeamId Then
				Throw "Historical winner is not in " + fixture.id
			End If

			Local payload:TResultPayload = New TResultPayload
			payload.kind = EResultKind.SetBased
			payload.retiredParticipantId = retiredId
			For Local score:String = EachIn fields[5].Split(" ")
				Local pair:String[] = score.Split("/")
				If pair.Length <> 2 Then
					Throw "Invalid historical set score: " + score
				End If

				Local first:Int = Int(pair[0])
				Local second:Int = Int(pair[1].Split("(")[0])
				Local setScore:TSetScore = New TSetScore
				If winnerId = fixture.homeTeamId Then
					setScore.home = first
					setScore.away = second
				Else
					setScore.home = second
					setScore.away = first
				End If

				payload.sets :+ [setScore]
			Next

			engine.RecordResult(comp, state, stageId, fixture.id, payload)
			recorded :+ 1
		Next

		If tree.ChampionId(comp, state) <> 1 Then
			Throw "Historical replay did not produce Jannik Sinner"
		End If

		Return tree.ChampionId(comp, state)
	End Function
End Type
