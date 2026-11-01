' Timed heat qualification: automatic places in each heat, then fastest
' remaining entrants across all heats. A final is generated after all heats.
Rem
bbdoc: A timed entrant considered at a heat advancement cutoff.
End Rem
Type THeatCandidate
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Index of the heat for this heat candidate.
	End Rem
	Field heatIndex:Int
	Rem
	bbdoc: Place for this heat candidate.
	End Rem
	Field place:Int
	Rem
	bbdoc: Rank for this heat candidate.
	End Rem
	Field rank:Int
	Rem
	bbdoc: Millis for this heat candidate.
	End Rem
	Field millis:Long
	Rem
	bbdoc: Current status of this heat candidate.
	End Rem
	Field status:ETimeStatus
End Type

Rem
bbdoc: Generates heats, repechage rounds, and finals.
End Rem
Type THeatsScheduler Implements IStageScheduler, IProgressiveStageScheduler
	Method QualifyingRoundCount:Int(cfg:THeatsConfig)
		If cfg.qualifyingRounds <> Null And cfg.qualifyingRounds.Length > 0 Then
			Return cfg.qualifyingRounds.Length
		End If

		Return 1
	End Method

	Method RoundConfig:THeatRoundConfig(cfg:THeatsConfig, round:Int)
		If round < 1 Or round > QualifyingRoundCount(cfg) Then
			Throw "Unknown heats qualifying round"
		End If

		If cfg.qualifyingRounds <> Null And cfg.qualifyingRounds.Length > 0 Then
			Return cfg.qualifyingRounds[round - 1]
		End If

		Local rule:THeatRoundConfig = New THeatRoundConfig
		rule.heatCount = cfg.heatCount
		rule.automaticPlaces = cfg.automaticPlaces
		rule.fastestRemaining = cfg.fastestRemaining
		rule.cutoffTiePolicy = cfg.cutoffTiePolicy
		rule.repechage = cfg.repechage
		rule.lanes = cfg.lanes
		Return rule
	End Method

	Method AssignLanes(fixture:TFixtureState, policy:THeatLanePolicy)
		If policy = Null Then
			Return
		End If

		If policy.laneCount < 1 Then
			Throw "Heat lane count must be positive"
		End If

		If fixture.heatEntrants.Length > policy.laneCount Then
			Throw "Heat has more entrants than configured lanes"
		End If

		If policy.fixedAssignments <> Null And policy.fixedAssignments.Length > 0 Then
			Local used:Int[]
			For Local id:Int = EachIn fixture.heatEntrants
				Local selected:THeatLaneAssignment
				For Local assignment:THeatLaneAssignment = EachIn policy.fixedAssignments
					If assignment.participantId = id Then selected = assignment; Exit
				Next

				If selected = Null Then
					Throw "Fixed lane map omits a heat entrant"
				End If

				For Local prior:Int = EachIn used
					If prior = selected.lane Then
						Throw "Fixed lane map assigns a lane twice in one heat"
					End If
				Next

				used :+ [selected.lane]
				Local copy:THeatLaneAssignment = New THeatLaneAssignment
				copy.participantId = id
				copy.lane = selected.lane
				fixture.heatLanes :+ [copy]
			Next

			Return
		End If

		If policy.allocation = EHeatLaneAllocation.Random And policy.preference <> Null And policy.preference.Length > 0 Then
			Throw "Random lane draw cannot also specify a lane preference"
		End If

		Local preferred:Int[]
		If policy.preference <> Null And policy.preference.Length > 0 Then
			If policy.preference.Length <> policy.laneCount Then
				Throw "Heat lane preference must list every lane"
			End If

			For Local lane:Int = EachIn policy.preference
				If lane < 1 Or lane > policy.laneCount Then
					Throw "Heat lane preference is out of range"
				End If

				For Local previous:Int = EachIn preferred
					If previous = lane Then
						Throw "Heat lane preference contains a duplicate"
					End If
				Next

				preferred :+ [lane]
			Next
		Else
			For Local lane:Int = 1 To policy.laneCount
				preferred :+ [lane]
			Next
		End If

		If policy.allocation = EHeatLaneAllocation.Random Then
			' Derive a local stream from the configured seed and fixture identity.
			' This does not alter BlitzMax's global random state or earlier draws.
			Local draw:Long = policy.drawSeed
			If draw < 0 Then
				draw = -draw
			End If

			For Local i:Int = 0 Until fixture.id.Length
				draw = (draw * 31 + fixture.id[i]) Mod 2147483647:Long
			Next

			For Local i:Int = preferred.Length - 1 To 1 Step -1
				draw = (draw * 1103515245:Long + 12345) Mod 2147483647:Long
				Local j:Int = Int(draw Mod (i + 1))
				Local swap:Int = preferred[i]
				preferred[i] = preferred[j]
				preferred[j] = swap
			Next
		End If

		For Local i:Int = 0 Until fixture.heatEntrants.Length
			Local assignment:THeatLaneAssignment = New THeatLaneAssignment
			assignment.participantId = fixture.heatEntrants[i]
			assignment.lane = preferred[i]
			fixture.heatLanes :+ [assignment]
		Next
	End Method

	Method ValidateFixedLanes(fixtures:TFixtureState[], policy:THeatLanePolicy)
		If policy = Null Or policy.fixedAssignments = Null Or policy.fixedAssignments.Length = 0 Then
			Return
		End If

		If policy.allocation = EHeatLaneAllocation.Random Or (policy.preference <> Null And policy.preference.Length > 0) Then
			Throw "Fixed lanes cannot be combined with random or preferred lanes"
		End If

		Local entrants:Int[]
		For Local fixture:TFixtureState = EachIn fixtures
			For Local id:Int = EachIn fixture.heatEntrants
				entrants :+ [id]
			Next
		Next

		If policy.fixedAssignments.Length <> entrants.Length Then
			Throw "Fixed lane map must cover every round entrant"
		End If

		Local assigned:Int[]
		For Local assignment:THeatLaneAssignment = EachIn policy.fixedAssignments
			If assignment = Null Or assignment.lane < 1 Or assignment.lane > policy.laneCount Then
				Throw "Fixed lane is out of range"
			End If

			Local eligible:Int
			For Local id:Int = EachIn entrants
				If id = assignment.participantId Then eligible = True; Exit
			Next

			If Not eligible Then
				Throw "Fixed lane map contains an ineligible entrant"
			End If

			For Local prior:Int = EachIn assigned
				If prior = assignment.participantId Then
					Throw "Fixed lane map assigns an entrant twice"
				End If
			Next

			assigned :+ [assignment.participantId]
		Next
	End Method

	Method ValidateRound(rule:THeatRoundConfig, entrantCount:Int, repechage:Int = False)
		If rule = Null Or rule.heatCount < 1 Or (rule.heatCount < 2 And Not repechage) Or rule.automaticPlaces < 1 Or rule.fastestRemaining < 0 Then
			Throw "Invalid heats qualification configuration"
		End If

		If repechage And rule.repechage <> Null Then
			Throw "A repechage cannot contain another repechage"
		End If

		If entrantCount < rule.heatCount Then
			Throw "Heats need at least one entrant per heat"
		End If

		If rule.automaticPlaces * rule.heatCount + rule.fastestRemaining > entrantCount Then
			Throw "Heats qualification exceeds entrant count"
		End If
	End Method

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
		Local cfg:THeatsConfig = THeatsConfig(stage.config)
		If cfg = Null Then
			Throw "Heats stage needs THeatsConfig"
		End If

		If comp.participants = Null Then
			Throw "Heats need entrants"
		End If

		Local rule:THeatRoundConfig = RoundConfig(cfg, 1)
		ValidateRound(rule, comp.participants.Length)
		Local entrants:TParticipant[] = comp.participants[..]
		For Local i:Int = 0 Until entrants.Length
			For Local j:Int = i + 1 Until entrants.Length
				Local a:Int = entrants[i].seedRank
				Local b:Int = entrants[j].seedRank
				If a <= 0 Then
					a = entrants[i].id
				End If

				If b <= 0 Then
					b = entrants[j].id
				End If

				If b < a Or (b = a And entrants[j].id < entrants[i].id) Then
					Local swap:TParticipant = entrants[i]
					entrants[i] = entrants[j]
					entrants[j] = swap
				End If
			Next
		Next

		Local ids:Int[]
		For Local entrant:TParticipant = EachIn entrants
			ids :+ [entrant.id]
		Next

		Return AssignRound(stage, ids, 1, rule.heatCount, cfg.qualifyingRounds = Null Or cfg.qualifyingRounds.Length = 0, EHeatPhase.Main, 1, rule.lanes, rule.fixedGroups)
	End Method

	Method AssignRound:TFixtureState[](stage:TStage, ids:Int[], round:Int, heatCount:Int, legacyFirst:Int, phase:EHeatPhase, ruleIndex:Int, lanes:THeatLanePolicy, fixedGroups:THeatGroup[] = Null)
		Local fixtures:TFixtureState[] = New TFixtureState[heatCount]
		For Local h:Int = 0 Until heatCount
			Local fixture:TFixtureState = New TFixtureState
			If legacyFirst And round = 1 Then
				fixture.id = stage.id + "_HEAT_" + (h + 1)
			ElseIf phase = EHeatPhase.Repechage Then
				fixture.id = stage.id + "_R" + round + "_REP_" + (h + 1)
			Else
				fixture.id = stage.id + "_R" + round + "_HEAT_" + (h + 1)
			End If

			fixture.round = round
			fixture.heatPhase = phase
			fixture.heatRuleIndex = ruleIndex
			fixture.status = EFixtureStatus.Scheduled
			fixtures[h] = fixture
		Next

		If fixedGroups <> Null And fixedGroups.Length > 0 Then
			If fixedGroups.Length <> heatCount Then
				Throw "Fixed heat groups must match the heat count"
			End If

			Local assignedIds:Int[]
			For Local h:Int = 0 Until heatCount
				If fixedGroups[h] = Null Or fixedGroups[h].participantIds = Null Or fixedGroups[h].participantIds.Length = 0 Then
					Throw "Fixed heat group cannot be empty"
				End If

				For Local id:Int = EachIn fixedGroups[h].participantIds
					Local eligible:Int
					For Local candidate:Int = EachIn ids
						If candidate = id Then eligible = True; Exit
					Next

					If Not eligible Then
						Throw "Fixed heat group contains an ineligible entrant"
					End If

					For Local prior:Int = EachIn assignedIds
						If prior = id Then
							Throw "Fixed heat groups contain a duplicate entrant"
						End If
					Next

					assignedIds :+ [id]
					Local assigned:TFixtureState = fixtures[h]
					assigned.heatEntrants :+ [id]
				Next
			Next

			If assignedIds.Length <> ids.Length Then
				Throw "Fixed heat groups omit an eligible entrant"
			End If
		Else
			For Local i:Int = 0 Until ids.Length
				Local cycle:Int = i / heatCount
				Local position:Int = i Mod heatCount
				If cycle Mod 2 = 1 Then
					position = heatCount - 1 - position
				End If

				Local assigned:TFixtureState = fixtures[position]
				assigned.heatEntrants :+ [ids[i]]
			Next
		End If

		ValidateFixedLanes(fixtures, lanes)
		For Local fixture:TFixtureState = EachIn fixtures
			AssignLanes(fixture, lanes)
		Next

		Return fixtures
	End Method

	Method NextFixtures:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:THeatsConfig = THeatsConfig(stage.config)
		Local current:Int
		Local currentFixture:TFixtureState
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.round > current Then current = fixture.round; currentFixture = fixture
		Next

		If current = 0 Or currentFixture.heatPhase = EHeatPhase.Final Then
			Return Null
		End If

		Local count:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.round <> current Then
				Continue
			End If

			count :+ 1
			If fixture.status <> EFixtureStatus.Completed Then
				Return Null
			End If
		Next

		Local ruleIndex:Int = currentFixture.heatRuleIndex
		If ruleIndex = 0 Then
			ruleIndex = current
		End If

		Local rule:THeatRoundConfig = RoundConfig(cfg, ruleIndex)
		Local scorer:THeatsScorer = New THeatsScorer
		Local qualifiers:Int[]
		If currentFixture.heatPhase = EHeatPhase.Repechage Then
			If rule.repechage = Null Or count <> rule.repechage.heatCount Then
				Throw "Heats stage has an unexpected repechage"
			End If

			qualifiers = scorer.Qualifiers(state, rule, current - 1)
			Local recovered:Int[] = scorer.Qualifiers(state, rule.repechage, current)
			For Local id:Int = EachIn recovered
				If Not scorer.Contains(qualifiers, id) Then
					qualifiers :+ [id]
				End If
			Next
		Else
			If count <> rule.heatCount Then
				Throw "Heats stage has an unexpected number of heats"
			End If

			qualifiers = scorer.Qualifiers(state, rule, current)
			If rule.repechage <> Null Then
				Local eligible:Int[] = scorer.RepechageEntrants(state, current, qualifiers)
				If eligible.Length > 0 Then
					ValidateRound(rule.repechage, eligible.Length, True)
					Return AssignRound(stage, eligible, current + 1, rule.repechage.heatCount, False, EHeatPhase.Repechage, ruleIndex, rule.repechage.lanes, rule.repechage.fixedGroups)
				End If
			End If
		End If

		If ruleIndex < QualifyingRoundCount(cfg) Then
			Local nextRule:THeatRoundConfig = RoundConfig(cfg, ruleIndex + 1)
			ValidateRound(nextRule, qualifiers.Length)
			Return AssignRound(stage, qualifiers, current + 1, nextRule.heatCount, False, EHeatPhase.Main, ruleIndex + 1, nextRule.lanes, nextRule.fixedGroups)
		End If

		Local finalFixture:TFixtureState = New TFixtureState
		finalFixture.id = stage.id + "_FINAL"
		finalFixture.round = current + 1
		finalFixture.heatPhase = EHeatPhase.Final
		finalFixture.status = EFixtureStatus.Scheduled
		finalFixture.heatEntrants = qualifiers
		ValidateFixedLanes([finalFixture], cfg.finalLanes)
		AssignLanes(finalFixture, cfg.finalLanes)
		Return [finalFixture]
	End Method
End Type

Rem
bbdoc: Ranks timed heat results and determines qualifiers.
End Rem
Type THeatsScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, state:TStageState, fixtureId:String, result:TResultPayload)
		If result.kind <> EResultKind.TimeBased Then
			Throw "Heats need timed results"
		End If

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.id <> fixtureId Then
				Continue
			End If

			If result.times.Length <> fixture.heatEntrants.Length Then
				Throw "Timed heat result must cover every assigned entrant"
			End If

			Local finishers:Int
			Local placed:Int
			For Local time:TParticipantTime = EachIn result.times
				Local found:Int
				For Local id:Int = EachIn fixture.heatEntrants
					If id = time.participantId Then found = True; Exit
				Next

				If Not found Then
					Throw "Timed result includes an entrant from another heat"
				End If

				If time.millis < 0 Or time.penaltyMillis < 0 Then
					Throw "Timed heat values cannot be negative"
				End If

				If time.place < 0 Then
					Throw "Timed result place cannot be negative"
				End If

				If time.status = ETimeStatus.Finished Then
					finishers :+ 1
					If time.place > 0 Then
						placed :+ 1
					End If
				ElseIf time.place <> 0 Then
					Throw "A nonfinisher cannot have a timed place"
				End If
			Next

			If placed > 0 And placed <> finishers Then
				Throw "Official timed places must cover every finisher"
			End If

			If placed > 0 Then
				For Local a:TParticipantTime = EachIn result.times
					If a.status <> ETimeStatus.Finished Then
						Continue
					End If

					For Local b:TParticipantTime = EachIn result.times
						If b.status <> ETimeStatus.Finished Or a.participantId = b.participantId Then
							Continue
						End If

						Local aTime:Long = a.millis + a.penaltyMillis
						Local bTime:Long = b.millis + b.penaltyMillis
						If aTime < bTime And a.place >= b.place Then
							Throw "Official timed places conflict with times"
						End If

						If aTime > bTime And a.place <= b.place Then
							Throw "Official timed places conflict with times"
						End If

						If aTime = bTime And a.place = b.place Then
							Continue
						End If
					Next
				Next
			End If

			fixture.timeResults = result.times[..]
			fixture.status = EFixtureStatus.Completed
			fixture.resultLog :+ [result]
			Return
		Next

		Throw "Unknown heat fixture: " + fixtureId
	End Method

	Method Candidates:THeatCandidate[](state:TStageState, round:Int)
		Local candidates:THeatCandidate[]
		Local heatIndex:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.round <> round Or fixture.status <> EFixtureStatus.Completed Then
				Continue
			End If

			heatIndex :+ 1
			Local inHeat:THeatCandidate[]
			For Local time:TParticipantTime = EachIn fixture.timeResults
				Local candidate:THeatCandidate = New THeatCandidate
				candidate.participantId = time.participantId
				candidate.heatIndex = heatIndex
				candidate.place = time.place
				candidate.status = time.status
				candidate.millis = time.millis + time.penaltyMillis
				inHeat :+ [candidate]
			Next

			SortCandidates(inHeat)
			Local lastMillis:Long = -1
			Local lastRank:Int
			For Local i:Int = 0 Until inHeat.Length
				If inHeat[i].status = ETimeStatus.Finished Then
					If inHeat[i].millis <> lastMillis Then
						lastRank = i + 1
					End If

					If inHeat[i].place > 0 Then
						inHeat[i].rank = inHeat[i].place
					Else
						inHeat[i].rank = lastRank
					End If

					lastMillis = inHeat[i].millis
				End If

				candidates :+ [inHeat[i]]
			Next
		Next

		Return candidates
	End Method

	Method Qualifiers:Int[](state:TStageState, rule:THeatRoundConfig, round:Int)
		Local candidates:THeatCandidate[] = Candidates(state, round)
		Local automatic:Int[]
		Local remaining:THeatCandidate[]
		For Local candidate:THeatCandidate = EachIn candidates
			If candidate.status <> ETimeStatus.Finished Then
				Continue
			End If

			If candidate.rank <= rule.automaticPlaces Then
				automatic :+ [candidate.participantId]
			Else
				remaining :+ [candidate]
			End If
		Next

		SortCandidates(remaining)
		Local places:Int = rule.fastestRemaining - (automatic.Length - rule.automaticPlaces * rule.heatCount)
		places = Max(0, places)
		Local selected:Int[] = automatic[..]
		For Local i:Int = 0 Until Min(places, remaining.Length)
			selected :+ [remaining[i].participantId]
		Next

		If places > 0 And places < remaining.Length And remaining[places - 1].millis = remaining[places].millis Then
			If rule.cutoffTiePolicy = EHeatCutoffTiePolicy.RequireResolution Then
				Throw "Timed qualification has an unresolved cutoff tie"
			End If

			For Local i:Int = places Until remaining.Length
				If remaining[i].millis <> remaining[places - 1].millis Then
					Exit
				End If

				selected :+ [remaining[i].participantId]
			Next
		End If

		If selected.Length = 0 Then
			Throw "No heat entrant qualified for the final"
		End If

		Local ordered:THeatCandidate[]
		For Local candidate:THeatCandidate = EachIn candidates
			If Contains(selected, candidate.participantId) Then
				ordered :+ [candidate]
			End If
		Next

		SortCandidates(ordered)
		Local ids:Int[]
		For Local candidate:THeatCandidate = EachIn ordered
			ids :+ [candidate.participantId]
		Next

		Return ids
	End Method

	Method RepechageEntrants:Int[](state:TStageState, round:Int, direct:Int[])
		Local candidates:THeatCandidate[] = Candidates(state, round)
		SortCandidates(candidates)
		Local ids:Int[]
		For Local candidate:THeatCandidate = EachIn candidates
			If candidate.status = ETimeStatus.Finished And Not Contains(direct, candidate.participantId) Then
				ids :+ [candidate.participantId]
			End If
		Next

		Return ids
	End Method

	Method SortCandidates(candidates:THeatCandidate[])
		For Local i:Int = 0 Until candidates.Length
			For Local j:Int = i + 1 Until candidates.Length
				Local a:THeatCandidate = candidates[i]
				Local b:THeatCandidate = candidates[j]
				Local swap:Int
				If b.status.Ordinal() < a.status.Ordinal() Then
					swap = True
				ElseIf a.status = b.status Then
					If a.status = ETimeStatus.Finished Then
						If b.millis < a.millis Then
							swap = True
						ElseIf b.millis = a.millis Then
							If a.heatIndex = b.heatIndex And a.place > 0 And b.place > 0 And a.place <> b.place Then
								If b.place < a.place Then
									swap = True
								End If
							ElseIf b.participantId < a.participantId Then
								swap = True
							End If
						End If
					ElseIf b.participantId < a.participantId Then
						swap = True
					End If
				End If

				If swap Then candidates[i] = b; candidates[j] = a
			Next
		Next
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, state:TStageState)
		Local rows:TLeaderboardRow[]
		Local seen:Int[]
		Local lastRound:Int
		Local latest:TFixtureState
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.round > lastRound Then lastRound = fixture.round; latest = fixture
		Next

		If latest <> Null And latest.heatPhase = EHeatPhase.Repechage Then
			Local scheduler:THeatsScheduler = New THeatsScheduler
			Local rule:THeatRoundConfig = scheduler.RoundConfig(THeatsConfig(stage.config), latest.heatRuleIndex)
			Local direct:Int[] = Qualifiers(state, rule, lastRound - 1)
			For Local id:Int = EachIn direct
				Local row:TLeaderboardRow = New TLeaderboardRow
				row.participantId = id
				rows :+ [row]
				seen :+ [id]
			Next
		End If

		For Local round:Int = lastRound To 1 Step -1
			Local candidates:THeatCandidate[] = Candidates(state, round)
			SortCandidates(candidates)
			For Local candidate:THeatCandidate = EachIn candidates
				If Contains(seen, candidate.participantId) Then
					Continue
				End If

				Local row:TLeaderboardRow = New TLeaderboardRow
				row.participantId = candidate.participantId
				rows :+ [row]
				seen :+ [candidate.participantId]
			Next

			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.round <> round Or fixture.status = EFixtureStatus.Completed Then
					Continue
				End If

				For Local id:Int = EachIn fixture.heatEntrants
					If Contains(seen, id) Then
						Continue
					End If

					Local row:TLeaderboardRow = New TLeaderboardRow
					row.participantId = id
					rows :+ [row]
					seen :+ [id]
				Next
			Next
		Next

		For Local id:Int = EachIn state.entrants
			If Contains(seen, id) Then
				Continue
			End If

			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = id
			rows :+ [row]
		Next

		state.leaderboard.rows = rows
	End Method

	Method Contains:Int(ids:Int[], id:Int)
		For Local candidate:Int = EachIn ids
			If candidate = id Then
				Return True
			End If
		Next

		Return False
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, state:TStageState) { asBool }
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.heatPhase = EHeatPhase.Final Or fixture.id = stage.id + "_FINAL" Then
				Return fixture.status = EFixtureStatus.Completed
			End If
		Next

		Return False
	End Method
End Type
