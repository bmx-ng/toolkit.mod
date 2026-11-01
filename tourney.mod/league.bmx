' A league may use the built-in round robin or supply an exact fixture list.
' Bespoke asymmetric pairing algorithms can implement IStageScheduler.
Rem
bbdoc: Assigns or revises league fixture weeks.
End Rem
Interface ILeagueWeekAllocator
	Rem
	bbdoc: Assigns week numbers while enforcing the league's week constraints.
	param: Competition definition and participant details.
	param: League matchup, bye, and week rules.
	param: Fixture states whose `round` fields receive week numbers.
	End Rem
	Method Assign(comp:TCompetition, schedule:TLeagueScheduleConfig, fixtures:TFixtureState[])
End Interface

Rem
bbdoc: Allocates league games across weeks while enforcing byes and gaps.
End Rem
Type TLeagueWeekAllocator Implements ILeagueWeekAllocator
	Method Assign(comp:TCompetition, schedule:TLeagueScheduleConfig, fixtures:TFixtureState[])
		If schedule.minWeeksBetweenMeetings < 0 Then
			Throw "minWeeksBetweenMeetings cannot be negative"
		End If

		Local weeks:Int = schedule.weeks
		If weeks <= 0 Then
			weeks = 1
		End If

		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.round <= 0 Then
				Continue
			End If

			If schedule.weeks > 0 And fixture.round > weeks Then
				Throw "League fixture is outside configured weeks: " + fixture.id
			End If

			If Not IsAvailable(schedule, fixtures, fixture, fixture.round) Then
				Throw "League fixture conflicts with a bye or another fixture: " + fixture.id
			End If

			weeks = Max(weeks, fixture.round)
		Next

		If schedule.weeks > 0 Then
			If Not AssignWithinWeeks(schedule, fixtures, weeks) Then
				Throw "Cannot assign all league fixtures within configured weeks"
			End If

			Return
		End If

		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.round > 0 Then
				Continue
			End If

			Local assigned:Int = False
			Local week:Int = 1
			While week <= weeks
				If IsAvailable(schedule, fixtures, fixture, week) Then
					fixture.round = week
					assigned = True
					Exit
				End If

				week :+ 1
			Wend

			If Not assigned And schedule.weeks = 0 Then
				Repeat
					weeks :+ 1
				Until IsAvailable(schedule, fixtures, fixture, weeks)

				fixture.round = weeks
				assigned = True
			End If

			If Not assigned Then
				Throw "Cannot assign all league fixtures within configured weeks"
			End If
		Next
	End Method

	' Backtrack when a fixed season length is requested: first-fit alone can
	' reject a valid edge-colouring simply because of fixture input order.
	Method AssignWithinWeeks:Int(schedule:TLeagueScheduleConfig, fixtures:TFixtureState[], weeks:Int)
		Local nextFixture:TFixtureState = Null
		Local fewest:Int = weeks + 1
		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.round > 0 Then
				Continue
			End If

			Local choices:Int = 0
			For Local week:Int = 1 To weeks
				If IsAvailable(schedule, fixtures, fixture, week) Then
					choices :+ 1
				End If
			Next

			If choices = 0 Then
				Return False
			End If

			If choices < fewest Then
				fewest = choices
				nextFixture = fixture
			End If
		Next

		If nextFixture = Null Then
			Return True
		End If

		For Local week:Int = 1 To weeks
			If Not IsAvailable(schedule, fixtures, nextFixture, week) Then
				Continue
			End If

			nextFixture.round = week
			If AssignWithinWeeks(schedule, fixtures, weeks) Then
				Return True
			End If

			nextFixture.round = 0
		Next

		Return False
	End Method

	Method IsAvailable:Int(schedule:TLeagueScheduleConfig, fixtures:TFixtureState[], fixture:TFixtureState, week:Int)
		For Local bye:TParticipantByeWeek = EachIn schedule.byeWeeks
			If bye.week = week And (bye.participantId = fixture.homeTeamId Or bye.participantId = fixture.awayTeamId) Then
				Return False
			End If
		Next

		For Local other:TFixtureState = EachIn fixtures
			If other = fixture Or other.round <= 0 Then
				Continue
			End If

			If other.round = week Then
				If fixture.homeTeamId = other.homeTeamId Or fixture.homeTeamId = other.awayTeamId Then
					Return False
				End If

				If fixture.awayTeamId = other.homeTeamId Or fixture.awayTeamId = other.awayTeamId Then
					Return False
				End If
			End If

			If schedule.minWeeksBetweenMeetings > 0 And other.round >= week - schedule.minWeeksBetweenMeetings And other.round <= week + schedule.minWeeksBetweenMeetings Then
				If (fixture.homeTeamId = other.homeTeamId And fixture.awayTeamId = other.awayTeamId) Or (fixture.homeTeamId = other.awayTeamId And fixture.awayTeamId = other.homeTeamId) Then
					Return False
				End If
			End If
		Next

		Return True
	End Method
End Type

Rem
bbdoc: Generates league opponents, fixtures, and week assignments.
End Rem
Type TLeagueScheduler Extends TGroupScheduler
	Rem
	bbdoc: Week allocator for this league scheduler.
	End Rem
	Field weekAllocator:ILeagueWeekAllocator
	Rem
	bbdoc: Defer weeks for this league scheduler.
	End Rem
	Field deferWeeks:Int

	Method RegisterWeekAllocator(allocator:ILeagueWeekAllocator)
		weekAllocator = allocator
	End Method

	Method BuildFixtures:TFixtureState[](comp:TCompetition, stage:TStage) Override
		Local cfg:TLeagueConfig = TLeagueConfig(stage.config)
		If cfg = Null Then
			Throw "League stage needs TLeagueConfig"
		End If

		Local schedule:TLeagueScheduleConfig = cfg.schedule
		If schedule <> Null And (schedule.vsSameConference <> Null Or schedule.vsOtherConference <> Null Or schedule.strengthSchedule) Then
			Throw "Use matchupRules for conference and rank-based league pairings"
		End If

		If schedule <> Null And schedule.fixedFixtures <> Null And schedule.fixedFixtures.Length > 0 Then
			Local fixtures:TFixtureState[]
			For Local i:Int = 0 Until schedule.fixedFixtures.Length
				Local source:TFixture = schedule.fixedFixtures[i]
				Local f:TFixtureState = New TFixtureState
				f.id = stage.id + "_F" + (i + 1)
				f.round = source.round
				f.leg = source.leg
				f.homeTeamId = source.homeTeamId
				f.awayTeamId = source.awayTeamId
				f.status = EFixtureStatus.Scheduled
				fixtures :+ [f]
			Next

			ValidateGameCounts(comp, schedule, fixtures)
			Local allocator:ILeagueWeekAllocator = weekAllocator
			If allocator = Null Then
				allocator = New TLeagueWeekAllocator
			End If

			If Not deferWeeks Then
				allocator.Assign(comp, schedule, fixtures)
			End If

			Return fixtures
		End If

		If schedule <> Null And schedule.matchupRules <> Null And schedule.matchupRules.Length > 0 Then
			Local fixtures:TFixtureState[] = BuildRuleFixtures(comp, stage, schedule)
			ValidateGameCounts(comp, schedule, fixtures)
			Local allocator:ILeagueWeekAllocator = weekAllocator
			If allocator = Null Then
				allocator = New TLeagueWeekAllocator
			End If

			If Not deferWeeks Then
				allocator.Assign(comp, schedule, fixtures)
			End If

			Return fixtures
		End If

		If schedule <> Null And schedule.divisions <> Null And schedule.divisions.Length > 1 Then
			Throw "Multi-division league needs matchupRules, fixedFixtures, or a custom scheduler"
		End If

		Local perOpponent:Int = 1
		If schedule <> Null Then
			If schedule.vsOwnDivision > 0 Then
				perOpponent = schedule.vsOwnDivision
			ElseIf schedule.totalGamesPerTeam > 0 And comp.participants.Length > 1 Then
				Local opponents:Int = comp.participants.Length - 1
				If schedule.totalGamesPerTeam Mod opponents <> 0 Then
					Throw "League totalGamesPerTeam requires fixedFixtures for an asymmetric schedule"
				End If

				perOpponent = schedule.totalGamesPerTeam / opponents
			End If
		End If

		Local group:TGroupConfig = New TGroupConfig
		group.groups = 1
		group.roundRobinPerOpponent = perOpponent
		group.policy = cfg.policy
		Local delegated:TStage = New TStage
		delegated.id = stage.id
		delegated.stageType = EStageType.Group
		delegated.input = stage.input
		delegated.config = group
		delegated.schedule = stage.schedule
		Local fixtures:TFixtureState[] = Super.BuildFixtures(comp, delegated)
		If schedule <> Null Then
			ValidateGameCounts(comp, schedule, fixtures)
			If deferWeeks Or schedule.weeks > 0 Or schedule.minWeeksBetweenMeetings > 0 Or (schedule.byeWeeks <> Null And schedule.byeWeeks.Length > 0) Then
				' Generated round-robin rounds are suggestions, not published dates.
				For Local fixture:TFixtureState = EachIn fixtures
					fixture.round = 0
				Next
			End If

			Local allocator:ILeagueWeekAllocator = weekAllocator
			If allocator = Null Then
				allocator = New TLeagueWeekAllocator
			End If

			If Not deferWeeks Then
				allocator.Assign(comp, schedule, fixtures)
			End If
		End If

		Return fixtures
	End Method

	Method ValidateGameCounts(comp:TCompetition, schedule:TLeagueScheduleConfig, fixtures:TFixtureState[])
		If schedule.totalGamesPerTeam <= 0 Then
			Return
		End If

		For Local participant:TParticipant = EachIn comp.participants
			Local games:Int = 0
			For Local fixture:TFixtureState = EachIn fixtures
				If fixture.homeTeamId = participant.id Or fixture.awayTeamId = participant.id Then
					games :+ 1
				End If
			Next

			If games <> schedule.totalGamesPerTeam Then
				Throw "League game count differs from totalGamesPerTeam for participant: " + participant.id
			End If
		Next
	End Method

	Method BuildRuleFixtures:TFixtureState[](comp:TCompetition, stage:TStage, schedule:TLeagueScheduleConfig)
		Local fixtures:TFixtureState[]
		Local scheduledPairs:TStringMap = New TStringMap
		For Local rule:TMatchupRule = EachIn schedule.matchupRules
			If rule.gamesPerPair < 1 Then
				Throw "Matchup rule needs gamesPerPair >= 1"
			End If

			If rule.mode = EMatchupMode.RotatingDivisionPairs Then
				ValidateRotatingPairs(rule)
			End If

			Local seen:TStringMap = New TStringMap
			For Local source:TParticipant = EachIn comp.participants
				If Not InDivisions(source.divisionId, rule.sourceDivisionIds) Then
					Continue
				End If

				Local rotated:String = ""
				If rule.mode = EMatchupMode.RotatingDivision Then
					If rule.targetDivisionIds = Null Or rule.targetDivisionIds.Length = 0 Then
						Throw "RotatingDivision needs target divisions"
					End If

					Local ordinal:Int = DivisionOrdinal(schedule, source.divisionId)
					Local index:Int = (ordinal + schedule.rotationSeed + rule.rotationOffset) Mod rule.targetDivisionIds.Length
					If index < 0 Then
						index :+ rule.targetDivisionIds.Length
					End If

					rotated = rule.targetDivisionIds[index]
				ElseIf rule.mode = EMatchupMode.RotatingDivisionPairs Then
					rotated = PairedDivision(rule.sourceDivisionIds, source.divisionId, schedule.rotationSeed + rule.rotationOffset)
				End If

				For Local target:TParticipant = EachIn comp.participants
					If target.id = source.id Then
						Continue
					End If

					If rotated <> "" Then
						If target.divisionId <> rotated Then
							Continue
						End If
					ElseIf rule.targetDivisionIds <> Null And rule.targetDivisionIds.Length > 0 Then
						If Not InDivisions(target.divisionId, rule.targetDivisionIds) Then
							Continue
						End If
					ElseIf Not InDivisions(target.divisionId, rule.sourceDivisionIds) Then
						Continue
					End If

					If (rule.mode = EMatchupMode.SameRank Or rule.sameRankOnly) And (source.previousRank = 0 Or source.previousRank <> target.previousRank) Then
						Continue
					End If

					Local low:Int = Min(source.id, target.id)
					Local high:Int = Max(source.id, target.id)
					Local key:String = low + "-" + high
					If seen.Contains(key) Then
						Continue
					End If

					seen.Insert(key, "1")
					If rule.excludeAlreadyScheduled And scheduledPairs.Contains(key) Then
						Continue
					End If

					scheduledPairs.Insert(key, "1")
					For Local game:Int = 1 To rule.gamesPerPair
						Local fixture:TFixtureState = New TFixtureState
						fixture.id = stage.id + "_G" + (fixtures.Length + 1)
						fixture.leg = game
						If game Mod 2 = 1 Then
							fixture.homeTeamId = low
							fixture.awayTeamId = high
						Else
							fixture.homeTeamId = high
							fixture.awayTeamId = low
						End If

						fixture.status = EFixtureStatus.Scheduled
						fixtures :+ [fixture]
					Next
				Next
			Next
		Next

		If schedule.balanceHomeAway Then
			BalanceHomeAway(comp, fixtures)
		End If

		Return fixtures
	End Method

	Method ValidateRotatingPairs(rule:TMatchupRule)
		If rule.sourceDivisionIds = Null Or rule.sourceDivisionIds.Length < 2 Or rule.sourceDivisionIds.Length Mod 2 <> 0 Then
			Throw "RotatingDivisionPairs needs an even source division pool of at least two"
		End If

		If rule.targetDivisionIds <> Null And rule.targetDivisionIds.Length > 0 Then
			Throw "RotatingDivisionPairs uses sourceDivisionIds only"
		End If

		For Local i:Int = 0 Until rule.sourceDivisionIds.Length
			If rule.sourceDivisionIds[i] = "" Then
				Throw "RotatingDivisionPairs needs named divisions"
			End If

			For Local j:Int = i + 1 Until rule.sourceDivisionIds.Length
				If rule.sourceDivisionIds[i] = rule.sourceDivisionIds[j] Then
					Throw "RotatingDivisionPairs has duplicate divisions"
				End If
			Next
		Next
	End Method

	Method PairedDivision:String(divisions:String[], source:String, round:Int)
		Local count:Int = divisions.Length
		Local positions:Int[] = New Int[count]
		positions[0] = 0
		Local shift:Int = round Mod (count - 1)
		If shift < 0 Then
			shift :+ count - 1
		End If

		For Local i:Int = 1 Until count
			positions[1 + ((i - 1 + shift) Mod (count - 1))] = i
		Next

		For Local position:Int = 0 Until count
			If divisions[positions[position]] = source Then
				Return divisions[positions[count - 1 - position]]
			End If
		Next

		Throw "RotatingDivisionPairs source is outside its division pool: " + source
	End Method

	' Repeated meetings first receive reciprocal hosts. The remaining odd
	' meeting for each pair forms an undirected graph, which can be oriented
	' within one home game per participant by augmenting odd-degree vertices
	' and traversing Euler walks.
	Method BalanceHomeAway(comp:TCompetition, fixtures:TFixtureState[])
		Local fromIndex:Int[]
		Local toIndex:Int[]
		Local fixtureIndex:Int[]
		Local degree:Int[] = New Int[comp.participants.Length]
		Local grouped:Int[] = New Int[fixtures.Length]
		For Local i:Int = 0 Until fixtures.Length
			If grouped[i] Then
				Continue
			End If

			Local home:Int = ParticipantIndex(comp, fixtures[i].homeTeamId)
			Local away:Int = ParticipantIndex(comp, fixtures[i].awayTeamId)
			If home < 0 Or away < 0 Then
				Throw "League fixture refers to an unknown participant"
			End If

			If home = away Then
				Throw "League fixture cannot pair a participant with itself"
			End If

			Local meetings:Int[]
			For Local j:Int = i Until fixtures.Length
				If grouped[j] Then
					Continue
				End If

				Local a:Int = fixtures[j].homeTeamId
				Local b:Int = fixtures[j].awayTeamId
				If (a = fixtures[i].homeTeamId And b = fixtures[i].awayTeamId) Or (a = fixtures[i].awayTeamId And b = fixtures[i].homeTeamId) Then
					grouped[j] = True
					meetings :+ [j]
				End If
			Next

			For Local game:Int = 0 Until (meetings.Length / 2) * 2
				Local fixture:TFixtureState = fixtures[meetings[game]]
				If game Mod 2 = 0 Then
					fixture.homeTeamId = comp.participants[home].id
					fixture.awayTeamId = comp.participants[away].id
				Else
					fixture.homeTeamId = comp.participants[away].id
					fixture.awayTeamId = comp.participants[home].id
				End If
			Next

			If meetings.Length Mod 2 = 0 Then
				Continue
			End If

			fromIndex :+ [home]
			toIndex :+ [away]
			fixtureIndex :+ [meetings[meetings.Length - 1]]
			degree[home] :+ 1
			degree[away] :+ 1
		Next

		Local odd:Int = -1
		For Local i:Int = 0 Until degree.Length
			If degree[i] Mod 2 = 0 Then
				Continue
			End If

			If odd < 0 Then
				odd = i
			Else
				fromIndex :+ [odd]
				toIndex :+ [i]
				fixtureIndex :+ [-1]
				odd = -1
			End If
		Next

		Local used:Int[] = New Int[fromIndex.Length]
		Local stack:Int[] = New Int[fromIndex.Length + 1]
		For Local start:Int = 0 Until comp.participants.Length
			Local top:Int = 0
			stack[top] = start
			While top >= 0
				Local current:Int = stack[top]
				Local edge:Int = -1
				For Local i:Int = 0 Until fromIndex.Length
					If used[i] Then
						Continue
					End If

					If fromIndex[i] = current Or toIndex[i] = current Then
						edge = i
						Exit
					End If
				Next

				If edge < 0 Then
					top :- 1
					Continue
				End If

				used[edge] = True
				Local other:Int = fromIndex[edge]
				If other = current Then
					other = toIndex[edge]
				End If

				If fixtureIndex[edge] >= 0 Then
					Local fixture:TFixtureState = fixtures[fixtureIndex[edge]]
					fixture.homeTeamId = comp.participants[current].id
					fixture.awayTeamId = comp.participants[other].id
				End If

				top :+ 1
				stack[top] = other
			Wend
		Next
	End Method

	Method ParticipantIndex:Int(comp:TCompetition, participantId:Int)
		For Local i:Int = 0 Until comp.participants.Length
			If comp.participants[i].id = participantId Then
				Return i
			End If
		Next

		Return -1
	End Method

	Method InDivisions:Int(id:String, divisions:String[])
		If divisions = Null Or divisions.Length = 0 Then
			Return True
		End If

		For Local division:String = EachIn divisions
			If division = id Then
				Return True
			End If
		Next

		Return False
	End Method

	Method DivisionOrdinal:Int(schedule:TLeagueScheduleConfig, id:String)
		If schedule.divisions <> Null Then
			For Local i:Int = 0 Until schedule.divisions.Length
				If schedule.divisions[i].id = id Then
					Return i
				End If
			Next
		End If

		Local hash:Int = 0
		For Local i:Int = 0 Until id.Length
			hash = (hash * 31 + id[i]) & $7fffffff
		Next

		Return hash
	End Method
End Type

Rem
bbdoc: Updates league standings after a fixture result.
End Rem
Type TLeagueScorer Extends TGroupScorer
End Type
