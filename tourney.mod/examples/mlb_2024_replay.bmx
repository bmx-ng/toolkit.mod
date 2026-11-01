' Complete 2024 MLB season replay.
Type TMLB2024Replay
	Function Pool:TPostseasonPool(code:String, divisions:String[])
		Local p:TPostseasonPool = New TPostseasonPool
		p.code = code; p.divisionIds = divisions
		Return p
	End Function

	Function Rules:TPostseasonTieRules()
		Local r:TPostseasonTieRules = New TPostseasonTieRules
		r.twoTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.DivisionRecord, EPostseasonCriterion.PoolRecord]
		r.manyTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.DivisionRecord, EPostseasonCriterion.PoolRecord]
		Return r
	End Function

	Function Stage:TStageState(state:TCompetitionState, id:String)
		For Local s:TStageState = EachIn state.stages
			If s.stageId = id Then
				Return s
			End If
		Next

		Throw "Missing MLB stage " + id
	End Function

	Function Fixture:TFixtureState(s:TStageState, home:Int, away:Int, leg:Int)
		If s.status <> EStageStatus.Running Then
			Return Null
		End If

		For Local f:TFixtureState = EachIn s.fixtures
			If f.status = EFixtureStatus.Scheduled And f.leg = leg And ((f.homeTeamId = home And f.awayTeamId = away) Or (f.homeTeamId = away And f.awayTeamId = home)) Then
				Return f
			End If
		Next

		Return Null
	End Function

	Function Series(s:TStage, n:Int, pattern:Int[])
		Local c:TBracketConfig = TBracketConfig(s.config)
		c.matchFormat = New TMatchFormat
		c.matchFormat.bestOfMatches = n
		c.policy = New TSchedulePolicy
		c.policy.venuePolicy = New TVenuePolicy
		c.policy.venuePolicy.venueType = EVenue.HigherSeedHome
		c.policy.venuePolicy.seriesTemplate = New THomeCourtSeries
		c.policy.venuePolicy.seriesTemplate.bestOf = n
		c.policy.venuePolicy.seriesTemplate.pattern = pattern
	End Function

	Function Seeds:String(s:TStageState)
		Local result:String
		For Local id:Int = EachIn s.inputs[0].entrantIds
			If result <> "" Then
				result :+ ","
			End If

			result :+ String(id)
		Next

		Return result
	End Function

	Function Run:Int(path:String, observer:ICompetitionResultObserver = Null, restoreAfterRegular:Int = 0)
		If restoreAfterRegular < 0 Or restoreAfterRegular > 2429 Then
			Throw "Invalid MLB restore point"
		End If

		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "2024 MLB season"
		Local games:String[]
		Local fixtures:TFixture[]
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local v:String[] = line.Split("|")
			If v[0] = "T" Then
				Local p:TParticipant = New TParticipant
				p.id = Int(v[1]); p.name = v[2]; p.divisionId = v[3]; p.kind = EParticipantKind.Team
				comp.participants :+ [p]
			ElseIf v[0] = "G" Then
				games :+ [line]
				If v[1] = "REG" Then
					Local f:TFixture = New TFixture
					f.round = Int(v[2]); f.awayTeamId = Int(v[3]); f.homeTeamId = Int(v[5])
					fixtures :+ [f]
				End If
			End If
		Wend

		stream.Close()
		If comp.participants.Length <> 30 Or fixtures.Length <> 2429 Or games.Length <> 2472 Then
			Throw "Incomplete MLB data"
		End If

		Local league:TStage = New TStage
		league.id = "REG"; league.stageType = EStageType.League
		Local lc:TLeagueConfig = New TLeagueConfig
		lc.pointsWin = 1; lc.pointsDraw = 0; lc.pointsLoss = 0
		lc.tiebreakers = [ETiebreaker.Points]
		lc.schedule = New TLeagueScheduleConfig
		lc.schedule.fixedFixtures = fixtures
		lc.postseason = New TPostseasonConfig
		lc.postseason.pools = [Pool("AL", ["ALE", "ALC", "ALW"]), Pool("NL", ["NLE", "NLC", "NLW"])]
		lc.postseason.divisionWinnersPerDivision = 1
		lc.postseason.atLargePlaces = 3
		lc.postseason.divisionTie = Rules()
		lc.postseason.atLargeTie = Rules()
		lc.postseason.seedTie = Rules()
		league.config = lc
		comp.stages = [league]
		Local seed:TSeedingPolicy = New TSeedingPolicy
		seed.seedingMethod = ESeedingMethod.Ranking
		Local ao:TEliminationTreeOptions = New TEliminationTreeOptions
		ao.idPrefix = "AL"; ao.size = 8; ao.kind = EEliminationTreeKind.SingleElimination
		ao.fromStageId = "REG"; ao.seeding = seed
		Local al:TEliminationTree = New TEliminationTreeBuilder.Append(comp, ao)
		Local no:TEliminationTreeOptions = New TEliminationTreeOptions
		no.idPrefix = "NL"; no.size = 8; no.kind = EEliminationTreeKind.SingleElimination
		no.fromStageId = "REG"; no.seeding = seed
		Local nl:TEliminationTree = New TEliminationTreeBuilder.Append(comp, no)
		For Local s:TStage = EachIn comp.stages
			If s.id = "AL_W1" Or s.id = "NL_W1" Then
				s.input.postseasonPoolCode = s.id[..2]
				Series(s, 3, [3])
			ElseIf s.id = "AL_W2" Or s.id = "NL_W2" Then
				Series(s, 5, [2, 2, 1])
			ElseIf s.id = "AL_W3" Or s.id = "NL_W3" Then
				Series(s, 7, [2, 3, 2])
			End If
		Next

		Local ws:TStage = New TStage
		ws.id = "WORLD_SERIES"; ws.stageType = EStageType.Bracket
		ws.input = New TEntrySource
		ws.input.fromStageIds = [al.finalStageId, nl.finalStageId]
		ws.input.seeding = New TSeedingPolicy
		ws.input.seeding.seedingMethod = ESeedingMethod.Ranking
		ws.input.seeding.rankingStageId = "REG"
		ws.config = New TBracketConfig
		TBracketConfig(ws.config).size = 2
		Series(ws, 7, [2, 3, 2])
		comp.stages :+ [ws]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		engine.RegisterScorer(EStageType.League, New TLeagueScorer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		If observer <> Null Then
			engine.AddResultObserver(observer)
		End If

		Local state:TCompetitionState = engine.Initialize(comp)
		Local regular:Int, playoffs:Int
		For Local line:String = EachIn games
			Local v:String[] = line.Split("|")
			Local sid:String = "REG"
			If v[1] = "W" Then
				sid = ws.id
			ElseIf v[1] <> "REG" Then
				Local prefix:String = "AL"
				For Local p:TParticipant = EachIn comp.participants
					If p.id = Int(v[3]) And p.divisionId.StartsWith("NL") Then prefix = "NL"; Exit
				Next

				Select v[1]
					Case "F" sid = prefix + "_W1"
					Case "D" sid = prefix + "_W2"
					Case "L" sid = prefix + "_W3"
				End Select
			End If

			Local leg:Int = Int(v[2])
			If v[1] = "REG" Then
				leg = 0
			End If

			Local f:TFixtureState = Fixture(Stage(state, sid), Int(v[5]), Int(v[3]), leg)
			If f = Null Then
				Throw "No live MLB fixture for " + line + " in " + sid
			End If

			If v[1] <> "REG" And f.homeTeamId <> Int(v[5]) Then
				Throw "Wrong MLB home field for " + line
			End If

			Local r:TResultPayload = New TResultPayload
			r.kind = EResultKind.HeadToHeadScore
			If f.homeTeamId = Int(v[5]) Then
				r.scoreHome = Int(v[6]); r.scoreAway = Int(v[4])
			Else
				r.scoreHome = Int(v[4]); r.scoreAway = Int(v[6])
			End If

			engine.RecordResult(comp, state, sid, f.id, r)
			If v[1] = "REG" Then regular :+ 1 Else playoffs :+ 1

			If restoreAfterRegular > 0 And regular = restoreAfterRegular And playoffs = 0 Then
				Local saved:TJConv = New TJConvBuilder.RegisterSerializer("TConfig", New TConfigSerializer).WithEmptyArrays().Build()
				Local stateJson:String = saved.ToJson(state)
				state = TCompetitionState(saved.FromJson(stateJson, "TCompetitionState"))
				If state.actions.Length <> regular Or Stage(state, "REG").fixtures.Length <> 2429 Then
					Throw "Incomplete MLB save/restore"
				End If
			End If

			If regular = 2429 And playoffs = 0 Then
				If Seeds(Stage(state, "AL_W1")) <> "147,114,117,110,118,116" Then
					Throw "Wrong AL seeds: " + Seeds(Stage(state, "AL_W1"))
				End If

				If Seeds(Stage(state, "NL_W1")) <> "119,143,158,135,144,121" Then
					Throw "Wrong NL seeds: " + Seeds(Stage(state, "NL_W1"))
				End If
			End If
		Next

		If regular <> 2429 Or playoffs <> 43 Then
			Throw "Incomplete MLB replay"
		End If

		Local winners:Int[] = (New TBracketAdvancer).DetermineWinners(comp, ws, Stage(state, ws.id), 1)
		If winners.Length <> 1 Or winners[0] <> 119 Then
			Throw "Wrong World Series champion"
		End If

		Return regular + playoffs
	End Function
End Type
