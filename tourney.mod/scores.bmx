Rem
bbdoc: Validates and scores set-based matches and ties.
End Rem
Type TSetBasedScorer Implements IStageScorer

	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload) Override
		If Not result or result.kind <> EResultKind.SetBased Then
			Throw "SetBasedScorer: ApplyResult called with non-set result"
		End If

		' mark the fixture as final (winner will be inferred during standings calc)
		For Local f:TFixtureState = EachIn st.fixtures
			If f.id = fxId Then
				f.status = EFixtureStatus.Completed
				f.setResults = result.sets[..]

				f.resultLog :+ [ result ]
			End If
		Next
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState)
		' NOTE: Works for Group/League style stages (table); for Bracket you typically
		' only need winner progression (not a points table). This scorer still computes
		' a table so your engine can read TopN if needed.
		Local cfgGroup:TGroupConfig = TGroupConfig(stage.config)
		Local ptsW:Int
		If cfgGroup <> Null Then
			ptsW = cfgGroup.pointsWin
		Else
			ptsW = 3
		End If

		Local ptsD:Int
		If cfgGroup <> Null Then
			ptsD = cfgGroup.pointsDraw
		Else
			ptsD = 1
		End If

		Local ptsL:Int
		If cfgGroup <> Null Then
			ptsL = cfgGroup.pointsLoss
		Else
			ptsL = 0
		End If

		' Build rows
		Local rows:TLeaderboardRow[]
		For Local p:TParticipant = EachIn comp.participants
			Local r:TLeaderboardRow = New TLeaderboardRow
			r.participantId = p.id
			rows :+ [r]
		Next

		' Helper
		Function RowFor:TLeaderboardRow(id:Int, rows:TLeaderboardRow[])
			For Local r:TLeaderboardRow = EachIn rows
				If r.participantId = id Then
					Return r
				End If
			Next

			Return Null
		End Function

		' Accumulate finished fixtures using stored sets
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local sets:TSetScore[] = f.setResults
			If sets = Null Or sets.Length = 0 Then
				Continue
			End If

			' Count sets won
			Local homeSets:Int = 0, awaySets:Int = 0
			For Local s:TSetScore = EachIn sets
				If s.home > s.away Then
					homeSets :+ 1
				End If

				If s.away > s.home Then
					awaySets :+ 1
				End If
			Next

			Local rh:TLeaderboardRow = RowFor(f.homeTeamId, rows)
			Local ra:TLeaderboardRow = RowFor(f.awayTeamId, rows)

			' Optional: store aggregate games as GF/GA (handy for tie-breaks in tennis groups)
			Local gfh:Int = 0
			Local gfa:Int = 0
			For Local s:TSetScore = EachIn sets
				gfh :+ s.home
				gfa :+ s.away
			Next

			rh.gf :+ gfh
			rh.ga :+ gfa
			ra.gf :+ gfa
			ra.ga :+ gfh

			If homeSets > awaySets Then
				rh.wins :+ 1
				ra.losses :+ 1
				rh.points :+ ptsW
			ElseIf awaySets > homeSets Then
				ra.wins :+ 1
				rh.losses :+ 1
				ra.points :+ ptsW
			Else
				' If you ever support draws for set sports, enable the next 3 lines:
				' rh.draws :+ 1; ra.draws :+ 1
				' rh.points :+ ptsD; ra.points :+ ptsD
				' Continue
				' For now, treat equal sets as unresolved; skip or raise:
				' (Shouldn't occur if ApplySetResult is used with valid sets.)
			End If
		Next

		' Sort by points, GD (games diff), GF — common for set-based groups
		SortTableByPointsGdGf(rows)
		st.leaderboard.rows = rows
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState) {asBool}
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Return False
			End If
		Next

		Return True
	End Method

End Type


' -------- TIME-BASED SCORER --------
Rem
bbdoc: Ranks timed results and penalties for a series stage.
End Rem
Type TTimeScorer Implements IStageScorer

	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload) Override
		If Not result or result.kind <> EResultKind.TimeBased Then
			Throw "TimeScorer: ApplyResult called with non-time result"
		End If

		For Local f:TFixtureState = EachIn st.fixtures
			If f.id = fxId Then
				f.timeResults = result.times[..]   ' copy
				f.status = EFixtureStatus.Completed

				f.resultLog :+ [ result ]
				Exit
			End If
		Next
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState)
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		Local scoring:TScoringSystem

		If cfg <> Null Then
			scoring = cfg.scoring
		End If

		' Build rows (entrants-aware)
		Local rowsByPid:TIntMap = New TIntMap
		Local allowed:Int[]
		If st.entrants <> Null And st.entrants.Length Then
			allowed = st.entrants
		End If

		Function IsAllowed:Int(pid:Int, allowed:Int[])
			If allowed = Null Then
				Return True
			End If

			For Local x:Int = EachIn allowed
				If x = pid Then
					Return True
				End If
			Next

			Return False
		End Function

		' optional points table
		Local hasPts:Int = (scoring <> Null And scoring.table <> Null And scoring.table.Length > 0)
		Local ptsByPos:Int[]
		Local maxPos:Int = 0
		If hasPts Then
			For Local e:TPointsTableEntry = EachIn scoring.table
				If e.position > maxPos Then
					maxPos = e.position
				End If
			Next

			ptsByPos = New Int[maxPos + 1]
			For Local e:TPointsTableEntry = EachIn scoring.table
				ptsByPos[e.position] = e.points
			Next
		End If

		' local cumulative time map (pid -> total millis)
		Local cumMillis:Long[]    ' parallel to a pid list for sorting
		Local pidIndex:TIntMap = New TIntMap ' pid -> index in arrays
		Local pids:Int[]
		Local hasDNF:Int[]
		Local hasDSQ:Int[]

		Function IndexFor:Int(pid:Int, pidIndex:TIntMap, pids:Int[] Var, cumMillis:Long[] Var, rowsByPid:TIntMap, hasDNF:Int[] Var, hasDSQ:Int[] Var)
			Local got:String = String(pidIndex.ValueForKey(pid))
			If got <> Null Then
				Return got.ToInt()
			End If

			Local idx:Int = pids.Length
			pids :+ [pid]
			pidIndex.Insert(pid, String(idx))
			cumMillis :+ [0:Long]
			hasDNF :+ [0]
			hasDSQ :+ [0]
			' ensure row exists
			If rowsByPid.ValueForKey(pid) = Null Then
				Local r:TLeaderboardRow = New TLeaderboardRow
				r.participantId = pid
				rowsByPid.Insert(pid, r)
			End If

			Return idx
		End Function

		' Walk finalized fixtures
		Local lastFinalFx:TFixtureState = Null
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Continue
			End If

			lastFinalFx = f

			Local times:TParticipantTime[]
			If f.timeResults <> Null Then
				times = f.timeResults
			End If

			If times.Length = 0 Then
				Continue
			End If

			' filter to entrants
			If allowed <> Null Then
				Local filtered:TParticipantTime[]
				For Local t:TParticipantTime = EachIn times
					If IsAllowed(t.participantId, allowed) Then
						filtered :+ [t]
					End If
				Next

				times = filtered
			End If

			If times.Length = 0 Then
				Continue
			End If

			' ranked order with DNF/DSQ positioning
			Local ord:TTimedRank[] = BuildRanked(times)

			' points + cumulative
			For Local i:Int = 0 Until ord.Length
				Local r:TTimedRank = ord[i]
				Local idx:Int = IndexFor(r.participantId, pidIndex, pids, cumMillis, rowsByPid, hasDNF, hasDSQ)

				If r.status = ETimeStatus.Finished Then
					cumMillis[idx] :+ r.adjustedMillis
					If hasPts And i + 1 <= maxPos Then
						Local row:TLeaderboardRow = TLeaderboardRow(rowsByPid.ValueForKey(r.participantId))
						row.points :+ ptsByPos[i + 1]
					End If
				ElseIf r.status = ETimeStatus.DNF Then
					hasDNF[idx] = 1
				ElseIf r.status = ETimeStatus.DSQ Then
					hasDSQ[idx] = 1
				End If
			Next
		Next

		' Decide ranking mode
		Local sumTimes:Int = (scoring <> Null And scoring.aggregation <> Null And scoring.aggregation.sumTimes)
		Local qualifyingMode:Int = (Not hasPts And Not sumTimes) ' rank by last finalized event only

		Local out:TLeaderboardRow[]

		If qualifyingMode And lastFinalFx <> Null Then
			' rank by last event times
			Local times:TParticipantTime[]
			If lastFinalFx.timeResults <> Null Then
				times = lastFinalFx.timeResults
			End If

			If allowed <> Null Then
				Local filtered:TParticipantTime[]
				For Local t:TParticipantTime = EachIn times
					If IsAllowed(t.participantId, allowed) Then
						filtered :+ [t]
					End If
				Next

				times = filtered
			End If
			' Local ord:TParticipantTime[] = times[..]
			Local ord:TTimedRank[] = BuildRanked(times)

			Local arr:TLeaderboardRow[]
			For Local i:Int = 0 Until ord.Length
				Local r:TLeaderboardRow = New TLeaderboardRow
				r.participantId = ord[i].participantId
				r.points = 0
				arr :+ [r]
			Next

			st.leaderboard.rows = arr
			Return
		End If

		' SUM OF TIMES: finishers (by cumMillis asc) → DNFs → DSQs
		If sumTimes Then
			' ensure everyone in entrants (or all participants) gets a row/index
			If allowed <> Null Then
				For Local pid:Int = EachIn allowed
					IndexFor(pid, pidIndex, pids, cumMillis, rowsByPid, hasDNF, hasDSQ)
				Next
			Else
				For Local p:TParticipant = EachIn comp.participants
					IndexFor(p.id, pidIndex, pids, cumMillis, rowsByPid, hasDNF, hasDSQ)
				Next
			End If

			' build index list and sort
			Local idxs:Int[]
			For Local i:Int = 0 Until pids.Length
				idxs :+ [i]
			Next

			' comparator: finished first, then DNF, then DSQ; within finished sort by cumMillis asc, tie by pid
			For Local i:Int = 0 Until idxs.Length - 1
				For Local j:Int = i + 1 Until idxs.Length
					Local a:Int = idxs[i]
					Local b:Int = idxs[j]
					Local catA:Int
					If hasDSQ[a] = 1 Then
						catA = 2
					Else If hasDNF[a] = 1 Then
						catA = 1
					End If

					Local catB:Int
					If hasDSQ[b] = 1 Then
						catB = 2
					Else If hasDNF[b] = 1 Then
						catB = 1
					End If

					If catA > catB ..
                    Or (catA = 0 And catB = 0 And (cumMillis[a] > cumMillis[b] Or (cumMillis[a] = cumMillis[b] And pids[a] > pids[b]))) ..
                    Or (catA = catB And catA <> 0 And pids[a] > pids[b]) Then
						Local tmp:Int = idxs[i]; idxs[i] = idxs[j]; idxs[j] = tmp
					End If
				Next
			Next

			Local out:TLeaderboardRow[] = []
			For Local k:Int = 0 Until idxs.Length
				Local pid:Int = pids[idxs[k]]
				out :+ [ TLeaderboardRow(rowsByPid.ValueForKey(pid)) ]
			Next

			st.leaderboard.rows = out
			Return
		End If

		' default points-based ordering (desc)
		' ensure rows exist for entrants even if no points yet
		If allowed <> Null Then
			For Local pid:Int = EachIn allowed
				If rowsByPid.ValueForKey(pid) = Null Then
					Local r:TLeaderboardRow = New TLeaderboardRow
					r.participantId = pid
					rowsByPid.Insert(pid, r)
				End If
			Next
		End If

		For Local it:TIntKey = EachIn rowsByPid.Keys()
			out :+ [ TLeaderboardRow(rowsByPid.ValueForKey(it.value)) ]
		Next

		For Local i:Int = 0 Until out.Length - 1
			For Local j:Int = i + 1 Until out.Length
				If out[i].points < out[j].points Then
					Local t:TLeaderboardRow = out[i]
					out[i] = out[j]
					out[j] = t
				End If
			Next
		Next

		st.leaderboard.rows = out
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState)
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Return False
			End If
		Next

		Return True
	End Method

	Method LoadTimesLocal:TParticipantTime[](st:TStageState, fxId:String)
		For Local f:TFixtureState = EachIn st.fixtures
			If f.id = fxId Then
				If f.timeResults <> Null Then
					Return f.timeResults
				End If

				Exit
			End If
		Next

		Return []
	End Method

	Function BuildRanked:TTimedRank[](times:TParticipantTime[])
		Local out:TTimedRank[]
		For Local t:TParticipantTime = EachIn times
			Local r:TTimedRank = New TTimedRank
			r.participantId = t.participantId
			r.status = t.status
			r.adjustedMillis = t.millis + t.penaltyMillis
			out :+ [r]
		Next
		' Order key: Finished (by time asc) → DNF → DSQ → DNS; tie by participantId
		Function Key:Int(s:ETimeStatus)
			Select s
				Case ETimeStatus.Finished Return 0
				Case ETimeStatus.DNF      Return 1
				Case ETimeStatus.DSQ      Return 2
				Default                   Return 3
			End Select
		End Function

		For Local i:Int = 0 Until out.Length - 1
			For Local j:Int = i + 1 Until out.Length
				Local ai:Int = Key(out[i].status)
				Local aj:Int = Key(out[j].status)
				If ai > aj ..
				Or (ai = aj And out[i].status = ETimeStatus.Finished And out[i].adjustedMillis > out[j].adjustedMillis) ..
				Or (ai = aj And out[i].status <> ETimeStatus.Finished And out[i].participantId > out[j].participantId) Then
					Local tmp:TTimedRank = out[i]
					out[i] = out[j]
					out[j] = tmp
				End If
			Next
		Next

		Return out
	End Function
End Type
