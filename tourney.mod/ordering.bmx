Rem
bbdoc: Places entrants by ranking, pots, random draw, and draw constraints.
End Rem
Type TEntrantsOrderer

	Method ShuffleIds(ids:Int[])
		For Local i:Int = ids.Length - 1 To 1 Step -1
			Local j:Int = Rand(0, i)
			Local t:Int = ids[i]
			ids[i] = ids[j]
			ids[j] = t
		Next
	End Method

	Rem
	bbdoc: Orders entrants according to the stage's seeding and draw policy.
	param: Competition definition containing the entrants.
	param: Stage with its entry source and seeding policy.
	returns: Participant IDs in draw order.
	End Rem
	Method OrderEntrantsByPolicy:Int[](comp:TCompetition, stage:TStage)
		Local ids:Int[]
		For Local p:TParticipant = EachIn comp.participants
			ids :+ [p.id]
		Next

		Local pol:TSeedingPolicy = stage.input.seeding
		Local _method:ESeedingMethod
		If pol <> Null Then
			_method = pol.seedingMethod
		Else
			_method = ESeedingMethod.Random
		End If

		Select _method
			Case ESeedingMethod.Random
				ShuffleIds(ids)

			Case ESeedingMethod.Ranking
				' Rank explicitly when available, retaining the legacy ID fallback.
				For Local i:Int = 0 Until ids.Length - 1
					For Local j:Int = i + 1 Until ids.Length
						Local ri:Int = GetRank(comp, ids[i])
						Local rj:Int = GetRank(comp, ids[j])
						If rj < ri Then
							Local t:Int = ids[i]
							ids[i] = ids[j]
							ids[j] = t
						End If
					Next
				Next

				If pol <> Null And pol.seedBands <> Null And pol.seedBands.Length > 0 Then
					ShuffleRankBands(ids, pol.seedBands)
				End If

			Case ESeedingMethod.ProtectedTopN
				Local topN:Int
				If pol <> Null Then
					topN = pol.protectedTopN
				End If
				' sort by rank…
				For Local i:Int = 0 Until ids.Length - 1
					For Local j:Int = i + 1 Until ids.Length
						Local ri:Int = GetRank(comp, ids[i])
						Local rj:Int = GetRank(comp, ids[j])
						If rj < ri Then
							Local t:Int = ids[i]
							ids[i] = ids[j]
							ids[j] = t
						End If
					Next
				Next
				' then shuffle the rest
				Local cut:Int = Min(topN, ids.Length)
				Local rest:Int[] = ids[cut..]
				ShuffleIds(rest)
				ids = ids[0..cut] + rest

			Case ESeedingMethod.Pots
				' ' interleave by participant.meta["pot"] matching pol.pots[]
				' ids = InterleaveByPots(comp, pol)

				' Retrieve group count from current stage (if present)
				Local groupCount:Int = 1
				If stage.config <> Null Then
					Local gcfg:TGroupConfig = TGroupConfig(stage.config)
					If gcfg <> Null And gcfg.groups > 0 Then
						groupCount = gcfg.groups
					End If
				End If

				ids = OrderByPots(comp, pol, groupCount)
			Default
				ShuffleIds(ids)
		End Select

		Return ids
	End Method

	Method ShuffleRankBands(ids:Int[], bands:Int[])
		Local start:Int = 0
		For Local count:Int = EachIn bands
			If count < 1 Or start + count > ids.Length Then
				Throw "Seed bands exceed the entrant count"
			End If

			For Local i:Int = start + count - 1 To start + 1 Step -1
				Local j:Int = Rand(start, i)
				Local tmp:Int = ids[i]
				ids[i] = ids[j]
				ids[j] = tmp
			Next

			start :+ count
		Next
		' Entries after the last named band form an unrestricted final band.
		For Local i:Int = ids.Length - 1 To start + 1 Step -1
			Local j:Int = Rand(start, i)
			Local tmp:Int = ids[i]
			ids[i] = ids[j]
			ids[j] = tmp
		Next
	End Method

	Method GetRank:Int(comp:TCompetition, pid:Int)
		' An explicit rank keeps seeding independent of participant ID and order.
		' Positive IDs remain the fallback for older ranking-based definitions.
		For Local p:TParticipant = EachIn comp.participants
			If p.id = pid Then
				If p.seedRank > 0 Then
					Return p.seedRank
				End If

				If p.id > 0 Then
					Return p.id
				End If
			End If
		Next

		Return 999999
	End Method

	Method OrderByPots:Int[](comp:TCompetition, pol:TSeedingPolicy, groupCount:Int)
		' 1) Build buckets by pot name (as defined in policy.pots)
		Local buckets:Int[][]
		buckets = buckets[..pol.pots.Length]

		For Local p:TParticipant = EachIn comp.participants
			' If participants explicitly declare their pot, use that; otherwise, distribute sequentially.
			' We'll look for p.divisionId or p.region == potName as a more typed alternative to meta.
			Local potName:String = ""
			If p.drawPot <> "" Then
				potName = p.drawPot
			ElseIf p.divisionId <> "" Then
				potName = p.divisionId
			ElseIf p.region <> "" Then
				potName = p.region
			ElseIf p.meta <> Null Then
				Local m:TMap = TMap(p.meta)
				If m <> Null And m.Contains("pot") Then
					potName = String(m.ValueForKey("pot"))
				End If
			End If

			Local idx:Int = IndexOfString(pol.pots, potName)
			If idx >= 0 Then
				buckets[idx] :+ [p.id]
			End If
		Next

		' 2) Shuffle within each pot (optional randomness)
		For Local i:Int = 0 Until buckets.Length
			ShuffleIds(buckets[i])
		Next

		' 3) Sanity check: every pot should have enough participants to cover all groups
		For Local i:Int = 0 Until buckets.Length
			If buckets[i].Length < groupCount Then
				Throw "Pot '" + pol.pots[i] + "' has only " + buckets[i].Length + " participants; need " + groupCount
			End If
		Next

		' 4) Output as pot blocks: all from pot1, then all from pot2, etc.
		Local out:Int[]
		For Local i:Int = 0 Until buckets.Length
			out :+ buckets[i][0..groupCount] ' take only enough for 1 per group if extras exist
		Next

		' 5) Append any participants not in pots (extras, wildcards)
		For Local p:TParticipant = EachIn comp.participants
			If Not Contains(out, p.id) Then
				out :+ [p.id]
			End If
		Next

		Return out
	End Method

	Method IndexOfString:Int(arr:String[], s:String)
		For Local i:Int = 0 Until arr.Length
			If arr[i] = s Then
				Return i
			End If
		Next

		Return -1
	End Method

	Function Contains:Int(a:Int[], v:Int)
		For Local x:Int = EachIn a
			If x = v Then
				Return True
			End If
		Next

		Return False
	End Function

End Type

' Constraint search for one stage, with reservations from every previously
' scheduled stage. Hard constraints are checked before any slot is committed.
Rem
bbdoc: Assigns stage fixtures to candidate calendar slots.
End Rem
Type TCalendarSlotAllocator Implements IFixtureSlotAllocator, ICompetitionSlotAllocator
	Rem
	bbdoc: Nodes for this calendar slot allocator.
	End Rem
	Field nodes:Int
	Rem
	bbdoc: Hit limit for this calendar slot allocator.
	End Rem
	Field hitLimit:Int

	Method Assign(comp:TCompetition, stage:TStage, fixtures:TFixtureState[])
		AssignWithReservations(comp, stage, fixtures, Null)
	End Method

	Method AssignWithReservations(comp:TCompetition, stage:TStage, fixtures:TFixtureState[], reservations:TSlotReservation[])
		Local calendar:TCalendar = GetSchedulePolicy(stage).calendar
		If calendar = Null Or calendar.slots = Null Or calendar.slots.Length = 0 Then
			Throw "Calendar has no slots"
		End If

		For Local i:Int = 0 Until calendar.slots.Length
			If calendar.slots[i].id = "" Then
				Throw "Calendar slot needs an id"
			End If

			For Local j:Int = i + 1 Until calendar.slots.Length
				If calendar.slots[i].id = calendar.slots[j].id Then
					Throw "Duplicate calendar slot id: " + calendar.slots[i].id
				End If
			Next
		Next

		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.status = EFixtureStatus.Cancelled Or fixture.slotId = "" Then
				Continue
			End If

			Local slot:TSlot = FindSlot(calendar, fixture.slotId)
			If slot = Null Then
				Throw "Unknown preassigned calendar slot: " + fixture.slotId
			End If

			If fixture.venueId <> "" And fixture.venueId <> slot.venueId Then
				Throw "Preassigned fixture venue differs from its slot"
			End If

			If Not CanUse(comp, calendar, fixtures, fixture, slot, reservations) Then
				Throw "Preassigned calendar slot conflicts for fixture: " + fixture.id
			End If

			fixture.venueId = slot.venueId
		Next

		nodes = 0
		hitLimit = False
		If Not AssignRemaining(comp, calendar, fixtures, reservations) Then
			If hitLimit Then
				Throw "Calendar search limit reached"
			End If

			Throw "No feasible calendar assignment for stage: " + stage.id
		End If
	End Method

	Method AssignRemaining:Int(comp:TCompetition, calendar:TCalendar, fixtures:TFixtureState[], reservations:TSlotReservation[])
		nodes :+ 1
		Local limit:Int = calendar.maxSearchNodes
		If limit <= 0 Then
			limit = 100000
		End If

		If nodes > limit Then hitLimit = True; Return False

		Local chosen:TFixtureState = Null
		Local fewest:Int = 2147483647
		For Local fixture:TFixtureState = EachIn fixtures
			If fixture.status = EFixtureStatus.Cancelled Or fixture.awayTeamId = 0 Or fixture.slotId <> "" Then
				Continue
			End If

			Local choices:Int
			For Local slot:TSlot = EachIn calendar.slots
				If CanUse(comp, calendar, fixtures, fixture, slot, reservations) Then
					choices :+ 1
				End If
			Next

			If choices = 0 Then
				Return False
			End If

			If choices < fewest Then chosen = fixture; fewest = choices
		Next

		If chosen = Null Then
			Return True
		End If

		For Local slot:TSlot = EachIn calendar.slots
			If Not CanUse(comp, calendar, fixtures, chosen, slot, reservations) Then
				Continue
			End If

			chosen.slotId = slot.id
			chosen.venueId = slot.venueId
			If AssignRemaining(comp, calendar, fixtures, reservations) Then
				Return True
			End If

			chosen.slotId = ""
			chosen.venueId = ""
			If hitLimit Then
				Return False
			End If
		Next

		Return False
	End Method

	Method FindSlot:TSlot(calendar:TCalendar, id:String)
		For Local slot:TSlot = EachIn calendar.slots
			If slot.id = id Then
				Return slot
			End If
		Next

		Return Null
	End Method

	Method CanUse:Int(comp:TCompetition, calendar:TCalendar, fixtures:TFixtureState[], fixture:TFixtureState, slot:TSlot, reservations:TSlotReservation[])
		If slot.round <> 0 And slot.round <> fixture.round Then
			Return False
		End If

		For Local p:TParticipant = EachIn comp.participants
			If p.id = fixture.homeTeamId And p.homeVenueId <> "" And slot.venueId <> p.homeVenueId Then
				Return False
			End If
		Next

		If IsBlackout(calendar, fixture.homeTeamId, slot.id) Or IsBlackout(calendar, fixture.awayTeamId, slot.id) Then
			Return False
		End If

		For Local other:TFixtureState = EachIn fixtures
			If other = fixture Or other.slotId = "" Or other.status = EFixtureStatus.Cancelled Then
				Continue
			End If

			If other.slotId = slot.id Then
				Return False
			End If

			Local used:TSlot = FindSlot(calendar, other.slotId)
			If used = Null Then
				Throw "Unknown assigned calendar slot: " + other.slotId
			End If

			If Overlaps(slot.dateTime, slot.venueId, fixture.homeTeamId, fixture.awayTeamId, used.dateTime, used.venueId, other.homeTeamId, other.awayTeamId) Then
				Return False
			End If
		Next

		For Local other:TSlotReservation = EachIn reservations
			If Overlaps(slot.dateTime, slot.venueId, fixture.homeTeamId, fixture.awayTeamId, other.dateTime, other.venueId, other.homeTeamId, other.awayTeamId) Then
				Return False
			End If
		Next

		Return True
	End Method

	Method Overlaps:Int(timeA:String, venueA:String, homeA:Int, awayA:Int, timeB:String, venueB:String, homeB:Int, awayB:Int)
		If timeA = "" Or timeA <> timeB Then
			Return False
		End If

		If venueA <> "" And venueA = venueB Then
			Return True
		End If

		If homeA > 0 And (homeA = homeB Or homeA = awayB) Then
			Return True
		End If

		If awayA > 0 And (awayA = homeB Or awayA = awayB) Then
			Return True
		End If

		Return False
	End Method

	Method IsBlackout:Int(calendar:TCalendar, participantId:Int, slotId:String)
		For Local b:TTeamBlackout = EachIn calendar.blackouts
			If b.teamId = participantId And b.slotId = slotId Then
				Return True
			End If
		Next

		Return False
	End Method
End Type

Function GetSchedulePolicy:TSchedulePolicy(stage:TStage)
	If stage.schedule <> Null Then
		Return stage.schedule
	End If

	Local policy:TSchedulePolicy = Null
	Select stage.stageType
		Case EStageType.Group
			Local c:TGroupConfig = TGroupConfig(stage.config)
			If c <> Null Then
				policy = c.policy
			End If
		Case EStageType.League
			Local c:TLeagueConfig = TLeagueConfig(stage.config)
			If c <> Null Then
				policy = c.policy
			End If
		Case EStageType.Bracket
			Local c:TBracketConfig = TBracketConfig(stage.config)
			If c <> Null Then
				policy = c.policy
			End If
		Case EStageType.Series
		' Series typically neutral per session; leave Null okay
	End Select

	If policy = Null Then
		policy = New TSchedulePolicy
		policy.venuePolicy = New TVenuePolicy
	End If

	Return policy
End Function

Function EnsureStageInputDefaults(stage:TStage)
	If stage.input = Null Then
		stage.input = New TEntrySource
	End If

	If stage.input.seeding = Null Then
		stage.input.seeding = New TSeedingPolicy
		stage.input.seeding.seedingMethod = ESeedingMethod.Random
	End If

	If stage.input.constraints = Null Then
		stage.input.constraints = New TDrawConstraints
		' All fields default to 0 / empty arrays; avoidPairs can stay Null or [].
	End If
End Function

' -------- GROUP SCHEDULER --------
