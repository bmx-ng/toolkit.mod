Rem
bbdoc: Schedules round-robin groups and applies draw constraints.
End Rem
Type TGroupScheduler Extends TEntrantsOrderer Implements IStageScheduler
	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)

		Local cfg:TGroupConfig = TGroupConfig(stage.config)
		EnsureStageInputDefaults(stage)

		Local policy:TSchedulePolicy = GetSchedulePolicy(stage)
		If policy.scheduleSeed <> 0 Then
			SeedRnd(policy.scheduleSeed)
		End If

		Local groups:Int[][]
		Local groupCodes:String[]
		If cfg.presetGroups <> Null And cfg.presetGroups.Length > 0 Then
			If cfg.groups > 0 And cfg.groups <> cfg.presetGroups.Length Then
				Throw "Preset group count differs from group configuration"
			End If

			Local seen:Int[]
			For Local preset:TPresetGroup = EachIn cfg.presetGroups
				If preset = Null Or preset.code = "" Then
					Throw "Preset group needs a code"
				End If

				For Local code:String = EachIn groupCodes
					If code = preset.code Then
						Throw "Duplicate preset group code: " + code
					End If
				Next

				If preset.participantIds = Null Or preset.participantIds.Length < 2 Then
					Throw "Preset group needs at least two entrants: " + preset.code
				End If

				If cfg.groupSize > 0 And preset.participantIds.Length <> cfg.groupSize Then
					Throw "Preset group size differs from configuration: " + preset.code
				End If

				For Local id:Int = EachIn preset.participantIds
					Local found:Int
					For Local participant:TParticipant = EachIn comp.participants
						If participant.id = id Then found = True; Exit
					Next

					If Not found Then
						Throw "Unknown preset group entrant: " + id
					End If

					For Local used:Int = EachIn seen
						If used = id Then
							Throw "Duplicate preset group entrant: " + id
						End If
					Next

					seen :+ [id]
				Next

				groups :+ [preset.participantIds[..]]
				groupCodes :+ [preset.code]
			Next

			If seen.Length <> comp.participants.Length Then
				Throw "Preset groups must include every entrant once"
			End If
		Else
			' Draw entrants when no membership has already been published.
			Local ordered:Int[] = OrderEntrantsByPolicy(comp, stage)
			Local sizes:Int[] = ComputeGroupSizes(ordered.Length, cfg.groups, cfg.groupSize, cfg.groupSizes)
			Local idxData:TDrawIndex = BuildDrawIndex(comp.participants, stage.input.constraints.avoidPairs)
			groups = PlaceWithConstraints(comp, ordered, sizes, stage.input.constraints, idxData)
		End If

		' 4) generate fixtures per group (round-robin, single or double)
		Local out:TFixtureState[]
		For Local gi:Int = 0 Until groups.Length
			Local gid:String = "G" + (gi + 1)
			If groupCodes <> Null Then
				gid = groupCodes[gi]
			End If

			Local teamIds:Int[] = groups[gi]
			If teamIds.Length <= 1 Then
				Continue
			End If

			Local base:TFixture[] = GenerateRoundRobinFixturesN(stage.id + "_" + gid, teamIds, cfg.roundRobinPerOpponent, 1)

			' Apply venue balancing on TFixture[] BEFORE minting TFixtureState
			Local pol:TSchedulePolicy = GetSchedulePolicy(stage)
			If pol <> Null And pol.venuePolicy <> Null And pol.venuePolicy.venueType = EVenue.HomeAway Then
				BalanceVenueStreaks_Fixture(base, pol.maxConsecHome, pol.maxConsecAway, cfg.roundRobinPerOpponent)
			End If

			For Local f:TFixture = EachIn base
				Local s:TFixtureState = New TFixtureState
				s.id = stage.id + "_" + gid + "_R" + f.round + "_" + f.homeTeamId + "v" + f.awayTeamId
				s.round = f.round
				s.leg = f.leg
				s.homeTeamId = f.homeTeamId
				s.awayTeamId = f.awayTeamId
				s.status = EFixtureStatus.Scheduled
				s.scoreHome = 0
				s.scoreAway = 0
				s.groupKey = gid
				out :+ [s]
			Next
		Next

		Return out
	End Method

	Method ComputeGroupSizes:Int[](nEntrants:Int, explicitGroups:Int, targetSize:Int, preComputedSizes:Int[] = Null)
		' pre-computed sizes override everything
		If preComputedSizes <> Null And preComputedSizes.Length > 0 Then
			Return preComputedSizes[..] ' copy
		End If

		Local g:Int
		If explicitGroups > 0 Then
			g = Min(explicitGroups, nEntrants)
		Else
			Local tgt:Int
			If targetSize <= 0 Then
				tgt = 8
			Else
				tgt = Max(2, targetSize)
			End If

			g = Max(1, Int(Float(nEntrants) / Float(tgt) + 0.5)) ' nearest
		End If

		Local base:Int = nEntrants / g
		Local extra:Int = nEntrants Mod g
		Local sizes:Int[] = New Int[g]
		For Local i:Int = 0 Until g
			sizes[i] = base
			If i < extra Then
				sizes[i] :+ 1
			End If
		Next

		Return sizes
	End Method

	Method BuildDrawIndex:TDrawIndex(parts:TParticipant[], avoidPairs:Int[][])
		Local n:Int = parts.Length
		Local pids:Int[]
		For Local p:TParticipant = EachIn parts
			pids :+ [p.id]
		Next

		' collect unique regions/divisions
		Local regions:String[]
		Local divisions:String[]
		Local pots:String[]
		Local regionIdx:Int[] = New Int[n]
		For Local i:Int = 0 Until n
			regionIdx[i] = -1
		Next

		Local divisionIdx:Int[] = New Int[n]
		Local potIdx:Int[] = New Int[n]
		For Local i:Int = 0 Until n
			divisionIdx[i] = -1
			potIdx[i] = -1
		Next

		For Local i:Int = 0 Until n
			Local r:String = parts[i].region
			If r <> "" Then
				Local ri:Int = IndexOfString(regions, r)
				If ri = -1 Then
					regions :+ [r]
					ri = regions.Length - 1
				End If

				regionIdx[i] = ri
			End If

			Local d:String = parts[i].divisionId
			If d <> "" Then
				Local di:Int = IndexOfString(divisions, d)
				If di = -1 Then
					divisions :+ [d]
					di = divisions.Length - 1
				End If

				divisionIdx[i] = di
			End If

			Local pot:String = parts[i].drawPot
			If pot <> "" Then
				Local potNumber:Int = IndexOfString(pots, pot)
				If potNumber = -1 Then
					pots :+ [pot]
					potNumber = pots.Length - 1
				End If

				potIdx[i] = potNumber
			End If
		Next

		' build pid -> participantIndex (array only)
		Function FindIndexByPid:Int(pids:Int[], pid:Int)
			For Local i:Int = 0 Until pids.Length
				If pids[i] = pid Then
					Return i
				End If
			Next

			Return -1
		End Function

		' avoid matrix
		Local avoid:Int[][] = New Int[n][]
		For Local i:Int = 0 Until n
			avoid[i] = New Int[n]
		Next

		For Local pr:Int[] = EachIn avoidPairs
			If pr.Length < 2 Then
				Continue
			End If

			Local aIdx:Int = FindIndexByPid(pids, pr[0])
			Local bIdx:Int = FindIndexByPid(pids, pr[1])
			If aIdx >= 0 And bIdx >= 0 Then
				avoid[aIdx][bIdx] = 1
				avoid[bIdx][aIdx] = 1
			End If
		Next

		Local idx:TDrawIndex = New TDrawIndex
		idx.pids = pids
		idx.regions = regions
		idx.divisions = divisions
		idx.pots = pots
		idx.regionIdx = regionIdx
		idx.divisionIdx = divisionIdx
		idx.potIdx = potIdx
		idx.avoid = avoid
		Return idx
	End Method

	Method PlaceWithConstraints:Int[][](comp:TCompetition, orderedIds:Int[], groupSizes:Int[], constraints:TDrawConstraints, idxData:TDrawIndex)

		If Not CheckFeasible(groupSizes, idxData, constraints) Then
			Throw "Draw constraints are unsatisfiable with current group sizes."
		End If

		Local nGroups:Int = groupSizes.Length
		Local groups:Int[][]
		For Local g:Int = 0 Until nGroups
			groups :+ [New Int[0]]
		Next

		' prepare counts/flags (arrays)
		Local nRegions:Int = idxData.regions.Length
		Local nDivs:Int = idxData.divisions.Length
		Local regionCount:Int[][]
		Local divisionUsed:Int[][]
		For Local g:Int = 0 Until nGroups
			regionCount :+ [ New Int[nRegions] ]
			divisionUsed :+ [ New Int[nDivs] ]
		Next

		' helper: find participant index by pid (array-only)
		Function FindIdxByPid:Int(pids:Int[], pid:Int)
			For Local i:Int = 0 Until pids.Length
				If pids[i] = pid Then
					Return i
				End If
			Next

			Return -1
		End Function

		' constraint check
		Function CanPlace:Int(gi:Int, pid:Int, groups:Int[][], groupSizes:Int[], idxData:TDrawIndex, regionCount:Int[][], constraints:TDrawConstraints, divisionUsed:Int[][])
			If groups[gi].Length >= groupSizes[gi] Then
				Return False
			End If

			Local pIdx:Int = FindIdxByPid(idxData.pids, pid)
			If pIdx < 0 Then
				Return False
			End If

			' Avoid pairs and limit entrants from the same draw pot.
			Local samePot:Int = 0
			For Local q:Int = EachIn groups[gi]
				Local qIdx:Int = FindIdxByPid(idxData.pids, q)
				If qIdx >= 0 And idxData.avoid[pIdx][qIdx] = 1 Then
					Return False
				End If

				If qIdx >= 0 And idxData.potIdx[pIdx] >= 0 And idxData.potIdx[pIdx] = idxData.potIdx[qIdx] Then
					samePot :+ 1
				End If
			Next

			If constraints.maxFromPot > 0 And samePot >= constraints.maxFromPot Then
				Return False
			End If

			' region constraints
			Local rIdx:Int = idxData.regionIdx[pIdx]
			If rIdx >= 0 Then
				Local cur:Int = regionCount[gi][rIdx]
				If constraints.disallowSameRegion And cur > 0 Then
					Return False
				End If

				If constraints.maxFromRegion > 0 And cur >= constraints.maxFromRegion Then
					Return False
				End If
			End If

			' division constraints (use divisionId as "prior group")
			If constraints.disallowSameGroup Then
				Local dIdx:Int = idxData.divisionIdx[pIdx]
				If dIdx >= 0 And divisionUsed[gi][dIdx] = 1 Then
					Return False
				End If
			End If

			Return True
		End Function

		' push/pop updates (fast array ops)
		Function Push:Int(g:Int, pid:Int, groups:Int[][], idxData:TDrawIndex, regionCount:Int[][], divisionUsed:Int[][], constraints:TDrawConstraints)
			groups[g] :+ [pid]
			Local pIdx:Int = FindIdxByPid(idxData.pids, pid)

			Local rIdx:Int = idxData.regionIdx[pIdx]
			If rIdx >= 0 Then
				regionCount[g][rIdx] :+ 1
			End If

			If constraints.disallowSameGroup Then
				Local dIdx:Int = idxData.divisionIdx[pIdx]
				If dIdx >= 0 Then
					divisionUsed[g][dIdx] = 1
				End If
			End If

			Return True
		End Function

		Function Pop(g:Int, groups:Int[][], idxData:TDrawIndex, regionCount:Int[][], divisionUsed:Int[][], constraints:TDrawConstraints)
			Local pid:Int = groups[g][groups[g].Length - 1]
			groups[g] = groups[g][..groups[g].Length - 1]
			Local pIdx:Int = FindIdxByPid(idxData.pids, pid)

			Local rIdx:Int = idxData.regionIdx[pIdx]
			If rIdx >= 0 Then
				regionCount[g][rIdx] :- 1
			End If

			If constraints.disallowSameGroup Then
				Local dIdx:Int = idxData.divisionIdx[pIdx]
				If dIdx >= 0 Then
					' recompute flag for that division (cheap: scan group members)
					divisionUsed[g][dIdx] = 0
					For Local q:Int = EachIn groups[g]
						Local qIdx:Int = FindIdxByPid(idxData.pids, q)
						If idxData.divisionIdx[qIdx] = dIdx Then
							divisionUsed[g][dIdx] = 1
						End If
					Next
				End If
			End If
		End Function

		' stacks per depth
		Local candLists:Int[][] = New Int[][orderedIds.Length]
		Local candPos:Int[] = New Int[orderedIds.Length]
		Local chosenGroup:Int[] = New Int[orderedIds.Length]

		Local i:Int = 0
		While i < orderedIds.Length
			If candLists[i] = Null Then
				' compute & shuffle candidates once for this depth
				Local pid:Int = orderedIds[i]
				Local cand:Int[]
				For Local g:Int = 0 Until nGroups
					If CanPlace(g, pid, groups, groupSizes, idxData, regionCount, constraints, divisionUsed) Then
						cand :+ [g]
					End If
				Next

				If cand.Length = 0 Then
					' backtrack
					If i = 0 Then
						Throw "No valid draw (unsatisfiable or too tight)."
					End If

					i :- 1
					' pop previous placement and advance its candidate pointer
					Pop(chosenGroup[i], groups, idxData, regionCount, divisionUsed, constraints)
					candPos[i] :+ 1
					Continue
				End If

				ShuffleIds(cand)
				candLists[i] = cand
				candPos[i] = 0
			End If

			If candPos[i] >= candLists[i].Length Then
				' exhausted options at this depth -> backtrack
				candLists[i] = Null
				candPos[i] = 0
				If i = 0 Then
					Throw "No valid draw (unsatisfiable or too tight)."
				End If

				i :- 1
				Pop(chosenGroup[i], groups, idxData, regionCount, divisionUsed, constraints)
				candPos[i] :+ 1
				Continue
			End If

			' try next candidate
			Local gPick:Int = candLists[i][candPos[i]]
			If CanPlace(gPick, orderedIds[i], groups, groupSizes, idxData, regionCount, constraints, divisionUsed) Then
				Push(gPick, orderedIds[i], groups, idxData, regionCount, divisionUsed, constraints)
				chosenGroup[i] = gPick
				i :+ 1
			Else
				candPos[i] :+ 1
			End If
		Wend

		' if not all placed (very rare with moderate constraints), fallback shuffle & retry
		If i < orderedIds.Length Then
			ShuffleIds(orderedIds)
			Return PlaceWithConstraints(comp, orderedIds, groupSizes, constraints, idxData)
		End If

		Return groups
	End Method

	Method CheckFeasible:Int(groupSizes:Int[], idx:TDrawIndex, constraints:TDrawConstraints)
		Local g:Int = groupSizes.Length
		If constraints.disallowSameRegion Then
			' each region count must be ≤ number of groups
			Local counts:Int[] = New Int[idx.regions.Length]
			' count per region across entrants
			For Local pIdx:Int = 0 Until idx.pids.Length
				Local r:Int = idx.regionIdx[pIdx]
				If r >= 0 Then
					counts[r] :+ 1
				End If
			Next

			For Local r:Int = 0 Until counts.Length
				If counts[r] > g Then
					Return False
				End If
			Next
		End If

		If constraints.maxFromRegion > 0 Then
			' total capacity for a region across all groups
			Local cap:Int = 0
			For Local i:Int = 0 Until g
				cap :+ Min(constraints.maxFromRegion, groupSizes[i])
			Next
			' check worst region doesn’t exceed cap
			Local counts:Int[] = New Int[idx.regions.Length]
			For Local pIdx:Int = 0 Until idx.pids.Length
				Local r:Int = idx.regionIdx[pIdx]
				If r >= 0 Then
					counts[r] :+ 1
				End If
			Next

			For Local r:Int = 0 Until counts.Length
				If counts[r] > cap Then
					Return False
				End If
			Next
		End If

		If constraints.maxFromPot > 0 Then
			Local cap:Int = 0
			For Local i:Int = 0 Until g
				cap :+ Min(constraints.maxFromPot, groupSizes[i])
			Next

			Local counts:Int[] = New Int[idx.pots.Length]
			For Local pIdx:Int = 0 Until idx.pids.Length
				Local pot:Int = idx.potIdx[pIdx]
				If pot >= 0 Then
					counts[pot] :+ 1
				End If
			Next

			For Local pot:Int = 0 Until counts.Length
				If counts[pot] > cap Then
					Return False
				End If
			Next
		End If

		Return True
	End Method
End Type

' -------- GROUP SCORER --------
Rem
bbdoc: Updates group tables and sporting tie ranks from results.
End Rem
Type TGroupScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload)
		If Not result Or result.kind <> EResultKind.HeadToHeadScore Then
			Throw "GroupScorer: ApplyResult called with wrong result kind"
		End If

		For Local f:TFixtureState = EachIn st.fixtures
			If f.id = fxId Then
				If result.fairPlayHome < 0 Or result.fairPlayAway < 0 Then
					Throw "Fair-play penalty units cannot be negative"
				End If

				f.status = EFixtureStatus.Completed
				f.scoreHome = result.scoreHome
				f.scoreAway = result.scoreAway
				f.fairPlayHome = result.fairPlayHome
				f.fairPlayAway = result.fairPlayAway
				f.resultLog :+ [result]
				Exit
			End If
		Next
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState)
		Local cfg:TGroupConfig = TGroupConfig(stage.config)
		Local league:TLeagueConfig = TLeagueConfig(stage.config)
		Local pointsWin:Int = 3
		Local pointsDraw:Int = 1
		Local pointsLoss:Int = 0
		Local tiebreakers:ETiebreaker[]
		Local reapplyHeadToHead:Int
		If cfg <> Null Then
			pointsWin = cfg.pointsWin
			pointsDraw = cfg.pointsDraw
			pointsLoss = cfg.pointsLoss
			tiebreakers = cfg.tiebreakers
			reapplyHeadToHead = cfg.reapplyHeadToHead
		ElseIf league <> Null Then
			pointsWin = league.pointsWin
			pointsDraw = league.pointsDraw
			pointsLoss = league.pointsLoss
			tiebreakers = league.tiebreakers
			reapplyHeadToHead = league.reapplyHeadToHead
		End If

		' 1) one row per participant
		Local rows:TLeaderboardRow[]
		For Local p:TParticipant = EachIn comp.participants
			Local r:TLeaderboardRow = New TLeaderboardRow
			r.participantId = p.id
			rows :+ [r]
		Next

		' helper to find row by team id
		Function RowFor:TLeaderboardRow(id:Int, rows:TLeaderboardRow[])
			For Local r:TLeaderboardRow = EachIn rows
				If r.participantId = id Then
					Return r
				End If
			Next

			Return Null
		End Function

		' 2) accumulate finished fixtures
		For Local f:TFixtureState = EachIn st.fixtures

			If f.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local h:TLeaderboardRow = RowFor(f.homeTeamId, rows)
			Local a:TLeaderboardRow = RowFor(f.awayTeamId, rows)

			h.gf :+ f.scoreHome
			h.ga :+ f.scoreAway
			a.gf :+ f.scoreAway
			a.ga :+ f.scoreHome

			If f.scoreHome > f.scoreAway Then
				h.wins :+ 1
				a.losses :+ 1
				h.points :+ pointsWin
				a.points :+ pointsLoss
			ElseIf f.scoreHome < f.scoreAway Then
				a.wins :+ 1
				h.losses :+ 1
				a.points :+ pointsWin
				h.points :+ pointsLoss
			Else
				h.draws :+ 1
				a.draws :+ 1
				h.points :+ pointsDraw
				a.points :+ pointsDraw
			End If
		Next

		SortTableByTiebreakers(rows, tiebreakers, st.fixtures, pointsWin, pointsDraw, pointsLoss, reapplyHeadToHead, st.tableTieDecisions)

		' 4) assign
		st.leaderboard.rows = rows
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState) { asBool }
		' all fixtures final
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Return False
			End If
		Next

		Return True
	End Method
End Type

Function SortTableByTiebreakers(rows:TLeaderboardRow[], rules:ETiebreaker[], fixtures:TFixtureState[], winPoints:Int = 3, drawPoints:Int = 1, lossPoints:Int = 0, reapplyHeadToHead:Int = False, decisions:TTableTieDecision[] = Null, scopeKey:String = "")
	If rules = Null Or rules.Length = 0 Then
		rules = [ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor]
	End If

	For Local ruleIndex:Int = 0 Until rules.Length
		Local rule:ETiebreaker = rules[ruleIndex]
		Select rule
			Case ETiebreaker.SetsWonPct, ETiebreaker.GamesWonPct, ETiebreaker.FinishCountback
				Throw "Tiebreaker requires a sport-specific scorer"
			Case ETiebreaker.RandomDraw
				If ruleIndex <> rules.Length - 1 Then
					Throw "RandomDraw must be the final table tiebreaker"
				End If
		End Select
	Next

	RankTableSubset(rows, 0, rows.Length, rules, 0, fixtures, winPoints, drawPoints, lossPoints, reapplyHeadToHead, Null, -1, decisions, scopeKey)
End Function

Function RankTableSubset(rows:TLeaderboardRow[], first:Int, last:Int, rules:ETiebreaker[], ruleIndex:Int, fixtures:TFixtureState[], winPoints:Int, drawPoints:Int, lossPoints:Int, reapplyHeadToHead:Int, headMembers:TLeaderboardRow[] = Null, headStart:Int = -1, decisions:TTableTieDecision[] = Null, scopeKey:String = "")
	If last - first < 2 Then
		If last > first Then
			rows[first].sportingRank = first + 1
		End If

		Return
	End If

	If ruleIndex >= rules.Length Or rules[ruleIndex] = ETiebreaker.RandomDraw Then
		Local decision:TTableTieDecision
		For Local candidate:TTableTieDecision = EachIn decisions
			If candidate.scopeKey <> scopeKey Or candidate.participantIds = Null Or candidate.participantIds.Length <> last - first Then
				Continue
			End If

			Local matches:Int = True
			For Local id:Int = EachIn candidate.participantIds
				Local found:Int
				For Local i:Int = first Until last
					If rows[i].participantId = id Then
						found :+ 1
					End If
				Next

				If found <> 1 Then matches = False; Exit
			Next

			If matches Then decision = candidate; Exit
		Next

		If decision <> Null Then
			For Local i:Int = first Until last
				For Local j:Int = i Until last
					If rows[j].participantId = decision.participantIds[i - first] Then
						Local swap:TLeaderboardRow = rows[i]; rows[i] = rows[j]; rows[j] = swap
						Exit
					End If
				Next

				rows[i].sportingRank = i + 1
			Next

			Return
		End If

		For Local i:Int = first Until last
			rows[i].sportingRank = first + 1
		Next

		For Local i:Int = first Until last - 1
			For Local j:Int = i + 1 Until last
				If rows[j].participantId < rows[i].participantId Then
					Local swap:TLeaderboardRow = rows[i]; rows[i] = rows[j]; rows[j] = swap
				End If
			Next
		Next

		Return
	End If

	Local rule:ETiebreaker = rules[ruleIndex]
	Local members:TLeaderboardRow[] = rows[first..last]
	Local isHead:Int = rule = ETiebreaker.HeadToHeadPoints Or rule = ETiebreaker.HeadToHeadGD
	If isHead Then
		If headMembers = Null Then headMembers = members; headStart = ruleIndex

		members = headMembers
	End If

	For Local i:Int = first Until last - 1
		For Local j:Int = i + 1 Until last
			If TableRuleValue(rows[j], rule, members, fixtures, winPoints, drawPoints, lossPoints) > TableRuleValue(rows[i], rule, members, fixtures, winPoints, drawPoints, lossPoints) Then
				Local swap:TLeaderboardRow = rows[i]; rows[i] = rows[j]; rows[j] = swap
			End If
		Next
	Next

	Local start:Int = first
	While start < last
		Local value:Int = TableRuleValue(rows[start], rule, members, fixtures, winPoints, drawPoints, lossPoints)
		Local finish:Int = start + 1
		While finish < last And TableRuleValue(rows[finish], rule, members, fixtures, winPoints, drawPoints, lossPoints) = value
			finish :+ 1
		Wend

		Local nextRule:Int = ruleIndex + 1
		Local nextIsHead:Int
		Local nextMembers:TLeaderboardRow[] = headMembers
		If nextRule < rules.Length Then
			nextIsHead = rules[nextRule] = ETiebreaker.HeadToHeadPoints Or rules[nextRule] = ETiebreaker.HeadToHeadGD
		End If

		If isHead And Not nextIsHead Then
			If reapplyHeadToHead And finish - start > 1 And finish - start < headMembers.Length Then
				nextRule = headStart
			End If

			nextMembers = Null
		End If

		RankTableSubset(rows, start, finish, rules, nextRule, fixtures, winPoints, drawPoints, lossPoints, reapplyHeadToHead, nextMembers, headStart, decisions, scopeKey)
		start = finish
	Wend
End Function

Function TableRuleValue:Int(row:TLeaderboardRow, rule:ETiebreaker, members:TLeaderboardRow[], fixtures:TFixtureState[], winPoints:Int, drawPoints:Int, lossPoints:Int)
	Select rule
		Case ETiebreaker.Points
			Return row.points
		Case ETiebreaker.GoalDifference
			Return row.gf - row.ga
		Case ETiebreaker.GoalsFor, ETiebreaker.PointsFor
			Return row.gf
		Case ETiebreaker.PointsAgainst
			Return -row.ga
		Case ETiebreaker.Wins
			Return row.wins
		Case ETiebreaker.FairPlay
			Local penalties:Int
			For Local fixture:TFixtureState = EachIn fixtures
				If fixture.status <> EFixtureStatus.Completed Then
					Continue
				End If

				If fixture.homeTeamId = row.participantId Then
					penalties :+ fixture.fairPlayHome
				End If

				If fixture.awayTeamId = row.participantId Then
					penalties :+ fixture.fairPlayAway
				End If
			Next

			Return -penalties
		Case ETiebreaker.HeadToHeadPoints, ETiebreaker.HeadToHeadGD
			Local value:Int
			For Local f:TFixtureState = EachIn fixtures
				If f.status <> EFixtureStatus.Completed Then
					Continue
				End If

				If f.homeTeamId <> row.participantId And f.awayTeamId <> row.participantId Then
					Continue
				End If

				Local opponent:Int = f.awayTeamId
				Local ownScore:Int = f.scoreHome
				Local otherScore:Int = f.scoreAway
				If f.awayTeamId = row.participantId Then opponent = f.homeTeamId; ownScore = f.scoreAway; otherScore = f.scoreHome

				Local included:Int
				For Local member:TLeaderboardRow = EachIn members
					If member.participantId = opponent Then included = True; Exit
				Next

				If Not included Then
					Continue
				End If

				If rule = ETiebreaker.HeadToHeadGD Then
					value :+ ownScore - otherScore
				ElseIf ownScore > otherScore Then
					value :+ winPoints
				ElseIf ownScore < otherScore Then
					value :+ lossPoints
				Else
					value :+ drawPoints
				End If
			Next

			Return value
	End Select

	Return 0
End Function

Function SortTableByPointsGdGf(rows:TLeaderboardRow[])
	' simple bubble for clarity
	For Local i:Int = 0 Until rows.Length - 1
		For Local j:Int = 0 Until rows.Length - 1 - i
			If RowCmp(rows[j], rows[j + 1]) < 0 Then
				Local t:TLeaderboardRow = rows[j]
				rows[j] = rows[j + 1]
				rows[j + 1] = t
			End If
		Next
	Next
End Function

Function RowCmp:Int(a:TLeaderboardRow, b:TLeaderboardRow)
	Local ap:Int = a.points, bp:Int = b.points
	If ap <> bp Then
		Return ap - bp
	End If

	Local agd:Int = (a.gf - a.ga), bgd:Int = (b.gf - b.ga)
	If agd <> bgd Then
		Return agd - bgd
	End If

	If a.gf <> b.gf Then
		Return a.gf - b.gf
	End If

	Return -(a.participantId - b.participantId)
End Function

' -------- GROUP ADVANCER (TopN per group) --------
Rem
bbdoc: Selects qualifiers from group standings.
End Rem
Type TGroupAdvancer Implements IStageAdvancer
	Rem
	bbdoc: #TUnresolvedTableTie value used by this group advancer.
	End Rem
	Field unresolvedCrossGroupTie:TUnresolvedTableTie

	Method ProduceAdvancements:TParticipant[](comp:TCompetition, stage:TStage, st:TStageState)
		unresolvedCrossGroupTie = Null

		' ensure we have group tables; if scorer didn't populate them, build a snapshot from fixtures
		If st.groups = Null Or st.groups.Length = 0 Then
			st.groups = SnapshotGroupTables(comp, stage, st)
		End If

		Local out:TParticipant[]
		Local checkGroups:Int
		Local checkOverall:Int

		' If multiple rules, apply in order, removing already-selected teams between rules.
		For Local adv:TAdvancement = EachIn stage.advancement
			Local rules:TFilterRule[] = adv.rules
			If rules = Null Or rules.Length = 0 Then
				If adv.rule <> Null Then
					rules = [adv.rule]
				End If
			End If

			For Local rule:TFilterRule = EachIn rules

				Select rule.kind
					Case EFilterKind.TopN
						If rule.scope = EFilterScope.PerGroup Then
							checkGroups = True
							If st.groups <> Null And st.groups.Length > 0 Then
								For Local gt:TGroupTable = EachIn st.groups
									Local picked:Int = 0
									For Local i:Int = Max(0, rule.startRank - 1) Until gt.rows.Length
										If picked >= rule.n Then
											Exit
										End If

										Local pid:Int = gt.rows[i].participantId
										If Not AlreadyPicked(pid, out) Then
											out :+ [ FindParticipant(comp, pid) ]
											picked :+ 1
										End If
									Next
								Next
							End If
						Else
							checkOverall = True
							' global TopN as fallback from leaderboard
							Local picked:Int = 0
							For Local i:Int = Max(0, rule.startRank - 1) Until st.leaderboard.rows.Length
								If picked >= rule.n Then
									Exit
								End If

								Local pid:Int = st.leaderboard.rows[i].participantId
								If Not AlreadyPicked(pid, out) Then
									out :+ [ FindParticipant(comp, pid) ]
									picked :+ 1
								End If
							Next
						End If

					Case EFilterKind.BottomN
						checkOverall = True
						Local picked:Int = 0
						For Local i:Int = st.leaderboard.rows.Length - 1 To 0 Step -1
							If picked >= rule.n Then
								Exit
							End If

							Local pid:Int = st.leaderboard.rows[i].participantId
							If Not AlreadyPicked(pid, out) Then
								out :+ [FindParticipant(comp, pid)]
								picked :+ 1
							End If
						Next

					' Best X across groups (wild cards)
					Case EFilterKind.BestXAcrossGroups
						checkGroups = True
						' startRank selects one rank from each group (e.g. third place).
						' Zero retains the legacy pool of all unselected entrants.
						Local pool:TLeaderboardRow[]
						If st.groups <> Null Then
							For Local gt:TGroupTable = EachIn st.groups
								For Local rankIndex:Int = 0 Until gt.rows.Length
									If rule.startRank > 0 And rankIndex + 1 <> rule.startRank Then
										Continue
									End If

									Local r:TLeaderboardRow = gt.rows[rankIndex]
									If Not AlreadyPicked(r.participantId, out) Then
										pool :+ [ r ]
									End If
								Next
							Next
						Else
							If rule.startRank > 0 Then
								Throw "Rank-specific best-across-groups selection requires group tables"
							End If
							' fallback to global leaderboard if groups not present
							For Local r:TLeaderboardRow = EachIn st.leaderboard.rows
								If Not AlreadyPicked(r.participantId, out) Then
									pool :+ [ r ]
								End If
							Next
						End If

						' Sort pool by points desc (reuse RowCmp if you expose it; inline here)
						For Local i:Int = 0 Until pool.Length - 1
							For Local j:Int = i + 1 Until pool.Length
								' reverse of RowCmp (we want best first)
								Local ai:TLeaderboardRow = pool[i]
								Local aj:TLeaderboardRow = pool[j]
								Local diff:Int = 0
								If ai.points <> aj.points Then
									diff = aj.points - ai.points
								End If

								If diff = 0 Then
									Local agd:Int = (ai.gf - ai.ga)
									Local bgd:Int = (aj.gf - aj.ga)
									diff = bgd - agd
								End If

								If diff = 0 Then
									diff = aj.gf - ai.gf
								End If

								If diff > 0 Then
									Local t:TLeaderboardRow = pool[i]
									pool[i] = pool[j]
									pool[j] = t
								End If
							Next
						Next

						Local take:Int = Min(rule.n, pool.Length)
						Local resolvedBoundary:Int
						Local block:Int
						While block < pool.Length
							Local stop:Int = block + 1
							While stop < pool.Length And pool[stop].points = pool[block].points And pool[stop].gf - pool[stop].ga = pool[block].gf - pool[block].ga And pool[stop].gf = pool[block].gf
								stop :+ 1
							Wend

							For Local decision:TTableTieDecision = EachIn st.tableTieDecisions
								If decision.scopeKey <> "bestAcross" Or decision.participantIds = Null Or decision.participantIds.Length <> stop - block Then
									Continue
								End If

								Local matches:Int = True
								For Local id:Int = EachIn decision.participantIds
									Local found:Int
									For Local k:Int = block Until stop
										If pool[k].participantId = id Then
											found :+ 1
										End If
									Next

									If found <> 1 Then matches = False; Exit
								Next

								If Not matches Then
									Continue
								End If

								For Local k:Int = block Until stop
									For Local j:Int = k Until stop
										If pool[j].participantId = decision.participantIds[k - block] Then
											Local swap:TLeaderboardRow = pool[k]; pool[k] = pool[j]; pool[j] = swap
											Exit
										End If
									Next
								Next

								If block < take And take < stop Then
									resolvedBoundary = True
								End If

								Exit
							Next

							block = stop
						Wend

						If take > 0 And take < pool.Length Then
							Local upper:TLeaderboardRow = pool[take - 1]
							Local lower:TLeaderboardRow = pool[take]
							If upper.sportingRank > 0 And lower.sportingRank > 0 And upper.points = lower.points And upper.gf - upper.ga = lower.gf - lower.ga And upper.gf = lower.gf And Not resolvedBoundary Then
								Local first:Int = take - 1
								While first > 0 And pool[first - 1].points = upper.points And pool[first - 1].gf - pool[first - 1].ga = upper.gf - upper.ga And pool[first - 1].gf = upper.gf
									first :- 1
								Wend

								Local last:Int = take
								While last + 1 < pool.Length And pool[last + 1].points = upper.points And pool[last + 1].gf - pool[last + 1].ga = upper.gf - upper.ga And pool[last + 1].gf = upper.gf
									last :+ 1
								Wend

								unresolvedCrossGroupTie = New TUnresolvedTableTie
								unresolvedCrossGroupTie.stageId = stage.id
								unresolvedCrossGroupTie.scopeKey = "bestAcross"
								For Local k:Int = first To last
									unresolvedCrossGroupTie.participantIds :+ [pool[k].participantId]
								Next

								Return Null
							End If
						End If

						For Local k:Int = 0 Until take
							out :+ [ FindParticipant(comp, pool[k].participantId) ]
						Next

					Case EFilterKind.All
						If st.groups <> Null Then
							For Local gt:TGroupTable = EachIn st.groups
								For Local r:TLeaderboardRow = EachIn gt.rows
									If Not AlreadyPicked(r.participantId, out) Then
										out :+ [ FindParticipant(comp, r.participantId) ]
									End If
								Next
							Next
						Else
							For Local r:TLeaderboardRow = EachIn st.leaderboard.rows
								If Not AlreadyPicked(r.participantId, out) Then
									out :+ [ FindParticipant(comp, r.participantId) ]
								End If
							Next
						End If

					Default
					' other kinds not implemented here yet
				End Select
			Next
		Next

		If checkGroups Then
			For Local group:TGroupTable = EachIn st.groups
				If SelectionSplitsTie(group.rows, out) Then
					Return Null
				End If
			Next
		End If

		If checkOverall And SelectionSplitsTie(st.leaderboard.rows, out) Then
			Return Null
		End If

		Return out
	End Method

	Method SelectionSplitsTie:Int(rows:TLeaderboardRow[], selected:TParticipant[])
		For Local i:Int = 0 Until rows.Length
			For Local j:Int = i + 1 Until rows.Length
				If rows[i].sportingRank = 0 Or rows[i].sportingRank <> rows[j].sportingRank Then
					Continue
				End If

				If AlreadyPicked(rows[i].participantId, selected) <> AlreadyPicked(rows[j].participantId, selected) Then
					Return True
				End If
			Next
		Next

		Return False
	End Method

	Method AlreadyPicked:Int(pid:Int, arr:TParticipant[])
		For Local p:TParticipant = EachIn arr
			If p.id = pid Then
				Return True
			End If
		Next

		Return False
	End Method

	Method FindParticipant:TParticipant(comp:TCompetition, id:Int)
		For Local p:TParticipant = EachIn comp.participants
			If p.id = id Then
				Return p
			End If
		Next

		Return Null
	End Method

	' Build per-group standings from finalized fixtures only.
	' Uses TGroupConfig points (defaults 3/1/0), computes GF/GA/GD, sorts Points desc, GD desc, GF desc.
	Method SnapshotGroupTables:TGroupTable[](comp:TCompetition, stage:TStage, st:TStageState)
		Local gcfg:TGroupConfig = TGroupConfig(stage.config)
		Local ptsW:Int
		If gcfg <> Null Then
			ptsW = gcfg.pointsWin
		Else
			ptsW = 3
		End If

		Local ptsD:Int
		If gcfg <> Null Then
			ptsD = gcfg.pointsDraw
		Else
			ptsD = 1
		End If

		Local ptsL:Int
		If gcfg <> Null Then
			ptsL = gcfg.pointsLoss
		Else
			ptsL = 0
		End If

		' groupKey -> pid -> row
		Local byGroup:TStringMap = New TStringMap

		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local gkey:String = f.groupKey
			If gkey = "" Then
				Continue
			End If

			Local mapRows:TStringMap = TStringMap(byGroup.ValueForKey(gkey))
			If mapRows = Null Then
				mapRows = New TStringMap
				byGroup.Insert(gkey, mapRows)
			End If

			' ensure rows exist
			Local rH:TLeaderboardRow = TLeaderboardRow(mapRows.ValueForKey(f.homeTeamId))
			If rH = Null Then
				rH = New TLeaderboardRow
				rH.participantId = f.homeTeamId
				mapRows.Insert(f.homeTeamId, rH)
			End If

			Local rA:TLeaderboardRow = TLeaderboardRow(mapRows.ValueForKey(f.awayTeamId))
			If rA = Null Then
				rA = New TLeaderboardRow
				rA.participantId = f.awayTeamId
				mapRows.Insert(f.awayTeamId, rA)
			End If

			' update GF/GA
			rH.gf :+ f.scoreHome
			rH.ga :+ f.scoreAway
			rA.gf :+ f.scoreAway
			rA.ga :+ f.scoreHome

			' update points
			If f.scoreHome > f.scoreAway Then
				rH.points :+ ptsW
				rA.points :+ ptsL
				rH.wins :+ 1
				rA.losses :+ 1
			ElseIf f.scoreHome < f.scoreAway Then
				rA.points :+ ptsW
				rH.points :+ ptsL
				rA.wins :+ 1
				rH.losses :+ 1
			Else
				rH.points :+ ptsD
				rA.points :+ ptsD
				rH.draws :+ 1
				rA.draws :+ 1
			End If
		Next

		' build TGroupTable[] and sort rows per group
		Local out:TGroupTable[]
		For Local it:String = EachIn byGroup.Keys()
			Local gkey:String = it
			Local mapRows:TStringMap = TStringMap(byGroup.ValueForKey(gkey))

			Local rows:TLeaderboardRow[] = []
			For Local kt:String = EachIn mapRows.Keys()
				rows :+ [ TLeaderboardRow(mapRows.ValueForKey(kt)) ]
			Next

			For Local row:TLeaderboardRow = EachIn rows
				For Local adjustment:TPointAdjustment = EachIn st.adjustments
					If adjustment.participantId = row.participantId Then
						row.points :+ adjustment.pointsDelta
					End If
				Next
			Next

			Local rules:ETiebreaker[]
			If gcfg <> Null Then
				rules = gcfg.tiebreakers
			End If

			Local reapply:Int
			If gcfg <> Null Then
				reapply = gcfg.reapplyHeadToHead
			End If

			SortTableByTiebreakers(rows, rules, st.fixtures, ptsW, ptsD, ptsL, reapply, st.tableTieDecisions, gkey)

			Local gt:TGroupTable = New TGroupTable
			gt.key = gkey
			gt.rows = rows
			out :+ [gt]
		Next

		' Map iteration order is unspecified. Advancement routes with fixed
		' slots need a stable group order, especially for preset draws.
		For Local i:Int = 0 Until out.Length
			For Local j:Int = i + 1 Until out.Length
				Local first:Int = -1
				Local second:Int = -1
				If gcfg <> Null And gcfg.presetGroups <> Null Then
					For Local k:Int = 0 Until gcfg.presetGroups.Length
						If gcfg.presetGroups[k].code = out[i].key Then
							first = k
						End If

						If gcfg.presetGroups[k].code = out[j].key Then
							second = k
						End If
					Next
				ElseIf out[i].key.StartsWith("G") And out[j].key.StartsWith("G") Then
					first = Int(out[i].key[1..])
					second = Int(out[j].key[1..])
				End If

				Local swapRows:Int
				If first >= 0 And second >= 0 Then
					swapRows = second < first
				Else
					swapRows = out[j].key < out[i].key
				End If

				If swapRows Then
					Local temporary:TGroupTable = out[i]
					out[i] = out[j]
					out[j] = temporary
				End If
			Next
		Next

		Return out
	End Method
End Type

' -------- ROUND-ROBIN FIXTURE GENERATOR --------
' Generates fixtures for a round-robin group of teams, each team plays each other perOpp times.
' If perOpp > 1, alternates home/away on odd repetitions.
' Rounds are numbered starting from startRound.
' Returns TFixture[] with stageId, round, leg, homeTeamId, awayTeamId set.
' Uses standard "circle method" for round-robin generation.
' If odd number of teams, one team has a bye each round (teamId=0).
' Does NOT balance home/away streaks; use BalanceVenueStreaks_Fixture()
