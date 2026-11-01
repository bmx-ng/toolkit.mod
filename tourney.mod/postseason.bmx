' Postseason selection from one completed league's results. No sport names are
' embedded here: pools, divisions, berth counts, and tie criteria are data.
Rem
bbdoc: Selected postseason entrants with their seed order.
End Rem
Type TSeededField
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Entrant IDs associated with this seeded field.
	about: Seed 1 first.
	End Rem
	Field entrantIds:Int[] ' seed 1 first
End Type

Rem
bbdoc: Exact win percentage or record comparison for postseason seeding.
End Rem
Type TPostseasonFraction
	Rem
	bbdoc: Numerator for this postseason fraction.
	End Rem
	Field numerator:Long
	Rem
	bbdoc: Denominator for this postseason fraction.
	End Rem
	Field denominator:Long = 1
	Rem
	bbdoc: Applicable for this postseason fraction.
	End Rem
	Field applicable:Int = True
End Type

Rem
bbdoc: Selects division winners, at-large entrants, and pool seeds.
End Rem
Type TPostseasonSelector
	Rem
	bbdoc: #TCompetition value used by this postseason selector.
	End Rem
	Field comp:TCompetition
	Rem
	bbdoc: #TStageState value used by this postseason selector.
	End Rem
	Field league:TStageState
	Rem
	bbdoc: #TPostseasonConfig value used by this postseason selector.
	End Rem
	Field config:TPostseasonConfig
	Rem
	bbdoc: #TPostseasonPool value used by this postseason selector.
	End Rem
	Field pool:TPostseasonPool

	Rem
	bbdoc: Selects and seeds qualifiers from a completed league pool.
	param: Competition definition with participants and divisions.
	param: Completed league standings and results.
	param: Berth counts and ordered sporting tie criteria.
	param: Named pool to select, such as a conference.
	returns: A #TSeededField containing qualifiers in seed order.
	about: An unresolved sporting tie requires a configured #TPostseasonTieDecision; stable display order does not choose a berth.
	End Rem
	Function Select:TSeededField(comp:TCompetition, league:TStageState, config:TPostseasonConfig, poolCode:String)
		If comp = Null Or league = Null Or config = Null Then
			Throw "Postseason selection needs a competition, league results and rules"
		End If

		If league.status <> EStageStatus.Complete Then
			Throw "Postseason source league is unfinished"
		End If

		Local selector:TPostseasonSelector = New TPostseasonSelector
		selector.comp = comp
		selector.league = league
		selector.config = config
		For Local candidate:TPostseasonPool = EachIn config.pools
			If candidate.code = poolCode Then selector.pool = candidate; Exit
		Next

		If selector.pool = Null Then
			Throw "Unknown postseason pool: " + poolCode
		End If

		If config.divisionWinnersPerDivision < 1 Or config.atLargePlaces < 0 Then
			Throw "Invalid postseason berth counts"
		End If

		If config.divisionTie = Null Or config.atLargeTie = Null Or config.seedTie = Null Then
			Throw "Postseason tie rules are incomplete"
		End If

		Return selector.Build()
	End Function

	Method Build:TSeededField()
		Local winners:Int[]
		For Local division:String = EachIn pool.divisionIds
			Local remaining:Int[]
			For Local participant:TParticipant = EachIn comp.participants
				If participant.divisionId = division And IsEntrant(participant.id) Then
					remaining :+ [participant.id]
				End If
			Next

			If remaining.Length < config.divisionWinnersPerDivision Then
				Throw "Division has too few postseason candidates: " + division
			End If

			For Local place:Int = 0 Until config.divisionWinnersPerDivision
				Local id:Int = RankOne(remaining, config.divisionTie)
				winners :+ [id]
				remaining = Without(remaining, id)
			Next
		Next

		Local seeded:TSeededField = New TSeededField
		seeded.code = pool.code
		While winners.Length > 0
			Local id:Int = RankOne(winners, config.seedTie)
			seeded.entrantIds :+ [id]
			winners = Without(winners, id)
		Wend

		Local remaining:Int[]
		For Local participant:TParticipant = EachIn comp.participants
			If Not IsEntrant(participant.id) Or Not InPool(participant.id) Then
				Continue
			End If

			If Contains(seeded.entrantIds, participant.id) Then
				Continue
			End If

			remaining :+ [participant.id]
		Next

		For Local place:Int = 0 Until config.atLargePlaces
			If remaining.Length = 0 Then
				Throw "Too few at-large candidates"
			End If

			Local id:Int = RankOne(remaining, config.atLargeTie)
			seeded.entrantIds :+ [id]
			remaining = Without(remaining, id)
		Next

		Return seeded
	End Method

	Method RankOne:Int(candidates:Int[], rules:TPostseasonTieRules)
		If candidates.Length = 0 Then
			Throw "Empty postseason candidate list"
		End If

		If candidates.Length = 1 Then
			Return candidates[0]
		End If

		Local tied:Int[] = BestOverall(candidates)
		If tied.Length = 1 Then
			Return tied[0]
		End If

		If rules.reduceByDivision Then
			Local reduced:Int[]
			For Local id:Int = EachIn tied
				Local division:String = Division(id)
				Local seen:Int
				For Local other:Int = EachIn reduced
					If Division(other) = division Then seen = True; Exit
				Next

				If seen Then
					Continue
				End If

				Local same:Int[]
				For Local other:Int = EachIn tied
					If Division(other) = division Then
						same :+ [other]
					End If
				Next

				reduced :+ [RankOne(same, config.divisionTie)]
			Next

			If reduced.Length = 1 Then
				Return reduced[0]
			End If

			tied = reduced
		End If

		Local criteria:EPostseasonCriterion[] = rules.twoTeams
		If tied.Length > 2 Then
			criteria = rules.manyTeams
		End If

		For Local criterion:EPostseasonCriterion = EachIn criteria
			If criterion = EPostseasonCriterion.HeadToHead And tied.Length > 2 And rules.headToHeadSweep Then
				Local swept:Int[] = Sweep(tied)
				If swept.Length = 1 Then
					Return swept[0]
				End If

				If swept.Length > 1 And swept.Length < tied.Length Then
					Return RankOne(swept, rules)
				End If

				Continue
			End If

			Local best:Int[] = BestByCriterion(tied, criterion)
			If best.Length = 1 Then
				Return best[0]
			End If

			If best.Length > 1 And best.Length < tied.Length Then
				Return RankOne(best, rules)
			End If
		Next

		For Local decision:TPostseasonTieDecision = EachIn config.tieDecisions
			If decision.poolCode <> pool.code Or decision.participantIds.Length <> tied.Length Or decision.reason = "" Then
				Continue
			End If

			Local same:Int = True
			For Local id:Int = EachIn tied
				If Not Contains(decision.participantIds, id) Then same = False; Exit
			Next

			If same And Contains(tied, decision.winnerId) Then
				Return decision.winnerId
			End If
		Next

		Throw "Unresolved postseason tie in " + pool.code + "; record another criterion or an explicit decision"
	End Method

	Method BestOverall:Int[](ids:Int[])
		Local best:Int[]
		Local top:TPostseasonFraction
		For Local id:Int = EachIn ids
			Local value:TPostseasonFraction = Record(id, 0, 0, Null)
			If top = Null Or Compare(value, top) > 0 Then
				best = [id]
				top = value
			ElseIf Compare(value, top) = 0 Then
				best :+ [id]
			End If
		Next

		Return best
	End Method

	Method BestByCriterion:Int[](ids:Int[], criterion:EPostseasonCriterion)
		Local best:Int[]
		Local top:TPostseasonFraction
		For Local id:Int = EachIn ids
			Local value:TPostseasonFraction = Metric(id, ids, criterion)
			If Not value.applicable Then
				Return ids
			End If

			If top = Null Or Compare(value, top) > 0 Then
				best = [id]
				top = value
			ElseIf Compare(value, top) = 0 Then
				best :+ [id]
			End If
		Next

		Return best
	End Method

	Function Compare:Int(a:TPostseasonFraction, b:TPostseasonFraction)
		Local left:Long = a.numerator * b.denominator
		Local right:Long = b.numerator * a.denominator
		If left > right Then
			Return 1
		End If

		If left < right Then
			Return -1
		End If

		Return 0
	End Function

	Method Metric:TPostseasonFraction(id:Int, tied:Int[], criterion:EPostseasonCriterion)
		Select criterion
			Case EPostseasonCriterion.HeadToHead
				Return Record(id, 1, 0, tied)
			Case EPostseasonCriterion.DivisionRecord
				Return Record(id, 2, 0, Null)
			Case EPostseasonCriterion.PoolRecord
				Return Record(id, 3, 0, Null)
			Case EPostseasonCriterion.CommonOpponents
				Local common:Int[] = CommonOpponents(tied)
				Local result:TPostseasonFraction = Record(id, 1, 0, common)
				If result.denominator < 4 Then
					result.applicable = False
				End If

				Return result
			Case EPostseasonCriterion.StrengthOfVictory
				Return Strength(id, True)
			Case EPostseasonCriterion.StrengthOfSchedule
				Return Strength(id, False)
			Case EPostseasonCriterion.PointsScored
				Return ScoreMetric(id, 1)
			Case EPostseasonCriterion.PointsAllowed
				Return ScoreMetric(id, 2)
			Case EPostseasonCriterion.NetPoints
				Return ScoreMetric(id, 3)
			Case EPostseasonCriterion.CombinedPointsRankPool
				Return CombinedPointsRank(id, True)
			Case EPostseasonCriterion.CombinedPointsRankAll
				Return CombinedPointsRank(id, False)
			Case EPostseasonCriterion.NetPointsPool
				Return ScopedNetPoints(id, 1, Null)
			Case EPostseasonCriterion.NetPointsCommon
				Return ScopedNetPoints(id, 2, CommonOpponents(tied))
		End Select

		Throw "Unsupported postseason tie criterion"
	End Method

	' mode 0: all games; 1: named opponents; 2: division; 3: pool.
	Method Record:TPostseasonFraction(id:Int, mode:Int, unused:Int, opponents:Int[])
		Local result:TPostseasonFraction = New TPostseasonFraction
		result.denominator = 0
		For Local fixture:TFixtureState = EachIn league.fixtures
			If fixture.status <> EFixtureStatus.Completed Then
				Continue
			End If

			Local opponent:Int
			Local own:Int, other:Int
			If fixture.homeTeamId = id Then
				opponent = fixture.awayTeamId
				own = fixture.scoreHome; other = fixture.scoreAway
			ElseIf fixture.awayTeamId = id Then
				opponent = fixture.homeTeamId
				own = fixture.scoreAway; other = fixture.scoreHome
			Else
				Continue
			End If

			If mode = 1 And Not Contains(opponents, opponent) Then
				Continue
			End If

			If mode = 2 And Division(id) <> Division(opponent) Then
				Continue
			End If

			If mode = 3 And Not InPool(opponent) Then
				Continue
			End If

			result.denominator :+ 1
			If own > other Then
				result.numerator :+ 2
			End If

			If own = other Then
				result.numerator :+ 1
			End If
		Next

		If result.denominator = 0 Then result.applicable = False; result.denominator = 1

		Return result
	End Method

	Method CommonOpponents:Int[](ids:Int[])
		Local common:Int[]
		For Local fixture:TFixtureState = EachIn league.fixtures
			If fixture.homeTeamId <> ids[0] And fixture.awayTeamId <> ids[0] Then
				Continue
			End If

			Local opponent:Int = fixture.homeTeamId
			If opponent = ids[0] Then
				opponent = fixture.awayTeamId
			End If

			If Contains(common, opponent) Then
				Continue
			End If

			Local all:Int = True
			For Local i:Int = 1 Until ids.Length
				Local found:Int
				For Local other:TFixtureState = EachIn league.fixtures
					If (other.homeTeamId = ids[i] And other.awayTeamId = opponent) Or (other.awayTeamId = ids[i] And other.homeTeamId = opponent) Then found = True; Exit
				Next

				If Not found Then all = False; Exit
			Next

			If all Then
				common :+ [opponent]
			End If
		Next

		Return common
	End Method

	Method Strength:TPostseasonFraction(id:Int, onlyWins:Int)
		Local result:TPostseasonFraction = New TPostseasonFraction
		result.numerator = 0
		result.denominator = 0
		For Local fixture:TFixtureState = EachIn league.fixtures
			Local opponent:Int
			If fixture.homeTeamId = id Then
				If onlyWins And fixture.scoreHome <= fixture.scoreAway Then
					Continue
				End If

				opponent = fixture.awayTeamId
			ElseIf fixture.awayTeamId = id Then
				If onlyWins And fixture.scoreAway <= fixture.scoreHome Then
					Continue
				End If

				opponent = fixture.homeTeamId
			Else
				Continue
			End If

			Local record:TPostseasonFraction = Record(opponent, 0, 0, Null)
			' Opponents can have different games played; combine their records,
			' counting a repeated opponent once per scheduled meeting.
			result.numerator :+ record.numerator
			result.denominator :+ record.denominator
		Next

		If result.denominator = 0 Then result.applicable = False; result.denominator = 1

		Return result
	End Method

	Method ScoreMetric:TPostseasonFraction(id:Int, mode:Int)
		Local result:TPostseasonFraction = New TPostseasonFraction
		For Local fixture:TFixtureState = EachIn league.fixtures
			If fixture.homeTeamId = id Then
				Select mode
					Case 1 result.numerator :+ fixture.scoreHome
					Case 2 result.numerator :- fixture.scoreAway
					Case 3 result.numerator :+ fixture.scoreHome - fixture.scoreAway
				End Select
			ElseIf fixture.awayTeamId = id Then
				Select mode
					Case 1 result.numerator :+ fixture.scoreAway
					Case 2 result.numerator :- fixture.scoreHome
					Case 3 result.numerator :+ fixture.scoreAway - fixture.scoreHome
				End Select
			End If
		Next

		Return result
	End Method

	Method ScopedNetPoints:TPostseasonFraction(id:Int, mode:Int, opponents:Int[])
		Local result:TPostseasonFraction = New TPostseasonFraction
		For Local fixture:TFixtureState = EachIn league.fixtures
			Local opponent:Int
			Local margin:Int
			If fixture.homeTeamId = id Then
				opponent = fixture.awayTeamId
				margin = fixture.scoreHome - fixture.scoreAway
			ElseIf fixture.awayTeamId = id Then
				opponent = fixture.homeTeamId
				margin = fixture.scoreAway - fixture.scoreHome
			Else
				Continue
			End If

			If mode = 1 And Not InPool(opponent) Then
				Continue
			End If

			If mode = 2 And Not Contains(opponents, opponent) Then
				Continue
			End If

			result.numerator :+ margin
		Next

		Return result
	End Method

	Method CombinedPointsRank:TPostseasonFraction(id:Int, poolOnly:Int)
		Local ownFor:Long = ScoreMetric(id, 1).numerator
		Local ownAllowed:Long = -ScoreMetric(id, 2).numerator
		Local combined:Long = 2
		For Local participant:TParticipant = EachIn comp.participants
			If participant.id = id Or Not IsEntrant(participant.id) Or (poolOnly And Not InPool(participant.id)) Then
				Continue
			End If

			If ScoreMetric(participant.id, 1).numerator > ownFor Then
				combined :+ 1
			End If

			If -ScoreMetric(participant.id, 2).numerator < ownAllowed Then
				combined :+ 1
			End If
		Next

		Local result:TPostseasonFraction = New TPostseasonFraction
		result.numerator = -combined
		Return result
	End Method

	Method Sweep:Int[](ids:Int[])
		Local winner:Int
		Local loser:Int
		For Local id:Int = EachIn ids
			Local beatsAll:Int = True
			Local losesAll:Int = True
			For Local other:Int = EachIn ids
				If other = id Then
					Continue
				End If

				Local meeting:TPostseasonFraction = Record(id, 1, 0, [other])
				If Not meeting.applicable Or meeting.numerator <> 2 * meeting.denominator Then
					beatsAll = False
				End If

				If Not meeting.applicable Or meeting.numerator <> 0 Then
					losesAll = False
				End If
			Next

			If beatsAll Then
				winner = id
			End If

			If losesAll Then
				loser = id
			End If
		Next

		If winner <> 0 Then
			Return [winner]
		End If

		If loser <> 0 Then
			Return Without(ids, loser)
		End If

		Return ids
	End Method

	Method Division:String(id:Int)
		For Local participant:TParticipant = EachIn comp.participants
			If participant.id = id Then
				Return participant.divisionId
			End If
		Next

		Throw "Unknown postseason participant " + id
	End Method

	Method InPool:Int(id:Int)
		Local division:String = Division(id)
		For Local value:String = EachIn pool.divisionIds
			If division = value Then
				Return True
			End If
		Next

		Return False
	End Method

	Method IsEntrant:Int(id:Int)
		If league.entrants = Null Or league.entrants.Length = 0 Then
			Return True
		End If

		Return Contains(league.entrants, id)
	End Method

	Function Contains:Int(values:Int[], value:Int)
		For Local item:Int = EachIn values
			If item = value Then
				Return True
			End If
		Next

		Return False
	End Function

	Function Without:Int[](values:Int[], excluded:Int)
		Local result:Int[]
		For Local value:Int = EachIn values
			If value <> excluded Then
				result :+ [value]
			End If
		Next

		Return result
	End Function
End Type
