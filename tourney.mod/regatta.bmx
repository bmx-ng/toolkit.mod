' Configurable low-point fleet regattas. The engine owns scheduling and status changes;
' this scorer owns race points, discards, medal qualification and series ties.
Rem
bbdoc: Shared scoring and discard calculations for fleet racing.
End Rem
Type TRegattaRules
	Function HasId:Int(ids:Int[], id:Int)
		For Local value:Int = EachIn ids
			If value = id Then
				Return True
			End If
		Next

		Return False
	End Function

	Function ScoreUnits:Int(cfg:TRegattaConfig, score:TRegattaRaceScore, fleetSize:Int)
		If score.scoreUnits > 0 Then
			Return score.scoreUnits
		End If

		If score.place > 0 Then
			Return score.place * cfg.pointScale
		End If

		Local automatic:Int
		If cfg.penaltyCodes <> Null Then
			For Local code:String = EachIn cfg.penaltyCodes
				If score.code = code Then
					automatic = True
				End If
			Next
		Else
			Select score.code
				Case "BFD", "DNC", "DNF", "DNS", "DSQ", "RET", "UFD", "DNE", "OCS", "NSC"
					automatic = True
			End Select
		End If

		If automatic Then
			Return (fleetSize + cfg.penaltyOffset) * cfg.pointScale
		End If

		Throw "Regatta score needs a place, exact score, or penalty code"
	End Function

	Function Better:Int(a:TRegattaStanding, b:TRegattaStanding, cfg:TRegattaConfig)
		If cfg.medalRanksAhead And a.medalQualified <> b.medalQualified Then
			Return a.medalQualified
		End If

		If a.totalUnits <> b.totalUnits Then
			Return a.totalUnits < b.totalUnits
		End If
		' RRS A8.1: compare included scores, best to worst.
		Local aa:Int[]
		Local bb:Int[]
		For Local score:TRegattaScore = EachIn a.scores
			If Not score.discarded Then
				aa :+ [score.scoreUnits]
			End If
		Next

		For Local score:TRegattaScore = EachIn b.scores
			If Not score.discarded Then
				bb :+ [score.scoreUnits]
			End If
		Next

		For Local i:Int = 0 Until aa.Length
			For Local j:Int = i + 1 Until aa.Length
				If aa[j] < aa[i] Then Local swap:Int = aa[i]; aa[i] = aa[j]; aa[j] = swap
			Next
		Next

		For Local i:Int = 0 Until bb.Length
			For Local j:Int = i + 1 Until bb.Length
				If bb[j] < bb[i] Then Local swap:Int = bb[i]; bb[i] = bb[j]; bb[j] = swap
			Next
		Next

		Local length:Int = Min(aa.Length, bb.Length)
		For Local i:Int = 0 Until length
			If aa[i] <> bb[i] Then
				Return aa[i] < bb[i]
			End If
		Next
		' RRS A8.2: latest race first, including discarded scores.
		For Local i:Int = Min(a.scores.Length, b.scores.Length) - 1 To 0 Step -1
			If a.scores[i].scoreUnits <> b.scores[i].scoreUnits Then
				Return a.scores[i].scoreUnits < b.scores[i].scoreUnits
			End If
		Next

		Return a.participantId < b.participantId
	End Function
End Type

Rem
bbdoc: Schedules sailing races and a possible medal race.
End Rem
Type TRegattaScheduler Implements IStageScheduler, IProgressiveStageScheduler
	Method Validate(cfg:TRegattaConfig, entrants:Int)
		If cfg = Null Or entrants < 2 Then
			Throw "Regatta needs at least two entrants"
		End If

		If cfg.scheduledRaces < 1 Or cfg.minimumRaces < 1 Or cfg.minimumRaces > cfg.scheduledRaces Then
			Throw "Invalid regatta race count"
		End If

		If cfg.pointScale < 1 Or cfg.penaltyOffset < 0 Then
			Throw "Invalid regatta point scale or penalty offset"
		End If

		If cfg.discardCount < 0 Or cfg.discardAfterRaces < 1 Then
			Throw "Invalid regatta discard rule"
		End If

		If cfg.medalPlaces < 0 Or cfg.medalPlaces > entrants Or (cfg.medalPlaces > 0 And cfg.medalMultiplier < 1) Then
			Throw "Invalid regatta medal rule"
		End If
	End Method

	Method NewRace:TFixtureState(stage:TStage, ids:Int[], round:Int, medal:Int = False)
		Local fixture:TFixtureState = New TFixtureState
		fixture.id = stage.id + "_RACE_" + round
		If medal Then
			fixture.id = stage.id + "_MEDAL"
		End If

		fixture.round = round
		fixture.participantIds = ids[..]
		fixture.status = EFixtureStatus.Scheduled
		Return fixture
	End Method

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
		Local cfg:TRegattaConfig = TRegattaConfig(stage.config)
		Validate(cfg, comp.participants.Length)
		Local ids:Int[]
		For Local participant:TParticipant = EachIn comp.participants
			If participant = Null Or participant.id <= 0 Or TRegattaRules.HasId(ids, participant.id) Then
				Throw "Invalid regatta entrant"
			End If

			ids :+ [participant.id]
		Next

		Return [NewRace(stage, ids, 1)]
	End Method

	Method NextFixtures:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TRegattaConfig = TRegattaConfig(stage.config)
		Local latest:TFixtureState = state.fixtures[state.fixtures.Length - 1]
		If latest.status <> EFixtureStatus.Completed And latest.status <> EFixtureStatus.Cancelled And latest.status <> EFixtureStatus.Abandoned Then
			Return Null
		End If

		If latest.round < cfg.scheduledRaces Then
			Return [NewRace(stage, state.fixtures[0].participantIds, latest.round + 1)]
		End If

		If latest.round > cfg.scheduledRaces Or cfg.medalPlaces = 0 Then
			Return Null
		End If

		Local sailed:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status = EFixtureStatus.Completed Then
				sailed :+ 1
			End If
		Next

		If sailed < cfg.minimumRaces Then
			Throw "Regatta has too few completed races for a medal race"
		End If

		Local ids:Int[]
		For Local i:Int = 0 Until cfg.medalPlaces
			ids :+ [state.regattaStandings[i].participantId]
		Next

		Return [NewRace(stage, ids, cfg.scheduledRaces + 1, True)]
	End Method
End Type

Rem
bbdoc: Scores low-point races, discards, and medal standings.
End Rem
Type TRegattaScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, state:TStageState, fixtureId:String, result:TResultPayload)
		If result.kind <> EResultKind.Custom Or result.customCode <> "regatta-race" Then
			Throw "Regatta needs race scores"
		End If

		Local fixture:TFixtureState
		For Local candidate:TFixtureState = EachIn state.fixtures
			If candidate.id = fixtureId Then fixture = candidate; Exit
		Next

		If fixture = Null Then
			Throw "Unknown regatta race"
		End If

		If fixture.status <> EFixtureStatus.Scheduled And fixture.status <> EFixtureStatus.InProgress Then
			Throw "Regatta race is not playable"
		End If

		If result.regattaScores = Null Or result.regattaScores.Length <> fixture.participantIds.Length Then
			Throw "Regatta result must cover every race entrant"
		End If

		Local cfg:TRegattaConfig = TRegattaConfig(stage.config)
		Local ids:Int[]
		Local places:Int[]
		For Local score:TRegattaRaceScore = EachIn result.regattaScores
			If score = Null Or Not TRegattaRules.HasId(fixture.participantIds, score.participantId) Or TRegattaRules.HasId(ids, score.participantId) Then
				Throw "Invalid or duplicate regatta race entrant"
			End If

			If score.place < 0 Or score.place > fixture.participantIds.Length Then
				Throw "Invalid regatta finishing place"
			End If

			If score.place > 0 And TRegattaRules.HasId(places, score.place) Then
				Throw "Duplicate regatta finishing place"
			End If

			If score.scoreUnits < 0 Then
				Throw "Regatta points cannot be negative"
			End If

			If score.code = "" And score.place = 0 And score.scoreUnits = 0 Then
				Throw "Regatta score has no result"
			End If

			If fixture.round > cfg.scheduledRaces And score.nonDiscardable Then
				Throw "Medal race is already non-discardable"
			End If

			TRegattaRules.ScoreUnits(cfg, score, fixture.participantIds.Length)
			ids :+ [score.participantId]
			If score.place > 0 Then
				places :+ [score.place]
			End If
		Next

		fixture.regattaScores = result.regattaScores[..]
		fixture.status = EFixtureStatus.Completed
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TRegattaConfig = TRegattaConfig(stage.config)
		Local standings:TRegattaStanding[]
		Local medal:TFixtureState
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.round > cfg.scheduledRaces Then medal = fixture; Exit
		Next

		For Local id:Int = EachIn state.fixtures[0].participantIds
			Local standing:TRegattaStanding = New TRegattaStanding
			standing.participantId = id
			If medal <> Null Then
				standing.medalQualified = TRegattaRules.HasId(medal.participantIds, id)
			End If

			Local opening:TRegattaScore[]
			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.status <> EFixtureStatus.Completed Then
					Continue
				End If

				For Local raw:TRegattaRaceScore = EachIn fixture.regattaScores
					If raw.participantId <> id Then
						Continue
					End If

					Local score:TRegattaScore = New TRegattaScore
					score.round = fixture.round
					score.code = raw.code
					score.nonDiscardable = raw.nonDiscardable Or raw.code = "DNE"
					score.scoreUnits = TRegattaRules.ScoreUnits(cfg, raw, fixture.participantIds.Length)
					If fixture.round > cfg.scheduledRaces Then
						score.scoreUnits :* cfg.medalMultiplier
						standing.medalUnits = score.scoreUnits
					Else
						opening :+ [score]
					End If

					standing.scores :+ [score]
					Exit
				Next
			Next

			If opening.Length >= cfg.discardAfterRaces Then
				For Local discard:Int = 0 Until Min(cfg.discardCount, opening.Length)
					Local worst:TRegattaScore
					For Local score:TRegattaScore = EachIn opening
						If score.discarded Or score.nonDiscardable Then
							Continue
						End If
						' If two worst scores tie, discard the earliest sailed one.
						If worst = Null Or score.scoreUnits > worst.scoreUnits Then
							worst = score
						End If
					Next

					If worst <> Null Then
						worst.discarded = True
					End If
				Next
			End If

			For Local score:TRegattaScore = EachIn opening
				If Not score.discarded Then
					standing.openingUnits :+ score.scoreUnits
				End If
			Next

			standing.totalUnits = standing.openingUnits + standing.medalUnits
			standings :+ [standing]
		Next

		For Local i:Int = 0 Until standings.Length
			For Local j:Int = i + 1 Until standings.Length
				If TRegattaRules.Better(standings[j], standings[i], cfg) Then
					Local swap:TRegattaStanding = standings[i]
					standings[i] = standings[j]
					standings[j] = swap
				End If
			Next
		Next

		state.regattaStandings = standings
		state.leaderboard = New TLeaderboard
		For Local standing:TRegattaStanding = EachIn standings
			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = standing.participantId
			row.points = standing.totalUnits
			Local metric:TLeaderboardMetric = New TLeaderboardMetric
			metric.code = "regatta-points-units"
			metric.value = standing.totalUnits
			row.metrics = [metric]
			state.leaderboard.rows :+ [row]
		Next
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TRegattaConfig = TRegattaConfig(stage.config)
		If state.fixtures.Length < cfg.scheduledRaces Then
			Return False
		End If

		Local sailed:Int
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status = EFixtureStatus.Scheduled Or fixture.status = EFixtureStatus.InProgress Or fixture.status = EFixtureStatus.Postponed Then
				Return False
			End If

			If fixture.round <= cfg.scheduledRaces And fixture.status = EFixtureStatus.Completed Then
				sailed :+ 1
			End If
		Next

		If sailed < cfg.minimumRaces Then
			Return False
		End If

		If cfg.medalPlaces > 0 Then
			If state.fixtures.Length <> cfg.scheduledRaces + 1 Then
				Return False
			End If

			Return state.fixtures[cfg.scheduledRaces].status = EFixtureStatus.Completed
		End If

		Return True
	End Method
End Type
