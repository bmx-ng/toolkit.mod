' Joint week and slot search for fixtures that have already been generated. The planner
' changes only runtime fixture assignments; the competition definition remains
' serializable and independent of the search.
Function CalendarCanPlanLeagueWeeks:Int(schedule:TLeagueScheduleConfig, calendar:TCalendar)
	If schedule = Null Or calendar = Null Or calendar.slots = Null Or calendar.slots.Length = 0 Then
		Return False
	End If

	If schedule.weeks > 0 Then
		Return True
	End If
	' Without a configured length, every slot must identify its week to bound the search.
	For Local slot:TSlot = EachIn calendar.slots
		If slot = Null Or slot.round <= 0 Then
			Return False
		End If
	Next

	Return True
End Function

Rem
bbdoc: A fixture and its candidate week-and-slot domain in joint planning.
End Rem
Type TCalendarPlanItem
	Rem
	bbdoc: Index of the stage for this calendar plan item.
	End Rem
	Field stageIndex:Int
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: #TFixtureState value used by this calendar plan item.
	End Rem
	Field fixture:TFixtureState
	Rem
	bbdoc: #TCalendar value used by this calendar plan item.
	End Rem
	Field calendar:TCalendar
	Rem
	bbdoc: #TLeagueScheduleConfig value used by this calendar plan item.
	End Rem
	Field leagueSchedule:TLeagueScheduleConfig
	Rem
	bbdoc: #TFixtureState entries associated with this calendar plan item.
	End Rem
	Field stageFixtures:TFixtureState[]
	Rem
	bbdoc: Original round for this calendar plan item.
	End Rem
	Field originalRound:Int
	Rem
	bbdoc: Pinned round for this calendar plan item.
	End Rem
	Field pinnedRound:Int
	Rem
	bbdoc: ID of the original slot associated with this calendar plan item.
	End Rem
	Field originalSlotId:String
	Rem
	bbdoc: ID of the original venue associated with this calendar plan item.
	End Rem
	Field originalVenueId:String
	Rem
	bbdoc: Calendar max week for this calendar plan item.
	End Rem
	Field calendarMaxWeek:Int
End Type

Rem
bbdoc: Candidate slots for one scarce planning resource.
End Rem
Type TCalendarCapacityDomain
	Rem
	bbdoc: #TCalendarPlanItem value used by this calendar capacity domain.
	End Rem
	Field item:TCalendarPlanItem
	Rem
	bbdoc: Weeks values associated with this calendar capacity domain.
	End Rem
	Field weeks:Int[]
	Rem
	bbdoc: Times values associated with this calendar capacity domain.
	End Rem
	Field times:String[]
	Rem
	bbdoc: Forced venue of this calendar capacity domain.
	End Rem
	Field forcedVenue:String
	Rem
	bbdoc: Venue flexible for this calendar capacity domain.
	End Rem
	Field venueFlexible:Int

	Method AddCandidate(week:Int, slot:TSlot)
		Local found:Int
		For Local candidate:Int = EachIn weeks
			If candidate = week Then found = True; Exit
		Next

		If Not found Then
			weeks :+ [week]
		End If

		If slot.venueId = "" Or slot.dateTime = "" Then
			venueFlexible = True
			Return
		End If

		If forcedVenue = "" Then
			forcedVenue = slot.venueId
		ElseIf forcedVenue <> slot.venueId Then
			venueFlexible = True
		End If

		For Local time:String = EachIn times
			If time = slot.dateTime Then
				Return
			End If
		Next

		times :+ [slot.dateTime]
	End Method
End Type

Rem
bbdoc: A participant's scheduled game used when scoring soft preferences.
End Rem
Type TPreferenceEvent
	Rem
	bbdoc: #TFixtureState value used by this preference event.
	End Rem
	Field fixture:TFixtureState
	Rem
	bbdoc: #TSlot value used by this preference event.
	End Rem
	Field slot:TSlot
	Rem
	bbdoc: Home for this preference event.
	End Rem
	Field home:Int
End Type

' A concrete dead end from the joint search. This is a witness, not a minimal
' conflicting set of rules: another branch may fail for different reasons.
Rem
bbdoc: A structured explanation of a failed schedule plan.
about: This report records a concrete capacity shortage or dead end encountered by the search. `searchLimitReached` distinguishes an exhausted node budget from a proved lack of placements.
End Rem
Type TScheduleFailureReport
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Assigned fixtures for this schedule failure report.
	End Rem
	Field assignedFixtures:Int
	Rem
	bbdoc: Total candidates for this schedule failure report.
	End Rem
	Field totalCandidates:Int
	Rem
	bbdoc: Candidate slots values associated with this schedule failure report.
	End Rem
	Field candidateSlots:String[]
	Rem
	bbdoc: Candidate reasons values associated with this schedule failure report.
	End Rem
	Field candidateReasons:String[]
	Rem
	bbdoc: Nodes for this schedule failure report.
	End Rem
	Field nodes:Int
	Rem
	bbdoc: Search limit reached for this schedule failure report.
	End Rem
	Field searchLimitReached:Int
	Rem
	bbdoc: Capacity conflict for this schedule failure report.
	End Rem
	Field capacityConflict:Int
	Rem
	bbdoc: Capacity kind of this schedule failure report.
	End Rem
	Field capacityKind:String
	Rem
	bbdoc: Capacity resource of this schedule failure report.
	End Rem
	Field capacityResource:String
	Rem
	bbdoc: Required fixtures for this schedule failure report.
	End Rem
	Field requiredFixtures:Int
	Rem
	bbdoc: Available resources for this schedule failure report.
	End Rem
	Field availableResources:Int

	Rem
	bbdoc: Summarizes the resource shortage or search dead end.
	returns: A readable description of the failed planning attempt.
	about: This is a witness from one branch of the search, not necessarily a minimal conflicting set of rules.
	End Rem
	Method Summary:String()
		If capacityKind <> "" Then
			Return stageId + " has " + requiredFixtures + " fixtures needing " + capacityKind + " " + capacityResource + " but only " + availableResources + " available placements"
		End If

		If capacityConflict Then
			Return stageId + " cannot assign its remaining fixtures to distinct calendar slots"
		End If

		Local result:String = stageId + "/" + fixtureId + " has no available week/slot after " + assignedFixtures + " assignments"
		For Local index:Int = 0 Until candidateSlots.Length
			result :+ "; " + candidateSlots[index] + ": " + candidateReasons[index]
		Next

		If totalCandidates > candidateSlots.Length Then
			result :+ "; " + (totalCandidates - candidateSlots.Length) + " more choices omitted"
		End If

		Return result
	End Method
End Type

Rem
bbdoc: Searches week and calendar assignments across started stages.
End Rem
Type TCompetitionCalendarPlanner
	Rem
	bbdoc: #TCompetition value used by this competition calendar planner.
	End Rem
	Field comp:TCompetition
	Rem
	bbdoc: #TCalendarPlanItem entries associated with this competition calendar planner.
	End Rem
	Field items:TCalendarPlanItem[]
	Rem
	bbdoc: #TCalendarSlotAllocator value used by this competition calendar planner.
	End Rem
	Field rules:TCalendarSlotAllocator
	Rem
	bbdoc: #TLeagueWeekAllocator value used by this competition calendar planner.
	End Rem
	Field weekRules:TLeagueWeekAllocator
	Rem
	bbdoc: Plan weeks for this competition calendar planner.
	End Rem
	Field planWeeks:Int
	Rem
	bbdoc: Nodes for this competition calendar planner.
	End Rem
	Field nodes:Int
	Rem
	bbdoc: Max nodes for this competition calendar planner.
	End Rem
	Field maxNodes:Int
	Rem
	bbdoc: Hit limit for this competition calendar planner.
	End Rem
	Field hitLimit:Int
	Rem
	bbdoc: Failure reason of this competition calendar planner.
	End Rem
	Field failureReason:String
	Rem
	bbdoc: #TScheduleFailureReport value used by this competition calendar planner.
	End Rem
	Field failureReport:TScheduleFailureReport
	Rem
	bbdoc: Week cap for this competition calendar planner.
	End Rem
	Field weekCap:Int
	Rem
	bbdoc: Open ended for this competition calendar planner.
	End Rem
	Field openEnded:Int
	Rem
	bbdoc: Max open week for this competition calendar planner.
	End Rem
	Field maxOpenWeek:Int
	Rem
	bbdoc: Has preferences for this competition calendar planner.
	End Rem
	Field hasPreferences:Int
	Rem
	bbdoc: Has best for this competition calendar planner.
	End Rem
	Field hasBest:Int
	Rem
	bbdoc: Best score for this competition calendar planner.
	End Rem
	Field bestScore:Long
	Rem
	bbdoc: Best horizon for this competition calendar planner.
	End Rem
	Field bestHorizon:Int
	Rem
	bbdoc: Optimal for this competition calendar planner.
	End Rem
	Field optimal:Int = True
	Rem
	bbdoc: Pruned nodes for this competition calendar planner.
	End Rem
	Field prunedNodes:Int
	Rem
	bbdoc: Best rounds values associated with this competition calendar planner.
	End Rem
	Field bestRounds:Int[]
	Rem
	bbdoc: Best slots values associated with this competition calendar planner.
	End Rem
	Field bestSlots:String[]
	Rem
	bbdoc: Best venues values associated with this competition calendar planner.
	End Rem
	Field bestVenues:String[]

	Method Assign:Int(comp:TCompetition, state:TCompetitionState, reassign:Int = False, maxSearchNodes:Int = 100000, planWeeks:Int = False)
		If comp = Null Or state = Null Or comp.stages = Null Or state.stages = Null Or comp.stages.Length <> state.stages.Length Then
			Throw "Calendar planning needs matching competition and state stages"
		End If

		If maxSearchNodes <= 0 Then
			Throw "Calendar planning search limit must be positive"
		End If

		Self.comp = comp
		Self.maxNodes = maxSearchNodes
		Self.planWeeks = planWeeks
		rules = New TCalendarSlotAllocator
		weekRules = New TLeagueWeekAllocator
		For Local index:Int = 0 Until comp.stages.Length
			If comp.stages[index] = Null Or state.stages[index] = Null Or comp.stages[index].id <> state.stages[index].stageId Then
				Throw "Calendar planning stage mismatch at index " + index
			End If

			Local calendar:TCalendar = GetSchedulePolicy(comp.stages[index]).calendar
			If calendar = Null Then
				Continue
			End If

			For Local fixture:TFixtureState = EachIn state.stages[index].fixtures
				If fixture.status = EFixtureStatus.Cancelled Or fixture.awayTeamId = 0 Then
					Continue
				End If

				If calendar.slots = Null Or calendar.slots.Length = 0 Then
					Throw "Calendar has no slots for stage: " + comp.stages[index].id
				End If

				Local item:TCalendarPlanItem = New TCalendarPlanItem
				item.stageIndex = index
				item.stageId = comp.stages[index].id
				item.fixture = fixture
				item.calendar = calendar
				If planWeeks Then
					Local league:TLeagueConfig = TLeagueConfig(comp.stages[index].config)
					If league <> Null And CalendarCanPlanLeagueWeeks(league.schedule, calendar) Then
						item.leagueSchedule = league.schedule
						item.stageFixtures = state.stages[index].fixtures
						If league.schedule.weeks = 0 Then
							openEnded = True
							For Local slot:TSlot = EachIn calendar.slots
								item.calendarMaxWeek = Max(item.calendarMaxWeek, slot.round)
							Next

							maxOpenWeek = Max(maxOpenWeek, item.calendarMaxWeek)
						End If

						If league.schedule.minWeeksBetweenMeetings < 0 Then
							Throw "minWeeksBetweenMeetings cannot be negative"
						End If

						If league.schedule.fixedFixtures <> Null Then
							For Local sourceIndex:Int = 0 Until league.schedule.fixedFixtures.Length
								Local source:TFixture = league.schedule.fixedFixtures[sourceIndex]
								If source.round > 0 And item.fixture.id = comp.stages[index].id + "_F" + (sourceIndex + 1) Then
									item.pinnedRound = source.round
								End If
							Next
						End If
					End If
				End If

				item.originalRound = fixture.round
				If item.pinnedRound = 0 And fixture.round > 0 And Not reassign Then
					item.pinnedRound = fixture.round
				End If

				item.originalSlotId = fixture.slotId
				item.originalVenueId = fixture.venueId
				items :+ [item]
			Next
		Next

		If items = Null Or items.Length = 0 Then
			Return 0
		End If

		Try
			ValidateCalendars()
			ValidatePreferences()
			If hasPreferences And reassign Then
				SeedExistingSchedule()
			End If

			Local planned:Int
			For Local item:TCalendarPlanItem = EachIn items
				If reassign And (item.fixture.status = EFixtureStatus.Scheduled Or item.fixture.status = EFixtureStatus.Postponed) Then
					item.fixture.slotId = ""
					item.fixture.venueId = ""
					If planWeeks And item.leagueSchedule <> Null Then
						item.fixture.round = item.pinnedRound
					End If
				End If

				If item.fixture.slotId = "" Or (item.leagueSchedule <> Null And item.fixture.round = 0) Then
					planned :+ 1
				End If
			Next

			ValidateLocked()
			Local solved:Int
			If openEnded Then
				Local firstCap:Int = 1
				For Local item:TCalendarPlanItem = EachIn items
					If item.leagueSchedule <> Null And item.leagueSchedule.weeks = 0 Then
						firstCap = Max(firstCap, Max(item.fixture.round, item.pinnedRound))
					End If
				Next

				For Local candidateCap:Int = firstCap To Max(firstCap, maxOpenWeek)
					weekCap = candidateCap
					failureReport = Null
					failureReason = ""
					If hasPreferences Then
						SearchPreferred()
						If hasBest And bestHorizon <= weekCap Then solved = True; Exit
					Else
						If Search() Then solved = True; Exit
					End If

					If hitLimit Then
						Exit
					End If
				Next
			Else
				If hasPreferences Then
					SearchPreferred()
					solved = hasBest
				Else
					solved = Search()
				End If
			End If

			If Not solved And hasPreferences And hitLimit And hasBest Then
				solved = True
			End If

			If Not solved Then
				If failureReport <> Null Then
					failureReport.nodes = nodes
					failureReport.searchLimitReached = hitLimit
					failureReason = failureReport.Summary()
				End If

				If hitLimit Then
					Local message:String = "Competition calendar search limit reached after " + nodes + " nodes"
					If failureReason <> "" Then
						message :+ "; example dead end: " + failureReason
					End If

					Throw message
				End If

				Throw "No feasible competition calendar: " + failureReason
			End If

			If hasPreferences Then
				If hitLimit Then
					optimal = False
				End If

				RestoreBest()
			End If

			failureReport = Null
			Return planned
		Catch problem:Object
			For Local item:TCalendarPlanItem = EachIn items
				item.fixture.slotId = item.originalSlotId
				item.fixture.venueId = item.originalVenueId
				item.fixture.round = item.originalRound
			Next

			Throw problem
		End Try
	End Method

	Method ValidatePreferences()
		For Local index:Int = 0 Until comp.stages.Length
			Local preferences:TSchedulePreferences = GetSchedulePolicy(comp.stages[index]).preferences
			If preferences = Null Then
				Continue
			End If

			If preferences.minRestWeeks < 0 Or preferences.restShortfallWeight < 0 Or preferences.maxHomeStreak < 0 Or preferences.maxAwayStreak < 0 Or preferences.streakExcessWeight < 0 Or preferences.venueTransitionWeight < 0 Then
				Throw "Schedule preference values cannot be negative in stage: " + comp.stages[index].id
			End If

			For Local cost:TVenueTransitionCost = EachIn preferences.venueTransitions
				If cost = Null Or cost.cost < 0 Or cost.fromVenueId = "" Or cost.toVenueId = "" Then
					Throw "Invalid venue transition cost in stage: " + comp.stages[index].id
				End If

				For Local other:TVenueTransitionCost = EachIn preferences.venueTransitions
					If other = cost Then
						Exit
					End If

					If other.fromVenueId = cost.fromVenueId And other.toVenueId = cost.toVenueId Then
						Throw "Duplicate venue transition cost in stage: " + comp.stages[index].id
					End If
				Next
			Next

			Local hasStageItems:Int
			For Local item:TCalendarPlanItem = EachIn items
				If item.stageIndex = index Then hasStageItems = True; Exit
			Next

			If Not hasStageItems Then
				Continue
			End If

			If preferences.minRestWeeks > 0 And preferences.restShortfallWeight > 0 Then
				hasPreferences = True
			End If

			If preferences.streakExcessWeight > 0 And (preferences.maxHomeStreak > 0 Or preferences.maxAwayStreak > 0) Then
				hasPreferences = True
			End If

			If preferences.venueTransitionWeight > 0 And preferences.venueTransitions <> Null And preferences.venueTransitions.Length > 0 Then
				hasPreferences = True
			End If
		Next
	End Method

	Method ValidateCalendars()
		For Local index:Int = 0 Until comp.stages.Length
			Local calendar:TCalendar = GetSchedulePolicy(comp.stages[index]).calendar
			If calendar = Null Or calendar.slots = Null Then
				Continue
			End If

			For Local i:Int = 0 Until calendar.slots.Length
				Local slot:TSlot = calendar.slots[i]
				If slot = Null Or slot.id = "" Then
					Throw "Calendar slot needs an id in stage: " + comp.stages[index].id
				End If

				For Local j:Int = 0 Until i
					If calendar.slots[j].id = slot.id Then
						Throw "Duplicate calendar slot id in stage " + comp.stages[index].id + ": " + slot.id
					End If
				Next
			Next
		Next
	End Method

	Method SeedExistingSchedule()
		For Local item:TCalendarPlanItem = EachIn items
			If item.fixture.slotId = "" Or (item.leagueSchedule <> Null And item.fixture.round <= 0) Then
				Return
			End If

			If item.pinnedRound > 0 And item.fixture.round <> item.pinnedRound Then
				Return
			End If
		Next

		Local valid:Int = True
		Try
			ValidateLocked()
		Catch problem:Object
			valid = False
		End Try

		If valid Then
			SaveBest(PreferenceScore())
		End If

		For Local item:TCalendarPlanItem = EachIn items
			item.fixture.round = item.originalRound
			item.fixture.slotId = item.originalSlotId
			item.fixture.venueId = item.originalVenueId
		Next
	End Method

	Method CurrentOpenHorizon:Int()
		Local horizon:Int
		For Local item:TCalendarPlanItem = EachIn items
			If item.leagueSchedule <> Null And item.leagueSchedule.weeks = 0 Then
				horizon = Max(horizon, item.fixture.round)
			End If
		Next

		Return horizon
	End Method

	Method ValidateLocked()
		For Local item:TCalendarPlanItem = EachIn items
			If item.pinnedRound > 0 And item.fixture.round <> item.pinnedRound Then
				Throw "Fixture week differs from its fixed week for " + item.stageId + "/" + item.fixture.id
			End If

			If item.fixture.slotId = "" Then
				If item.leagueSchedule <> Null And item.fixture.round > 0 And Not weekRules.IsAvailable(item.leagueSchedule, item.stageFixtures, item.fixture, item.fixture.round) Then
					Throw "Preassigned league week conflicts for " + item.stageId + "/" + item.fixture.id
				End If

				Continue
			End If

			Local slot:TSlot = rules.FindSlot(item.calendar, item.fixture.slotId)
			If slot = Null Then
				Throw "Unknown preassigned calendar slot for " + item.stageId + "/" + item.fixture.id
			End If

			If item.fixture.venueId <> "" And item.fixture.venueId <> slot.venueId Then
				Throw "Preassigned venue differs from slot for " + item.stageId + "/" + item.fixture.id
			End If

			If item.fixture.round > 0 And Not CanUse(item, slot, item.fixture.round) Then
				Throw "Preassigned calendar slot conflicts for " + item.stageId + "/" + item.fixture.id
			End If

			item.fixture.venueId = slot.venueId
		Next
	End Method

	Method SearchPreferred()
		nodes :+ 1
		If nodes > maxNodes Then hitLimit = True; Return

		If hasBest And (Not openEnded Or bestHorizon <= weekCap) And PreferenceScore(True) >= bestScore Then
			prunedNodes :+ 1
			Return
		End If

		Local chosen:TCalendarPlanItem
		Local fewest:Int = 2147483647
		For Local item:TCalendarPlanItem = EachIn items
			If item.fixture.slotId <> "" And (item.fixture.round > 0 Or item.leagueSchedule = Null) Then
				Continue
			End If

			Local choices:Int
			For Local week:Int = FirstWeek(item) To LastWeek(item)
				For Local slot:TSlot = EachIn item.calendar.slots
					If item.fixture.slotId <> "" And item.fixture.slotId <> slot.id Then
						Continue
					End If

					If CanUse(item, slot, week) Then
						choices :+ 1
					End If
				Next
			Next

			If choices = 0 Then
				RecordFailure(item)
				Return
			End If

			If choices < fewest Then chosen = item; fewest = choices
		Next

		If chosen = Null Then
			Local score:Long = PreferenceScore()
			Local horizon:Int = CurrentOpenHorizon()
			If Not hasBest Or (openEnded And horizon < bestHorizon) Or (horizon = bestHorizon And score < bestScore) Then
				SaveBest(score)
			End If

			Return
		End If

		If Not HasDistinctSlotCapacity() Or Not HasSharedCapacity() Then
			Return
		End If

		Local oldRound:Int = chosen.fixture.round
		Local oldSlot:String = chosen.fixture.slotId
		Local oldVenue:String = chosen.fixture.venueId
		For Local week:Int = FirstWeek(chosen) To LastWeek(chosen)
			For Local slot:TSlot = EachIn chosen.calendar.slots
				If oldSlot <> "" And oldSlot <> slot.id Then
					Continue
				End If

				If Not CanUse(chosen, slot, week) Then
					Continue
				End If

				chosen.fixture.round = week
				chosen.fixture.slotId = slot.id
				chosen.fixture.venueId = slot.venueId
				SearchPreferred()
				chosen.fixture.round = oldRound
				chosen.fixture.slotId = oldSlot
				chosen.fixture.venueId = oldVenue
				If hitLimit Or (hasBest And bestScore = 0 And (Not openEnded Or bestHorizon <= weekCap)) Then
					Return
				End If
			Next
		Next
	End Method

	Method SaveBest(score:Long)
		hasBest = True
		bestScore = score
		bestHorizon = CurrentOpenHorizon()
		bestRounds = []
		bestSlots = []
		bestVenues = []
		For Local item:TCalendarPlanItem = EachIn items
			bestRounds :+ [item.fixture.round]
			bestSlots :+ [item.fixture.slotId]
			bestVenues :+ [item.fixture.venueId]
		Next
	End Method

	Method RestoreBest()
		For Local index:Int = 0 Until items.Length
			items[index].fixture.round = bestRounds[index]
			items[index].fixture.slotId = bestSlots[index]
			items[index].fixture.venueId = bestVenues[index]
		Next
	End Method

	Method PreferenceScore:Long(partial:Int = False)
		Local total:Long
		For Local stageIndex:Int = 0 Until comp.stages.Length
			Local preferences:TSchedulePreferences = GetSchedulePolicy(comp.stages[stageIndex]).preferences
			If preferences = Null Then
				Continue
			End If

			For Local participant:TParticipant = EachIn comp.participants
				Local events:TPreferenceEvent[] = []
				Local fixtureCount:Int
				Local leagueSchedule:TLeagueScheduleConfig
				For Local item:TCalendarPlanItem = EachIn items
					If item.stageIndex <> stageIndex Then
						Continue
					End If

					If item.fixture.homeTeamId <> participant.id And item.fixture.awayTeamId <> participant.id Then
						Continue
					End If

					fixtureCount :+ 1
					leagueSchedule = item.leagueSchedule
					If item.fixture.slotId = "" Or (item.leagueSchedule <> Null And item.fixture.round <= 0) Then
						Continue
					End If

					Local event:TPreferenceEvent = New TPreferenceEvent
					event.fixture = item.fixture
					event.slot = rules.FindSlot(item.calendar, item.fixture.slotId)
					event.home = item.fixture.homeTeamId = participant.id
					Local position:Int = events.Length
					events :+ [event]
					While position > 0 And EventBefore(event, events[position - 1])
						events[position] = events[position - 1]
						position :- 1
					Wend

					events[position] = event
				Next

				If partial And events.Length < fixtureCount Then
					If leagueSchedule <> Null And preferences.minRestWeeks > 0 And preferences.restShortfallWeight > 0 And fixtureCount > 1 Then
						Local weeks:Int = leagueSchedule.weeks
						If weeks = 0 Then
							weeks = weekCap
						End If

						Local shortfall:Int = Max(0, (fixtureCount - 1) * preferences.minRestWeeks - Max(0, weeks - fixtureCount))
						total :+ Long(shortfall) * preferences.restShortfallWeight
					End If

					Continue
				End If

				Local streak:Int
				For Local index:Int = 0 Until events.Length
					Local event:TPreferenceEvent = events[index]
					If index = 0 Or event.home <> events[index - 1].home Then
						streak = 1
					Else
						streak :+ 1
					End If

					If event.home And preferences.maxHomeStreak > 0 And streak > preferences.maxHomeStreak Then
						total :+ preferences.streakExcessWeight
					End If

					If Not event.home And preferences.maxAwayStreak > 0 And streak > preferences.maxAwayStreak Then
						total :+ preferences.streakExcessWeight
					End If

					If index = 0 Then
						Continue
					End If

					Local previous:TPreferenceEvent = events[index - 1]
					If event.fixture.round > 0 And previous.fixture.round > 0 Then
						Local idleWeeks:Int = Max(0, event.fixture.round - previous.fixture.round - 1)
						If idleWeeks < preferences.minRestWeeks Then
							total :+ Long(preferences.minRestWeeks - idleWeeks) * preferences.restShortfallWeight
						End If
					End If

					total :+ Long(VenueTransitionCost(preferences, previous.slot.venueId, event.slot.venueId)) * preferences.venueTransitionWeight
				Next
			Next
		Next

		Return total
	End Method

	Method EventBefore:Int(left:TPreferenceEvent, right:TPreferenceEvent)
		If left.fixture.round <> right.fixture.round Then
			Return left.fixture.round < right.fixture.round
		End If

		If left.slot.dateTime <> right.slot.dateTime Then
			Return left.slot.dateTime < right.slot.dateTime
		End If

		Return left.fixture.id < right.fixture.id
	End Method

	Method VenueTransitionCost:Int(preferences:TSchedulePreferences, fromVenue:String, toVenue:String)
		For Local cost:TVenueTransitionCost = EachIn preferences.venueTransitions
			If cost.fromVenueId = fromVenue And cost.toVenueId = toVenue Then
				Return cost.cost
			End If
		Next

		Return 0
	End Method

	Method Search:Int()
		nodes :+ 1
		If nodes > maxNodes Then hitLimit = True; Return False

		Local chosen:TCalendarPlanItem
		Local fewest:Int = 2147483647
		For Local item:TCalendarPlanItem = EachIn items
			If item.fixture.slotId <> "" And (item.fixture.round > 0 Or item.leagueSchedule = Null) Then
				Continue
			End If

			Local choices:Int
			For Local week:Int = FirstWeek(item) To LastWeek(item)
				For Local slot:TSlot = EachIn item.calendar.slots
					If item.fixture.slotId <> "" And item.fixture.slotId <> slot.id Then
						Continue
					End If

					If CanUse(item, slot, week) Then
						choices :+ 1
					End If
				Next
			Next

			If choices = 0 Then
				RecordFailure(item)
				Return False
			End If

			If choices < fewest Then chosen = item; fewest = choices
		Next

		If chosen = Null Then
			Return True
		End If

		If Not HasDistinctSlotCapacity() Or Not HasSharedCapacity() Then
			Return False
		End If

		Local oldRound:Int = chosen.fixture.round
		Local oldSlot:String = chosen.fixture.slotId
		Local oldVenue:String = chosen.fixture.venueId
		For Local week:Int = FirstWeek(chosen) To LastWeek(chosen)
			For Local slot:TSlot = EachIn chosen.calendar.slots
				If oldSlot <> "" And oldSlot <> slot.id Then
					Continue
				End If

				If Not CanUse(chosen, slot, week) Then
					Continue
				End If

				chosen.fixture.round = week
				chosen.fixture.slotId = slot.id
				chosen.fixture.venueId = slot.venueId
				If Search() Then
					Return True
				End If

				chosen.fixture.round = oldRound
				chosen.fixture.slotId = oldSlot
				chosen.fixture.venueId = oldVenue
				If hitLimit Then
					Return False
				End If
			Next
		Next

		Return False
	End Method

	' A necessary condition: each unplaced fixture in a stage needs a different
	' slot ID. Matching the current domains detects Hall-style capacity failures
	' before exploring branches; other venue/team rules remain in the search.
	Method HasDistinctSlotCapacity:Int()
		For Local stageIndex:Int = 0 Until comp.stages.Length
			Local calendar:TCalendar = GetSchedulePolicy(comp.stages[stageIndex]).calendar
			If calendar = Null Then
				Continue
			End If

			Local remaining:Int[]
			For Local itemIndex:Int = 0 Until items.Length
				Local item:TCalendarPlanItem = items[itemIndex]
				If item.stageIndex <> stageIndex Then
					Continue
				End If

				If item.fixture.slotId = "" Or (item.leagueSchedule <> Null And item.fixture.round = 0) Then
					remaining :+ [itemIndex]
				End If
			Next
			' The full matching check is useful for crowded small stages. Keep its
			' repeated cost bounded for long seasons; ordinary search still applies.
			If remaining.Length < 3 Or remaining.Length > 32 Or calendar.slots.Length > 64 Then
				Continue
			End If

			Local owners:Int[calendar.slots.Length]
			For Local slotIndex:Int = 0 Until owners.Length
				owners[slotIndex] = -1
			Next

			For Local itemIndex:Int = EachIn remaining
				Local seen:Int[calendar.slots.Length]
				If Not AugmentSlotMatch(itemIndex, calendar, owners, seen) Then
					Local report:TScheduleFailureReport = New TScheduleFailureReport
					report.stageId = comp.stages[stageIndex].id
					report.fixtureId = items[itemIndex].fixture.id
					report.capacityConflict = True
					For Local assigned:TCalendarPlanItem = EachIn items
						If assigned.fixture.slotId <> "" Then
							report.assignedFixtures :+ 1
						End If
					Next

					report.candidateSlots = []
					report.candidateReasons = []
					failureReport = report
					failureReason = report.Summary()
					Return False
				End If
			Next
		Next

		Return True
	End Method

	Method AugmentSlotMatch:Int(itemIndex:Int, calendar:TCalendar, owners:Int[], seen:Int[])
		Local item:TCalendarPlanItem = items[itemIndex]
		For Local slotIndex:Int = 0 Until calendar.slots.Length
			If seen[slotIndex] Then
				Continue
			End If

			Local slot:TSlot = calendar.slots[slotIndex]
			If item.fixture.slotId <> "" And item.fixture.slotId <> slot.id Then
				Continue
			End If

			Local available:Int
			For Local week:Int = FirstWeek(item) To LastWeek(item)
				If CanUse(item, slot, week) Then available = True; Exit
			Next

			If Not available Then
				Continue
			End If

			seen[slotIndex] = True
			If owners[slotIndex] = -1 Or AugmentSlotMatch(owners[slotIndex], calendar, owners, seen) Then
				owners[slotIndex] = itemIndex
				Return True
			End If
		Next

		Return False
	End Method

	' Necessary capacity bounds across stages. A league participant can play at
	' most once in each week; a physical venue can host at most once at each
	' exact date/time. These bounds use current feasible domains, so fixed games,
	' byes and blackouts have already removed unavailable choices.
	Method HasSharedCapacity:Int()
		Local remaining:Int
		Local largeCalendar:Int
		For Local item:TCalendarPlanItem = EachIn items
			If item.fixture.slotId = "" Or (item.leagueSchedule <> Null And item.fixture.round = 0) Then
				remaining :+ 1
				If item.calendar.slots.Length > 64 Then
					largeCalendar = True
				End If
			End If
		Next

		If remaining < 2 Or ((remaining > 32 Or largeCalendar) And nodes > 1) Then
			Return True
		End If

		Local domains:TCalendarCapacityDomain[]
		For Local item:TCalendarPlanItem = EachIn items
			If item.fixture.slotId <> "" And (item.leagueSchedule = Null Or item.fixture.round > 0) Then
				Continue
			End If

			Local domain:TCalendarCapacityDomain = New TCalendarCapacityDomain
			domain.item = item
			For Local week:Int = FirstWeek(item) To LastWeek(item)
				For Local slot:TSlot = EachIn item.calendar.slots
					If item.fixture.slotId <> "" And item.fixture.slotId <> slot.id Then
						Continue
					End If

					If CanUse(item, slot, week) Then
						domain.AddCandidate(week, slot)
					End If
				Next
			Next

			domains :+ [domain]
		Next

		Local checkedParticipants:String[]
		For Local domain:TCalendarCapacityDomain = EachIn domains
			If domain.item.leagueSchedule = Null Then
				Continue
			End If

			For Local participantId:Int = EachIn [domain.item.fixture.homeTeamId, domain.item.fixture.awayTeamId]
				If participantId <= 0 Then
					Continue
				End If

				Local key:String = domain.item.stageIndex + ":" + participantId
				If ContainsCapacityKey(checkedParticipants, key) Then
					Continue
				End If

				checkedParticipants :+ [key]
				Local count:Int
				Local weeks:Int[]
				For Local candidate:TCalendarCapacityDomain = EachIn domains
					If candidate.item.stageIndex <> domain.item.stageIndex Then
						Continue
					End If

					If candidate.item.fixture.homeTeamId <> participantId And candidate.item.fixture.awayTeamId <> participantId Then
						Continue
					End If

					count :+ 1
					For Local week:Int = EachIn candidate.weeks
						Local exists:Int
						For Local known:Int = EachIn weeks
							If known = week Then exists = True; Exit
						Next

						If Not exists Then
							weeks :+ [week]
						End If
					Next
				Next

				If count > weeks.Length Then
					RecordCapacityFailure(domain.item, "weeks for participant", participantId, count, weeks.Length)
					Return False
				End If
			Next
		Next

		Local checkedVenues:String[]
		For Local domain:TCalendarCapacityDomain = EachIn domains
			If domain.forcedVenue = "" Or domain.venueFlexible Then
				Continue
			End If

			If ContainsCapacityKey(checkedVenues, domain.forcedVenue) Then
				Continue
			End If

			checkedVenues :+ [domain.forcedVenue]
			Local count:Int
			Local times:String[]
			For Local candidate:TCalendarCapacityDomain = EachIn domains
				If candidate.forcedVenue <> domain.forcedVenue Or candidate.venueFlexible Then
					Continue
				End If

				count :+ 1
				For Local time:String = EachIn candidate.times
					If Not ContainsCapacityKey(times, time) Then
						times :+ [time]
					End If
				Next
			Next

			If count > times.Length Then
				RecordCapacityFailure(domain.item, "venue", domain.forcedVenue, count, times.Length)
				Return False
			End If
		Next

		Return True
	End Method

	Method ContainsCapacityKey:Int(values:String[], key:String)
		For Local value:String = EachIn values
			If value = key Then
				Return True
			End If
		Next

		Return False
	End Method

	Method RecordCapacityFailure(item:TCalendarPlanItem, kind:String, resource:String, required:Int, available:Int)
		Local report:TScheduleFailureReport = New TScheduleFailureReport
		report.stageId = item.stageId
		report.fixtureId = item.fixture.id
		report.capacityConflict = True
		report.capacityKind = kind
		report.capacityResource = resource
		report.requiredFixtures = required
		report.availableResources = available
		report.candidateSlots = []
		report.candidateReasons = []
		For Local assigned:TCalendarPlanItem = EachIn items
			If assigned.fixture.slotId <> "" Then
				report.assignedFixtures :+ 1
			End If
		Next

		failureReport = report
		failureReason = report.Summary()
	End Method

	Method FirstWeek:Int(item:TCalendarPlanItem)
		If item.fixture.round > 0 Then
			Return item.fixture.round
		End If

		If item.pinnedRound > 0 Then
			Return item.pinnedRound
		End If

		If item.leagueSchedule = Null Then
			Return 0
		End If

		Return 1
	End Method

	Method LastWeek:Int(item:TCalendarPlanItem)
		If item.fixture.round > 0 Then
			Return item.fixture.round
		End If

		If item.pinnedRound > 0 Then
			Return item.pinnedRound
		End If

		If item.leagueSchedule <> Null Then
			If item.leagueSchedule.weeks > 0 Then
				Return item.leagueSchedule.weeks
			End If

			Return Min(item.calendarMaxWeek, weekCap)
		End If

		Return 0
	End Method

	Method CanUse:Int(item:TCalendarPlanItem, slot:TSlot, week:Int)
		Return ConflictReason(item, slot, week) = ""
	End Method

	Method RecordFailure(item:TCalendarPlanItem)
		Local report:TScheduleFailureReport = New TScheduleFailureReport
		report.stageId = item.stageId
		report.fixtureId = item.fixture.id
		report.candidateSlots = []
		report.candidateReasons = []
		For Local other:TCalendarPlanItem = EachIn items
			If other <> item And other.fixture.slotId <> "" Then
				report.assignedFixtures :+ 1
			End If
		Next

		For Local week:Int = FirstWeek(item) To LastWeek(item)
			For Local slot:TSlot = EachIn item.calendar.slots
				If item.fixture.slotId <> "" And item.fixture.slotId <> slot.id Then
					Continue
				End If

				report.totalCandidates :+ 1
				If report.candidateSlots.Length < 8 Then
					report.candidateSlots :+ ["week " + week + "/" + slot.id]
					report.candidateReasons :+ [ConflictReason(item, slot, week)]
				End If
			Next
		Next

		If failureReport <> Null Then
			If report.assignedFixtures > failureReport.assignedFixtures Then
				Return
			End If

			If report.assignedFixtures = failureReport.assignedFixtures And report.totalCandidates >= failureReport.totalCandidates Then
				Return
			End If
		End If

		failureReport = report
		failureReason = report.Summary()
	End Method

	Method ConflictReason:String(item:TCalendarPlanItem, slot:TSlot, week:Int)
		Local fixture:TFixtureState = item.fixture
		If item.leagueSchedule <> Null Then
			If week < 1 Or (item.leagueSchedule.weeks > 0 And week > item.leagueSchedule.weeks) Then
				Return "week outside configured season"
			End If

			If Not weekRules.IsAvailable(item.leagueSchedule, item.stageFixtures, fixture, week) Then
				Return "week conflicts with bye, participant, or rematch gap"
			End If
		End If

		If slot.round <> 0 And slot.round <> week Then
			Return "round differs"
		End If

		For Local participant:TParticipant = EachIn comp.participants
			If participant.id = fixture.homeTeamId And participant.homeVenueId <> "" And participant.homeVenueId <> slot.venueId Then
				Return "home venue differs"
			End If
		Next

		If rules.IsBlackout(item.calendar, fixture.homeTeamId, slot.id) Or rules.IsBlackout(item.calendar, fixture.awayTeamId, slot.id) Then
			Return "participant blackout"
		End If

		For Local other:TCalendarPlanItem = EachIn items
			If other = item Or other.fixture.slotId = "" Then
				Continue
			End If

			If other.stageIndex = item.stageIndex And other.fixture.slotId = slot.id Then
				Return "already used by " + other.stageId + "/" + other.fixture.id
			End If

			Local used:TSlot = rules.FindSlot(other.calendar, other.fixture.slotId)
			If used = Null Then
				Throw "Unknown assigned calendar slot for " + other.stageId + "/" + other.fixture.id
			End If

			If rules.Overlaps(slot.dateTime, slot.venueId, fixture.homeTeamId, fixture.awayTeamId, used.dateTime, used.venueId, other.fixture.homeTeamId, other.fixture.awayTeamId) Then
				If slot.venueId <> "" And slot.venueId = used.venueId Then
					Return "shared venue occupied by " + other.stageId + "/" + other.fixture.id
				End If

				Return "participant occupied by " + other.stageId + "/" + other.fixture.id
			End If
		Next

		Return ""
	End Method
End Type
