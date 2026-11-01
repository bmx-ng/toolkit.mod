Rem
bbdoc: Tracks bonus-award limits while scoring a series event.
End Rem
Type TSeriesAwardLedger
	Rem
	bbdoc: #TStringMap value used by this series award ledger.
	End Rem
	Field perSession:TStringMap = New TStringMap
	Rem
	bbdoc: #TStringMap value used by this series award ledger.
	End Rem
	Field perEvent:TStringMap = New TStringMap
	Rem
	bbdoc: #TStringMap value used by this series award ledger.
	End Rem
	Field perParticipantEvent:TStringMap = New TStringMap
End Type

Rem
bbdoc: Creates fixtures for configured series events and sessions.
End Rem
Type TSeriesScheduler Implements IStageScheduler
	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)

		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)

		EnsureStageInputDefaults(stage)

		Local out:TFixtureState[]
		Local round:Int = 1

		For Local ev:TSeriesEvent = EachIn cfg.events
			If ev.sessions = Null Or ev.sessions.Length = 0 Then
				' fallback: create a single "RACE" session if none declared
				Local s:TFixtureState = New TFixtureState
				s.id = stage.id + "_" + ev.id + "_RACE"
				s.seriesEventId = ev.id
				s.sessionCode = "RACE"
				s.round = round
				s.status = EFixtureStatus.Scheduled
				out :+ [s]
				round :+ 1
			Else
				For Local sess:TSession = EachIn ev.sessions
					Local s:TFixtureState = New TFixtureState
					s.id = stage.id + "_" + ev.id + "_" + sess.code
					s.seriesEventId = ev.id
					s.sessionCode = sess.code
					s.round = round
					s.status = EFixtureStatus.Scheduled
					out :+ [s]
					round :+ 1
				Next
			End If
		Next

		Return out
	End Method
End Type

' -------- SERIES SCORER --------
Rem
bbdoc: Awards session points and computes series championships.
End Rem
Type TSeriesScorer Implements IStageScorer

	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload) Override
		If Not result Or (result.kind <> EResultKind.Classification And result.kind <> EResultKind.TimeBased) Then
			Throw "SeriesScorer: ApplyResult called with wrong result kind"
		End If

		' Apply results and mark the event final
		For Local f:TFixtureState = EachIn st.fixtures
			If f.id = fxId Then
				If result.kind = EResultKind.Classification Then
					ValidateAwardCaps(stage, f, result.awards)
				End If

				f.status = EFixtureStatus.Completed
				If result.kind = EResultKind.Classification Then
					f.awards = result.awards[..]
					f.classificationOrder = result.order[..]
					f.finishStatuses = result.statuses[..]
				Else
					f.timeResults = result.times[..]
					f.finishStatuses = []
					For Local time:TParticipantTime = EachIn result.times
						Local status:TFinishStatus = New TFinishStatus
						status.participantId = time.participantId
						Select time.status
							Case ETimeStatus.DNF status.flag = EFinishFlag.DNF
							Case ETimeStatus.DSQ status.flag = EFinishFlag.DSQ
							Case ETimeStatus.DNS status.flag = EFinishFlag.DNS
							Default status.flag = EFinishFlag.OK
						End Select

						f.finishStatuses :+ [status]
					Next

					Local ranked:TTimedRank[] = TTimeScorer.BuildRanked(result.times)
					f.classificationOrder = []
					For Local rank:TTimedRank = EachIn ranked
						f.classificationOrder :+ [rank.participantId]
					Next
				End If

				f.resultLog :+ [ result ]
				Exit
			End If
		Next

	End Method

	Function ValidateAwardCaps(stage:TStage, fixture:TFixtureState, awards:TResultAward[])
		If awards = Null Or awards.Length = 0 Then
			Return
		End If

		Local config:TSeriesConfig = TSeriesConfig(stage.config)
		ValidateScoringAwardCaps(ResolveSessionScoring(stage, fixture.seriesEventId, fixture.sessionCode), awards, config.pointsScale)
		For Local championship:TChampionshipConfig = EachIn config.championships
			If championship.scoringOverride = Null Then
				Continue
			End If

			If championship.sessionCodes <> Null And championship.sessionCodes.Length > 0 Then
				Local included:Int = False
				For Local code:String = EachIn championship.sessionCodes
					If code = fixture.sessionCode Then included = True; Exit
				Next

				If Not included Then
					Continue
				End If
			End If

			ValidateScoringAwardCaps(championship.scoringOverride, awards, config.pointsScale)
		Next
	End Function

	Function ValidateScoringAwardCaps(scoring:TScoringSystem, awards:TResultAward[], scale:Int)
		If scoring = Null Then
			Return
		End If

		For Local award:TResultAward = EachIn awards
			For Local rule:TBonusRule = EachIn scoring.bonuses
				If rule.code <> award.code Then
					Continue
				End If

				Local points:Int = AwardUnits(award, rule, scale)
				Local cap:Int = ConfigPointUnits(rule.maxPointsPerAward, rule.maxPointsPerAwardExact, scale)
				If cap > 0 And points > cap Then
					Throw "Award exceeds its configured point cap: " + rule.code
				End If
			Next
		Next
	End Function

	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState)
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		If cfg.scoring <> Null And cfg.scoring.mode = EScoringMode.TimeBased And (cfg.championships = Null Or cfg.championships.Length = 0) Then
			Local timeScorer:TTimeScorer = New TTimeScorer
			timeScorer.ComputeStandings(comp, stage, st)
			Return
		End If

		st.leaderboard.rows = ComputeRows(comp, stage, st, Null)
		st.championships = []
		For Local championship:TChampionshipConfig = EachIn cfg.championships
			Local named:TNamedLeaderboard = New TNamedLeaderboard
			named.code = championship.code
			named.leaderboard = New TLeaderboard
			named.leaderboard.rows = ComputeRows(comp, stage, st, championship)
			st.championships :+ [named]
		Next
	End Method

	Method ComputeRows:TLeaderboardRow[](comp:TCompetition, stage:TStage, st:TStageState, championship:TChampionshipConfig)
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		If cfg.pointsScale < 1 Then
			Throw "Series pointsScale must be positive"
		End If

		Local rows:TIntMap = New TIntMap ' pid -> TLeaderboardRow
		Local awardsLedger:TSeriesAwardLedger = New TSeriesAwardLedger

		If championship <> Null And championship.parentTeamPoints Then
			For Local p:TParticipant = EachIn comp.participants
				If p.kind = EParticipantKind.Team Then
					Local r:TLeaderboardRow = New TLeaderboardRow
					r.participantId = p.id
					rows.Insert(p.id, r)
				End If
			Next
		ElseIf st.entrants <> Null And st.entrants.Length > 0 Then
			For Local id:Int = EachIn st.entrants
				If championship <> Null And championship.filterByKind Then
					Local participant:TParticipant = FindParticipantById(comp, id)
					If participant = Null Or participant.kind <> championship.participantKind Then
						Continue
					End If
				End If

				Local r:TLeaderboardRow = New TLeaderboardRow
				r.participantId = id
				rows.Insert(id, r)
			Next
		Else
			For Local p:TParticipant = EachIn comp.participants
				Local r:TLeaderboardRow = New TLeaderboardRow
				r.participantId = p.id
				rows.Insert(p.id, r)
			Next
		End If

		' award points for each finalized event
		For Local f:TFixtureState = EachIn st.fixtures

			If f.status <> EFixtureStatus.Completed Then
				Continue
			End If

			If championship <> Null And championship.sessionCodes <> Null And championship.sessionCodes.Length > 0 Then
				Local allowed:Int = False
				For Local code:String = EachIn championship.sessionCodes
					If code = f.sessionCode Then allowed = True; Exit
				Next

				If Not allowed Then
					Continue
				End If
			End If

			' 1) Get the right scoring for this session
			Local sessScoring:TScoringSystem = ResolveSessionScoring(stage, f.seriesEventId, f.sessionCode)
			If championship <> Null And championship.scoringOverride <> Null Then
				sessScoring = championship.scoringOverride
			End If

			If sessScoring = Null Then
				Continue
			End If

			' 2) Get the session classification order (you already stored this when applying results)
			Local order:Int[] = f.classificationOrder

			Local sessionRows:TIntMap = New TIntMap
			For Local pid:Int = EachIn order
				Local row:TLeaderboardRow = New TLeaderboardRow
				row.participantId = pid
				sessionRows.Insert(pid, row)
			Next

			If sessScoring.table <> Null And order <> Null Then
				AwardPoints(sessionRows, order, sessScoring, cfg.pointsScale)
			End If

			If f.awards <> Null And f.awards.Length > 0 Then
				ApplyAwards(sessionRows, order, sessScoring, f.sessionCode, f.seriesEventId, f.awards, f.finishStatuses, awardsLedger, cfg.pointsScale)
			End If

			For Local pid:Int = EachIn order
				Local earned:TLeaderboardRow = TLeaderboardRow(sessionRows.ValueForKey(pid))
				Local targetId:Int = pid
				If championship <> Null And championship.parentTeamPoints Then
					Local participant:TParticipant = FindParticipantById(comp, pid)
					If participant = Null Or participant.parentTeamId = 0 Then
						Continue
					End If

					targetId = participant.parentTeamId
				End If

				Local total:TLeaderboardRow = TLeaderboardRow(rows.ValueForKey(targetId))
				If total <> Null Then
					total.points :+ EventPointsUnits(stage, f.seriesEventId, earned.points)
				End If
			Next
		Next

		' Rank the recorded table with the same rules used by qualification analysis.
		Local arr:TLeaderboardRow[]
		For Local it:TIntKey = EachIn rows.Keys()
			Local pid:Int = it.value
			arr :+ [ TLeaderboardRow(rows.ValueForKey(pid)) ]
		Next

		Local scopeKey:String
		If championship <> Null Then
			scopeKey = championship.code
		End If

		TSeriesRanker.SortRows(arr, TSeriesRanker.Build(comp, stage, st, championship, arr), st.tableTieDecisions, scopeKey)
		Return arr
	End Method

	' Convert the exact stored unit count to a displayable decimal point total.
	Rem
	bbdoc: Formats stored standings units as a point total.
	param: Standings row containing the scaled integer points.
	param: Series configuration defining units per point.
	returns: An exact decimal where possible, or a fraction for other scales.
	End Rem
	Function PointsText:String(row:TLeaderboardRow, config:TSeriesConfig)
		If config.pointsScale < 1 Then
			Throw "Series pointsScale must be positive"
		End If

		If row.points Mod config.pointsScale = 0 Then
			Return String(row.points / config.pointsScale)
		End If

		Local factor:Int = config.pointsScale
		While factor Mod 2 = 0
			factor :/ 2
		Wend

		While factor Mod 5 = 0
			factor :/ 5
		Wend

		If factor = 1 Then
			Return (Decimal(row.points) / Decimal(config.pointsScale)).ToString()
		End If

		Return String(row.points) + "/" + String(config.pointsScale)
	End Function

	Function FindParticipantById:TParticipant(comp:TCompetition, id:Int)
		For Local p:TParticipant = EachIn comp.participants
			If p.id = id Then
				Return p
			End If
		Next

		Return Null
	End Function

	Function EventMultiplier:Float(stage:TStage, eventId:String)
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		For Local event:TSeriesEvent = EachIn cfg.events
			If event.id = eventId Then
				If event.pointsMultiplierExact <> "" Then
					Return Float(event.pointsMultiplierExact)
				End If

				If event.pointsMultiplier > 0 Then
					Return event.pointsMultiplier
				End If

				Return 1.0
			End If
		Next

		Return 1.0
	End Function

	' Convert one session's whole points to the configured integer units. Decimal
	' multipliers must fit those units exactly, preventing silent point loss.
	Function EventPoints:Int(stage:TStage, eventId:String, basePoints:Int)
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		Return EventPointsUnits(stage, eventId, ConfigPointUnits(basePoints, "", cfg.pointsScale))
	End Function

	Function EventPointsUnits:Int(stage:TStage, eventId:String, baseUnits:Int)
		Local cfg:TSeriesConfig = TSeriesConfig(stage.config)
		If cfg.pointsScale < 1 Then
			Throw "Series pointsScale must be positive"
		End If

		For Local event:TSeriesEvent = EachIn cfg.events
			If event.id <> eventId Then
				Continue
			End If

			If event.pointsMultiplierExact <> "" Then
				Local value:TDecimal = Decimal(baseUnits) * Decimal(event.pointsMultiplierExact)
				If value > Decimal(2000000000) Or value < Decimal(-2000000000) Then
					Throw "Series points exceed integer range"
				End If

				Local units:Int = value.ToInt()
				If value <> Decimal(units) Then
					Throw "Series pointsScale cannot represent event points exactly"
				End If

				Return units
			End If

			Exit
		Next

		Local legacyValue:Float = Float(baseUnits) * EventMultiplier(stage, eventId)
		If legacyValue > 2000000000.0 Or legacyValue < -2000000000.0 Then
			Throw "Series points exceed integer range"
		End If

		Return Int(legacyValue + 0.5)
	End Function

	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState) {asBool}
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Return False
			End If
		Next

		Return True
	End Method

	' ---- helpers ----

	Method AwardPoints(rows:TIntMap, order:Int[], scoring:TScoringSystem, scale:Int)
		' Build a fast lookup for points by finishing position (1-based)
		Local maxPos:Int = 0
		For Local e:TPointsTableEntry = EachIn scoring.table
			If e.position > maxPos Then
				maxPos = e.position
			End If
		Next

		Local pts:Int[] = New Int[maxPos + 1]
		For Local e:TPointsTableEntry = EachIn scoring.table
			pts[e.position] = ConfigPointUnits(e.points, e.pointsExact, scale)
		Next

		For Local i:Int = 0 Until order.Length
			Local pid:Int = order[i]
			Local pos:Int = i + 1
			Local row:TLeaderboardRow = TLeaderboardRow(rows.ValueForKey(pid))
			If row = Null Then
				Continue
			End If

			If pos <= maxPos Then
				row.points :+ pts[pos]
			End If
		Next
	End Method

	' Apply structured awards to leaderboard rows.
	' - rows: TIntMap of pid -> TLeaderboardRow (same map you pass to AwardPoints)
	' - order: final classification order for this session (used for minFinishPosition checks)
	' - scoring: stage scoring config (source of truth for allowed bonuses/rules)
	' - sessionCode/eventId: context (allow/uniqueness). Pass "" if not tracking.
	' - awards: awards attached to this session (e.g., from fixture.f.awards)
	Function ApplyAwards(rows:TIntMap, order:Int[], scoring:TScoringSystem, sessionCode:String, eventId:String, awards:TResultAward[], statuses:TFinishStatus[], ledger:TSeriesAwardLedger, scale:Int)
		If scoring = Null Or scoring.bonuses = Null Or awards = Null Or awards.Length = 0 Then
			Return
		End If

		' Build registry: code -> TBonusRule
		Local reg:TStringMap = New TStringMap
		For Local r:TBonusRule = EachIn scoring.bonuses
			reg.Insert(r.code, r)
		Next

		' Build position index (pid -> pos) for minFinishPosition checks
		Local posIndex:TIntMap = New TIntMap
		For Local i:Int = 0 Until order.Length
			posIndex.Insert(order[i], String(i + 1))
		Next

		' Uniqueness trackers
		Local seenPerSession:TStringMap = ledger.perSession
		Local seenPerEvent:TStringMap = ledger.perEvent
		Local seenByPartEvent:TStringMap = ledger.perParticipantEvent

		For Local aw:TResultAward = EachIn awards
			' Lookup rule
			Local rule:TBonusRule = TBonusRule(reg.ValueForKey(aw.code))
			If rule = Null Then
				Continue ' unknown code -> ignore (or Throw if you want strict)
			End If

			' Session allow-list
			If rule.allowedSessions <> Null And rule.allowedSessions.Length > 0 Then
				Local ok:Int
				For Local s:String = EachIn rule.allowedSessions
					If s = sessionCode Then
						ok = True
						Exit
					End If
				Next

				If Not ok Then
					Continue
				End If
			End If

			' Eligibility: typed conditions
			Local pos:Int = Int(String(posIndex.ValueForKey(aw.participantId)))
			If rule.minFinishPosition > 0 And (pos = 0 Or pos > rule.minFinishPosition) Then
				Continue
			End If

			If aw.conditions <> Null And aw.conditions.minFinishPosition > 0 Then
				If pos = 0 Or pos > aw.conditions.minFinishPosition Then
					Continue
				End If
			End If

			If rule.requireFinish Or (aw.conditions <> Null And aw.conditions.mustFinish) Then
				Local finished:Int = True
				For Local status:TFinishStatus = EachIn statuses
					If status.participantId = aw.participantId And status.flag <> EFinishFlag.OK Then
						finished = False
					End If
				Next

				If Not finished Then
					Continue
				End If
			End If

			' Uniqueness / caps
			If rule.uniquePerSession Then
				Local sessionKey:String = eventId + "|" + sessionCode + "|" + rule.code
				Local c:Int = Int(String(seenPerSession.ValueForKey(sessionKey)))
				If c >= 1 Then
					Continue
				End If

				seenPerSession.Insert(sessionKey, String(c + 1))
			End If

			Local evKey:String = eventId
			If rule.uniquePerEvent Or rule.maxAwardsPerEvent > 0 Then
				Local c:Int = Int(String(seenPerEvent.ValueForKey(rule.code + "|" + evKey)))
				If rule.uniquePerEvent And c >= 1 Then
					Continue
				End If

				If rule.maxAwardsPerEvent > 0 And c >= rule.maxAwardsPerEvent Then
					Continue
				End If

				seenPerEvent.Insert(rule.code + "|" + evKey, String(c + 1))
			End If

			If rule.uniquePerParticipantPerEvent Then
				Local k:String = rule.code + "|" + evKey + "|" + aw.participantId
				If Int(String(seenByPartEvent.ValueForKey(k))) = 1 Then
					Continue
				End If

				seenByPartEvent.Insert(k, "1")
			End If

			' Points: override > 0 else default from rule
			Local pts:Int = AwardUnits(aw, rule, scale)

			If pts <= 0 Then
				Continue
			End If

			Local cap:Int = ConfigPointUnits(rule.maxPointsPerAward, rule.maxPointsPerAwardExact, scale)
			If cap > 0 And pts > cap Then
				Throw "Award exceeds its configured point cap: " + rule.code
			End If

			' Apply to leaderboard
			Local row:TLeaderboardRow = TLeaderboardRow(rows.ValueForKey(aw.participantId))
			If row <> Null Then
				row.points :+ pts
			End If
		Next
	End Function

	Function AwardUnits:Int(award:TResultAward, rule:TBonusRule, scale:Int)
		If award.pointsOverrideExact <> "" Then
			Return ExactPointUnits(award.pointsOverrideExact, scale)
		End If

		If award.pointsOverride > 0 Then
			Return ConfigPointUnits(award.pointsOverride, "", scale)
		End If

		Return ConfigPointUnits(rule.points, rule.pointsExact, scale)
	End Function

	Function ResolveSessionScoring:TScoringSystem(stage:TStage, eventId:String, sessionCode:String)
		Local scfg:TSeriesConfig = TSeriesConfig(stage.config)
		If scfg = Null Then
			Return Null
		End If

		' look up event
		Local ev:TSeriesEvent = Null
		For Local e:TSeriesEvent = EachIn scfg.events
			If e.id = eventId Then
				ev = e
				Exit
			End If
		Next

		If ev = Null Then
			Return scfg.scoring ' fallback to base
		End If

		' look up session override
		If ev.sessions <> Null Then
			For Local sess:TSession = EachIn ev.sessions
				If sess.code = sessionCode And sess.scoringOverride <> Null Then
					Return sess.scoringOverride
				End If
			Next
		End If

		Return scfg.scoring ' default base scoring
	End Function
End Type

Rem
bbdoc: Selects participants from completed series standings.
End Rem
Type TSeriesAdvancer Implements IStageAdvancer
	Method ProduceAdvancements:TParticipant[](comp:TCompetition, stage:TStage, st:TStageState)
		If stage.advancement = Null Or stage.advancement.Length = 0 Then
			Return []
		End If
		' Use the first rule (you can iterate if you add multiple)
		Local rule:TFilterRule = stage.advancement[0].rule
		If rule.kind <> EFilterKind.TopN Then
			Return []
		End If

		Local n:Int = Max(0, rule.n)

		Local out:TParticipant[]
		Local rows:TLeaderboardRow[] = st.leaderboard.rows
		If stage.advancement[0].championshipCode <> "" Then
			rows = Null
			For Local named:TNamedLeaderboard = EachIn st.championships
				If named.code = stage.advancement[0].championshipCode Then rows = named.leaderboard.rows; Exit
			Next

			If rows = Null Then
				Throw "Unknown series championship for advancement: " + stage.advancement[0].championshipCode
			End If
		End If

		Local selected:Int[]
		For Local i:Int = Max(0, rule.startRank - 1) Until Min(Max(0, rule.startRank - 1) + n, rows.Length)
			Local pid:Int = rows[i].participantId
			selected :+ [pid]
			' lookup participant
			For Local p:TParticipant = EachIn comp.participants
				If p.id = pid Then
					out :+ [p]
					Exit
				End If
			Next
		Next

		For Local i:Int = 0 Until rows.Length
			For Local j:Int = i + 1 Until rows.Length
				If rows[i].sportingRank > 0 And rows[i].sportingRank = rows[j].sportingRank And InSelected(selected, rows[i].participantId) <> InSelected(selected, rows[j].participantId) Then
					Return Null
				End If
			Next
		Next

		Return out
	End Method

	Function InSelected:Int(ids:Int[], id:Int)
		For Local candidate:Int = EachIn ids
			If candidate = id Then
				Return True
			End If
		Next

		Return False
	End Function
End Type



' -------- SET-BASED SCORER --------
