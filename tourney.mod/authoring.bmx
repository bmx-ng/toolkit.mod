' Optional conveniences for constructing the ordinary, serializable definition types.
Rem
bbdoc: Creates common configuration objects and validates scoring values.
End Rem
Type TTourneyAuthoring
	Rem
	bbdoc: Creates round-robin group configuration.
	param: Number of groups.
	param: Entrants in each group.
	param: Games each opponent pair plays.
	returns: A #TGroupConfig.
	End Rem
	Function Groups:TGroupConfig(count:Int, size:Int, gamesPerOpponent:Int = 1)
		If count < 1 Or size < 1 Or gamesPerOpponent < 1 Then
			Throw "Groups need positive counts, size, and games per opponent"
		End If

		Local config:TGroupConfig = New TGroupConfig
		config.groups = count
		config.groupSize = size
		config.roundRobinPerOpponent = gamesPerOpponent
		Return config
	End Function

	Rem
	bbdoc: Creates a power-of-two knockout configuration.
	param: Bracket size, including any bye positions.
	param: Odd number of matches in each best-of series.
	returns: A #TBracketConfig.
	End Rem
	Function Bracket:TBracketConfig(size:Int, bestOfMatches:Int = 1)
		If size < 2 Or (size & (size - 1)) <> 0 Then
			Throw "Bracket size must be a power of two"
		End If

		If bestOfMatches < 1 Or bestOfMatches Mod 2 = 0 Then
			Throw "Best-of matches must be a positive odd number"
		End If

		Local config:TBracketConfig = New TBracketConfig
		config.size = size
		If bestOfMatches > 1 Then
			config.matchFormat = New TMatchFormat
			config.matchFormat.bestOfMatches = bestOfMatches
		End If

		Return config
	End Function

	Rem
	bbdoc: Creates a scored multi-event series configuration.
	param: Events to include.
	param: Position, bonus, and aggregation scoring.
	param: Integer units stored per point.
	returns: A #TSeriesConfig.
	about: Point values must be exactly representable at @pointsScale.
	End Rem
	Function Series:TSeriesConfig(events:TSeriesEvent[], scoring:TScoringSystem, pointsScale:Int = 1)
		If pointsScale < 1 Then
			Throw "Series pointsScale must be positive"
		End If

		If events = Null Or events.Length = 0 Then
			Throw "Series needs at least one event"
		End If

		If scoring = Null Then
			Throw "Series needs a scoring system"
		End If

		ValidateScoring(scoring, pointsScale)
		Local config:TSeriesConfig = New TSeriesConfig
		config.events = events[..]
		config.scoring = scoring
		config.pointsScale = pointsScale
		Return config
	End Function

	Rem
	bbdoc: Creates a position-points table from decimal strings.
	param: Points for first, second, and later positions in order.
	param: Integer units stored per point.
	returns: A #TScoringSystem using position-table scoring.
	End Rem
	Function PositionScoring:TScoringSystem(points:String[], pointsScale:Int = 1)
		If points = Null Or points.Length = 0 Then
			Throw "Position scoring needs a point table"
		End If

		Local scoring:TScoringSystem = New TScoringSystem
		scoring.mode = EScoringMode.PositionTable
		For Local i:Int = 0 Until points.Length
			ExactPointUnits(points[i], pointsScale)
			Local entry:TPointsTableEntry = New TPointsTableEntry
			entry.position = i + 1
			entry.pointsExact = points[i]
			scoring.table :+ [entry]
		Next

		Return scoring
	End Function

	Rem
	bbdoc: Creates a named bonus rule with an optional cap.
	param: Award code used in recorded results.
	param: Default award as an exact decimal string.
	param: Maximum award as an exact decimal string, or empty for no cap.
	param: Integer units stored per point.
	returns: A #TBonusRule.
	End Rem
	Function Bonus:TBonusRule(code:String, points:String, cap:String, pointsScale:Int = 1)
		If code = "" Then
			Throw "Bonus needs a code"
		End If

		Local units:Int = ExactPointUnits(points, pointsScale)
		If cap <> "" And ExactPointUnits(cap, pointsScale) < units Then
			Throw "Bonus cap is below its default award"
		End If

		Local rule:TBonusRule = New TBonusRule
		rule.code = code
		rule.pointsExact = points
		rule.maxPointsPerAwardExact = cap
		Return rule
	End Function

	Rem
	bbdoc: Creates a series event and its named sessions.
	param: Unique event ID.
	param: Session codes in play order.
	param: Exact decimal points multiplier, or empty for the default.
	returns: A #TSeriesEvent.
	End Rem
	Function Event:TSeriesEvent(id:String, sessionCodes:String[], multiplierExact:String = "")
		If id = "" Then
			Throw "Series event needs an id"
		End If

		If multiplierExact <> "" Then
			Decimal(multiplierExact)
		End If

		Local event:TSeriesEvent = New TSeriesEvent
		event.id = id
		event.pointsMultiplierExact = multiplierExact
		For Local code:String = EachIn sessionCodes
			If code = "" Then
				Throw "Series session needs a code"
			End If

			Local session:TSession = New TSession
			session.code = code
			event.sessions :+ [session]
		Next

		Return event
	End Function

	Rem
	bbdoc: Selects a consecutive range of top-ranked entrants.
	param: Number of entrants to select.
	param: Table scope for the selection.
	param: One-based rank of the first selected entrant.
	returns: A #TFilterRule.
	End Rem
	Function Top:TFilterRule(n:Int, scope:EFilterScope = EFilterScope.All, startRank:Int = 1)
		If n < 1 Or startRank < 1 Then
			Throw "Top selection needs a positive count and starting rank"
		End If

		Local rule:TFilterRule = New TFilterRule
		rule.kind = EFilterKind.TopN
		rule.n = n
		rule.scope = scope
		rule.startRank = startRank
		Return rule
	End Function

	Rem
	bbdoc: Selects the best entrants at one rank across groups.
	param: One-based rank within each group.
	param: Number of entrants to select.
	returns: A #TFilterRule.
	End Rem
	Function BestAtRankAcrossGroups:TFilterRule(rank:Int, n:Int)
		If rank < 1 Or n < 1 Then
			Throw "Best-at-rank selection needs a positive rank and count"
		End If

		Local rule:TFilterRule = New TFilterRule
		rule.kind = EFilterKind.BestXAcrossGroups
		rule.startRank = rank
		rule.n = n
		rule.scope = EFilterScope.PerGroup
		Return rule
	End Function

	Rem
	bbdoc: Checks scoring values against the configured points scale.
	param: Scoring system to check; #Null is allowed.
	param: Integer units stored per point.
	about: Throws when a configured exact value cannot be represented or a bonus cap is below its default.
	End Rem
	Function ValidateScoring(scoring:TScoringSystem, pointsScale:Int)
		If pointsScale < 1 Then
			Throw "pointsScale must be positive"
		End If

		If scoring = Null Then
			Return
		End If

		For Local entry:TPointsTableEntry = EachIn scoring.table
			If entry = Null Then
				Throw "Point table has a missing entry"
			End If

			If entry.position < 0 Then
				Throw "Point table position must not be negative"
			End If

			ConfigPointUnits(entry.points, entry.pointsExact, pointsScale)
		Next

		For Local bonus:TBonusRule = EachIn scoring.bonuses
			If bonus = Null Or bonus.code = "" Then
				Throw "Bonus needs a code"
			End If

			Local defaultUnits:Int = ConfigPointUnits(bonus.points, bonus.pointsExact, pointsScale)
			Local capUnits:Int = ConfigPointUnits(bonus.maxPointsPerAward, bonus.maxPointsPerAwardExact, pointsScale)
			If capUnits > 0 And capUnits < defaultUnits Then
				Throw "Bonus cap is below its default award: " + bonus.code
			End If
		Next
	End Function
End Type

Rem
bbdoc: A stage and field path identifying an authoring preflight problem.
End Rem
Type TAuthoringIssue
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: Field path of this authoring issue.
	End Rem
	Field fieldPath:String
	Rem
	bbdoc: Message of this authoring issue.
	End Rem
	Field message:String
End Type
