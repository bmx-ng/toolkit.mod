Rem
bbdoc: Creates seeded, fixed, or random bracket fixtures and later rounds.
End Rem
Type TBracketScheduler Extends TEntrantsOrderer Implements IStageScheduler
	Rem
	bbdoc: Last bye positions values associated with this bracket scheduler.
	End Rem
	Field lastByePositions:Int[]
	Rem
	bbdoc: Last bye entrants values associated with this bracket scheduler.
	End Rem
	Field lastByeEntrants:Int[]

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
		lastByePositions = Null
		lastByeEntrants = Null

		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		If cfg = Null Then
			Return []
		End If

		If cfg.format = EBracketFormat.DoubleElim Or cfg.doubleElim <> Null Then
			Throw "Build double elimination with TEliminationTreeBuilder"
		End If

		If cfg.consolation <> EConsolation.None Then
			Throw "Build consolation matches with TEliminationTreeBuilder or explicit stages"
		End If

		EnsureStageInputDefaults(stage)

		Local policy:TSchedulePolicy = GetSchedulePolicy(stage)
		If policy.scheduleSeed <> 0 Then
			SeedRnd(policy.scheduleSeed)
		End If

		' --- legs safe default ---
		Local legs:Int = 1
		If cfg.matchFormat <> Null And cfg.matchFormat.legs > 0 Then
			legs = cfg.matchFormat.legs
		End If

		Local bestOf:Int = 0
		If cfg.matchFormat <> Null Then
			bestOf = cfg.matchFormat.bestOfMatches
		End If

		If bestOf > 1 Then
			If bestOf Mod 2 = 0 Then
				Throw "Best-of series needs an odd number of games"
			End If

			If legs <> 1 Or cfg.matchFormat.aggregateScores Then
				Throw "Best-of games and aggregate legs are separate match formats"
			End If
		End If

		' --- venue safe default ---
		Local venue:EVenue
		If cfg.policy <> Null And cfg.policy.venuePolicy <> Null Then
			venue = cfg.policy.venuePolicy.venueType
		Else
			' default heuristics: two-leg ties → TwoLegAggregate, otherwise HigherSeedHome
			If legs >= 2 Or (cfg.matchFormat <> Null And cfg.matchFormat.aggregateScores <> 0) Then
				venue = EVenue.TwoLegAggregate
			Else
				venue = EVenue.HigherSeedHome
			End If
		End If

		' 1) Order entrants by seeding policy (seed #1 first)
		Local ordered:Int[]
		If Not cfg.reseedEachRound And ContinuesBracket(comp, stage) Then
			For Local participant:TParticipant = EachIn comp.participants
				ordered :+ [participant.id]
			Next
		Else
			ordered = OrderEntrantsByPolicy(comp, stage)
		End If

		If ordered.Length > cfg.size Then
			Throw "Bracket size is smaller than its entrant count"
		End If

		If cfg.size < 2 Or (cfg.size & (cfg.size - 1)) <> 0 Then
			Throw "Bracket size must be a power of two"
		End If

		If ordered.Length < cfg.size / 2 Then
			Throw "Bracket has too many empty slots for this draw size"
		End If

		If cfg.byes > 0 And cfg.byes <> cfg.size - ordered.Length Then
			Throw "Bracket bye count differs from empty slots"
		End If

		' 2) Seeded slot order (e.g., [1,8,4,5,3,6,2,7] for size=8)
		Local seedSlots:Int[] = SeededBracketOrder(cfg.size)
		If Not cfg.reseedEachRound And ContinuesBracket(comp, stage) Then
			For Local i:Int = 0 Until cfg.size
				seedSlots[i] = i + 1
			Next
		End If

		' 3) Map seeds -> participant ids (ids[seed-1] = pid or 0 if bye)
		Local idsBySeed:Int[] = New Int[cfg.size]

		For Local s:Int = 1 To cfg.size
			If s <= ordered.Length Then
				idsBySeed[s - 1] = ordered[s - 1]
			Else
				idsBySeed[s - 1] = 0 ' bye / empty
			End If
		Next

		Local idsByPosition:Int[] = New Int[cfg.size]
		For Local pos:Int = 0 Until cfg.size
			idsByPosition[pos] = idsBySeed[seedSlots[pos] - 1]
		Next

		If stage.input.constraints.lockedSlots <> Null And stage.input.constraints.lockedSlots.Length > 0 Then
			idsByPosition = ApplyLockedSlots(ordered, seedSlots, stage.input.constraints.lockedSlots)
		End If

		' 4) First round fixtures only (QF for size=8). Later rounds get built after advancement.
		'Local legs:Int = Max(1, cfg.matchFormat.legs)
		Local out:TFixtureState[]

		For Local i:Int = 0 Until cfg.size / 2
			Local seedA:Int = seedSlots[i * 2]
			Local seedB:Int = seedSlots[i * 2 + 1]
			Local pidA:Int = idsByPosition[i * 2]
			Local pidB:Int = idsByPosition[i * 2 + 1]

			' Bye handling: if either side empty, no R1 fixture (seed with opponent=0 advances automatically)
			If pidA = 0 Or pidB = 0 Then
				If pidA <> 0 Or pidB <> 0 Then
					lastByePositions :+ [i + 1]
					lastByeEntrants :+ [Max(pidA, pidB)]
				End If

				Continue
			End If

			' Determine home/away for leg 1 (and possibly leg 2)
			Local home1:Int, away1:Int, home2:Int, away2:Int
			Select venue
				Case EVenue.HigherSeedHome
					' lower seed number = higher seed
					If GetRank(comp, pidA) < GetRank(comp, pidB) Then
						home1 = pidA
						away1 = pidB
					Else
						home1 = pidB
						away1 = pidA
					End If
					' leg 2 (if any): flip homes
					home2 = away1
					away2 = home1

				Case EVenue.TwoLegAggregate
					' conventional: leg1 host = first in pairing, leg2 host = second
					home1 = pidA
					away1 = pidB
					home2 = pidB
					away2 = pidA

				Default
					' neutral/rotation: keep deterministic order by seeds
					If GetRank(comp, pidA) < GetRank(comp, pidB) Then
						home1 = pidA
						away1 = pidB
					Else
						home1 = pidB
						away1 = pidA
					End If

					home2 = away1
					away2 = home1
			End Select

			If bestOf > 1 Then
				Local homeTemplate:THomeCourtSeries = Null
				If policy <> Null And policy.venuePolicy <> Null Then
					homeTemplate = policy.venuePolicy.seriesTemplate
				End If

				If homeTemplate <> Null And homeTemplate.bestOf > 0 And homeTemplate.bestOf <> bestOf Then
					Throw "Home pattern length differs from best-of series"
				End If

				For Local game:Int = 1 To bestOf
					Local higherHosts:Int = game Mod 2 = 1
					If homeTemplate <> Null And homeTemplate.pattern <> Null And homeTemplate.pattern.Length > 0 Then
						Local covered:Int = 0
						For Local block:Int = 0 Until homeTemplate.pattern.Length
							If homeTemplate.pattern[block] < 1 Then
								Throw "Home pattern blocks must be positive"
							End If

							covered :+ homeTemplate.pattern[block]
							If game <= covered Then higherHosts = block Mod 2 = 0; Exit
						Next

						If game > covered Then
							Throw "Home pattern is shorter than the series"
						End If
					End If

					Local gameFixture:TFixtureState = New TFixtureState
					gameFixture.id = stage.id + "_R1_M" + (i + 1) + "_G" + game
					gameFixture.round = 1
					gameFixture.leg = game
					gameFixture.bracketPosition = i + 1
					If higherHosts Then
						gameFixture.homeTeamId = home1
						gameFixture.awayTeamId = away1
					Else
						gameFixture.homeTeamId = away1
						gameFixture.awayTeamId = home1
					End If

					gameFixture.status = EFixtureStatus.Scheduled
					out :+ [gameFixture]
				Next

				Continue
			End If

			' Emit leg 1
			Local f1:TFixtureState = New TFixtureState
			f1.id = stage.id + "_R1_M" + (i + 1) + "_L1"
			f1.round = 1
			f1.leg = 1
			f1.bracketPosition = i + 1
			f1.homeTeamId = home1
			f1.awayTeamId = away1
			f1.status = EFixtureStatus.Scheduled
			out :+ [f1]

			' Emit leg 2 if needed
			If legs >= 2 Then
				Local f2:TFixtureState = New TFixtureState
				f2.id = stage.id + "_R1_M" + (i + 1) + "_L2"
				f2.round = 1
				f2.leg = 2
				f2.bracketPosition = i + 1
				f2.homeTeamId = home2
				f2.awayTeamId = away2
				f2.status = EFixtureStatus.Scheduled
				out :+ [f2]
			End If
		Next

		Return out
	End Method

	Method ApplyLockedSlots:Int[](ordered:Int[], seedSlots:Int[], locks:TPresetSlot[])
		Local slots:Int[] = New Int[seedSlots.Length]
		Local lockedIds:Int[]
		For Local placed:TPresetSlot = EachIn locks
			Local position:Int = Int(placed.slotId)
			If position < 1 Or position > slots.Length Or String(position) <> placed.slotId Then
				Throw "Bracket slot must be a numeric draw position"
			End If

			If Not Contains(ordered, placed.participantId) Then
				Throw "Locked bracket entrant is not in the stage"
			End If

			If slots[position - 1] <> 0 Or Contains(lockedIds, placed.participantId) Then
				Throw "Duplicate bracket slot or entrant"
			End If

			slots[position - 1] = placed.participantId
			lockedIds :+ [placed.participantId]
		Next

		For Local rank:Int = 0 Until ordered.Length
			Local pid:Int = ordered[rank]
			If Contains(lockedIds, pid) Then
				Continue
			End If

			Local preferred:Int = -1
			For Local pos:Int = 0 Until seedSlots.Length
				If seedSlots[pos] = rank + 1 Then preferred = pos; Exit
			Next

			If preferred >= 0 And slots[preferred] = 0 Then
				slots[preferred] = pid
			Else
				For Local pos:Int = 0 Until slots.Length
					If slots[pos] = 0 Then slots[pos] = pid; Exit
				Next
			End If
		Next

		Return slots
	End Method

	Method ContinuesBracket:Int(comp:TCompetition, stage:TStage)
		If stage.independent Then
			Return False
		End If

		Local sourceId:String = ""
		If stage.input <> Null Then
			If stage.input.fromStageIds <> Null And stage.input.fromStageIds.Length > 1 Then
				Return False
			End If

			If stage.input.fromStageId <> "" Then
				sourceId = stage.input.fromStageId
			ElseIf stage.input.fromStageIds <> Null And stage.input.fromStageIds.Length = 1 Then
				sourceId = stage.input.fromStageIds[0]
			End If
		End If

		If sourceId = "" Then
			For Local source:TStage = EachIn comp.stages
				For Local route:TAdvancement = EachIn source.advancement
					If route.toStageId = stage.id Then
						If sourceId <> "" Then
							Return False
						End If

						sourceId = source.id
					End If
				Next
			Next
		End If

		If sourceId = "" Then
			For Local i:Int = 1 Until comp.stages.Length
				If comp.stages[i].id = stage.id Then sourceId = comp.stages[i - 1].id; Exit
			Next
		End If

		If sourceId = "" Then
			Return False
		End If

		For Local source:TStage = EachIn comp.stages
			If source.id = sourceId Then
				Return source.stageType = EStageType.Bracket
			End If
		Next

		Return False
	End Method

	' Recursive standard seeded order: size=8 -> [1,8,4,5,3,6,2,7]
	Method SeededBracketOrder:Int[](n:Int)
		If n <= 1 Then
			Return [1]
		End If

		Local half:Int = n / 2
		Local prev:Int[] = SeededBracketOrder(half)
		Local out:Int[] = New Int[n]
		Local idx:Int = 0
		For Local i:Int = 0 Until prev.Length
			Local s:Int = prev[i]
			out[idx] = s
			idx :+ 1
			out[idx] = n - s + 1
			idx :+ 1
		Next

		Return out
	End Method

End Type

' -------- BRACKET SCORER --------
Rem
bbdoc: Applies match and series results to a bracket stage.
End Rem
Type TBracketScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload) Override
		If Not result Or (result.kind <> EResultKind.HeadToHeadScore And result.kind <> EResultKind.SetBased) Then
			Throw "BracketScorer: ApplyResult called with wrong result kind"
		End If

		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		Local mf:TMatchFormat = cfg.matchFormat
		Local recordedHome:Int = result.scoreHome
		Local recordedAway:Int = result.scoreAway
		Local winnerOverrideId:Int
		If result.kind = EResultKind.SetBased Then
			If mf = Null Or mf.setRules = Null Or Not mf.setRules.usesSets Then
				Throw "Set result needs set rules"
			End If

			If result.afterExtraTime Or result.penaltiesHome <> 0 Or result.penaltiesAway <> 0 Then
				Throw "Set results cannot include extra time or penalties"
			End If

			Local setScore:Int[]
			If result.retiredParticipantId <> 0 Then
				If mf.legs > 1 Then
					Throw "Set match retirement needs a single-leg tie"
				End If

				setScore = ResolveRetiredSetMatch(result.sets, mf.setRules)
			Else
				setScore = ResolveSetMatch(result.sets, mf.setRules)
			End If

			recordedHome = setScore[0]
			recordedAway = setScore[1]
		End If

		If mf <> Null And mf.bestOfMatches > 1 And recordedHome = recordedAway And result.penaltiesHome = result.penaltiesAway And result.retiredParticipantId = 0 Then
			Throw "A best-of game needs a winner"
		End If

		If result.penaltiesHome < 0 Or result.penaltiesAway < 0 Then
			Throw "Penalty scores cannot be negative"
		End If

		If result.afterExtraTime And (mf = Null Or mf.extraTimeMinutes <= 0) Then
			Throw "Extra time is not configured for this tie"
		End If

		If (result.penaltiesHome > 0 Or result.penaltiesAway > 0) And (mf = Null Or Not mf.penalties) Then
			Throw "Penalties are not configured for this tie"
		End If

		If result.penaltiesHome > 0 Or result.penaltiesAway > 0 Then
			If result.penaltiesHome = result.penaltiesAway Then
				Throw "Penalties require a winner"
			End If
		End If

		For Local f:TFixtureState = EachIn st.fixtures
			If f.id = fxId Then
				If result.retiredParticipantId <> 0 Then
					If result.kind <> EResultKind.SetBased Then
						Throw "Retirement requires a set result"
					End If

					If result.retiredParticipantId = f.homeTeamId Then
						winnerOverrideId = f.awayTeamId
					ElseIf result.retiredParticipantId = f.awayTeamId Then
						winnerOverrideId = f.homeTeamId
					Else
						Throw "Retired participant is not in the fixture"
					End If
				End If

				If mf <> Null And mf.bestOfMatches > 1 Then
					For Local earlier:TFixtureState = EachIn st.fixtures
						If earlier.bracketPosition = f.bracketPosition And earlier.leg < f.leg And earlier.status <> EFixtureStatus.Completed Then
							Throw "Best-of games must be recorded in order"
						End If
					Next
				End If

				If mf <> Null And mf.legs > 1 And f.leg < mf.legs And (result.penaltiesHome > 0 Or result.penaltiesAway > 0) Then
					Throw "Only the deciding leg may use penalties"
				End If

				f.scoreHome = recordedHome
				f.scoreAway = recordedAway
				f.retiredParticipantId = result.retiredParticipantId
				f.winnerOverrideId = winnerOverrideId
				f.afterExtraTime = result.afterExtraTime
				f.penaltiesHome = result.penaltiesHome
				f.penaltiesAway = result.penaltiesAway
				f.status = EFixtureStatus.Completed
				Local pair:TFixtureState[]
				Local completed:TFixtureState[]
				For Local other:TFixtureState = EachIn st.fixtures
					If other.bracketPosition = f.bracketPosition Then
						pair :+ [other]
						If other.status = EFixtureStatus.Completed Then
							completed :+ [other]
						End If
					End If
				Next

				Local resolver:TBracketAdvancer = New TBracketAdvancer
				If result.penaltiesHome > 0 Or result.penaltiesAway > 0 Then
					f.penaltiesHome = 0
					f.penaltiesAway = 0
					Local scoreWinner:Int = resolver.ComputePairWinner(cfg, completed)
					f.penaltiesHome = result.penaltiesHome
					f.penaltiesAway = result.penaltiesAway
					If scoreWinner <> 0 Then
						f.status = EFixtureStatus.Scheduled
						f.scoreHome = 0
						f.scoreAway = 0
						f.afterExtraTime = False
						f.penaltiesHome = 0
						f.penaltiesAway = 0
						Throw "Shootout is unnecessary because the tie already has a winner"
					End If
				End If

				Local winner:Int = resolver.ComputePairWinner(cfg, completed)
				Local allPlayed:Int = True
				For Local other:TFixtureState = EachIn pair
					If other.status = EFixtureStatus.Scheduled Then allPlayed = False; Exit
				Next

				If winner = 0 And allPlayed Then
					f.status = EFixtureStatus.Scheduled
					f.scoreHome = 0
					f.scoreAway = 0
					f.afterExtraTime = False
					f.penaltiesHome = 0
					f.penaltiesAway = 0
					Throw "Knockout result leaves the tie without a winner"
				End If

				If winner <> 0 And mf <> Null And mf.bestOfMatches > 1 Then
					For Local other:TFixtureState = EachIn pair
						If other.status = EFixtureStatus.Scheduled Then
							other.status = EFixtureStatus.Cancelled
						End If
					Next
				End If

				f.resultLog :+ [result]
				If result.kind = EResultKind.SetBased Then
					f.setResults = result.sets[..]
				End If

				Exit
			End If
		Next
	End Method

	Method ResolveSetMatch:Int[](sets:TSetScore[], rules:TSetRules)
		If rules.setsBestOf < 1 Or rules.setsBestOf Mod 2 = 0 Then
			Throw "Set match needs an odd setsBestOf"
		End If

		If sets = Null Or sets.Length = 0 Or sets.Length > rules.setsBestOf Then
			Throw "Invalid set count"
		End If

		Local needed:Int = rules.setsBestOf / 2 + 1
		Local home:Int = 0, away:Int = 0
		For Local i:Int = 0 Until sets.Length
			Local setScore:TSetScore = sets[i]
			If setScore = Null Or setScore.home < 0 Or setScore.away < 0 Or setScore.home = setScore.away Then
				Throw "A completed set needs a winner"
			End If

			If rules.gamesPerSetTarget > 0 Then
				Local high:Int = Max(setScore.home, setScore.away)
				Local low:Int = Min(setScore.home, setScore.away)
				If high < rules.gamesPerSetTarget Then
					Throw "Set ended before its game target"
				End If

				Local margin:Int = Max(1, rules.gamesMargin)
				If high - low < margin And Not (rules.tiebreakAtGames > 0 And low = rules.tiebreakAtGames And high = low + 1) Then
					Throw "Set does not meet its game margin"
				End If
			End If

			If setScore.home > setScore.away Then home :+ 1 Else away :+ 1

			If i < sets.Length - 1 And (home = needed Or away = needed) Then
				Throw "Sets continue after the match was won"
			End If
		Next

		If home < needed And away < needed Then
			Throw "Set match has no winner yet"
		End If

		Return [home, away]
	End Method

	Method ResolveRetiredSetMatch:Int[](sets:TSetScore[], rules:TSetRules)
		If rules.setsBestOf < 1 Or rules.setsBestOf Mod 2 = 0 Then
			Throw "Set match needs an odd setsBestOf"
		End If

		If sets = Null Or sets.Length = 0 Or sets.Length > rules.setsBestOf Then
			Throw "Invalid set count"
		End If

		Local needed:Int = rules.setsBestOf / 2 + 1
		Local home:Int, away:Int
		For Local i:Int = 0 Until sets.Length
			Local setScore:TSetScore = sets[i]
			If setScore = Null Or setScore.home < 0 Or setScore.away < 0 Then
				Throw "Set games cannot be negative"
			End If

			Local high:Int = Max(setScore.home, setScore.away)
			Local low:Int = Min(setScore.home, setScore.away)
			Local completed:Int = setScore.home <> setScore.away
			If rules.gamesPerSetTarget > 0 Then
				completed = completed And high >= rules.gamesPerSetTarget
				completed = completed And (high - low >= Max(1, rules.gamesMargin) Or (rules.tiebreakAtGames > 0 And low = rules.tiebreakAtGames And high = low + 1))
			End If

			If Not completed And i < sets.Length - 1 Then
				Throw "Only the last set may be unfinished"
			End If

			If completed Then
				If setScore.home > setScore.away Then home :+ 1 Else away :+ 1
			End If

			If home >= needed Or away >= needed Then
				Throw "Retirement cannot follow a decided match"
			End If
		Next

		Return [home, away]
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState)
		Local rows:TLeaderboardRow[]
		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		Local resolver:TBracketAdvancer = New TBracketAdvancer
		For Local position:Int = 1 To cfg.size / 2
			Local pair:TFixtureState[]
			For Local f:TFixtureState = EachIn st.fixtures
				If f.bracketPosition = position And f.status = EFixtureStatus.Completed Then
					pair :+ [f]
				End If
			Next

			If pair = Null Or pair.Length = 0 Then
				Continue
			End If

			Local winner:Int = resolver.ComputePairWinner(cfg, pair)
			If winner = 0 Then
				Continue
			End If

			Local winnerRow:TLeaderboardRow = New TLeaderboardRow
			winnerRow.participantId = winner
			winnerRow.points = 1
			rows :+ [winnerRow]
			Local loserRow:TLeaderboardRow = New TLeaderboardRow
			loserRow.participantId = pair[0].homeTeamId
			If loserRow.participantId = winner Then
				loserRow.participantId = pair[0].awayTeamId
			End If

			rows :+ [loserRow]
		Next

		st.leaderboard.rows = rows
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState) { asBool }
		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		Local resolver:TBracketAdvancer = New TBracketAdvancer
		Return resolver.DetermineWinners(comp, stage, st, 1).Length = cfg.size / 2
	End Method
End Type

' -------- BRACKET ADVANCER --------
Rem
bbdoc: Selects bracket winners, losers, or placements for downstream routes.
End Rem
Type TBracketAdvancer Extends TEntrantsOrderer Implements IStageAdvancer
	Method ProduceAdvancements:TParticipant[](comp:TCompetition, stage:TStage, st:TStageState)
		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		If cfg = Null Then
			Return []
		End If

		If stage.advancement <> Null And stage.advancement.Length > 0 And stage.advancement[0].outcome = EAdvancementOutcome.AllEntrants Then
			Local entrants:TParticipant[]
			For Local pid:Int = EachIn st.entrants
				For Local participant:TParticipant = EachIn comp.participants
					If participant.id = pid Then entrants :+ [participant]; Exit
				Next
			Next

			Return entrants
		End If

		' Determine which round is the latest fully completed one
		Local maxRound:Int = 0
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status = EFixtureStatus.Completed And f.round > maxRound Then
				maxRound = f.round
			End If
		Next

		If maxRound = 0 And st.bracketByeEntrants <> Null And st.bracketByeEntrants.Length > 0 Then
			maxRound = 1
		End If

		If maxRound = 0 Then
			Return []
		End If

		Local selectedIds:Int[]
		If stage.advancement <> Null And stage.advancement.Length > 0 And stage.advancement[0].outcome = EAdvancementOutcome.Loser Then
			selectedIds = DetermineLosers(stage, st, maxRound)
		Else
			selectedIds = DetermineWinners(comp, stage, st, maxRound)
		End If

		If selectedIds.Length = 0 Then
			Return []
		End If

		' Map IDs back to TParticipant objects
		Local winners:TParticipant[]
		For Local pid:Int = EachIn selectedIds
			For Local p:TParticipant = EachIn comp.participants
				If p.id = pid Then
					winners :+ [p]
					Exit
				End If
			Next
		Next

		Return winners
	End Method

	Method DetermineLosers:Int[](stage:TStage, st:TStageState, roundNum:Int)
		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		Local losers:Int[]
		For Local position:Int = 1 To cfg.size / 2
			Local pair:TFixtureState[]
			For Local fixture:TFixtureState = EachIn st.fixtures
				If fixture.round = roundNum And fixture.bracketPosition = position And fixture.status = EFixtureStatus.Completed Then
					pair :+ [fixture]
				End If
			Next

			If pair = Null Or pair.Length = 0 Then
				Continue
			End If

			Local winner:Int = ComputePairWinner(cfg, pair)
			If winner = 0 Then
				Continue
			End If

			Local loser:Int = pair[0].homeTeamId
			If loser = winner Then
				loser = pair[0].awayTeamId
			End If

			losers :+ [loser]
		Next

		Return losers
	End Method

	' Determine winners for a given round (single-leg or 2-leg aggregate)
	Method DetermineWinners:Int[](comp:TCompetition, stage:TStage, st:TStageState, roundNum:Int)
		Local cfg:TBracketConfig = TBracketConfig(stage.config)
		Local winners:Int[]
		Local maxPosition:Int = 0
		For Local f:TFixtureState = EachIn st.fixtures
			If f.round = roundNum Then
				maxPosition = Max(maxPosition, f.bracketPosition)
			End If
		Next

		If roundNum = 1 Then
			For Local pos:Int = EachIn st.bracketByePositions
				maxPosition = Max(maxPosition, pos)
			Next
		End If

		If maxPosition > 0 Then
			For Local pos:Int = 1 To maxPosition
				Local byeId:Int = 0
				If roundNum = 1 And st.bracketByePositions <> Null Then
					For Local i:Int = 0 Until st.bracketByePositions.Length
						If st.bracketByePositions[i] = pos Then byeId = st.bracketByeEntrants[i]; Exit
					Next
				End If

				If byeId <> 0 Then
					winners :+ [byeId]
					Continue
				End If

				Local pairFixtures:TFixtureState[]
				For Local f:TFixtureState = EachIn st.fixtures
					If f.round = roundNum And f.bracketPosition = pos And f.status = EFixtureStatus.Completed Then
						pairFixtures :+ [f]
					End If
				Next

				If pairFixtures <> Null And pairFixtures.Length > 0 Then
					Local winner:Int = ComputePairWinner(cfg, pairFixtures)
					If winner <> 0 Then
						winners :+ [winner]
					End If
				End If
			Next

			Return winners
		End If

		' group fixtures by pairing key (unordered) and leg within the target round
		Local pairs:TMap = New TMap ' key: "a-b" (min-max) -> TFixtureState[]
		For Local f:TFixtureState = EachIn st.fixtures
			If f.round <> roundNum Or f.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local a:Int = Min(f.homeTeamId, f.awayTeamId)
			Local b:Int = Max(f.homeTeamId, f.awayTeamId)
			Local key:String = a + "-" + b
			Local arr:TList = TList(pairs.ValueForKey(key))
			If arr = Null Then
				arr = New TList
				pairs.Insert(key, arr)
			End If

			arr.AddLast(f)
		Next

		' compute winner per pair
		For Local it:String = EachIn pairs.Keys()
			Local key:String = it
			Local arr:TList = TList(pairs.ValueForKey(key))
			Local fx:TFixtureState[]
			fx = fx[..0]
			For Local f:TFixtureState = EachIn arr
				fx :+ [TFixtureState(f)]
			Next

			Local winner:Int = ComputePairWinner(cfg, fx)

			If winner <> 0 Then
				winners :+ [winner]
			End If
		Next

		Return winners
	End Method

	' Returns winner participantId, or 0 if still tied / undecided.
	Method ComputePairWinner:Int(cfg:TBracketConfig, fx:TFixtureState[])
		' Sanity: need at least the configured number of legs
		Local legs:Int = 1
		If cfg.matchFormat <> Null And cfg.matchFormat.legs > 0 Then
			legs = cfg.matchFormat.legs
		End If

		If cfg.matchFormat <> Null And cfg.matchFormat.bestOfMatches > 1 Then
			Local targetWins:Int = cfg.matchFormat.bestOfMatches / 2 + 1
			Local first:Int = 0, second:Int = 0
			If fx = Null Or fx.Length = 0 Then
				Return 0
			End If

			Local firstId:Int = fx[0].homeTeamId
			Local secondId:Int = fx[0].awayTeamId
			For Local game:TFixtureState = EachIn fx
				Local gameWinner:Int = FixtureWinner(game, cfg.matchFormat)
				If gameWinner = firstId Then
					first :+ 1
				End If

				If gameWinner = secondId Then
					second :+ 1
				End If
			Next

			If first >= targetWins Then
				Return firstId
			End If

			If second >= targetWins Then
				Return secondId
			End If

			Return 0
		End If

		If fx = Null Or fx.Length < legs Then
			Return 0
		End If

		If legs = 1 And fx[0].winnerOverrideId <> 0 Then
			Return fx[0].winnerOverrideId
		End If

		' Identify the two participants from the fixtures (robust to leg order)
		Local teamIds:Int[]
		For Local f:TFixtureState = EachIn fx
			If Not Contains(teamIds, f.homeTeamId) Then
				teamIds :+ [f.homeTeamId]
			End If

			If Not Contains(teamIds, f.awayTeamId) Then
				teamIds :+ [f.awayTeamId]
			End If
		Next

		If teamIds.Length <> 2 Then
			Return 0 ' malformed tie
		End If

		Local tA:Int = teamIds[0]
		Local tB:Int = teamIds[1]

		' Aggregate goals and away goals per team
		Local aggA:Int = 0
		Local aggB:Int = 0
		Local awayA:Int = 0
		Local awayB:Int = 0

		For Local f:TFixtureState = EachIn fx
			' goals for A/B in this leg
			Local gA:Int = 0, gB:Int = 0
			If f.homeTeamId = tA Then
				gA = f.scoreHome
				gB = f.scoreAway
				' B is away here
				awayB :+ f.scoreAway
			ElseIf f.awayTeamId = tA Then
				gA = f.scoreAway
				gB = f.scoreHome
				' A is away here
				awayA :+ f.scoreAway
			Else
				' Unexpected: leg without one of the teams; skip
				Continue
			End If

			aggA :+ gA
			aggB :+ gB
		Next

		' Decide by aggregate
		If aggA > aggB Then
			Return tA
		End If

		If aggB > aggA Then
			Return tB
		End If

		' Away goals (if enabled)
		If legs > 1 And cfg.matchFormat <> Null And cfg.matchFormat.awayGoalsRule Then
			If awayA > awayB Then
				Return tA
			End If

			If awayB > awayA Then
				Return tB
			End If
		End If

		' A shootout resolves an otherwise tied aggregate or single match.
		If cfg.matchFormat <> Null And cfg.matchFormat.penalties Then
			For Local f:TFixtureState = EachIn fx
				If f.leg <> legs Then
					Continue
				End If

				If f.penaltiesHome > f.penaltiesAway Then
					Return f.homeTeamId
				End If

				If f.penaltiesAway > f.penaltiesHome Then
					Return f.awayTeamId
				End If
			Next
		End If

		Return 0
	End Method

	Method FixtureWinner:Int(f:TFixtureState, mf:TMatchFormat)
		If f.winnerOverrideId <> 0 Then
			Return f.winnerOverrideId
		End If

		If f.scoreHome > f.scoreAway Then
			Return f.homeTeamId
		End If

		If f.scoreAway > f.scoreHome Then
			Return f.awayTeamId
		End If

		If mf <> Null And mf.penalties Then
			If f.penaltiesHome > f.penaltiesAway Then
				Return f.homeTeamId
			End If

			If f.penaltiesAway > f.penaltiesHome Then
				Return f.awayTeamId
			End If
		End If

		Return 0
	End Method

	Method Contains:Int(arr:Int[], v:Int) {asBool}
		For Local x:Int = EachIn arr
			If x = v Then
				Return True
			End If
		Next

		Return False
	End Method
End Type

' ----- Bracket helpers -----

' Return seeded order array of teamIds (1 best) from entrants already in seed order.
Rem
bbdoc: Extracts participant IDs from entrants already ordered by seed.
param: Entrants in seed order, best first.
returns: Participant IDs in the same order.
End Rem
Function SeededIds:Int[](entrants:TParticipant[])
	Local ids:Int[]
	For Local p:TParticipant = EachIn entrants
		ids :+ [p.id]
	Next

	Return ids
End Function

' Pair highest vs lowest, next highest vs next lowest, etc.
Rem
bbdoc: Pairs the highest remaining seed with the lowest.
param: Participant IDs in seed order, best first.
returns: Two-ID pairs from opposite ends of the input order.
End Rem
Function PairHighLow:Int[][](ids:Int[])
	Local out:Int[][]
	Local L:Int = 0, R:Int = ids.Length - 1
	While L < R
		out :+ [[ids[L], ids[R]]]
		L :+ 1
		R :- 1
	Wend

	Return out
End Function

' Basic seeded fixed bracket mapping for a power-of-two field (1v16, 8v9, 5v12, 4v13, ...)
Rem
bbdoc: Places seeded entrants in fixed first-round bracket pairs.
param: Participant IDs in best-to-worst seed order for a power-of-two field.
returns: First-round two-ID pairs in bracket order.
End Rem
Function FixedBracketPairs:Int[][](ids:Int[])
	Local n:Int = ids.Length
	If n <= 2 Then
		Return [[ids[0], ids[1]]]
	End If
	' standard pattern: use induction
	Local half:Int = n / 2
	Local prev:Int[] = [1] ' seed numbers; we’ll expand numerically then map to ids
	While prev.Length < half
		Local nextSeeds:Int[] = []
		For Local s:Int = EachIn prev
			nextSeeds :+ [s, (n + 1 - s)]
		Next

		prev = nextSeeds
		n :* 0 ' prevent accidental use
	Wend
	' Remap to ids[]
	' ids[] already ordered by seed: ids[0] = seed #1, ids[1] = seed #2 ...
	Local pairs:Int[][]
	For Local i:Int = 0 Until prev.Length Step 2
		Local aSeed:Int = prev[i]
		Local bSeed:Int = prev[i + 1]
		pairs :+ [[ ids[aSeed - 1], ids[bSeed - 1] ]]
	Next

	Return pairs
End Function

Rem
bbdoc: Resolves a two-leg tie by aggregate, optional away goals, then penalties.
param: First leg with home and away teams.
param: Return leg with reversed home and away teams.
param: Match format controlling the away-goals rule.
returns: Winning participant ID, or zero while the tie remains unresolved.
End Rem
Function ResolveTwoLegWinner:Int(leg1:TLeg, leg2:TLeg, mf:TMatchFormat)
	Local teamA:Int = leg1.homeId
	Local teamB:Int = leg1.awayId
	Local aggA:Int = leg1.home + leg2.away
	Local aggB:Int = leg1.away + leg2.home
	If aggA > aggB Then
		Return teamA
	End If

	If aggB > aggA Then
		Return teamB
	End If

	If mf.awayGoalsRule Then
		Local Aaway:Int = leg2.away
		Local Baway:Int = leg1.away
		If Aaway > Baway Then
			Return teamA
		End If

		If Baway > Aaway Then
			Return teamB
		End If
	End If
	' Still tied -> use penalties in leg2 if provided
	If leg2.pensHome > leg2.pensAway Then
		Return leg2.homeId
	End If

	If leg2.pensAway > leg2.pensHome Then
		Return leg2.awayId
	End If

	Return 0
End Function

' -------- SERIES SCHEDULER --------
