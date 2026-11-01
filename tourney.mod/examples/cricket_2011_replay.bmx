' Replay all 49 matches of the 2011 ICC Men's Cricket World Cup.
Type TCricket2011Replay
	Function Stage:TStageState(state:TCompetitionState, id:String)
		For Local s:TStageState = EachIn state.stages
			If s.stageId = id Then
				Return s
			End If
		Next

		Throw "Missing cricket stage " + id
	End Function

	Function Fixture:TFixtureState(s:TStageState, first:Int, second:Int)
		If s.status <> EStageStatus.Running Then
			Return Null
		End If

		For Local f:TFixtureState = EachIn s.fixtures
			If f.status = EFixtureStatus.Scheduled And ((f.homeTeamId = first And f.awayTeamId = second) Or (f.homeTeamId = second And f.awayTeamId = first)) Then
				Return f
			End If
		Next

		Return Null
	End Function

	Function GroupOrder:String(s:TStageState, group:String)
		For Local table:TGroupTable = EachIn s.groups
			If table.key <> group Then
				Continue
			End If

			Local result:String
			For Local row:TLeaderboardRow = EachIn table.rows
				If result <> "" Then
					result :+ ","
				End If

				result :+ String(row.participantId)
			Next

			Return result
		Next

		Throw "Missing cricket group " + group
	End Function

	Function NetRate:Double(s:TStageState, id:Int)
		For Local row:TLeaderboardRow = EachIn s.leaderboard.rows
			If row.participantId = id Then
				Return row.netRate
			End If
		Next

		Throw "Missing cricket NRR row " + id
	End Function

	Function Run:Int(path:String)
		Local stream:TStream = ReadStream(path)
		If stream = Null Then
			Throw "Cannot read " + path
		End If

		Local comp:TCompetition = New TCompetition
		comp.name = "2011 ICC Cricket World Cup"
		Local games:String[], fixtures:TFixture[]
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
				If v[1] = "A" Or v[1] = "B" Then
					Local f:TFixture = New TFixture
					f.round = Int(v[2])
					f.homeTeamId = Int(v[3]); f.awayTeamId = Int(v[7])
					fixtures :+ [f]
				End If
			End If
		Wend

		stream.Close()
		If comp.participants.Length <> 14 Or fixtures.Length <> 42 Or games.Length <> 49 Then
			Throw "Incomplete 2011 cricket data"
		End If

		Local groups:TStage = New TStage
		groups.id = "GROUPS"; groups.stageType = EStageType.League; groups.formatCode = "cricket-group"
		Local gc:TCricketConfig = New TCricketConfig
		gc.schedule = New TLeagueScheduleConfig
		gc.schedule.fixedFixtures = fixtures
		groups.config = gc
		comp.stages = [groups]
		Local opts:TEliminationTreeOptions = New TEliminationTreeOptions
		opts.idPrefix = "KO"; opts.size = 8
		opts.kind = EEliminationTreeKind.SingleElimination
		opts.fromStageId = groups.id
		Local tree:TEliminationTree = New TEliminationTreeBuilder.Append(comp, opts)
		For Local stage:TStage = EachIn comp.stages
			If stage.id.StartsWith("KO_") Then
				stage.formatCode = "cricket-knockout"
			End If
		Next

		Local route:TAdvancement = New TAdvancement
		route.toStageId = tree.winnerRounds[0]
		route.rule = New TFilterRule
		route.rule.kind = EFilterKind.TopN
		route.rule.scope = EFilterScope.PerGroup
		route.rule.n = 4
		route.mapping = New TAdvancementMapping
		route.mapping.mode = EAdvMappingMode.FixedSlots
		route.mapping.toSlots = ["1", "7", "3", "5", "6", "4", "8", "2"]
		groups.advancement = [route]
		Local engine:TCompetitionEngine = New TCompetitionEngine
		engine.RegisterFormat("cricket-group", New TLeagueScheduler, New TCricketScorer, New TGroupAdvancer)
		engine.RegisterFormat("cricket-knockout", New TBracketScheduler, New TCricketScorer, New TBracketAdvancer)
		Local state:TCompetitionState = engine.Initialize(comp)
		Local groupCount:Int, knockoutCount:Int, ties:Int, noResults:Int, revised:Int
		For Local line:String = EachIn games
			Local v:String[] = line.Split("|")
			Local sid:String = "GROUPS"
			Select v[1]
				Case "QF" sid = tree.winnerRounds[0]
				Case "SF" sid = tree.winnerRounds[1]
				Case "F" sid = tree.winnerRounds[2]
			End Select

			Local f:TFixtureState = Fixture(Stage(state, sid), Int(v[3]), Int(v[7]))
			If f = Null Then
				Throw "No live cricket fixture for " + line + " in " + sid
			End If

			Local match:TCricketMatchResult = New TCricketMatchResult
			match.first = New TCricketInnings
			match.first.teamId = Int(v[3]); match.first.runs = Int(v[4])
			match.first.wickets = Int(v[5]); match.first.legalBalls = Int(v[6])
			match.first.allocatedBalls = 300
			match.second = New TCricketInnings
			match.second.teamId = Int(v[7]); match.second.runs = Int(v[8])
			match.second.wickets = Int(v[9]); match.second.legalBalls = Int(v[10])
			match.second.allocatedBalls = 300
			match.winnerId = Int(v[11])
			Select v[12]
				Case "W" match.outcome = ECricketOutcome.Win
				Case "T" match.outcome = ECricketOutcome.Tie
				Case "N" match.outcome = ECricketOutcome.NoResult
			End Select

			match.method = v[13]
			match.revisedTarget = Int(v[14])
			If match.outcome = ECricketOutcome.Tie Then
				ties :+ 1
			End If

			If match.outcome = ECricketOutcome.NoResult Then
				noResults :+ 1
			End If

			If match.revisedTarget > 0 Then
				revised :+ 1
			End If

			If match.revisedTarget > 0 Then
				match.second.allocatedBalls = 228
				match.first.creditedRuns = match.revisedTarget - 1
				match.first.creditedBalls = match.second.allocatedBalls
			End If

			Local payload:TResultPayload = New TResultPayload
			payload.kind = EResultKind.Custom
			payload.customCode = "cricket"
			payload.cricket = match
			engine.RecordResult(comp, state, sid, f.id, payload)
			If sid = "GROUPS" Then groupCount :+ 1 Else knockoutCount :+ 1

			If groupCount = 42 And knockoutCount = 0 Then
				If GroupOrder(Stage(state, sid), "A") <> "10,12,1,9,14,3,7" Then
					Throw "Wrong 2011 Group A table: " + GroupOrder(Stage(state, sid), "A")
				End If

				If GroupOrder(Stage(state, sid), "B") <> "11,5,4,13,2,6,8" Then
					Throw "Wrong 2011 Group B table: " + GroupOrder(Stage(state, sid), "B")
				End If

				If Abs(NetRate(Stage(state, sid), 10) - 0.758) > 0.001 Then
					Throw "Wrong Pakistan net run rate"
				End If

				If Abs(NetRate(Stage(state, sid), 12) - 2.582) > 0.001 Then
					Throw "Wrong Sri Lanka net run rate"
				End If

				If Abs(NetRate(Stage(state, sid), 11) - 2.026) > 0.001 Then
					Throw "Wrong South Africa net run rate"
				End If

				If Abs(NetRate(Stage(state, sid), 5) - 0.900) > 0.001 Then
					Throw "Wrong India net run rate"
				End If
			End If
		Next

		If groupCount <> 42 Or knockoutCount <> 7 Or ties <> 1 Or noResults <> 1 Or revised <> 1 Then
			Throw "Incomplete cricket replay"
		End If

		Local winner:Int[] = (New TBracketAdvancer).DetermineWinners(comp, comp.stages[3], Stage(state, tree.finalStageId), 1)
		If winner.Length <> 1 Or winner[0] <> 5 Then
			Throw "Wrong 2011 cricket champion"
		End If

		Return groupCount + knockoutCount
	End Function
End Type
