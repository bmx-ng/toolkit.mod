' Complete 2024 NFL season. The regular-season results determine playoff
' entrants and seeds; the recorded playoff scores determine the champion.
Type TNFL2024Replay
	Function Rules:TPostseasonTieRules(isDivision:Int, reduceByDivision:Int, sweep:Int)
		Local rules:TPostseasonTieRules = New TPostseasonTieRules
		rules.reduceByDivision = reduceByDivision
		rules.headToHeadSweep = sweep
		rules.twoTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.DivisionRecord, EPostseasonCriterion.CommonOpponents, EPostseasonCriterion.PoolRecord, EPostseasonCriterion.StrengthOfVictory, EPostseasonCriterion.StrengthOfSchedule, EPostseasonCriterion.CombinedPointsRankPool, EPostseasonCriterion.CombinedPointsRankAll, EPostseasonCriterion.NetPointsCommon, EPostseasonCriterion.NetPoints]
		If Not isDivision Then
			rules.twoTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.PoolRecord, EPostseasonCriterion.CommonOpponents, EPostseasonCriterion.StrengthOfVictory, EPostseasonCriterion.StrengthOfSchedule, EPostseasonCriterion.CombinedPointsRankPool, EPostseasonCriterion.CombinedPointsRankAll, EPostseasonCriterion.NetPointsPool, EPostseasonCriterion.NetPoints]
		End If

		rules.manyTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.DivisionRecord, EPostseasonCriterion.CommonOpponents, EPostseasonCriterion.PoolRecord, EPostseasonCriterion.StrengthOfVictory, EPostseasonCriterion.StrengthOfSchedule, EPostseasonCriterion.CombinedPointsRankPool, EPostseasonCriterion.CombinedPointsRankAll, EPostseasonCriterion.NetPointsCommon, EPostseasonCriterion.NetPoints]
		If Not isDivision Then
			rules.manyTeams = [EPostseasonCriterion.HeadToHead, EPostseasonCriterion.PoolRecord, EPostseasonCriterion.CommonOpponents, EPostseasonCriterion.StrengthOfVictory, EPostseasonCriterion.StrengthOfSchedule, EPostseasonCriterion.CombinedPointsRankPool, EPostseasonCriterion.CombinedPointsRankAll, EPostseasonCriterion.NetPointsPool, EPostseasonCriterion.NetPoints]
		End If

		Return rules
	End Function

	Function Pool:TPostseasonPool(code:String, divisions:String[])
		Local pool:TPostseasonPool = New TPostseasonPool
		pool.code = code
		pool.divisionIds = divisions
		Return pool
	End Function

	Function Ids:Int[](csv:String)
		Local ids:Int[]
		For Local value:String = EachIn csv.Split(",")
			ids :+ [Int(value)]
		Next

		Return ids
	End Function

	Function FindFixture:TFixtureState(state:TCompetitionState, home:Int, away:Int, stageId:String)
		For Local stage:TStageState = EachIn state.stages
			If stage.stageId <> stageId Or stage.status <> EStageStatus.Running Then
				Continue
			End If

			For Local fixture:TFixtureState = EachIn stage.fixtures
				If fixture.status <> EFixtureStatus.Scheduled Then
					Continue
				End If

				If (fixture.homeTeamId = home And fixture.awayTeamId = away) Or (fixture.homeTeamId = away And fixture.awayTeamId = home) Then
					Return fixture
				End If
			Next
		Next

		Return Null
	End Function

	Function Run:Int(path:String)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "2024 NFL season"
		Local games:String[]
		Local expected:TStringMap = New TStringMap
		Local fixtures:TFixture[]
		While Not stream.Eof()
			Local line:String = stream.ReadLine().Trim()
			If line = "" Or line.StartsWith("#") Then
				Continue
			End If

			Local fields:String[] = line.Split("|")
			Select fields[0]
				Case "T"
					Local team:TParticipant = New TParticipant
					team.id = Int(fields[1])
					team.name = fields[2]
					team.divisionId = fields[3]
					team.kind = EParticipantKind.Team
					comp.participants :+ [team]
				Case "G"
					games :+ [line]
					If fields[1] = "REG" Then
						Local fixture:TFixture = New TFixture
						fixture.round = Int(fields[2])
						fixture.awayTeamId = Int(fields[3])
						fixture.homeTeamId = Int(fields[5])
						fixtures :+ [fixture]
					End If
				Case "E"
					expected.Insert(fields[1], fields[2])
			End Select
		Wend

		stream.Close()
		If comp.participants.Length <> 32 Or fixtures.Length <> 272 Or games.Length <> 285 Then
			Throw "Incomplete NFL season"
		End If

		Local league:TStage = New TStage
		league.id = "REG"
		league.stageType = EStageType.League
		Local config:TLeagueConfig = New TLeagueConfig
		config.pointsWin = 2
		config.pointsDraw = 1
		config.pointsLoss = 0
		config.tiebreakers = [ETiebreaker.Points]
		config.schedule = New TLeagueScheduleConfig
		config.schedule.fixedFixtures = fixtures
		config.schedule.totalGamesPerTeam = 17
		config.schedule.weeks = 18
		config.postseason = New TPostseasonConfig
		config.postseason.pools = [Pool("AFC", ["AFCE", "AFCN", "AFCS", "AFCW"]), Pool("NFC", ["NFCE", "NFCN", "NFCS", "NFCW"])]
		config.postseason.divisionWinnersPerDivision = 1
		config.postseason.atLargePlaces = 3
		config.postseason.divisionTie = Rules(True, False, False)
		config.postseason.atLargeTie = Rules(False, True, True)
		config.postseason.seedTie = Rules(False, False, True)
		league.config = config
		comp.stages = [league]
		Local seeding:TSeedingPolicy = New TSeedingPolicy
		seeding.seedingMethod = ESeedingMethod.Ranking
		Local afcOptions:TEliminationTreeOptions = New TEliminationTreeOptions
		afcOptions.idPrefix = "AFC"
		afcOptions.size = 8
		afcOptions.kind = EEliminationTreeKind.SingleElimination
		afcOptions.fromStageId = league.id
		afcOptions.seeding = seeding
		Local afc:TEliminationTree = New TEliminationTreeBuilder.Append(comp, afcOptions)
		Local nfcOptions:TEliminationTreeOptions = New TEliminationTreeOptions
		nfcOptions.idPrefix = "NFC"
		nfcOptions.size = 8
		nfcOptions.kind = EEliminationTreeKind.SingleElimination
		nfcOptions.fromStageId = league.id
		nfcOptions.seeding = seeding
		Local nfc:TEliminationTree = New TEliminationTreeBuilder.Append(comp, nfcOptions)
		For Local stage:TStage = EachIn comp.stages
			If stage.id = afc.winnerRounds[0] Then
				stage.input.postseasonPoolCode = "AFC"
			End If

			If stage.id = nfc.winnerRounds[0] Then
				stage.input.postseasonPoolCode = "NFC"
			End If

			If stage.id = afc.winnerRounds[1] Or stage.id = nfc.winnerRounds[1] Or stage.id = afc.winnerRounds[2] Or stage.id = nfc.winnerRounds[2] Then
				TBracketConfig(stage.config).reseedEachRound = True
			End If
		Next

		Local superBowlStage:TStage = New TStage
		superBowlStage.id = "SUPER_BOWL"
		superBowlStage.stageType = EStageType.Bracket
		superBowlStage.input = New TEntrySource
		superBowlStage.input.fromStageIds = [afc.finalStageId, nfc.finalStageId]
		superBowlStage.config = New TBracketConfig
		TBracketConfig(superBowlStage.config).size = 2
		TBracketConfig(superBowlStage.config).policy = New TSchedulePolicy
		TBracketConfig(superBowlStage.config).policy.venuePolicy = New TVenuePolicy
		TBracketConfig(superBowlStage.config).policy.venuePolicy.venueType = EVenue.Neutral
		comp.stages :+ [superBowlStage]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
		engine.RegisterScorer(EStageType.League, New TLeagueScorer)
		engine.RegisterScheduler(EStageType.Bracket, New TBracketScheduler)
		engine.RegisterScorer(EStageType.Bracket, New TBracketScorer)
		engine.RegisterAdvancer(EStageType.Bracket, New TBracketAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local regCount:Int
		Local playoffCount:Int
		For Local line:String = EachIn games
			Local fields:String[] = line.Split("|")
			Local stageId:String = league.id
			If fields[1] <> "REG" Then
				Select fields[1]
					Case "WC", "DIV", "CON"
						Local prefix:String = "AFC"
						If Int(fields[3]) > 0 Then
							For Local participant:TParticipant = EachIn comp.participants
								If participant.id = Int(fields[3]) And participant.divisionId.StartsWith("NFC") Then prefix = "NFC"; Exit
							Next
						End If

						Select fields[1]
							Case "WC" stageId = prefix + "_W1"
							Case "DIV" stageId = prefix + "_W2"
							Case "CON" stageId = prefix + "_W3"
						End Select
					Case "SB" stageId = superBowlStage.id
				End Select
			End If

			Local fixture:TFixtureState = FindFixture(state, Int(fields[5]), Int(fields[3]), stageId)
			If fixture = Null Then
				Throw "No live NFL fixture for " + line + " in " + stageId
			End If

			Local payload:TResultPayload = New TResultPayload
			payload.kind = EResultKind.HeadToHeadScore
			If fixture.homeTeamId = Int(fields[5]) Then
				payload.scoreHome = Int(fields[6])
				payload.scoreAway = Int(fields[4])
			Else
				payload.scoreHome = Int(fields[4])
				payload.scoreAway = Int(fields[6])
			End If

			engine.RecordResult(comp, state, stageId, fixture.id, payload)
			If fields[1] = "REG" Then regCount :+ 1 Else playoffCount :+ 1

			If regCount = 272 And playoffCount = 0 Then
				For Local code:String = EachIn ["AFC", "NFC"]
					Local stage:TStageState = Null
					For Local candidate:TStageState = EachIn state.stages
						If candidate.stageId = code + "_W1" Then stage = candidate; Exit
					Next

					If stage = Null Or stage.inputs.Length <> 1 Then
						Throw "Missing derived playoff field " + code
					End If

					Local found:String = ""
					For Local id:Int = EachIn stage.inputs[0].entrantIds
						If found <> "" Then
							found :+ ","
						End If

						found :+ String(id)
					Next

					If found <> String(expected.ValueForKey(code)) Then
						Throw code + " playoff seeds: expected " + String(expected.ValueForKey(code)) + ", got " + found
					End If
				Next
			End If
		Next

		If regCount <> 272 Or playoffCount <> 13 Then
			Throw "Incomplete NFL replay"
		End If

		Local champion:TBracketAdvancer = New TBracketAdvancer
		For Local stage:TStageState = EachIn state.stages
			If stage.stageId = superBowlStage.id Then
				Local winners:Int[] = champion.DetermineWinners(comp, superBowlStage, stage, 1)
				If winners.Length <> 1 Or winners[0] <> 26 Then
					Throw "Wrong Super Bowl champion"
				End If

				Return regCount + playoffCount
			End If
		Next

		Throw "Missing Super Bowl"
	End Function
End Type
