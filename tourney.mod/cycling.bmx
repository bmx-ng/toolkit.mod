' Multi-classification stage races. Stage results and checkpoint crossings are
' retained verbatim; every classification is rebuilt from completed stages.
Rem
bbdoc: A team's stage place and time used in team classification.
End Rem
Type TCyclingTeamStage
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: Seconds for this cycling team stage.
	End Rem
	Field seconds:Long
	Rem
	bbdoc: Place sum for this cycling team stage.
	End Rem
	Field placeSum:Int
	Rem
	bbdoc: Best place for this cycling team stage.
	End Rem
	Field bestPlace:Int
End Type

Rem
bbdoc: Shared calculations and validation for cycling classifications.
End Rem
Type TCyclingRules
	Function HasId:Int(ids:Int[], id:Int)
		For Local value:Int = EachIn ids
			If value = id Then
				Return True
			End If
		Next

		Return False
	End Function

	Function Rider:TCyclingStanding(standings:TCyclingStanding[], id:Int)
		For Local standing:TCyclingStanding = EachIn standings
			If standing.participantId = id Then
				Return standing
			End If
		Next

		Return Null
	End Function

	Function Team:TCyclingTeamStanding(standings:TCyclingTeamStanding[], id:Int)
		For Local standing:TCyclingTeamStanding = EachIn standings
			If standing.teamId = id Then
				Return standing
			End If
		Next

		Return Null
	End Function

	Function Checkpoint:TCyclingCheckpointRule(rule:TCyclingStageRule, code:String)
		For Local checkpoint:TCyclingCheckpointRule = EachIn rule.checkpoints
			If checkpoint.code = code Then
				Return checkpoint
			End If
		Next

		Return Null
	End Function

	Function CheckpointPoints:Int[](cfg:TCyclingConfig, checkpoint:TCyclingCheckpointRule)
		If checkpoint.classification = "BONUS" Then
			Return Null
		End If

		If checkpoint.points <> Null And checkpoint.points.Length > 0 Then
			Return checkpoint.points
		End If

		If checkpoint.classification = "POINTS" Then
			Return cfg.sprintPoints
		End If

		For Local climb:TCyclingClimbRule = EachIn cfg.climbPoints
			If climb.category = checkpoint.category Then
				Return climb.points
			End If
		Next

		Throw "Missing cycling climb category: " + checkpoint.category
	End Function

	Function BonusSeconds:Int(rule:TCyclingStageRule, crossings:TCyclingCheckpointResult[], result:TCyclingRiderResult)
		Local awarded:Int
		If result.place > 0 And result.place <= rule.finishBonusSeconds.Length Then
			awarded :+ rule.finishBonusSeconds[result.place - 1]
		End If

		For Local crossing:TCyclingCheckpointResult = EachIn crossings
			Local definition:TCyclingCheckpointRule = Checkpoint(rule, crossing.code)
			For Local i:Int = 0 Until Min(crossing.order.Length, definition.bonusSeconds.Length)
				If crossing.order[i] = result.participantId Then
					awarded :+ definition.bonusSeconds[i]
				End If
			Next
		Next

		Return awarded
	End Function

	Function HasBonusPolicy:Int(rule:TCyclingStageRule)
		If rule.finishBonusSeconds.Length > 0 Then
			Return True
		End If

		For Local checkpoint:TCyclingCheckpointRule = EachIn rule.checkpoints
			If checkpoint.bonusSeconds.Length > 0 Then
				Return True
			End If
		Next

		Return False
	End Function

	Function ClimbWins:Int(standing:TCyclingStanding, category:String)
		For Local wins:TCyclingClimbWin = EachIn standing.climbWins
			If wins.category = category Then
				Return wins.wins
			End If
		Next

		Return 0
	End Function

	Function AddClimbWin(standing:TCyclingStanding, category:String)
		For Local wins:TCyclingClimbWin = EachIn standing.climbWins
			If wins.category = category Then wins.wins :+ 1; Return
		Next

		Local wins:TCyclingClimbWin = New TCyclingClimbWin
		wins.category = category
		wins.wins = 1
		standing.climbWins :+ [wins]
	End Function

	Function BetterGC:Int(a:TCyclingStanding, b:TCyclingStanding)
		If a.active <> b.active Then
			Return a.active
		End If

		If a.stagesFinished <> b.stagesFinished Then
			Return a.stagesFinished > b.stagesFinished
		End If

		If a.totalSeconds <> b.totalSeconds Then
			Return a.totalSeconds < b.totalSeconds
		End If

		If a.timeTrialHundredths <> b.timeTrialHundredths Then
			Return a.timeTrialHundredths < b.timeTrialHundredths
		End If

		If a.stagePlaceSum <> b.stagePlaceSum Then
			Return a.stagePlaceSum < b.stagePlaceSum
		End If

		If a.lastStagePlace <> b.lastStagePlace Then
			Return a.lastStagePlace < b.lastStagePlace
		End If

		Return a.participantId < b.participantId
	End Function

	Function GCRank:Int(gc:TCyclingStanding[], id:Int)
		For Local i:Int = 0 Until gc.Length
			If gc[i].participantId = id Then
				Return i + 1
			End If
		Next

		Return 2147483647
	End Function

	Function BetterPoints:Int(a:TCyclingStanding, b:TCyclingStanding, gc:TCyclingStanding[])
		If a.pointsUnits <> b.pointsUnits Then
			Return a.pointsUnits > b.pointsUnits
		End If

		If a.stageWins <> b.stageWins Then
			Return a.stageWins > b.stageWins
		End If

		If a.sprintWins <> b.sprintWins Then
			Return a.sprintWins > b.sprintWins
		End If

		Return GCRank(gc, a.participantId) < GCRank(gc, b.participantId)
	End Function

	Function BetterClimber:Int(a:TCyclingStanding, b:TCyclingStanding, gc:TCyclingStanding[], cfg:TCyclingConfig)
		If a.climberUnits <> b.climberUnits Then
			Return a.climberUnits > b.climberUnits
		End If

		For Local category:TCyclingClimbRule = EachIn cfg.climbPoints
			Local aw:Int = ClimbWins(a, category.category)
			Local bw:Int = ClimbWins(b, category.category)
			If aw <> bw Then
				Return aw > bw
			End If
		Next

		Return GCRank(gc, a.participantId) < GCRank(gc, b.participantId)
	End Function

	Function BetterTeamStage:Int(a:TCyclingTeamStage, b:TCyclingTeamStage)
		If a.seconds <> b.seconds Then
			Return a.seconds < b.seconds
		End If

		If a.placeSum <> b.placeSum Then
			Return a.placeSum < b.placeSum
		End If

		If a.bestPlace <> b.bestPlace Then
			Return a.bestPlace < b.bestPlace
		End If

		Return a.teamId < b.teamId
	End Function

	Function BetterTeam:Int(a:TCyclingTeamStanding, b:TCyclingTeamStanding, cfg:TCyclingConfig, gc:TCyclingStanding[])
		If a.eligible <> b.eligible Then
			Return a.eligible
		End If

		If a.totalSeconds <> b.totalSeconds Then
			Return a.totalSeconds < b.totalSeconds
		End If

		For Local i:Int = 0 Until Min(a.stagePlaces.Length, b.stagePlaces.Length)
			If a.stagePlaces[i] <> b.stagePlaces[i] Then
				Return a.stagePlaces[i] > b.stagePlaces[i]
			End If
		Next

		Local arank:Int = 2147483647
		Local brank:Int = 2147483647
		For Local i:Int = 0 Until gc.Length
			If gc[i].teamId = a.teamId And i + 1 < arank Then
				arank = i + 1
			End If

			If gc[i].teamId = b.teamId And i + 1 < brank Then
				brank = i + 1
			End If
		Next

		If arank <> brank Then
			Return arank < brank
		End If

		Return a.teamId < b.teamId
	End Function

	Function Row:TLeaderboardRow(id:Int, value:Int, seconds:Long = 0)
		Local row:TLeaderboardRow = New TLeaderboardRow
		row.participantId = id
		row.points = value
		row.timeSeconds = seconds
		Return row
	End Function

	Function Named:TNamedLeaderboard(code:String, rows:TLeaderboardRow[])
		Local board:TNamedLeaderboard = New TNamedLeaderboard
		board.code = code
		board.leaderboard = New TLeaderboard
		board.leaderboard.rows = rows
		Return board
	End Function
End Type

Rem
bbdoc: Schedules stages and checkpoints in a cycling race.
End Rem
Type TCyclingScheduler Implements IStageScheduler, IProgressiveStageScheduler
	Method Validate(comp:TCompetition, cfg:TCyclingConfig)
		If cfg = Null Or cfg.stages = Null Or cfg.stages.Length = 0 Then
			Throw "Cycling stage race needs stages"
		End If

		If cfg.pointsScale < 1 Or cfg.ridersPerTeam < 1 Then
			Throw "Invalid cycling points scale or team count"
		End If

		Local teams:Int[]
		Local riders:Int[]
		For Local participant:TParticipant = EachIn comp.participants
			If participant = Null Or participant.id <= 0 Then
				Throw "Invalid cycling participant"
			End If

			If participant.kind = EParticipantKind.Team Then
				If TCyclingRules.HasId(teams, participant.id) Or TCyclingRules.HasId(riders, participant.id) Then
					Throw "Duplicate cycling participant ID"
				End If

				teams :+ [participant.id]
			Else
				If TCyclingRules.HasId(teams, participant.id) Or TCyclingRules.HasId(riders, participant.id) Then
					Throw "Duplicate cycling participant ID"
				End If

				riders :+ [participant.id]
			End If
		Next

		If riders.Length < 2 Then
			Throw "Cycling stage race needs riders"
		End If

		For Local participant:TParticipant = EachIn comp.participants
			If participant.kind = EParticipantKind.Individual And participant.parentTeamId <> 0 And Not TCyclingRules.HasId(teams, participant.parentTeamId) Then
				Throw "Cycling rider has unknown team"
			End If
		Next

		For Local id:Int = EachIn cfg.youngRiderIds
			If Not TCyclingRules.HasId(riders, id) Then
				Throw "Unknown young rider"
			End If
		Next

		Local stageIds:String[]
		For Local rule:TCyclingStageRule = EachIn cfg.stages
			If rule = Null Or rule.id = "" Then
				Throw "Cycling stage needs an ID"
			End If

			For Local seen:String = EachIn stageIds
				If seen = rule.id Then
					Throw "Duplicate cycling stage ID"
				End If
			Next

			stageIds :+ [rule.id]
			Local codes:String[]
			For Local checkpoint:TCyclingCheckpointRule = EachIn rule.checkpoints
				If checkpoint = Null Or checkpoint.code = "" Then
					Throw "Cycling checkpoint needs a code"
				End If

				For Local code:String = EachIn codes
					If code = checkpoint.code Then
						Throw "Duplicate cycling checkpoint code"
					End If
				Next

				codes :+ [checkpoint.code]
				If checkpoint.classification <> "POINTS" And checkpoint.classification <> "CLIMBER" And checkpoint.classification <> "BONUS" Then
					Throw "Unknown cycling checkpoint classification"
				End If

				If checkpoint.classification = "BONUS" Then
					If checkpoint.bonusSeconds = Null Or checkpoint.bonusSeconds.Length = 0 Then
						Throw "Cycling bonus checkpoint needs awards"
					End If
				Else
					TCyclingRules.CheckpointPoints(cfg, checkpoint)
				End If
			Next
		Next
	End Method

	Method NewStage:TFixtureState(stage:TStage, ids:Int[], round:Int, cfg:TCyclingConfig)
		Local fixture:TFixtureState = New TFixtureState
		fixture.id = stage.id + "_" + cfg.stages[round - 1].id
		fixture.round = round
		fixture.participantIds = ids[..]
		fixture.status = EFixtureStatus.Scheduled
		Return fixture
	End Method

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage)
		Local cfg:TCyclingConfig = TCyclingConfig(stage.config)
		Validate(comp, cfg)
		Local ids:Int[]
		For Local participant:TParticipant = EachIn comp.participants
			If participant.kind = EParticipantKind.Individual Then
				ids :+ [participant.id]
			End If
		Next

		Return [NewStage(stage, ids, 1, cfg)]
	End Method

	Method NextFixtures:TFixtureState[](comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TCyclingConfig = TCyclingConfig(stage.config)
		Local latest:TFixtureState = state.fixtures[state.fixtures.Length - 1]
		If latest.status <> EFixtureStatus.Completed Or latest.round >= cfg.stages.Length Then
			Return Null
		End If

		Local ids:Int[]
		For Local result:TCyclingRiderResult = EachIn latest.cyclingResults
			If result.status = ECyclingRiderStatus.Finished Then
				ids :+ [result.participantId]
			End If
		Next

		If ids.Length = 0 Then
			Throw "Cycling stage race has no remaining riders"
		End If

		Return [NewStage(stage, ids, latest.round + 1, cfg)]
	End Method
End Type

Rem
bbdoc: Updates rider and team classifications from stage results.
End Rem
Type TCyclingScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, state:TStageState, fixtureId:String, result:TResultPayload)
		If result.kind <> EResultKind.Custom Or result.customCode <> "cycling-stage" Then
			Throw "Cycling needs stage results"
		End If

		Local fixture:TFixtureState
		For Local candidate:TFixtureState = EachIn state.fixtures
			If candidate.id = fixtureId Then fixture = candidate; Exit
		Next

		If fixture = Null Then
			Throw "Unknown cycling stage"
		End If

		If fixture.status <> EFixtureStatus.Scheduled And fixture.status <> EFixtureStatus.InProgress Then
			Throw "Cycling stage is not playable"
		End If

		If result.cyclingResults = Null Or result.cyclingResults.Length <> fixture.participantIds.Length Then
			Throw "Cycling result must cover every active rider"
		End If

		Local cfg:TCyclingConfig = TCyclingConfig(stage.config)
		Local rule:TCyclingStageRule = cfg.stages[fixture.round - 1]
		Local seen:Int[]
		Local places:Int[]
		For Local rider:TCyclingRiderResult = EachIn result.cyclingResults
			If rider = Null Or Not TCyclingRules.HasId(fixture.participantIds, rider.participantId) Or TCyclingRules.HasId(seen, rider.participantId) Then
				Throw "Missing, unknown or duplicate cycling rider"
			End If

			seen :+ [rider.participantId]
			If rider.status = ECyclingRiderStatus.Finished Then
				If rider.place < 1 Or rider.elapsedSeconds < 1 Or TCyclingRules.HasId(places, rider.place) Then
					Throw "Invalid cycling finish"
				End If

				If rider.bonusSeconds < 0 Or rider.penaltySeconds < 0 Or rider.timeTrialHundredths < 0 Or rider.timeTrialHundredths > 99 Then
					Throw "Invalid cycling time adjustment"
				End If

				If Long(rider.elapsedSeconds) - rider.bonusSeconds + rider.penaltySeconds + rider.gcAdjustmentSeconds < 1 Then
					Throw "Invalid credited cycling time"
				End If

				places :+ [rider.place]
			ElseIf rider.place <> 0 Or rider.elapsedSeconds <> 0 Then
				Throw "Non-finishing cyclist cannot have a stage time or place"
			End If
		Next

		Local checkpointCodes:String[]
		For Local checkpoint:TCyclingCheckpointResult = EachIn result.cyclingCheckpoints
			If checkpoint = Null Or TCyclingRules.Checkpoint(rule, checkpoint.code) = Null Then
				Throw "Unknown cycling checkpoint"
			End If

			For Local code:String = EachIn checkpointCodes
				If code = checkpoint.code Then
					Throw "Duplicate cycling checkpoint result"
				End If
			Next

			checkpointCodes :+ [checkpoint.code]
			Local definition:TCyclingCheckpointRule = TCyclingRules.Checkpoint(rule, checkpoint.code)
			Local table:Int[] = TCyclingRules.CheckpointPoints(cfg, definition)
			Local capacity:Int = definition.bonusSeconds.Length
			If table <> Null Then
				capacity = table.Length
			End If

			If checkpoint.order = Null Or checkpoint.order.Length = 0 Or checkpoint.order.Length > capacity Then
				Throw "Invalid cycling checkpoint order"
			End If

			Local checkpointRiders:Int[]
			For Local id:Int = EachIn checkpoint.order
				If Not TCyclingRules.HasId(fixture.participantIds, id) Or TCyclingRules.HasId(checkpointRiders, id) Then
					Throw "Invalid cycling checkpoint rider"
				End If

				checkpointRiders :+ [id]
			Next
		Next

		If checkpointCodes.Length <> rule.checkpoints.Length Then
			Throw "Cycling result must cover every configured checkpoint"
		End If

		For Local rider:TCyclingRiderResult = EachIn result.cyclingResults
			If rider.status <> ECyclingRiderStatus.Finished Then
				Continue
			End If

			Local computed:Int = TCyclingRules.BonusSeconds(rule, result.cyclingCheckpoints, rider)
			If rider.bonusRecorded And TCyclingRules.HasBonusPolicy(rule) And rider.bonusSeconds <> computed Then
				Throw "Recorded cycling bonus disagrees with configured awards"
			End If
		Next

		For Local adjustment:TCyclingPointAdjustment = EachIn result.cyclingAdjustments
			If adjustment = Null Or Not TCyclingRules.HasId(fixture.participantIds, adjustment.participantId) Then
				Throw "Invalid cycling points adjustment"
			End If
		Next

		For Local adjustment:TCyclingTeamAdjustment = EachIn result.cyclingTeamAdjustments
			If adjustment = Null Then
				Throw "Invalid cycling team adjustment"
			End If

			Local found:Int
			For Local participant:TParticipant = EachIn comp.participants
				If participant.kind = EParticipantKind.Team And participant.id = adjustment.teamId Then found = True; Exit
			Next

			If Not found Then
				Throw "Invalid cycling team adjustment"
			End If
		Next

		fixture.cyclingResults = result.cyclingResults[..]
		fixture.cyclingCheckpoints = result.cyclingCheckpoints[..]
		fixture.cyclingAdjustments = result.cyclingAdjustments[..]
		fixture.cyclingTeamAdjustments = result.cyclingTeamAdjustments[..]
		fixture.status = EFixtureStatus.Completed
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TCyclingConfig = TCyclingConfig(stage.config)
		Local riders:TCyclingStanding[]
		Local teams:TCyclingTeamStanding[]
		For Local participant:TParticipant = EachIn comp.participants
			If participant.kind = EParticipantKind.Team Then
				Local team:TCyclingTeamStanding = New TCyclingTeamStanding
				team.teamId = participant.id
				teams :+ [team]
			ElseIf TCyclingRules.HasId(state.fixtures[0].participantIds, participant.id) Then
				Local rider:TCyclingStanding = New TCyclingStanding
				rider.participantId = participant.id
				rider.teamId = participant.parentTeamId
				rider.active = True
				riders :+ [rider]
			End If
		Next

		For Local team:TCyclingTeamStanding = EachIn teams
			team.stagePlaces = New Int[teams.Length]
		Next

		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local rule:TCyclingStageRule = cfg.stages[fixture.round - 1]
			For Local raw:TCyclingRiderResult = EachIn fixture.cyclingResults
				Local rider:TCyclingStanding = TCyclingRules.Rider(riders, raw.participantId)
				If raw.status <> ECyclingRiderStatus.Finished Then
					rider.active = False
					Continue
				End If

				rider.stagesFinished :+ 1
				rider.elapsedSeconds :+ raw.elapsedSeconds
				Local awardedBonus:Int = TCyclingRules.BonusSeconds(rule, fixture.cyclingCheckpoints, raw)
				If Not TCyclingRules.HasBonusPolicy(rule) And raw.bonusRecorded Then
					awardedBonus = raw.bonusSeconds
				End If

				rider.bonusSeconds :+ awardedBonus
				rider.penaltySeconds :+ raw.penaltySeconds
				rider.gcAdjustmentSeconds :+ raw.gcAdjustmentSeconds
				rider.totalSeconds :+ raw.elapsedSeconds - awardedBonus + raw.penaltySeconds + raw.gcAdjustmentSeconds
				rider.stagePlaceSum :+ raw.place
				rider.lastStagePlace = raw.place
				If rule.isTimeTrial Then
					rider.timeTrialHundredths :+ raw.timeTrialHundredths
				End If

				If raw.place = 1 Then
					rider.stageWins :+ 1
				End If

				If raw.place <= rule.finishPoints.Length Then
					rider.pointsUnits :+ rule.finishPoints[raw.place - 1] * cfg.pointsScale
				End If
			Next

			For Local crossing:TCyclingCheckpointResult = EachIn fixture.cyclingCheckpoints
				Local checkpoint:TCyclingCheckpointRule = TCyclingRules.Checkpoint(rule, crossing.code)
				Local table:Int[] = TCyclingRules.CheckpointPoints(cfg, checkpoint)
				If checkpoint.classification = "BONUS" Then
					Continue
				End If

				For Local i:Int = 0 Until crossing.order.Length
					Local rider:TCyclingStanding = TCyclingRules.Rider(riders, crossing.order[i])
					If checkpoint.classification = "POINTS" Then
						rider.pointsUnits :+ table[i] * cfg.pointsScale
						If i = 0 Then
							rider.sprintWins :+ 1
						End If
					Else
						rider.climberUnits :+ table[i] * cfg.pointsScale
						If i = 0 Then
							TCyclingRules.AddClimbWin(rider, checkpoint.category)
						End If
					End If
				Next
			Next

			For Local adjustment:TCyclingPointAdjustment = EachIn fixture.cyclingAdjustments
				Local rider:TCyclingStanding = TCyclingRules.Rider(riders, adjustment.participantId)
				rider.pointsUnits :+ adjustment.pointsUnits
				rider.climberUnits :+ adjustment.climberUnits
			Next

			Local stageTeams:TCyclingTeamStage[]
			For Local team:TCyclingTeamStanding = EachIn teams
				Local times:Long[]
				Local places:Int[]
				For Local raw:TCyclingRiderResult = EachIn fixture.cyclingResults
					If raw.status <> ECyclingRiderStatus.Finished Then
						Continue
					End If

					Local rider:TCyclingStanding = TCyclingRules.Rider(riders, raw.participantId)
					If rider.teamId = team.teamId Then
						times :+ [raw.elapsedSeconds]
						places :+ [raw.place]
					End If
				Next

				If times.Length < cfg.ridersPerTeam Then
					Continue
				End If

				For Local i:Int = 0 Until times.Length
					For Local j:Int = i + 1 Until times.Length
						If times[j] < times[i] Then Local swap:Long = times[i]; times[i] = times[j]; times[j] = swap
					Next
				Next

				For Local i:Int = 0 Until places.Length
					For Local j:Int = i + 1 Until places.Length
						If places[j] < places[i] Then Local swap:Int = places[i]; places[i] = places[j]; places[j] = swap
					Next
				Next

				Local teamStage:TCyclingTeamStage = New TCyclingTeamStage
				teamStage.teamId = team.teamId
				For Local i:Int = 0 Until cfg.ridersPerTeam
					teamStage.seconds :+ times[i]
					teamStage.placeSum :+ places[i]
				Next

				teamStage.bestPlace = places[0]
				stageTeams :+ [teamStage]
				team.totalSeconds :+ teamStage.seconds
			Next

			For Local i:Int = 0 Until stageTeams.Length
				For Local j:Int = i + 1 Until stageTeams.Length
					If TCyclingRules.BetterTeamStage(stageTeams[j], stageTeams[i]) Then
						Local swap:TCyclingTeamStage = stageTeams[i]
						stageTeams[i] = stageTeams[j]
						stageTeams[j] = swap
					End If
				Next
			Next

			For Local i:Int = 0 Until stageTeams.Length
				Local team:TCyclingTeamStanding = TCyclingRules.Team(teams, stageTeams[i].teamId)
				team.stagePlaces[i] :+ 1
				If i = 0 Then
					team.stageWins :+ 1
				End If
			Next

			For Local adjustment:TCyclingTeamAdjustment = EachIn fixture.cyclingTeamAdjustments
				TCyclingRules.Team(teams, adjustment.teamId).totalSeconds :+ adjustment.seconds
			Next
		Next

		For Local team:TCyclingTeamStanding = EachIn teams
			For Local rider:TCyclingStanding = EachIn riders
				If rider.teamId = team.teamId And rider.active Then
					team.activeRiders :+ 1
				End If
			Next

			team.eligible = team.activeRiders >= cfg.ridersPerTeam
		Next

		For Local i:Int = 0 Until riders.Length
			For Local j:Int = i + 1 Until riders.Length
				If TCyclingRules.BetterGC(riders[j], riders[i]) Then
					Local swap:TCyclingStanding = riders[i]
					riders[i] = riders[j]
					riders[j] = swap
				End If
			Next
		Next

		state.cyclingStandings = riders
		state.leaderboard = New TLeaderboard
		For Local rider:TCyclingStanding = EachIn riders
			If rider.active Then
				state.leaderboard.rows :+ [TCyclingRules.Row(rider.participantId, 0, rider.totalSeconds)]
			End If
		Next

		Local points:TCyclingStanding[]
		Local climbers:TCyclingStanding[]
		Local youth:TCyclingStanding[]
		For Local rider:TCyclingStanding = EachIn riders
			If Not rider.active Then
				Continue
			End If

			If rider.pointsUnits > 0 Then
				points :+ [rider]
			End If

			If rider.climberUnits > 0 Then
				climbers :+ [rider]
			End If

			If TCyclingRules.HasId(cfg.youngRiderIds, rider.participantId) Then
				youth :+ [rider]
			End If
		Next

		For Local i:Int = 0 Until points.Length
			For Local j:Int = i + 1 Until points.Length
				If TCyclingRules.BetterPoints(points[j], points[i], riders) Then
					Local swap:TCyclingStanding = points[i]
					points[i] = points[j]
					points[j] = swap
				End If
			Next
		Next

		For Local i:Int = 0 Until climbers.Length
			For Local j:Int = i + 1 Until climbers.Length
				If TCyclingRules.BetterClimber(climbers[j], climbers[i], riders, cfg) Then
					Local swap:TCyclingStanding = climbers[i]
					climbers[i] = climbers[j]
					climbers[j] = swap
				End If
			Next
		Next

		For Local i:Int = 0 Until teams.Length
			For Local j:Int = i + 1 Until teams.Length
				If TCyclingRules.BetterTeam(teams[j], teams[i], cfg, riders) Then
					Local swap:TCyclingTeamStanding = teams[i]
					teams[i] = teams[j]
					teams[j] = swap
				End If
			Next
		Next

		state.cyclingTeamStandings = teams
		Local pointRows:TLeaderboardRow[]
		For Local rider:TCyclingStanding = EachIn points
			pointRows :+ [TCyclingRules.Row(rider.participantId, rider.pointsUnits)]
		Next

		Local climbRows:TLeaderboardRow[]
		For Local rider:TCyclingStanding = EachIn climbers
			climbRows :+ [TCyclingRules.Row(rider.participantId, rider.climberUnits)]
		Next

		Local youthRows:TLeaderboardRow[]
		For Local rider:TCyclingStanding = EachIn youth
			youthRows :+ [TCyclingRules.Row(rider.participantId, 0, rider.totalSeconds)]
		Next

		Local teamRows:TLeaderboardRow[]
		For Local team:TCyclingTeamStanding = EachIn teams
			If team.eligible Then
				teamRows :+ [TCyclingRules.Row(team.teamId, 0, team.totalSeconds)]
			End If
		Next

		state.championships = [TCyclingRules.Named("POINTS", pointRows), TCyclingRules.Named("CLIMBER", climbRows), TCyclingRules.Named("YOUTH", youthRows), TCyclingRules.Named("TEAM", teamRows)]
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, state:TStageState)
		Local cfg:TCyclingConfig = TCyclingConfig(stage.config)
		Return state.fixtures.Length = cfg.stages.Length And state.fixtures[cfg.stages.Length - 1].status = EFixtureStatus.Completed
	End Method
End Type
