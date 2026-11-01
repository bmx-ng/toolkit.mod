' Conservative point bounds for mathematically clinched championships.
Rem
bbdoc: Whether a leader's title is proven, still open, or unsupported.
End Rem
Enum EClinchStatus
	Rem
	bbdoc: Available bounds prove the leader cannot be caught.
	End Rem
	Clinched
	Rem
	bbdoc: The available bounds do not yet certify a winner.
	End Rem
	NotCertified
	Rem
	bbdoc: The format or remaining awards cannot provide finite usable bounds.
	End Rem
	Indeterminate
End Enum

Rem
bbdoc: Minimum and maximum attainable final points for one entrant.
End Rem
Type TClinchBound
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Current points for this clinch bound.
	End Rem
	Field currentPoints:Long
	Rem
	bbdoc: Minimum additional for this clinch bound.
	End Rem
	Field minimumAdditional:Long
	Rem
	bbdoc: Maximum additional for this clinch bound.
	End Rem
	Field maximumAdditional:Long
	Rem
	bbdoc: Minimum after next for this clinch bound.
	End Rem
	Field minimumAfterNext:Long
	Rem
	bbdoc: Maximum after next for this clinch bound.
	End Rem
	Field maximumAfterNext:Long

	Rem
	bbdoc: Returns current points plus the minimum remaining award.
	returns: The entrant's lower final-points bound.
	End Rem
	Method MinimumFinal:Long()
		Return currentPoints + minimumAdditional
	End Method

	Rem
	bbdoc: Returns current points plus the maximum remaining award.
	returns: The entrant's upper final-points bound.
	End Rem
	Method MaximumFinal:Long()
		Return currentPoints + maximumAdditional
	End Method
End Type

Rem
bbdoc: A possible next-event point total used in a clinching query.
End Rem
Type TProjectedPoints
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Points for this projected points.
	about: Total points once the next event or round has finished.
	End Rem
	Field points:Long ' total points once the next event or round has finished
End Type

Rem
bbdoc: Attainable bounds for entrants in a standings table.
End Rem
Type TClinchBoundsResult
	Rem
	bbdoc: #TClinchBound entries associated with this clinch bounds result.
	End Rem
	Field bounds:TClinchBound[]
	Rem
	bbdoc: ID of the next window associated with this clinch bounds result.
	End Rem
	Field nextWindowId:String
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: Calculates attainable points bounds for one format.
End Rem
Interface IClinchBoundsProvider
	Rem
	bbdoc: Computes attainable final points for a stage's entrants.
	param: Competition definition.
	param: Stage being analyzed.
	param: Current stage state and remaining fixtures.
	param: Named series championship, or #Null for the main table.
	param: Standings rows whose bounds are required.
	returns: A #TClinchBoundsResult, including a reason when bounds are unavailable.
	End Rem
	Method Calculate:TClinchBoundsResult(comp:TCompetition, stage:TStage, state:TStageState, championship:TChampionshipConfig, rows:TLeaderboardRow[])
End Interface

Rem
bbdoc: A clinching result and supporting point bounds.
about: A `Clinched` result proves the leader cannot be caught under the registered bounds. #ClinchesAfterNext checks a caller-supplied next-window points scenario against those bounds.
End Rem
Type TClinchAnalysis
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: Code identifying the associated championship.
	End Rem
	Field championshipCode:String
	Rem
	bbdoc: Current status of this clinch analysis.
	End Rem
	Field status:EClinchStatus
	Rem
	bbdoc: ID of the leader associated with this clinch analysis.
	End Rem
	Field leaderId:Int
	Rem
	bbdoc: ID of the clinched participant associated with this clinch analysis.
	End Rem
	Field clinchedParticipantId:Int
	Rem
	bbdoc: ID of the next window associated with this clinch analysis.
	End Rem
	Field nextWindowId:String
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
	Rem
	bbdoc: #TClinchBound entries associated with this clinch analysis.
	End Rem
	Field bounds:TClinchBound[]

	Rem
	bbdoc: Finds the attainable-points bounds for an entrant.
	param: Participant ID to find.
	returns: The matching #TClinchBound, or #Null.
	End Rem
	Method BoundFor:TClinchBound(participantId:Int)
		For Local bound:TClinchBound = EachIn bounds
			If bound.participantId = participantId Then
				Return bound
			End If
		Next

		Return Null
	End Method

	Rem
	bbdoc: Tests whether supplied next-window totals would clinch the title.
	param: Participant whose title is being tested.
	param: Projected total points for every entrant after the next window.
	returns: True only when the participant would be mathematically uncatchable.
	about: This evaluates a caller-supplied scenario; it does not generate match or race results. It throws if the scenario is incomplete or outside the available scoring bounds.
	End Rem
	Method ClinchesAfterNext:Int(participantId:Int, totals:TProjectedPoints[])
		If status = EClinchStatus.Indeterminate Then
			Throw "Clinching bounds are unavailable: " + reason
		End If

		If nextWindowId = "" Then
			Throw "No next scoring event or round remains"
		End If

		Local candidate:TClinchBound = BoundFor(participantId)
		If candidate = Null Then
			Throw "Unknown clinching participant"
		End If

		For Local bound:TClinchBound = EachIn bounds
			Local projected:Long = ProjectedTotal(bound.participantId, totals)
			Local minimum:Long = bound.currentPoints + bound.minimumAdditional - bound.minimumAfterNext
			Local maximum:Long = bound.currentPoints + bound.maximumAdditional - bound.maximumAfterNext
			If projected < minimum Or projected > maximum Then
				Throw "Projected points exceed the next-window scoring bounds"
			End If
		Next

		Local candidateTotal:Long = ProjectedTotal(participantId, totals)
		For Local rival:TClinchBound = EachIn bounds
			If rival.participantId = participantId Then
				Continue
			End If

			If candidateTotal + candidate.minimumAfterNext <= ProjectedTotal(rival.participantId, totals) + rival.maximumAfterNext Then
				Return False
			End If
		Next

		Return True
	End Method

	Method ProjectedTotal:Long(participantId:Int, totals:TProjectedPoints[])
		For Local projected:TProjectedPoints = EachIn totals
			If projected.participantId = participantId Then
				Return projected.points
			End If
		Next

		Throw "Missing projected points for participant " + participantId
	End Method
End Type

Rem
bbdoc: Compares attainable bounds to certify a title clinch.
End Rem
Type TClinchAnalyzer
	Method Analyze:TClinchAnalysis(comp:TCompetition, stage:TStage, state:TStageState, championshipCode:String, provider:IClinchBoundsProvider)
		If comp = Null Or stage = Null Or state = Null Then
			Throw "Clinching analysis needs a competition, stage and state"
		End If

		Local championship:TChampionshipConfig = Null
		If championshipCode <> "" Then
			Local config:TSeriesConfig = TSeriesConfig(stage.config)
			If config = Null Then
				Throw "Named championships need a series stage"
			End If

			For Local item:TChampionshipConfig = EachIn config.championships
				If item.code = championshipCode Then championship = item; Exit
			Next

			If championship = Null Then
				Throw "Unknown championship: " + championshipCode
			End If
		End If

		Local rows:TLeaderboardRow[] = ResolveRows(comp, stage, state, championship)
		Local analysis:TClinchAnalysis = New TClinchAnalysis
		analysis.stageId = stage.id
		analysis.championshipCode = championshipCode
		If rows = Null Or rows.Length = 0 Then
			analysis.status = EClinchStatus.Indeterminate
			analysis.reason = "No participants in this standings table"
			Return analysis
		End If

		If provider = Null Then
			analysis.status = EClinchStatus.Indeterminate
			analysis.reason = "No point-bounds provider is registered for this format"
			Return analysis
		End If

		Local calculated:TClinchBoundsResult = provider.Calculate(comp, stage, state, championship, rows)
		If calculated = Null Then
			Throw "Point-bounds provider returned no result"
		End If

		analysis.bounds = calculated.bounds
		analysis.nextWindowId = calculated.nextWindowId
		analysis.reason = calculated.reason
		If calculated.reason <> "" Then
			analysis.status = EClinchStatus.Indeterminate
			Return analysis
		End If

		If analysis.bounds = Null Or analysis.bounds.Length <> rows.Length Then
			Throw "Point-bounds provider omitted standings entrants"
		End If

		Local leaderPoints:Long = analysis.bounds[0].currentPoints
		analysis.leaderId = analysis.bounds[0].participantId
		For Local bound:TClinchBound = EachIn analysis.bounds
			If bound.currentPoints > leaderPoints Then
				leaderPoints = bound.currentPoints
				analysis.leaderId = bound.participantId
			End If
		Next

		analysis.status = EClinchStatus.NotCertified
		For Local candidate:TClinchBound = EachIn analysis.bounds
			Local clear:Int = True
			For Local rival:TClinchBound = EachIn analysis.bounds
				If rival.participantId = candidate.participantId Then
					Continue
				End If

				If candidate.MinimumFinal() <= rival.MaximumFinal() Then clear = False; Exit
			Next

			If clear Then
				analysis.status = EClinchStatus.Clinched
				analysis.clinchedParticipantId = candidate.participantId
				Exit
			End If
		Next

		Return analysis
	End Method

	Method ResolveRows:TLeaderboardRow[](comp:TCompetition, stage:TStage, state:TStageState, championship:TChampionshipConfig)
		If championship <> Null Then
			For Local named:TNamedLeaderboard = EachIn state.championships
				If named.code = championship.code And named.leaderboard <> Null And named.leaderboard.rows <> Null And named.leaderboard.rows.Length > 0 Then
					Return named.leaderboard.rows
				End If
			Next

			Return New TSeriesScorer.ComputeRows(comp, stage, state, championship)
		End If

		If state.leaderboard <> Null And state.leaderboard.rows <> Null And state.leaderboard.rows.Length > 0 Then
			Return state.leaderboard.rows
		End If

		If stage.stageType = EStageType.Series And stage.formatCode = "" Then
			Return New TSeriesScorer.ComputeRows(comp, stage, state, Null)
		End If

		Local rows:TLeaderboardRow[]
		For Local id:Int = EachIn state.entrants
			Local row:TLeaderboardRow = New TLeaderboardRow
			row.participantId = id
			rows :+ [row]
		Next

		Return rows
	End Method
End Type

Rem
bbdoc: Points bounds for remaining group or league matches.
End Rem
Type THeadToHeadClinchBounds Implements IClinchBoundsProvider
	Method Calculate:TClinchBoundsResult(comp:TCompetition, stage:TStage, state:TStageState, championship:TChampionshipConfig, rows:TLeaderboardRow[])
		Local result:TClinchBoundsResult = New TClinchBoundsResult
		Local win:Int, draw:Int, loss:Int
		Local league:TLeagueConfig = TLeagueConfig(stage.config)
		Local group:TGroupConfig = TGroupConfig(stage.config)
		If league <> Null Then
			win = league.pointsWin; draw = league.pointsDraw; loss = league.pointsLoss
		ElseIf group <> Null Then
			win = group.pointsWin; draw = group.pointsDraw; loss = group.pointsLoss
		Else
			result.reason = "Head-to-head point rules are missing"
			Return result
		End If

		Local maximum:Int = Max(0, Max(win, Max(draw, loss)))
		Local minimum:Int = Min(0, Min(win, Min(draw, loss)))
		Local nextRound:Int = 0
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status = EFixtureStatus.Completed Or fixture.status = EFixtureStatus.Cancelled Then
				Continue
			End If

			If nextRound = 0 Or fixture.round < nextRound Then
				nextRound = fixture.round
			End If
		Next

		If nextRound > 0 Then
			result.nextWindowId = "round:" + nextRound
		End If

		For Local row:TLeaderboardRow = EachIn rows
			Local bound:TClinchBound = New TClinchBound
			bound.participantId = row.participantId
			bound.currentPoints = row.points
			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.status = EFixtureStatus.Completed Or fixture.status = EFixtureStatus.Cancelled Then
					Continue
				End If

				If fixture.homeTeamId <> row.participantId And fixture.awayTeamId <> row.participantId Then
					Continue
				End If

				bound.minimumAdditional :+ minimum
				bound.maximumAdditional :+ maximum
				If fixture.round <> nextRound Then
					bound.minimumAfterNext :+ minimum
					bound.maximumAfterNext :+ maximum
				End If
			Next

			result.bounds :+ [bound]
		Next

		Return result
	End Method
End Type

Rem
bbdoc: Points bounds for remaining series sessions.
End Rem
Type TSeriesClinchBounds Implements IClinchBoundsProvider
	Method Calculate:TClinchBoundsResult(comp:TCompetition, stage:TStage, state:TStageState, championship:TChampionshipConfig, rows:TLeaderboardRow[])
		Local result:TClinchBoundsResult = New TClinchBoundsResult
		For Local fixture:TFixtureState = EachIn state.fixtures
			If fixture.status = EFixtureStatus.Completed Or fixture.status = EFixtureStatus.Cancelled Or Not Included(championship, fixture.sessionCode) Then
				Continue
			End If

			result.nextWindowId = fixture.seriesEventId
			Exit
		Next

		For Local row:TLeaderboardRow = EachIn rows
			Local bound:TClinchBound = New TClinchBound
			bound.participantId = row.participantId
			bound.currentPoints = row.points
			Local factor:Int = 1
			If championship <> Null And championship.parentTeamPoints Then
				factor = 0
				For Local participant:TParticipant = EachIn comp.participants
					If participant.parentTeamId <> row.participantId Then
						Continue
					End If

					For Local entrant:Int = EachIn state.entrants
						If entrant = participant.id Then factor :+ 1; Exit
					Next
				Next
			End If

			For Local fixture:TFixtureState = EachIn state.fixtures
				If fixture.status = EFixtureStatus.Completed Or fixture.status = EFixtureStatus.Cancelled Or Not Included(championship, fixture.sessionCode) Then
					Continue
				End If

				If factor = 0 Then
					Continue
				End If

				Local scoring:TScoringSystem = TSeriesScorer.ResolveSessionScoring(stage, fixture.seriesEventId, fixture.sessionCode)
				If championship <> Null And championship.scoringOverride <> Null Then
					scoring = championship.scoringOverride
				End If

				If scoring = Null Then
					Continue
				End If

				If scoring.mode <> EScoringMode.PositionTable Then
					result.reason = "Only position-table series have point bounds"
					Return result
				End If

				Local positions:Int[]
				Local positionPoints:Int[]
				For Local entry:TPointsTableEntry = EachIn scoring.table
					Local entryUnits:Int = ConfigPointUnits(entry.points, entry.pointsExact, TSeriesConfig(stage.config).pointsScale)
					If entryUnits < 0 Then result.reason = "Negative series points need a custom bounds provider"; Return result

					If entry.position < 1 Then
						Continue
					End If

					Local found:Int = False
					For Local i:Int = 0 Until positions.Length
						If positions[i] = entry.position Then positionPoints[i] = Max(positionPoints[i], entryUnits); found = True; Exit
					Next

					If Not found Then
						positions :+ [entry.position]
						positionPoints :+ [entryUnits]
					End If
				Next

				For Local i:Int = 0 Until positionPoints.Length - 1
					For Local j:Int = i + 1 Until positionPoints.Length
						If positionPoints[j] > positionPoints[i] Then
							Local swap:Int = positionPoints[i]
							positionPoints[i] = positionPoints[j]
							positionPoints[j] = swap
						End If
					Next
				Next

				Local bonusMaximum:Long = 0
				For Local rule:TBonusRule = EachIn scoring.bonuses
					If Not Allowed(rule, fixture.sessionCode) Then
						Continue
					End If

					Local scale:Int = TSeriesConfig(stage.config).pointsScale
					Local defaultUnits:Int = ConfigPointUnits(rule.points, rule.pointsExact, scale)
					Local capUnits:Int = ConfigPointUnits(rule.maxPointsPerAward, rule.maxPointsPerAwardExact, scale)
					If capUnits < defaultUnits Or capUnits < 1 Then
						result.reason = "Bonus " + rule.code + " has no finite per-award point cap"
						Return result
					End If

					Local cap:Int = rule.maxAwardsPerEvent
					If rule.uniquePerSession Or rule.uniquePerEvent Or rule.uniquePerParticipantPerEvent Then
						cap = 1
					End If

					If rule.maxAwardsPerEvent > 0 Then
						cap = Min(cap, rule.maxAwardsPerEvent)
					End If

					If cap < 1 Then
						result.reason = "Bonus " + rule.code + " has no finite award-count cap"
						Return result
					End If

					Local ruleMaximum:Long = Long(cap) * capUnits
					If ruleMaximum > 2000000000 - bonusMaximum Then
						result.reason = "Point bound exceeds the scorer's integer range"
						Return result
					End If

					bonusMaximum :+ ruleMaximum
				Next

				Local fixtureMaximum:Long = 0
				For Local child:Int = 0 Until factor
					Local positionPointsForChild:Int = 0
					If child < positionPoints.Length Then
						positionPointsForChild = positionPoints[child]
					End If

					Local possible:Long = Long(positionPointsForChild) + bonusMaximum
					If possible > 2000000000 Then
						result.reason = "Point bound exceeds the scorer's integer range"
						Return result
					End If

					Try
						fixtureMaximum :+ TSeriesScorer.EventPointsUnits(stage, fixture.seriesEventId, Int(possible))
					Catch problem:Object
						result.reason = "Point bound cannot be represented: " + problem.ToString()
						Return result
					End Try
				Next

				If bound.currentPoints + bound.maximumAdditional + fixtureMaximum > 2000000000 Then
					result.reason = "Season point bound exceeds the scorer's integer range"
					Return result
				End If

				bound.maximumAdditional :+ fixtureMaximum
				If fixture.seriesEventId <> result.nextWindowId Then
					bound.maximumAfterNext :+ fixtureMaximum
				End If
			Next

			result.bounds :+ [bound]
		Next

		Return result
	End Method

	Method Included:Int(championship:TChampionshipConfig, sessionCode:String)
		If championship = Null Or championship.sessionCodes = Null Or championship.sessionCodes.Length = 0 Then
			Return True
		End If

		For Local allowed:String = EachIn championship.sessionCodes
			If allowed = sessionCode Then
				Return True
			End If
		Next

		Return False
	End Method

	Method Allowed:Int(rule:TBonusRule, sessionCode:String)
		If rule.allowedSessions = Null Or rule.allowedSessions.Length = 0 Then
			Return True
		End If

		For Local allowed:String = EachIn rule.allowedSessions
			If allowed = sessionCode Then
				Return True
			End If
		Next

		Return False
	End Method
End Type
