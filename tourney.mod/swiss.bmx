' A basic results-driven Swiss policy. Pairings are generated one round at a
' time, from the saved fixtures and current standings. This is not a certified
' implementation of a particular FIDE pairing system.
Rem
bbdoc: Pairs Swiss rounds while tracking rematches, byes, and colour balance.
End Rem
Type TSwissScheduler Implements IStageScheduler, IProgressiveStageScheduler
	Rem
	bbdoc: Attempts for this swiss scheduler.
	End Rem
	Field attempts:Int
	Rem
	bbdoc: Reached limit for this swiss scheduler.
	End Rem
	Field reachedLimit:Int

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		ValidateConfig(cfg)
		If comp.participants = Null Or comp.participants.Length < 2 Then
			Throw "Swiss needs at least two entrants"
		End If

		For Local planned:TSwissPlannedUnplayed = EachIn cfg.plannedUnplayed
			Local found:Int
			For Local participant:TParticipant = EachIn comp.participants
				If participant.id = planned.participantId Then found = True; Exit
			Next

			If Not found Then
				Throw "Planned Swiss unplayed round has an unknown entrant: " + planned.participantId
			End If
		Next

		Local state:TStageState = New TStageState
		state.fixtures = []
		state.leaderboard = New TLeaderboard
		state.leaderboard.rows = []
		For Local participant:TParticipant = EachIn comp.participants
			state.entrants :+ [participant.id]
		Next

		Return BuildRound(comp, stage, state, 1)
	End Method

	Method NextFixtures:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		ValidateConfig(cfg)
		Local current:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			current = Max(current, fixture.round)
		Next

		If current = 0 Or current >= cfg.rounds Then
			Return Null
		End If

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.round = current And fixture.status <> EFixtureStatus.Completed Then
				Return Null
			End If
		Next

		Return BuildRound(comp, stage, state, current + 1)
	End Method

	Rem
	bbdoc: Checks Swiss pairing and scoring settings before scheduling.
	param: Swiss configuration to validate.
	End Rem
	Method ValidateConfig(cfg:TSwissConfig)
		If cfg = Null Then
			Throw "Swiss stage needs TSwissConfig"
		End If

		If cfg.rounds < 1 Then
			Throw "Swiss needs at least one round"
		End If

		If cfg.pointsScale < 1 Then
			Throw "Swiss pointsScale must be positive"
		End If

		SwissWinUnits(cfg)
		SwissDrawUnits(cfg)
		SwissLossUnits(cfg)
		SwissByeUnits(cfg)
		If cfg.pairingPolicy <> Null Then
			If cfg.pairingPolicy.system <> ESwissPairingSystem.Generic And cfg.pairingPolicy.system <> ESwissPairingSystem.DutchStyle Then
				Throw "Unsupported Swiss pairing system"
			End If

			If cfg.pairingPolicy.initialColour <> 1 And cfg.pairingPolicy.initialColour <> -1 Then
				Throw "Swiss initialColour must be 1 or -1"
			End If

			If cfg.pairingPolicy.system = ESwissPairingSystem.DutchStyle And cfg.initialSeeding = "random" Then
				Throw "Dutch-style Swiss pairing needs seed order"
			End If
		End If

		For Local rule:ESwissTieBreak = EachIn cfg.tiebreaks
			Select rule
				Case ESwissTieBreak.Buchholz, ESwissTieBreak.BuchholzCut1
				Default
					Throw "Unsupported Swiss tiebreak"
			End Select
		Next

		For Local i:Int = 0 Until cfg.plannedUnplayed.Length
			Local planned:TSwissPlannedUnplayed = cfg.plannedUnplayed[i]
			If planned = Null Or planned.participantId <= 0 Or planned.round < 1 Or planned.round > cfg.rounds Then
				Throw "Invalid planned Swiss unplayed round"
			End If

			If planned.kind <> ESwissUnplayedKind.RequestedBye And planned.kind <> ESwissUnplayedKind.Withdrawal Then
				Throw "Swiss planned round must be a requested bye or withdrawal"
			End If

			Local units:Int = SwissPlannedUnits(planned, cfg)
			If planned.kind = ESwissUnplayedKind.Withdrawal And units <> 0 Then
				Throw "Swiss withdrawal rounds award zero points"
			End If

			If planned.kind = ESwissUnplayedKind.RequestedBye And units <> 0 And units <> SwissDrawUnits(cfg) Then
				Throw "Swiss requested bye awards zero or draw points"
			End If

			For Local j:Int = i + 1 Until cfg.plannedUnplayed.Length
				If cfg.plannedUnplayed[j] = Null Then
					Throw "Invalid planned Swiss unplayed round"
				End If

				If cfg.plannedUnplayed[j].participantId = planned.participantId And cfg.plannedUnplayed[j].round = planned.round Then
					Throw "Duplicate planned Swiss unplayed round"
				End If

				If planned.kind = ESwissUnplayedKind.Withdrawal And cfg.plannedUnplayed[j].participantId = planned.participantId And cfg.plannedUnplayed[j].round > planned.round Then
					Throw "Swiss withdrawal cannot be followed by another planned round"
				End If

				If cfg.plannedUnplayed[j].kind = ESwissUnplayedKind.Withdrawal And cfg.plannedUnplayed[j].participantId = planned.participantId And cfg.plannedUnplayed[j].round < planned.round Then
					Throw "Swiss withdrawal cannot be followed by another planned round"
				End If
			Next
		Next

		If cfg.initialSeeding <> "" And cfg.initialSeeding <> "seed" And cfg.initialSeeding <> "random" Then
			Throw "Swiss initialSeeding must be seed or random"
		End If
	End Method

	Method BuildRound:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState, round:Int)
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		Local ordered:Int[] = state.entrants[..]
		SortEntrants(comp, state, ordered)
		If round = 1 And cfg.initialSeeding = "random" Then
			Local policy:TSchedulePolicy = GetSchedulePolicy(stage)
			If policy.scheduleSeed = 0 Then
				Throw "Random Swiss seeding needs scheduleSeed"
			End If

			SeedRnd(policy.scheduleSeed)
			For Local i:Int = ordered.Length - 1 To 1 Step -1
				Local j:Int = Rand(0, i)
				Local tmp:Int = ordered[i]
				ordered[i] = ordered[j]
				ordered[j] = tmp
			Next
		End If

		Local available:Int[]
		Local plannedFixtures:TFixtureState[]
		For Local id:Int = EachIn ordered
			Local planned:TSwissPlannedUnplayed = PlanFor(cfg, id, round)
			If planned = Null Then
				available :+ [id]
				Continue
			End If

			Local fixture:TFixtureState = New TFixtureState
			fixture.id = stage.id + "_R" + round + "_UNPLAYED_" + id
			fixture.round = round
			fixture.homeTeamId = id
			fixture.awayTeamId = 0
			fixture.status = EFixtureStatus.Completed
			fixture.swissUnplayedKind = planned.kind
			fixture.swissAwardedUnits = SwissPlannedUnits(planned, cfg)
			plannedFixtures :+ [fixture]
		Next

		ordered = available
		For Local planned:TSwissPlannedUnplayed = EachIn cfg.plannedUnplayed
			If planned.round <> round Then
				Continue
			End If

			Local found:Int
			For Local fixture:TFixtureState = EachIn plannedFixtures
				If fixture.homeTeamId = planned.participantId Then found = True; Exit
			Next

			If Not found Then
				Throw "Planned Swiss unplayed round has an unknown entrant: " + planned.participantId
			End If
		Next

		If ordered.Length < 2 Then
			Throw "Swiss round needs at least two available entrants"
		End If

		Local byeCandidates:Int[]
		If ordered.Length Mod 2 = 0 Then
			byeCandidates = [-1]
		Else
			For Local i:Int = ordered.Length - 1 To 0 Step -1
				If Not HasBye(state, ordered[i], cfg) Then
					byeCandidates :+ [i]
				End If
			Next

			If byeCandidates.Length = 0 Then
				Throw "Swiss cannot give a second pairing bye to every entrant"
			End If

			If IsDutchStyle(cfg) Then
				For Local i:Int = 0 Until byeCandidates.Length
					For Local j:Int = i + 1 Until byeCandidates.Length
						Local a:Int = ordered[byeCandidates[i]]
						Local b:Int = ordered[byeCandidates[j]]
						If Points(state, b) < Points(state, a) Or (Points(state, b) = Points(state, a) And UnplayedCount(state, b) < UnplayedCount(state, a)) Then
							Local swap:Int = byeCandidates[i]
							byeCandidates[i] = byeCandidates[j]
							byeCandidates[j] = swap
						End If
					Next
				Next
			End If
		End If

		attempts = 0
		reachedLimit = False
		For Local byeIndex:Int = EachIn byeCandidates
			Local active:Int[]
			For Local i:Int = 0 Until ordered.Length
				If i <> byeIndex Then
					active :+ [ordered[i]]
				End If
			Next

			Local used:Int[] = New Int[active.Length]
			Local sideA:Int[] = New Int[active.Length / 2]
			Local sideB:Int[] = New Int[active.Length / 2]
			If IsDutchStyle(cfg) Then
				If Not PairDutch(comp, cfg, state, active, used, sideA, sideB, 0, round) Then
					Continue
				End If
			Else
				If Not Pair(cfg, state, active, used, sideA, sideB, 0) Then
					Continue
				End If
			End If

			Local fixtures:TFixtureState[]
			For Local plannedFixture:TFixtureState = EachIn plannedFixtures
				fixtures :+ [plannedFixture]
			Next

			For Local i:Int = 0 Until sideA.Length
				Local fixture:TFixtureState = New TFixtureState
				fixture.id = stage.id + "_R" + round + "_M" + (i + 1)
				fixture.round = round
				fixture.homeTeamId = sideA[i]
				fixture.awayTeamId = sideB[i]
				fixture.status = EFixtureStatus.Scheduled
				fixtures :+ [fixture]
			Next

			If byeIndex >= 0 Then
				Local bye:TFixtureState = New TFixtureState
				bye.id = stage.id + "_R" + round + "_BYE"
				bye.round = round
				bye.homeTeamId = ordered[byeIndex]
				bye.awayTeamId = 0
				bye.status = EFixtureStatus.Completed
				bye.swissUnplayedKind = ESwissUnplayedKind.PairingBye
				bye.swissAwardedUnits = SwissByeUnits(cfg)
				fixtures :+ [bye]
			End If

			Return fixtures
		Next

		If reachedLimit Then
			Throw "Swiss pairing search limit reached"
		End If

		Throw "No Swiss pairing satisfies the repeat and bye rules for round " + round
	End Method

	Method IsDutchStyle:Int(cfg:TSwissConfig)
		Return cfg.pairingPolicy <> Null And cfg.pairingPolicy.system = ESwissPairingSystem.DutchStyle
	End Method

	Method UnplayedCount:Int(state:TStageState, id:Int)
		Local count:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status <> EFixtureStatus.Completed Then
				Continue
			End If

			If fixture.homeTeamId <> id And fixture.awayTeamId <> id Then
				Continue
			End If

			If fixture.awayTeamId = 0 Or IsSwissForfeit(fixture) Then
				count :+ 1
			End If
		Next

		Return count
	End Method

	Method PairDutch:Int(comp:TCompetition, cfg:TSwissConfig, state:TStageState, ids:Int[], used:Int[], sideA:Int[], sideB:Int[], depth:Int, round:Int)
		If depth = sideA.Length Then
			Return True
		End If

		Local first:Int = -1
		For Local i:Int = 0 Until ids.Length
			If Not used[i] Then first = i; Exit
		Next

		Local choices:Int[]
		For Local i:Int = first + 1 Until ids.Length
			If Not used[i] Then
				choices :+ [i]
			End If
		Next

		Local ideal:Int = first + (ids.Length / 2)
		For Local i:Int = 0 Until choices.Length
			For Local j:Int = i + 1 Until choices.Length
				Local ai:Int = choices[i]
				Local bi:Int = choices[j]
				Local gapA:Int = Abs(Points(state, ids[first]) - Points(state, ids[ai]))
				Local gapB:Int = Abs(Points(state, ids[first]) - Points(state, ids[bi]))
				Local halfA:Int = ai < ids.Length / 2
				Local halfB:Int = bi < ids.Length / 2
				If gapB < gapA Or (gapB = gapA And halfB < halfA) Or (gapB = gapA And halfB = halfA And Abs(bi - ideal) < Abs(ai - ideal)) Then
					Local swap:Int = choices[i]
					choices[i] = choices[j]
					choices[j] = swap
				End If
			Next
		Next

		used[first] = True
		For Local second:Int = EachIn choices
			attempts :+ 1
			If cfg.maxRepeatPairAttempts > 0 And attempts > cfg.maxRepeatPairAttempts Then
				reachedLimit = True
				Exit
			End If

			If Played(state, ids[first], ids[second]) Then
				Continue
			End If

			If Not DutchColourCompatible(state, ids[first], ids[second], cfg, round) Then
				Continue
			End If

			used[second] = True
			Local home:Int = ids[first]
			Local away:Int = ids[second]
			If state.fixtures.Length = 0 Then
				Local tpn:Int = Seed(comp, ids[first])
				If (tpn Mod 2 = 1 And cfg.pairingPolicy.initialColour = -1) Or (tpn Mod 2 = 0 And cfg.pairingPolicy.initialColour = 1) Then
					home = ids[second]
					away = ids[first]
				End If
			ElseIf ColourCost(state, away, home) < ColourCost(state, home, away) Then
				home = ids[second]
				away = ids[first]
			End If

			sideA[depth] = home
			sideB[depth] = away
			If PairDutch(comp, cfg, state, ids, used, sideA, sideB, depth + 1, round) Then
				Return True
			End If

			used[second] = False
			If reachedLimit Then
				Exit
			End If
		Next

		used[first] = False
		Return False
	End Method

	Method DutchColourCompatible:Int(state:TStageState, a:Int, b:Int, cfg:TSwissConfig, round:Int)
		If round <> cfg.rounds Then
			Local pa:Int = AbsoluteColourPreference(state, a)
			Local pb:Int = AbsoluteColourPreference(state, b)
			If pa <> 0 And pa = pb Then
				Return False
			End If
		Else
			Local threshold:Int = SwissWinUnits(cfg) * (cfg.rounds - 1)
			Local pa:Int = AbsoluteColourPreference(state, a)
			Local pb:Int = AbsoluteColourPreference(state, b)
			If pa <> 0 And pa = pb And Points(state, a) * 2 <= threshold And Points(state, b) * 2 <= threshold Then
				Return False
			End If
		End If

		Return True
	End Method

	Method AbsoluteColourPreference:Int(state:TStageState, id:Int)
		Local balance:Int
		Local last:Int
		Local previous:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status <> EFixtureStatus.Completed Or fixture.awayTeamId = 0 Or IsSwissForfeit(fixture) Then
				Continue
			End If

			Local side:Int
			If fixture.homeTeamId = id Then
				side = 1
			End If

			If fixture.awayTeamId = id Then
				side = -1
			End If

			If side = 0 Then
				Continue
			End If

			balance :+ side
			previous = last
			last = side
		Next

		If balance > 1 Or (last = 1 And previous = 1) Then
			Return -1
		End If

		If balance < -1 Or (last = -1 And previous = -1) Then
			Return 1
		End If

		Return 0
	End Method

	Method PlanFor:TSwissPlannedUnplayed(cfg:TSwissConfig, id:Int, round:Int)
		Local withdrawal:TSwissPlannedUnplayed
		For Local planned:TSwissPlannedUnplayed = EachIn cfg.plannedUnplayed
			If planned.participantId = id And planned.round = round Then
				Return planned
			End If

			If planned.participantId = id And planned.kind = ESwissUnplayedKind.Withdrawal And planned.round < round Then
				withdrawal = planned
			End If
		Next

		Return withdrawal
	End Method

	Method Pair:Int(cfg:TSwissConfig, state:TStageState, ids:Int[], used:Int[], sideA:Int[], sideB:Int[], depth:Int)
		If depth = sideA.Length Then
			Return True
		End If

		Local first:Int = -1
		For Local i:Int = 0 Until ids.Length
			If Not used[i] Then first = i; Exit
		Next

		used[first] = True
		For Local second:Int = first + 1 Until ids.Length
			If used[second] Then
				Continue
			End If

			attempts :+ 1
			If cfg.maxRepeatPairAttempts > 0 And attempts > cfg.maxRepeatPairAttempts Then
				reachedLimit = True
				Exit
			End If

			If cfg.avoidRematches And Played(state, ids[first], ids[second]) Then
				Continue
			End If

			used[second] = True
			Local home:Int = ids[first]
			Local away:Int = ids[second]
			If cfg.colourBalance And ColourCost(state, away, home) < ColourCost(state, home, away) Then
				home = ids[second]
				away = ids[first]
			End If

			sideA[depth] = home
			sideB[depth] = away
			If Pair(cfg, state, ids, used, sideA, sideB, depth + 1) Then
				Return True
			End If

			used[second] = False
			If reachedLimit Then
				Exit
			End If
		Next

		used[first] = False
		Return False
	End Method

	Method Played:Int(state:TStageState, a:Int, b:Int)
		For Local fixture:TFixtureState = EachIn state.fixtures
			If (fixture.homeTeamId = a And fixture.awayTeamId = b) Or (fixture.homeTeamId = b And fixture.awayTeamId = a) Then
				Return True
			End If
		Next

		Return False
	End Method

	Method HasBye:Int(state:TStageState, id:Int, cfg:TSwissConfig)
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.homeTeamId = id And fixture.awayTeamId = 0 And fixture.swissUnplayedKind = ESwissUnplayedKind.PairingBye Then
				Return True
			End If

			If fixture.homeTeamId = id And fixture.awayTeamId = 0 And fixture.swissUnplayedKind = ESwissUnplayedKind.None Then
				Return True
			End If

			If fixture.awayTeamId = 0 And fixture.homeTeamId = id And fixture.swissAwardedUnits >= SwissWinUnits(cfg) Then
				Return True
			End If

			If IsSwissForfeit(fixture) And fixture.status = EFixtureStatus.Completed Then
				If fixture.homeTeamId = id And fixture.scoreHome > fixture.scoreAway Then
					Return True
				End If

				If fixture.awayTeamId = id And fixture.scoreAway > fixture.scoreHome Then
					Return True
				End If
			End If
		Next

		Return False
	End Method

	Method ColourCost:Int(state:TStageState, home:Int, away:Int)
		Return SideCost(state, home, 1) + SideCost(state, away, -1)
	End Method

	Method SideCost:Int(state:TStageState, id:Int, side:Int)
		Local balance:Int
		Local last:Int
		Local previous:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.awayTeamId = 0 Or fixture.status <> EFixtureStatus.Completed Or IsSwissForfeit(fixture) Then
				Continue
			End If

			Local current:Int
			If fixture.homeTeamId = id Then
				current = 1
			End If

			If fixture.awayTeamId = id Then
				current = -1
			End If

			If current = 0 Then
				Continue
			End If

			balance :+ current
			previous = last
			last = current
		Next

		Local cost:Int = Abs(balance + side)
		If last = side Then
			cost :+ 2
		End If

		If last = side And previous = side Then
			cost :+ 20
		End If

		Return cost
	End Method

	Method SortEntrants(comp:TCompetition, state:TStageState, ids:Int[])
		For Local i:Int = 0 Until ids.Length
			For Local j:Int = i + 1 Until ids.Length
				Local a:Int = ids[i]
				Local b:Int = ids[j]
				Local swap:Int = False
				If Points(state, b) > Points(state, a) Then
					swap = True
				ElseIf Points(state, b) = Points(state, a) Then
					If Seed(comp, b) < Seed(comp, a) Then
						swap = True
					End If

					If Seed(comp, b) = Seed(comp, a) And b < a Then
						swap = True
					End If
				End If

				If swap Then ids[i] = b; ids[j] = a
			Next
		Next
	End Method

	Method Points:Int(state:TStageState, id:Int)
		If state.leaderboard = Null Then
			Return 0
		End If

		For Local row:TLeaderboardRow = EachIn state.leaderboard.rows
			If row.participantId = id Then
				Return row.points
			End If
		Next

		Return 0
	End Method

	Method Seed:Int(comp:TCompetition, id:Int)
		For Local participant:TParticipant = EachIn comp.participants
			If participant.id = id Then
				If participant.seedRank > 0 Then
					Return participant.seedRank
				End If

				Return id
			End If
		Next

		Throw "Swiss entrant is missing: " + id
	End Method
End Type

Function SwissUnits:Int(points:Float, scale:Int)
	Local scaled:Float = points * Float(scale)
	Local value:Int = Int(scaled)
	If Abs(scaled - Float(value)) > 0.0001 Then
		Throw "Swiss points cannot be represented by pointsScale"
	End If

	Return value
End Function

Function SwissWinUnits:Int(cfg:TSwissConfig)
	If cfg.pointsWinExact <> "" Then
		Return ExactPointUnits(cfg.pointsWinExact, cfg.pointsScale)
	End If

	Return SwissUnits(cfg.pointsWin, cfg.pointsScale)
End Function

Function SwissDrawUnits:Int(cfg:TSwissConfig)
	If cfg.pointsDrawExact <> "" Then
		Return ExactPointUnits(cfg.pointsDrawExact, cfg.pointsScale)
	End If

	Return SwissUnits(cfg.pointsDraw, cfg.pointsScale)
End Function

Function SwissLossUnits:Int(cfg:TSwissConfig)
	If cfg.pointsLossExact <> "" Then
		Return ExactPointUnits(cfg.pointsLossExact, cfg.pointsScale)
	End If

	Return SwissUnits(cfg.pointsLoss, cfg.pointsScale)
End Function

Function SwissByeUnits:Int(cfg:TSwissConfig)
	If cfg.byePointsExact <> "" Then
		Return ExactPointUnits(cfg.byePointsExact, cfg.pointsScale)
	End If

	Return SwissUnits(cfg.byePoints, cfg.pointsScale)
End Function

Function SwissPlannedUnits:Int(planned:TSwissPlannedUnplayed, cfg:TSwissConfig)
	If planned.awardedPointsExact <> "" Then
		Return ExactPointUnits(planned.awardedPointsExact, cfg.pointsScale)
	End If

	Return SwissUnits(planned.awardedPoints, cfg.pointsScale)
End Function

Function IsSwissForfeit:Int(fixture:TFixtureState)
	If fixture.resultLog.Length = 0 Then
		Return False
	End If

	Return fixture.resultLog[fixture.resultLog.Length - 1].forfeit
End Function

Rem
bbdoc: Scores Swiss games and computes Buchholz standings.
End Rem
Type TSwissScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, state:TStageState, fixtureId:String, result:TResultPayload)
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		If result.kind <> EResultKind.HeadToHeadScore Then
			Throw "Swiss needs a head-to-head score"
		End If

		If result.forfeit And result.scoreHome = result.scoreAway Then
			Throw "Swiss forfeits require a winner"
		End If

		If Not cfg.allowDraws And result.scoreHome = result.scoreAway Then
			Throw "Swiss draws are disabled"
		End If

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.id <> fixtureId Then
				Continue
			End If

			If fixture.awayTeamId = 0 Then
				Throw "A Swiss pairing bye has no playable result"
			End If

			fixture.scoreHome = result.scoreHome
			fixture.scoreAway = result.scoreAway
			fixture.status = EFixtureStatus.Completed
			fixture.resultLog :+ [result]
			Return
		Next

		Throw "Unknown Swiss fixture: " + fixtureId
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TSwissConfig = TSwissConfig(stage.config)
		Local rows:TLeaderboardRow[]
		For Local id:Int = EachIn state.entrants
			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = id
			rows :+ [row]
		Next

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local home:TLeaderboardRow = Row(rows, fixture.homeTeamId)
			If home = Null Then
				Throw "Swiss fixture has an unknown entrant"
			End If

			If fixture.awayTeamId = 0 Then
				If fixture.swissUnplayedKind = ESwissUnplayedKind.None Then
					home.points :+ SwissByeUnits(cfg)
				Else
					home.points :+ fixture.swissAwardedUnits
				End If

				home.noResults :+ 1
				Continue
			End If

			Local away:TLeaderboardRow = Row(rows, fixture.awayTeamId)
			If away = Null Then
				Throw "Swiss fixture has an unknown entrant"
			End If

			home.gf :+ fixture.scoreHome
			home.ga :+ fixture.scoreAway
			away.gf :+ fixture.scoreAway
			away.ga :+ fixture.scoreHome
			If fixture.scoreHome > fixture.scoreAway Then
				home.points :+ SwissWinUnits(cfg)
				away.points :+ SwissLossUnits(cfg)
				home.wins :+ 1
				away.losses :+ 1
			ElseIf fixture.scoreHome < fixture.scoreAway Then
				away.points :+ SwissWinUnits(cfg)
				home.points :+ SwissLossUnits(cfg)
				away.wins :+ 1
				home.losses :+ 1
			Else
				home.points :+ SwissDrawUnits(cfg)
				away.points :+ SwissDrawUnits(cfg)
				home.draws :+ 1
				away.draws :+ 1
			End If
		Next

		For Local row:TLeaderboardRow = EachIn rows
			Local contributions:Int[]
			Local voluntary:Int[]
			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.status <> EFixtureStatus.Completed Then
					Continue
				End If

				If fixture.homeTeamId = row.participantId And fixture.awayTeamId = 0 Then
					contributions :+ [Min(row.points, SwissDrawUnits(cfg) * cfg.rounds)]
					voluntary :+ [fixture.swissUnplayedKind = ESwissUnplayedKind.RequestedBye Or fixture.swissUnplayedKind = ESwissUnplayedKind.Withdrawal]
				ElseIf fixture.homeTeamId = row.participantId Then
					Local opponent:TLeaderboardRow = Row(rows, fixture.awayTeamId)
					Local contribution:Int = AdjustedScore(rows, state.fixtures, opponent.participantId, cfg)
					If IsSwissForfeit(fixture) Then
						contribution = Min(row.points, contribution)
					End If

					contributions :+ [contribution]
					voluntary :+ [IsSwissForfeit(fixture) And fixture.scoreHome < fixture.scoreAway]
				ElseIf fixture.awayTeamId = row.participantId Then
					Local opponent:TLeaderboardRow = Row(rows, fixture.homeTeamId)
					Local contribution:Int = AdjustedScore(rows, state.fixtures, opponent.participantId, cfg)
					If IsSwissForfeit(fixture) Then
						contribution = Min(row.points, contribution)
					End If

					contributions :+ [contribution]
					voluntary :+ [IsSwissForfeit(fixture) And fixture.scoreAway < fixture.scoreHome]
				End If
			Next

			Local buchholz:Int
			Local lowest:Int = 2147483647
			Local lowestVoluntary:Int = 2147483647
			For Local i:Int = 0 Until contributions.Length
				Local contribution:Int = contributions[i]
				buchholz :+ contribution
				lowest = Min(lowest, contribution)
				If voluntary[i] Then
					lowestVoluntary = Min(lowestVoluntary, contribution)
				End If
			Next

			Local cut1:Int = buchholz
			If lowestVoluntary <> 2147483647 Then
				lowest = lowestVoluntary
			End If

			If contributions.Length > 0 Then
				cut1 :- lowest
			End If

			AddMetric(row, "buchholz", buchholz)
			AddMetric(row, "buchholzCut1", cut1)
		Next

		For Local i:Int = 0 Until rows.Length
			For Local j:Int = i + 1 Until rows.Length
				Local swapRows:Int = False
				If rows[j].points > rows[i].points Then
					swapRows = True
				ElseIf rows[j].points = rows[i].points Then
					Local decided:Int
					For Local rule:ESwissTieBreak = EachIn cfg.tiebreaks
						Local code:String = TieBreakCode(rule)
						Local left:Int = Metric(rows[i], code)
						Local right:Int = Metric(rows[j], code)
						If left = right Then
							Continue
						End If

						decided = True
						If right > left Then
							swapRows = True
						End If

						Exit
					Next

					If Not decided And rows[j].participantId < rows[i].participantId Then
						swapRows = True
					End If
				End If

				If swapRows Then
					Local swap:TLeaderboardRow = rows[i]
					rows[i] = rows[j]
					rows[j] = swap
				End If
			Next
		Next

		state.leaderboard.rows = rows
	End Method

	Method AdjustedScore:Int(rows:TLeaderboardRow[], fixtures:TFixtureState[], id:Int, cfg:TSwissConfig)
		Local score:Int = Row(rows, id).points
		Local drawUnits:Int = SwissDrawUnits(cfg)
		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.status <> EFixtureStatus.Completed Or fixture.homeTeamId <> id Or fixture.awayTeamId <> 0 Then
				Continue
			End If

			If fixture.swissUnplayedKind <> ESwissUnplayedKind.RequestedBye And fixture.swissUnplayedKind <> ESwissUnplayedKind.Withdrawal Then
				Continue
			End If

			Local laterNonVoluntary:Int
			For Local later:TFixtureState = EachIn fixtures
				If later.round <= fixture.round Or later.status <> EFixtureStatus.Completed Then
					Continue
				End If

				If later.homeTeamId <> id And later.awayTeamId <> id Then
					Continue
				End If

				If later.awayTeamId = 0 Then
					If later.swissUnplayedKind = ESwissUnplayedKind.RequestedBye Or later.swissUnplayedKind = ESwissUnplayedKind.Withdrawal Then
						Continue
					End If
				ElseIf IsSwissForfeit(later) Then
					If (later.homeTeamId = id And later.scoreHome < later.scoreAway) Or (later.awayTeamId = id And later.scoreAway < later.scoreHome) Then
						Continue
					End If
				End If

				laterNonVoluntary = True
				Exit
			Next

			If Not laterNonVoluntary Then
				score :+ drawUnits - fixture.swissAwardedUnits
			End If
		Next

		Return score
	End Method

	Method TieBreakCode:String(rule:ESwissTieBreak)
		Select rule
			Case ESwissTieBreak.Buchholz
				Return "buchholz"
			Case ESwissTieBreak.BuchholzCut1
				Return "buchholzCut1"
		End Select

		Throw "Unsupported Swiss tiebreak"
	End Method

	Method AddMetric(row:TLeaderboardRow, code:String, value:Int)
		Local metric:TLeaderboardMetric = New TLeaderboardMetric
		metric.code = code
		metric.value = value
		row.metrics :+ [metric]
	End Method

	Method Metric:Int(row:TLeaderboardRow, code:String)
		For Local metric:TLeaderboardMetric = EachIn row.metrics
			If metric.code = code Then
				Return metric.value
			End If
		Next

		Return 0
	End Method

	Method Row:TLeaderboardRow(rows:TLeaderboardRow[], id:Int)
		For Local row:TLeaderboardRow = EachIn rows
			If row.participantId = id Then
				Return row
			End If
		Next

		Return Null
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, state:TStageState) { asBool }
		Local rounds:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			rounds = Max(rounds, fixture.round)
			If fixture.status <> EFixtureStatus.Completed Then
				Return False
			End If
		Next

		Return rounds >= TSwissConfig(stage.config).rounds
	End Method
End Type
