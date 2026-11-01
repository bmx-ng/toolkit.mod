' Exact top-N qualification for finite, points-only schedules.
' A tied boundary remains unresolved: every tied entrant is possible, but none
' is guaranteed the contested place without a configured final tie decision.
Rem
bbdoc: Possible, guaranteed, eliminated, or inconclusive qualification state.
End Rem
Enum EQualificationStatus
	Rem
	bbdoc: Every modeled legal completion puts the entrant in a qualifying place.
	End Rem
	Guaranteed
	Rem
	bbdoc: At least one completion qualifies the entrant, but another does not.
	End Rem
	Possible
	Rem
	bbdoc: No legal completion can put the entrant in a qualifying place.
	End Rem
	Eliminated
	Rem
	bbdoc: The configured model or search bound prevents a conclusive result.
	End Rem
	Indeterminate
End Enum

Rem
bbdoc: Qualification result for one participant under explored scenarios.
End Rem
Type TQualificationOutcome
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Result for this qualification outcome.
	about: One means home win, 0 = draw, -1 = away win.
	End Rem
	Field result:Int ' 1 = home win, 0 = draw, -1 = away win
	Rem
	bbdoc: Classification order values associated with this qualification outcome.
	about: Ordered classified entrants for a series session.
	End Rem
	Field classificationOrder:Int[] ' ordered classified entrants for a series session
End Type

Rem
bbdoc: Qualification status, witnesses, and search-limit information.
about: A qualifying or failing scenario shows one set of remaining results that supports the conclusion. `Indeterminate` means the modeled rules or scenario limit cannot justify a stronger result.
End Rem
Type TQualificationAnalysis
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: Key identifying the associated group.
	End Rem
	Field groupKey:String
	Rem
	bbdoc: Code identifying the associated championship.
	End Rem
	Field championshipCode:String
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Places for this qualification analysis.
	End Rem
	Field places:Int
	Rem
	bbdoc: Current status of this qualification analysis.
	End Rem
	Field status:EQualificationStatus
	Rem
	bbdoc: Scenarios examined for this qualification analysis.
	End Rem
	Field scenariosExamined:Int
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
	Rem
	bbdoc: #TQualificationOutcome entries associated with this qualification analysis.
	End Rem
	Field qualifyingScenario:TQualificationOutcome[]
	Rem
	bbdoc: #TQualificationOutcome entries associated with this qualification analysis.
	End Rem
	Field failingScenario:TQualificationOutcome[]
End Type

Rem
bbdoc: Search state for remaining head-to-head outcomes.
End Rem
Type TQualificationSearch
	Rem
	bbdoc: #TQualificationAnalysis value used by this qualification search.
	End Rem
	Field analysis:TQualificationAnalysis
	Rem
	bbdoc: Ids values associated with this qualification search.
	End Rem
	Field ids:Int[]
	Rem
	bbdoc: Points values associated with this qualification search.
	End Rem
	Field points:Long[]
	Rem
	bbdoc: #TFixtureState entries associated with this qualification search.
	End Rem
	Field fixtures:TFixtureState[]
	Rem
	bbdoc: #TQualificationOutcome entries associated with this qualification search.
	End Rem
	Field choices:TQualificationOutcome[]
	Rem
	bbdoc: Win points for this qualification search.
	End Rem
	Field winPoints:Int
	Rem
	bbdoc: Draw points for this qualification search.
	End Rem
	Field drawPoints:Int
	Rem
	bbdoc: Loss points for this qualification search.
	End Rem
	Field lossPoints:Int
	Rem
	bbdoc: Candidate for this qualification search.
	End Rem
	Field candidate:Int
	Rem
	bbdoc: Limit for this qualification search.
	End Rem
	Field limit:Int
	Rem
	bbdoc: Found possible for this qualification search.
	End Rem
	Field foundPossible:Int
	Rem
	bbdoc: Found not certain for this qualification search.
	End Rem
	Field foundNotCertain:Int
	Rem
	bbdoc: Exhausted for this qualification search.
	End Rem
	Field exhausted:Int

	Method IndexOf:Int(id:Int)
		For Local i:Int = 0 Until ids.Length
			If ids[i] = id Then
				Return i
			End If
		Next

		Return -1
	End Method

	Method CopyChoices:TQualificationOutcome[]()
		Local copy:TQualificationOutcome[]
		For Local item:TQualificationOutcome = EachIn choices
			Local entry:TQualificationOutcome = New TQualificationOutcome
			entry.fixtureId = item.fixtureId
			entry.result = item.result
			If item.classificationOrder <> Null Then
				entry.classificationOrder = item.classificationOrder[..]
			End If

			copy :+ [entry]
		Next

		Return copy
	End Method

	Method Visit(depth:Int)
		If foundPossible And foundNotCertain Then
			Return
		End If

		If depth = fixtures.Length Then ScoreLeaf(); Return

		Local fixture:TFixtureState = fixtures[depth]
		Local home:Int = IndexOf(fixture.homeTeamId)
		Local away:Int = IndexOf(fixture.awayTeamId)
		Local options:Int[] = [1, 0, -1]
		For Local option:Int = EachIn options
			If option = 1 Then
				points[home] :+ winPoints; points[away] :+ lossPoints
			ElseIf option = -1 Then
				points[home] :+ lossPoints; points[away] :+ winPoints
			Else
				points[home] :+ drawPoints; points[away] :+ drawPoints
			End If

			Local outcome:TQualificationOutcome = New TQualificationOutcome
			outcome.fixtureId = fixture.id
			outcome.result = option
			choices :+ [outcome]
			Visit(depth + 1)
			choices = choices[..choices.Length - 1]
			If option = 1 Then
				points[home] :- winPoints; points[away] :- lossPoints
			ElseIf option = -1 Then
				points[home] :- lossPoints; points[away] :- winPoints
			Else
				points[home] :- drawPoints; points[away] :- drawPoints
			End If

			If exhausted Or (foundPossible And foundNotCertain) Then
				Return
			End If
		Next
	End Method

	Method ScoreLeaf()
		If analysis.scenariosExamined >= limit Then exhausted = True; Return

		analysis.scenariosExamined :+ 1
		Local above:Int
		Local tied:Int
		For Local i:Int = 0 Until ids.Length
			Local comparison:Int = CompareRanks(i, candidate)
			If comparison > 0 Then
				above :+ 1
			End If

			If comparison = 0 Then
				tied :+ 1
			End If
		Next

		If above < analysis.places Then
			If Not foundPossible Then
				analysis.qualifyingScenario = CopyChoices()
			End If

			foundPossible = True
		End If

		If above + tied > analysis.places Then
			If Not foundNotCertain Then
				analysis.failingScenario = CopyChoices()
			End If

			foundNotCertain = True
		End If
	End Method

	Method CompareRanks:Int(a:Int, b:Int)
		If points[a] > points[b] Then
			Return 1
		End If

		If points[a] < points[b] Then
			Return -1
		End If

		Return 0
	End Method
End Type

Rem
bbdoc: Explores remaining group or league results for qualification.
End Rem
Type TQualificationAnalyzer
	Method Analyze:TQualificationAnalysis(stage:TStage, state:TStageState, participantId:Int, places:Int, groupKey:String = "", maxScenarios:Int = 100000)
		If stage = Null Or state = Null Then
			Throw "Qualification analysis needs a stage and state"
		End If

		If places < 1 Or maxScenarios < 1 Then
			Throw "Qualification places and search limit must be positive"
		End If

		Local result:TQualificationAnalysis = New TQualificationAnalysis
		result.stageId = stage.id
		result.groupKey = groupKey
		result.participantId = participantId
		result.places = places
		result.status = EQualificationStatus.Indeterminate
		Local league:TLeagueConfig = TLeagueConfig(stage.config)
		Local group:TGroupConfig = TGroupConfig(stage.config)
		If stage.formatCode <> "" Or (league = Null And group = Null) Then
			result.reason = "Exact qualification supports standard league and group stages"
			Return result
		End If

		If group <> Null And groupKey = "" Then
			result.reason = "A group key is required for group qualification"
			Return result
		End If

		If state.leaderboard = Null Or state.leaderboard.rows = Null Then
			result.reason = "Standings are unavailable"
			Return result
		End If

		Local rules:ETiebreaker[]
		Local search:TQualificationSearch = New TQualificationSearch
		If league <> Null Then
			rules = league.tiebreakers
			search.winPoints = league.pointsWin; search.drawPoints = league.pointsDraw; search.lossPoints = league.pointsLoss
		Else
			rules = group.tiebreakers
			search.winPoints = group.pointsWin; search.drawPoints = group.pointsDraw; search.lossPoints = group.pointsLoss
		End If

		If rules = Null Or rules.Length <> 1 Or rules[0] <> ETiebreaker.Points Then
			result.reason = "Exact qualification needs points-only ranking; future scores cannot yet be enumerated"
			Return result
		End If

		For Local fixture:TFixtureState = EachIn state.fixtures
			If group <> Null And fixture.groupKey <> groupKey Then
				Continue
			End If

			If fixture.status = EFixtureStatus.Cancelled Then
				Continue
			End If

			If fixture.homeTeamId < 1 Or fixture.awayTeamId < 1 Then
				result.reason = "A remaining fixture has unresolved entrants"
				Return result
			End If

			If group <> Null Then
				If search.IndexOf(fixture.homeTeamId) < 0 Then
					search.ids :+ [fixture.homeTeamId]
				End If

				If search.IndexOf(fixture.awayTeamId) < 0 Then
					search.ids :+ [fixture.awayTeamId]
				End If
			End If

			If fixture.status <> EFixtureStatus.Completed Then
				search.fixtures :+ [fixture]
			End If
		Next

		If league <> Null Then
			For Local row:TLeaderboardRow = EachIn state.leaderboard.rows
				search.ids :+ [row.participantId]
			Next
		End If

		If search.IndexOf(participantId) < 0 Then
			Throw "Unknown qualification participant"
		End If

		If places > search.ids.Length Then
			Throw "Qualification places exceed entrant count"
		End If

		For Local id:Int = EachIn search.ids
			Local found:Int
			For Local row:TLeaderboardRow = EachIn state.leaderboard.rows
				If row.participantId = id Then search.points :+ [Long(row.points)]; found = True; Exit
			Next

			If Not found Then
				result.reason = "Standings omit a fixture entrant"
				Return result
			End If
		Next

		For Local fixture:TFixtureState = EachIn search.fixtures
			If search.IndexOf(fixture.homeTeamId) < 0 Or search.IndexOf(fixture.awayTeamId) < 0 Then
				result.reason = "A fixture has an entrant outside the standings"
				Return result
			End If
		Next
		' Cheap independent bounds prove many answers without expanding the tree.
		Local minimum:Long[] = search.points[..]
		Local maximum:Long[] = search.points[..]
		Local low:Int = Min(search.winPoints, Min(search.drawPoints, search.lossPoints))
		Local high:Int = Max(search.winPoints, Max(search.drawPoints, search.lossPoints))
		For Local fixture:TFixtureState = EachIn search.fixtures
			Local home:Int = search.IndexOf(fixture.homeTeamId)
			Local away:Int = search.IndexOf(fixture.awayTeamId)
			minimum[home] :+ low; minimum[away] :+ low
			maximum[home] :+ high; maximum[away] :+ high
		Next

		Local candidate:Int = search.IndexOf(participantId)
		Local challengers:Int
		Local certainAbove:Int
		For Local i:Int = 0 Until search.ids.Length
			If i = candidate Then
				Continue
			End If

			If maximum[i] >= minimum[candidate] Then
				challengers :+ 1
			End If

			If minimum[i] > maximum[candidate] Then
				certainAbove :+ 1
			End If
		Next

		If challengers < places Then result.status = EQualificationStatus.Guaranteed; Return result

		If certainAbove >= places Then result.status = EQualificationStatus.Eliminated; Return result

		search.analysis = result
		search.candidate = candidate
		search.limit = maxScenarios
		search.Visit(0)
		If search.foundPossible And search.foundNotCertain Then
			result.status = EQualificationStatus.Possible
		ElseIf search.exhausted Then
			result.reason = "Search limit reached before qualification was decided"
		ElseIf search.foundPossible Then
			result.status = EQualificationStatus.Guaranteed
		Else
			result.status = EQualificationStatus.Eliminated
		End If

		Return result
	End Method
End Type
