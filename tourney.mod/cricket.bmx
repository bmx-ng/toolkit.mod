' Limited-overs cricket standings and result validation.

Rem
bbdoc: Limited-overs cricket scoring and net-run-rate rules.
End Rem
Type TCricketConfig Extends TLeagueConfig
	Rem
	bbdoc: Points no result for this cricket configuration.
	End Rem
	Field pointsNoResult:Int = 1
	Rem
	bbdoc: Wickets per innings for this cricket configuration.
	End Rem
	Field wicketsPerInnings:Int = 10
	Rem
	bbdoc: Balls per over for this cricket configuration.
	End Rem
	Field ballsPerOver:Int = 6
	Rem
	bbdoc: Whether rank wins before net rate applies to this cricket configuration.
	End Rem
	Field rankWinsBeforeNetRate:Int { asBool } = True

	Method New()
		configCode = "cricket"
		pointsWin = 2
		pointsDraw = 1
		pointsLoss = 0
	End Method
End Type

Rem
bbdoc: Creates cricket configurations for polymorphic jconv loading.
End Rem
Type TCricketConfigFactory Implements IConfigFactory
	Method Create:TConfig()
		Return New TCricketConfig
	End Method
End Type

Rem
bbdoc: Aggregated innings figures used to calculate net run rate.
End Rem
Type TCricketTotals
	Rem
	bbdoc: #TLeaderboardRow value used by this cricket totals.
	End Rem
	Field row:TLeaderboardRow
	Rem
	bbdoc: Runs for for this cricket totals.
	End Rem
	Field runsFor:Long
	Rem
	bbdoc: Balls for for this cricket totals.
	End Rem
	Field ballsFor:Long
	Rem
	bbdoc: Runs against for this cricket totals.
	End Rem
	Field runsAgainst:Long
	Rem
	bbdoc: Balls against for this cricket totals.
	End Rem
	Field ballsAgainst:Long
End Type

Rem
bbdoc: Applies limited-overs cricket outcomes to league standings.
End Rem
Type TCricketScorer Implements IStageScorer
	Method ApplyResult(comp:TCompetition, stage:TStage, st:TStageState, fxId:String, result:TResultPayload)
		If result = Null Or result.kind <> EResultKind.Custom Or result.customCode <> "cricket" Or result.cricket = Null Then
			Throw "Expected a cricket result"
		End If

		Local match:TCricketMatchResult = result.cricket
		Local fixture:TFixtureState
		For Local candidate:TFixtureState = EachIn st.fixtures
			If candidate.id = fxId Then fixture = candidate; Exit
		Next

		If fixture = Null Then
			Throw "Unknown cricket fixture"
		End If

		Local config:TCricketConfig = TCricketConfig(stage.config)
		Local wickets:Int = 10
		If config <> Null Then
			wickets = config.wicketsPerInnings
		End If

		If match.outcome = ECricketOutcome.NoResult Then
			If match.winnerId <> 0 Then
				Throw "No-result cricket match cannot have a winner"
			End If
		Else
			If match.first = Null Or match.second = Null Then
				Throw "Completed cricket match needs two innings"
			End If

			ValidateInnings(match.first, fixture, wickets)
			ValidateInnings(match.second, fixture, wickets)
			If match.first.teamId = match.second.teamId Then
				Throw "Both cricket innings belong to one team"
			End If

			If match.outcome = ECricketOutcome.Tie Then
				If match.first.runs <> match.second.runs Or match.winnerId <> 0 Or match.revisedTarget > 0 Then
					Throw "Invalid tied cricket result"
				End If
			Else
				Local winner:Int = match.first.teamId
				Local target:Int = match.first.runs + 1
				If match.revisedTarget > 0 Then
					target = match.revisedTarget
				End If

				If match.second.runs >= target Then
					winner = match.second.teamId
				End If

				If match.winnerId <> winner Then
					Throw "Cricket winner differs from innings totals or revised target"
				End If
			End If
		End If

		If stage.stageType = EStageType.Bracket And match.outcome <> ECricketOutcome.Win Then
			Throw "Cricket knockout needs a decided result"
		End If

		fixture.status = EFixtureStatus.Completed
		fixture.scoreHome = 0
		fixture.scoreAway = 0
		If match.winnerId = fixture.homeTeamId Then
			fixture.scoreHome = 1
		End If

		If match.winnerId = fixture.awayTeamId Then
			fixture.scoreAway = 1
		End If

		fixture.resultLog :+ [result]
	End Method

	Method ValidateInnings(innings:TCricketInnings, fixture:TFixtureState, maxWickets:Int)
		If innings.teamId <> fixture.homeTeamId And innings.teamId <> fixture.awayTeamId Then
			Throw "Cricket innings team is not in fixture"
		End If

		If innings.runs < 0 Or innings.wickets < 0 Or innings.wickets > maxWickets Then
			Throw "Invalid cricket runs or wickets"
		End If

		If innings.allocatedBalls < 1 Or innings.legalBalls < 0 Or innings.legalBalls > innings.allocatedBalls Then
			Throw "Invalid cricket legal-ball count"
		End If

		If (innings.creditedBalls = 0 And innings.creditedRuns <> 0) Or innings.creditedBalls < 0 Or innings.creditedRuns < 0 Then
			Throw "Invalid cricket NRR adjustment"
		End If
	End Method

	Method ComputeStandings(comp:TCompetition, stage:TStage, st:TStageState)
		If stage.stageType = EStageType.Bracket Then
			Return
		End If

		Local cfg:TCricketConfig = TCricketConfig(stage.config)
		Local winPoints:Int = 2, tiePoints:Int = 1, lossPoints:Int = 0, noResultPoints:Int = 1
		Local maxWickets:Int = 10, ballsPerOver:Int = 6
		If cfg <> Null Then
			winPoints = cfg.pointsWin; tiePoints = cfg.pointsDraw; lossPoints = cfg.pointsLoss
			noResultPoints = cfg.pointsNoResult; maxWickets = cfg.wicketsPerInnings; ballsPerOver = cfg.ballsPerOver
		End If

		Local totals:TCricketTotals[]
		For Local id:Int = EachIn st.entrants
			Local t:TCricketTotals = New TCricketTotals
			t.row = New TLeaderboardRow
			t.row.participantId = id
			totals :+ [t]
		Next

		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Or f.resultLog = Null Or f.resultLog.Length = 0 Then
				Continue
			End If

			Local match:TCricketMatchResult = f.resultLog[0].cricket
			Local home:TCricketTotals = Find(totals, f.homeTeamId)
			Local away:TCricketTotals = Find(totals, f.awayTeamId)
			If match.outcome = ECricketOutcome.NoResult Then
				home.row.noResults :+ 1; away.row.noResults :+ 1
				home.row.points :+ noResultPoints; away.row.points :+ noResultPoints
				Continue
			End If

			If match.outcome = ECricketOutcome.Tie Then
				home.row.draws :+ 1; away.row.draws :+ 1
				home.row.points :+ tiePoints; away.row.points :+ tiePoints
			ElseIf match.winnerId = f.homeTeamId Then
				home.row.wins :+ 1; away.row.losses :+ 1
				home.row.points :+ winPoints; away.row.points :+ lossPoints
			Else
				away.row.wins :+ 1; home.row.losses :+ 1
				away.row.points :+ winPoints; home.row.points :+ lossPoints
			End If

			AddNRR(totals, match.first, match.second, maxWickets)
			AddNRR(totals, match.second, match.first, maxWickets)
		Next

		For Local t:TCricketTotals = EachIn totals
			If t.ballsFor > 0 And t.ballsAgainst > 0 Then
				t.row.netRate = Double(ballsPerOver) * Double(t.runsFor) / Double(t.ballsFor) - Double(ballsPerOver) * Double(t.runsAgainst) / Double(t.ballsAgainst)
			End If
		Next

		Local groups:String[]
		For Local id:Int = EachIn st.entrants
			For Local p:TParticipant = EachIn comp.participants
				If p.id <> id Then
					Continue
				End If

				Local found:Int
				For Local existing:String = EachIn groups
					If existing = p.divisionId Then found = True; Exit
				Next

				If Not found Then
					groups :+ [p.divisionId]
				End If

				Exit
			Next
		Next

		For Local i:Int = 0 Until groups.Length - 1
			For Local j:Int = i + 1 Until groups.Length
				If groups[j] < groups[i] Then
					Local swap:String = groups[i]; groups[i] = groups[j]; groups[j] = swap
				End If
			Next
		Next

		Local allRows:TLeaderboardRow[]
		st.groups = []
		For Local group:String = EachIn groups
			Local rows:TLeaderboardRow[]
			For Local t:TCricketTotals = EachIn totals
				For Local p:TParticipant = EachIn comp.participants
					If p.id = t.row.participantId And p.divisionId = group Then rows :+ [t.row]; Exit
				Next
			Next

			For Local i:Int = 0 Until rows.Length - 1
				For Local j:Int = i + 1 Until rows.Length
					If Better(rows[j], rows[i], cfg) Then
						Local swap:TLeaderboardRow = rows[i]; rows[i] = rows[j]; rows[j] = swap
					End If
				Next
			Next

			Local gt:TGroupTable = New TGroupTable
			gt.key = group; gt.rows = rows
			st.groups :+ [gt]
			allRows :+ rows
		Next

		st.leaderboard.rows = allRows
	End Method

	Method Find:TCricketTotals(totals:TCricketTotals[], id:Int)
		For Local t:TCricketTotals = EachIn totals
			If t.row.participantId = id Then
				Return t
			End If
		Next

		Throw "Unknown cricket table entrant " + id
	End Method

	Method AddNRR(totals:TCricketTotals[], own:TCricketInnings, other:TCricketInnings, maxWickets:Int)
		Local t:TCricketTotals = Find(totals, own.teamId)
		Local ownBalls:Int = own.legalBalls
		If own.wickets = maxWickets Then
			ownBalls = own.allocatedBalls
		End If

		Local ownRuns:Int = own.runs
		If own.creditedBalls > 0 Then ownBalls = own.creditedBalls; ownRuns = own.creditedRuns

		Local otherBalls:Int = other.legalBalls
		If other.wickets = maxWickets Then
			otherBalls = other.allocatedBalls
		End If

		Local otherRuns:Int = other.runs
		If other.creditedBalls > 0 Then otherBalls = other.creditedBalls; otherRuns = other.creditedRuns

		t.runsFor :+ ownRuns; t.ballsFor :+ ownBalls
		t.runsAgainst :+ otherRuns; t.ballsAgainst :+ otherBalls
	End Method

	Method Better:Int(a:TLeaderboardRow, b:TLeaderboardRow, config:TCricketConfig)
		If a.points <> b.points Then
			Return a.points > b.points
		End If

		If config = Null Or config.rankWinsBeforeNetRate Then
			If a.wins <> b.wins Then
				Return a.wins > b.wins
			End If
		End If

		If a.netRate <> b.netRate Then
			Return a.netRate > b.netRate
		End If

		If a.wins <> b.wins Then
			Return a.wins > b.wins
		End If

		Return a.participantId < b.participantId
	End Method

	Method IsComplete:Int(comp:TCompetition, stage:TStage, st:TStageState) { asBool }
		For Local f:TFixtureState = EachIn st.fixtures
			If f.status <> EFixtureStatus.Completed Then
				Return False
			End If
		Next

		Return True
	End Method
End Type
