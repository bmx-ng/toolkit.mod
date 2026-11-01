' Copyright (c) 2026 Bruce A Henderson
'
' This software is provided 'as-is', without any express or implied warranty.
' In no event will the authors be held liable for any damages arising from
' the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the following restrictions:
'
' 1. The origin of this software must not be misrepresented; you must not
'    claim that you wrote the original software. If you use this software
'    in a product, an acknowledgment in the product documentation would be
'    appreciated but is not required.
' 2. Altered source versions must be plainly marked as such, and must not be
'    misrepresented as being the original software.
' 3. This notice may not be removed or altered from any source distribution.
'
SuperStrict

' ---------- Core ----------
Rem
bbdoc: Serializable definition of participants, stages, and season transitions.
about: Keep this definition alongside its #TCompetitionState when saving play. Participant and stage IDs are stable references in fixtures, results, and the correction journal.
End Rem
Type TCompetition
	Rem
	bbdoc: Name of the competition.
	End Rem
	Field name:String
	Rem
	bbdoc: Participants available to the competition stages.
	End Rem
	Field participants:TParticipant[]
	Rem
	bbdoc: Stages in their declared order.
	End Rem
	Field stages:TStage[]          ' ordered pipeline
	Rem
	bbdoc: Rules for promotion and relegation after the season.
	End Rem
	Field seasonTransitions:TSeasonTransitionRule[]
	Rem
	bbdoc: Appends a stage to the definition.
	param: Stage with a stable, unique ID.
	End Rem
	Method AddStage(stage:TStage)
		stages :+ [stage]
	End Method
End Type

Rem
bbdoc: An entrant, team, or individual identified by a stable integer ID.
End Rem
Type TParticipant
	Rem
	bbdoc: Stable participant ID used throughout definitions and playing state.
	End Rem
	Field id:Int
	Rem
	bbdoc: Display name of the participant.
	End Rem
	Field name:String
	Rem
	bbdoc: Region, association, or country used by draw rules.
	End Rem
	Field region:String            ' conf/assoc/country if useful
	Rem
	bbdoc: Division ID used by league scheduling.
	about: This field is optional: (NFL-style).
	End Rem
	Field divisionId:String        ' optional (NFL-style)
	Rem
	bbdoc: Venue ID used when the participant hosts.
	about: Teams can share the same venue.
	End Rem
	Field homeVenueId:String        ' teams can share the same venue
	Rem
	bbdoc: Previous division rank used by rotating schedules.
	about: This field is optional: rank within division for rotating schedules.
	End Rem
	Field previousRank:Int          ' optional rank within division for rotating schedules
	Rem
	bbdoc: Seed rank, with one highest and zero meaning unranked.
	End Rem
	Field seedRank:Int
	Rem
	bbdoc: Pot label used by pot-based draws.
	about: Independent of region and division.
	End Rem
	Field drawPot:String            ' independent of region and division
	Rem
	bbdoc: Optional application-specific data.
	End Rem
	Field meta:Object
	Rem
	bbdoc: Parent team ID for an individual, or zero when there is none.
	End Rem
	Field parentTeamId:Int
	Rem
	bbdoc: Whether the participant is a team or an individual.
	End Rem
	Field kind:EParticipantKind
End Type

Rem
bbdoc: Whether a participant represents a team or an individual.
End Rem
Enum EParticipantKind
    Team
    Individual
End Enum

Rem
bbdoc: One format and its entry, scheduling, scoring, and advancement rules.
about: A stage may start independently or wait for entrants from preceding stages. Use #TStage.formatCode with a registered custom format when the built-in stage types do not fit.
End Rem
Type TStage
	Rem
	bbdoc: Stable stage ID used by dependencies, routes, and result calls.
	End Rem
	Field id:String
	Rem
	bbdoc: Built-in format selected for this stage.
	End Rem
	Field stageType:EStageType
	Rem
	bbdoc: Registered custom format code, or empty for a built-in stage type.
	End Rem
	Field formatCode:String
	Rem
	bbdoc: Whether this stage starts alongside other root stages.
	End Rem
	Field independent:Int { asBool } ' start alongside other root stages
	Rem
	bbdoc: Rules for obtaining and drawing this stage's entrants.
	End Rem
	Field input:TEntrySource
	Rem
	bbdoc: Configuration interpreted by the stage format.
	End Rem
	Field config:TConfig           ' one of the configs below
	Rem
	bbdoc: Optional scheduling policy shared by all stage formats.
	End Rem
	Field schedule:TSchedulePolicy
	Rem
	bbdoc: Routes that deliver entrants to downstream stages.
	End Rem
	Field advancement:TAdvancement[]
	Rem
	bbdoc: Condition under which this dependent stage starts.
	End Rem
	Field activation:TStageActivation
End Type

Rem
bbdoc: Condition controlling whether a dependent stage starts.
End Rem
Type TStageActivation
	Rem
	bbdoc: Kind of this stage activation.
	End Rem
	Field kind:EStageActivationKind
	Rem
	bbdoc: ID of the reference source associated with this stage activation.
	about: Source whose entrant must lose in the immediate predecessor.
	End Rem
	Field referenceSourceId:String ' source whose entrant must lose in the immediate predecessor
End Type

Rem
bbdoc: Conditions for starting a stage after its dependencies finish.
End Rem
Enum EStageActivationKind
	Always
	IfReferenceEntrantLoses
End Enum

Rem
bbdoc: Built-in stage formats supported by the engine.
End Rem
Enum EStageType
    Group
    League
    Bracket
    Swiss
    Qualifying
    PlayIn
	Series
End Enum

' ---------- Entry / advancement ----------
Rem
bbdoc: Describes how a stage receives and draws its entrants.
about: `fromStageIds` records every source required by a merging stage. A postseason pool can instead derive seeded entrants from a completed league.
End Rem
Type TEntrySource
	Rem
	bbdoc: Way this stage obtains its entrants.
	End Rem
	Field mode:EEntryMode          ' Direct, FromStage, SeededDraw
	Rem
	bbdoc: ID of the source stage.
	End Rem
	Field fromStageId:String
	Rem
	bbdoc: All source stage IDs that must finish before a merging stage starts.
	End Rem
	Field fromStageIds:String[]
	Rem
	bbdoc: Policy for ordering or drawing entrants.
	End Rem
	Field seeding:TSeedingPolicy
	Rem
	bbdoc: Restrictions on seeded or random draws.
	End Rem
	Field constraints:TDrawConstraints
	Rem
	bbdoc: Rules selecting entrants from the source standings.
	about: For example, TopN per group, BestXAcrossGroups.
	End Rem
	Field filter:TFilterRule[]     ' e.g. TopN per group, BestXAcrossGroups
	Rem
	bbdoc: League postseason pool whose completed standings supply seeded entrants.
	End Rem
	Field postseasonPoolCode:String
End Type

Rem
bbdoc: Ways a stage obtains its entrants.
End Rem
Enum EEntryMode
	Direct
	FromStage
	SeededDraw
End Enum

Rem
bbdoc: A route carrying selected entrants or bracket outcomes to another stage.
about: A route can use a single `rule` or ordered `rules`, and may include a mapping that fixes destination positions without naming future qualifiers.
End Rem
Type TAdvancement
	Rem
	bbdoc: ID of the destination stage.
	End Rem
	Field toStageId:String
	Rem
	bbdoc: Named series championship used for selection, or empty for the main table.
	End Rem
	Field championshipCode:String
	Rem
	bbdoc: Single selection rule used when #rules is empty.
	End Rem
	Field rule:TFilterRule
	Rem
	bbdoc: Ordered selection rules for one destination; takes precedence over #rule.
	End Rem
	Field rules:TFilterRule[]
	Rem
	bbdoc: Bracket outcome or selected entrants delivered by this route.
	about: Selected preserves the configured filter rules; the other values route a bracket outcome or all entrants.
	End Rem
	Field outcome:EAdvancementOutcome ' bracket winner, loser, or all entrants; Selected preserves existing filters
	Rem
	bbdoc: Placement of routed entrants in the destination stage.
	End Rem
	Field mapping:TAdvancementMapping
End Type

Rem
bbdoc: Which entrants a completed stage sends along a route.
End Rem
Enum EAdvancementOutcome
	Rem
	bbdoc: Send entrants chosen by the route's filter rules.
	End Rem
	Selected
	Rem
	bbdoc: Send the winning side of a bracket contest.
	End Rem
	Winner
	Rem
	bbdoc: Send the losing side of a bracket contest.
	End Rem
	Loser
	Rem
	bbdoc: Send every entrant from the completed stage.
	End Rem
	AllEntrants
End Enum

Rem
bbdoc: Places routed entrants into destination draw slots or partitions.
about: Conditional slots select an assignment table from the groups that supplied the qualifying entrants; they do not name those entrants in advance.
End Rem
Type TAdvancementMapping
	Rem
	bbdoc: Mode used by this advancement mapping.
	End Rem
	Field mode:EAdvMappingMode         ' FixedSlots | Seeded | Partition
	Rem
	bbdoc: One-based destination draw positions aligned with selected entrants.
	End Rem
	Field toSlots:String[]
	Rem
	bbdoc: Partition key of this advancement mapping.
	about: "left" or "right" half of the destination draw.
	End Rem
	Field partitionKey:String          ' "left" or "right" half of the destination draw
	Rem
	bbdoc: Source-group rank whose qualifiers select a conditional slot case.
	End Rem
	Field qualifyingRank:Int
	Rem
	bbdoc: Slot assignments used in every conditional placement case.
	about: Assignments shared by every conditional case.
	End Rem
	Field baseAssignments:TGroupRankSlot[] ' assignments shared by every conditional case
	Rem
	bbdoc: #TConditionalSlotCase entries associated with this advancement mapping.
	End Rem
	Field conditionalCases:TConditionalSlotCase[]
End Type

' One possible combination of groups supplying a qualifier at qualifyingRank.
Rem
bbdoc: Slot assignments for one qualifying combination of source groups.
End Rem
Type TConditionalSlotCase
	Rem
	bbdoc: Qualifying group keys values associated with this conditional slot case.
	End Rem
	Field qualifyingGroupKeys:String[]
	Rem
	bbdoc: #TGroupRankSlot entries associated with this conditional slot case.
	End Rem
	Field assignments:TGroupRankSlot[]
End Type

' Identify a bracket entrant by its final rank within a source group.
Rem
bbdoc: Maps an entrant's source group and rank to a destination slot.
End Rem
Type TGroupRankSlot
	Rem
	bbdoc: Key identifying the associated group.
	End Rem
	Field groupKey:String
	Rem
	bbdoc: Rank for this group rank slot.
	End Rem
	Field rank:Int
	Rem
	bbdoc: ID of the associated calendar or draw slot.
	End Rem
	Field slotId:String
End Type

Rem
bbdoc: Ways to place entrants delivered by an advancement route.
End Rem
Enum EAdvMappingMode
	Rem
	bbdoc: Put selected entrants into specified one-based draw positions.
	End Rem
    FixedSlots     ' place selected entrants into numeric draw positions
	Rem
	bbdoc: Let the destination stage seed or reseed the entrants.
	End Rem
    Seeded         ' let the next stage reseed by seeding policy
	Rem
	bbdoc: Route entrants into one half of the destination bracket.
	End Rem
    Partition      ' route into the left or right half by partitionKey
	Rem
	bbdoc: Choose positions from a qualifying group combination.
	End Rem
    ConditionalSlots ' select group/rank slot assignments from a qualifying group combination
End Enum

Rem
bbdoc: Selects entrants by rank, group, division, or bracket outcome.
End Rem
Type TFilterRule
	Rem
	bbdoc: Kind of this filter rule.
	End Rem
	Field kind:EFilterKind
	Rem
	bbdoc: N for this filter rule.
	about: Top N / Best X / etc.
	End Rem
	Field n:Int                    ' Top N / Best X / etc.
	Rem
	bbdoc: Start rank for this filter rule.
	about: 1-based; e.g. ranks 3–6 with n=4.
	End Rem
	Field startRank:Int            ' 1-based; e.g. ranks 3–6 with n=4
	Rem
	bbdoc: Scope selected for this filter rule.
	End Rem
	Field scope:EFilterScope
End Type

Rem
bbdoc: Selection operations available to entry and advancement rules.
End Rem
Enum EFilterKind
	TopN
	BestXAcrossGroups
	ByRank
	All
	BottomN
	Winner
End Enum

' Applied after all referenced stages finish. Rules describe membership in
' the next season; no participant or competition is mutated by evaluation.
Rem
bbdoc: Selects standings positions for a division in the next season.
End Rem
Type TSeasonTransitionRule
	Rem
	bbdoc: ID of the source stage.
	End Rem
	Field fromStageId:String
	Rem
	bbdoc: Code identifying the associated championship.
	about: Series board used for this movement; empty is the main table.
	End Rem
	Field championshipCode:String ' series board used for this movement; empty is the main table
	Rem
	bbdoc: ID of the destination division associated with this season transition rule.
	End Rem
	Field destinationDivisionId:String
	Rem
	bbdoc: #TFilterRule value used by this season transition rule.
	End Rem
	Field selection:TFilterRule
End Type

Rem
bbdoc: A projected participant move between divisions after a season.
End Rem
Type TSeasonMovement
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: ID of the from division associated with this season movement.
	End Rem
	Field fromDivisionId:String
	Rem
	bbdoc: ID of the to division associated with this season movement.
	End Rem
	Field toDivisionId:String
	Rem
	bbdoc: ID of the source stage.
	End Rem
	Field sourceStageId:String
End Type

Rem
bbdoc: The table scope used when applying a selection rule.
End Rem
Enum EFilterScope
    PerGroup
    All
    PerDivision
End Enum

' ---------- Seeding / Draw ----------
Rem
bbdoc: Controls ranked, pot-based, protected, or random entrant placement.
End Rem
Type TSeedingPolicy
	Rem
	bbdoc: Seeding method selected for this seeding policy.
	End Rem
	Field seedingMethod:ESeedingMethod
	Rem
	bbdoc: Ranking source of this seeding policy.
	End Rem
	Field rankingSource:String
	Rem
	bbdoc: Completed standings stage used to rank entrants merged from several sources.
	End Rem
	Field rankingStageId:String
	Rem
	bbdoc: Protected top n for this seeding policy.
	End Rem
	Field protectedTopN:Int
	Rem
	bbdoc: Pots values associated with this seeding policy.
	about: This field is optional: labels or IDs.
	End Rem
	Field pots:String[]            ' optional: labels or IDs
	Rem
	bbdoc: Consecutive ranked band sizes within which a ranking draw may randomize.
	End Rem
	Field seedBands:Int[]
End Type

Rem
bbdoc: Methods for ordering or drawing entrants into a stage.
End Rem
Enum ESeedingMethod
	Ranking
	Pots
	Random
	ProtectedTopN
End Enum

Rem
bbdoc: Restrictions and locked positions for a seeded or random draw.
End Rem
Type TDrawConstraints
	Rem
	bbdoc: Whether disallow same group applies to this draw constraints.
	End Rem
	Field disallowSameGroup:Int { asBool }
	Rem
	bbdoc: Whether disallow same region applies to this draw constraints.
	End Rem
	Field disallowSameRegion:Int { asBool }
	Rem
	bbdoc: Max from region for this draw constraints.
	End Rem
	Field maxFromRegion:Int
	Rem
	bbdoc: Maximum entrants from one pot in a group; zero disables this limit.
	End Rem
	Field maxFromPot:Int
	Rem
	bbdoc: Avoid pairs values associated with this draw constraints.
	about: Team-id pairs to avoid.
	End Rem
	Field avoidPairs:Int[][]       ' team-id pairs to avoid
	Rem
	bbdoc: #TPresetSlot entries associated with this draw constraints.
	End Rem
	Field lockedSlots:TPresetSlot[]
	Rem
	bbdoc: #TAvoidRule entries associated with this draw constraints.
	End Rem
	Field avoidUntilRound:TAvoidRule[]
End Type

Rem
bbdoc: A fixed participant-to-slot placement in a draw.
End Rem
Type TPresetSlot
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: ID of the associated calendar or draw slot.
	about: For example, "A1" or "Group1_Pos1".
	End Rem
	Field slotId:String     ' e.g. "A1" or "Group1_Pos1"
End Type

Rem
bbdoc: A participant pair that must remain apart until a specified bracket round.
End Rem
Type TAvoidRule
	Rem
	bbdoc: Pair values associated with this avoid rule.
	about: [teamAId, teamBId] or use tags/regions instead.
	End Rem
	Field pair:Int[]        ' [teamAId, teamBId] or use tags/regions instead
	Rem
	bbdoc: Min round of this avoid rule.
	about: "QF", "SF", "Final" (or numeric round index).
	End Rem
	Field minRound:String   ' "QF", "SF", "Final" (or numeric round index)
End Type

' ---------- Scheduling ----------
Rem
bbdoc: Common venue, calendar, and preference settings for a stage.
End Rem
Type TSchedulePolicy
	Rem
	bbdoc: Rules for assigning home, away, and neutral venues.
	End Rem
	Field venuePolicy:TVenuePolicy
	Rem
	bbdoc: Order in which group fixtures are scheduled.
	about: Alternating/RoundRobin.
	End Rem
	Field groupOrder:EGroupScheduleType ' Alternating/RoundRobin
	Rem
	bbdoc: Maximum consecutive home fixtures allowed.
	End Rem
	Field maxConsecHome:Int
	Rem
	bbdoc: Maximum consecutive away fixtures allowed.
	End Rem
	Field maxConsecAway:Int
	Rem
	bbdoc: Whether home and away runs should be balanced at season ends.
	End Rem
	Field preferBalancedEnds:Int { asBool }
	Rem
	bbdoc: Candidate slots and blackout rules for the stage.
	End Rem
	Field calendar:TCalendar
	Rem
	bbdoc: Soft costs used to rank valid schedules.
	End Rem
	Field preferences:TSchedulePreferences
	Rem
	bbdoc: Seed used to make randomized scheduling reproducible.
	End Rem
	Field scheduleSeed:Int
End Type

' Optional soft costs for a stage. Zero weights disable each preference.
Rem
bbdoc: Soft costs used to rank otherwise feasible schedules.
End Rem
Type TSchedulePreferences
	Rem
	bbdoc: Preferred number of idle weeks between a participant's games.
	End Rem
	Field minRestWeeks:Int
	Rem
	bbdoc: Penalty for each missing idle week between games.
	about: Cost per missing idle week.
	End Rem
	Field restShortfallWeight:Int      ' cost per missing idle week
	Rem
	bbdoc: Preferred maximum run of home games; zero disables the preference.
	about: Zero disables the home-streak preference.
	End Rem
	Field maxHomeStreak:Int           ' 0 disables the home-streak preference
	Rem
	bbdoc: Preferred maximum run of away games; zero disables the preference.
	about: Zero disables the away-streak preference.
	End Rem
	Field maxAwayStreak:Int           ' 0 disables the away-streak preference
	Rem
	bbdoc: Penalty for each game beyond a preferred home or away streak.
	about: Cost per game beyond either limit.
	End Rem
	Field streakExcessWeight:Int      ' cost per game beyond either limit
	Rem
	bbdoc: Multiplier applied to listed venue travel costs.
	about: Multiplier for listed travel costs.
	End Rem
	Field venueTransitionWeight:Int   ' multiplier for listed travel costs
	Rem
	bbdoc: #TVenueTransitionCost entries associated with this schedule preferences.
	End Rem
	Field venueTransitions:TVenueTransitionCost[]
End Type

Rem
bbdoc: Directional cost of moving between two venues.
End Rem
Type TVenueTransitionCost
	Rem
	bbdoc: ID of the from venue associated with this venue transition cost.
	End Rem
	Field fromVenueId:String
	Rem
	bbdoc: ID of the to venue associated with this venue transition cost.
	End Rem
	Field toVenueId:String
	Rem
	bbdoc: Cost for this venue transition cost.
	about: Directional; list both directions if needed.
	End Rem
	Field cost:Int                    ' directional; list both directions if needed
End Type

Rem
bbdoc: Candidate fixture slots, team blackouts, and a planning search limit.
about: The planner compares exact slot time strings and venue IDs. A search limit can stop planning without proving the calendar impossible.
End Rem
Type TCalendar
	Rem
	bbdoc: Candidate date, time, and venue slots for fixtures.
	End Rem
	Field slots:TSlot[]             ' candidate date/time/venue slots
	Rem
	bbdoc: Slots in which specified teams cannot host.
	about: Team cannot host at time X.
	End Rem
	Field blackouts:TTeamBlackout[] ' team cannot host at time X
	Rem
	bbdoc: Calendar search bound; zero uses the planner's default bound.
	End Rem
	Field maxSearchNodes:Int = 100000
End Type

Rem
bbdoc: A candidate date, time, venue, and optional round for a fixture.
End Rem
Type TSlot
	Rem
	bbdoc: Stable identifier of this slot.
	End Rem
	Field id:String
	Rem
	bbdoc: Slot time as an ISO 8601 string.
	End Rem
	Field dateTime:String
	Rem
	bbdoc: ID of the associated venue.
	End Rem
	Field venueId:String
	Rem
	bbdoc: Required fixture round, or zero to allow any round.
	End Rem
	Field round:Int
End Type

' A scheduled fixture from another stage, resolved against that stage's slot.
Rem
bbdoc: An assignment from another stage that occupies a calendar resource.
End Rem
Type TSlotReservation
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Date time of this slot reservation.
	End Rem
	Field dateTime:String
	Rem
	bbdoc: ID of the associated venue.
	End Rem
	Field venueId:String
	Rem
	bbdoc: ID of the home team associated with this slot reservation.
	End Rem
	Field homeTeamId:Int
	Rem
	bbdoc: ID of the away team associated with this slot reservation.
	End Rem
	Field awayTeamId:Int
End Type

Rem
bbdoc: A slot in which a participant cannot host a game.
End Rem
Type TTeamBlackout
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: ID of the associated calendar or draw slot.
	End Rem
	Field slotId:String
End Type

Rem
bbdoc: Ordering styles for round-robin group fixtures.
End Rem
Enum EGroupScheduleType
	Alternating
	RoundRobin
End Enum

Rem
bbdoc: Home, away, neutral, and series venue rules.
End Rem
Type TVenuePolicy
	Rem
	bbdoc: Venue type selected for this venue policy.
	End Rem
	Field venueType:EVenue
	Rem
	bbdoc: Whether higher seed hosts applies to this venue policy.
	about: For brackets.
	End Rem
	Field higherSeedHosts:Int { asBool }         ' for brackets
	Rem
	bbdoc: Whether neutral final applies to this venue policy.
	End Rem
	Field neutralFinal:Int { asBool }
	Rem
	bbdoc: #THomeCourtSeries value used by this venue policy.
	about: For NBA/MLB style.
	End Rem
	Field seriesTemplate:THomeCourtSeries ' for NBA/MLB style
End Type

Rem
bbdoc: Venue allocation modes for fixtures and bracket ties.
End Rem
Enum EVenue
	Neutral
	HomeAway
	HigherSeedHome
	Rotation
	TwoLegAggregate
End Enum

Rem
bbdoc: Home-site pattern for the games in a best-of series.
End Rem
Type THomeCourtSeries
	Rem
	bbdoc: Best of for this home court series.
	about: 1, 3, 5, 7.
	End Rem
	Field bestOf:Int        ' 1, 3, 5, 7
	Rem
	bbdoc: Pattern values associated with this home court series.
	about: For example, [2,2,1,1,1] means H,H,A,A,H,A,H for higher seed.
	End Rem
	Field pattern:Int[]     ' e.g. [2,2,1,1,1] means H,H,A,A,H,A,H for higher seed
End Type

' ---------- Match rules ----------
Rem
bbdoc: Rules for single matches, legs, best-of series, and set-based ties.
End Rem
Type TMatchFormat
	Rem
	bbdoc: Best of matches for this match format.
	about: Series length for playoffs.
	End Rem
	Field bestOfMatches:Int    ' series length for playoffs
	Rem
	bbdoc: Legs for this match format.
	about: 1 or 2 (aggregate).
	End Rem
	Field legs:Int             ' 1 or 2 (aggregate)
	Rem
	bbdoc: Whether aggregate scores applies to this match format.
	about: For two-leg ties.
	End Rem
	Field aggregateScores:Int { asBool } ' for two-leg ties
	Rem
	bbdoc: Whether away goals rule applies to this match format.
	End Rem
	Field awayGoalsRule:Int { asBool }
	Rem
	bbdoc: Extra time minutes for this match format.
	about: 0 for none.
	End Rem
	Field extraTimeMinutes:Int ' 0 for none
	Rem
	bbdoc: Whether penalties applies to this match format.
	about: After ET if needed.
	End Rem
	Field penalties:Int { asBool } ' after ET if needed
	Rem
	bbdoc: Whether draw allowed applies to this match format.
	about: In group stage etc.
	End Rem
	Field drawAllowed:Int { asBool } ' in group stage etc.
	Rem
	bbdoc: #TSetRules value used by this match format.
	about: Null if not a set-based sport.
	End Rem
	Field setRules:TSetRules   ' Null if not a set-based sport
End Type

' ---------- Set rules ----------
Rem
bbdoc: Set, game, and tie-break targets for set-based matches.
End Rem
Type TSetRules
	Rem
	bbdoc: Whether uses sets applies to this set rules.
	about: True for tennis/volleyball.
	End Rem
	Field usesSets:Int { asBool }    ' true for tennis/volleyball
	Rem
	bbdoc: Sets best of for this set rules.
	about: For example, 3 or 5.
	End Rem
	Field setsBestOf:Int             ' e.g. 3 or 5
	Rem
	bbdoc: Games needed to take a set before the margin rule is applied.
	about: Tennis=6, can vary.
	End Rem
	Field gamesPerSetTarget:Int      ' tennis=6, can vary
	Rem
	bbdoc: Minimum lead in games required to take a set.
	about: Typically 2.
	End Rem
	Field gamesMargin:Int            ' typically 2
	Rem
	bbdoc: Games per side at which a tie-break begins.
	about: For example, 6 => tiebreak at 6–6.
	End Rem
	Field tiebreakAtGames:Int        ' e.g. 6 => tiebreak at 6–6
	Rem
	bbdoc: Whether tiebreak final set applies to this set rules.
	End Rem
	Field tiebreakFinalSet:Int { asBool }
	Rem
	bbdoc: Whether final set super tb applies to this set rules.
	about: For example, 10-pt super tiebreak.
	End Rem
	Field finalSetSuperTB:Int { asBool } ' e.g. 10-pt super tiebreak
	Rem
	bbdoc: Points needed to take a tie-break before its margin rule is applied.
	about: For example, 7 or 10.
	End Rem
	Field tiebreakPointsTarget:Int   ' e.g. 7 or 10
	Rem
	bbdoc: Minimum lead in points required to take a tie-break.
	about: Usually 2.
	End Rem
	Field tiebreakMargin:Int         ' usually 2
End Type

' ---------- Stage configs ----------
Rem
bbdoc: Base class for serializable stage configurations.
End Rem
Type TConfig Abstract
	Rem
	bbdoc: Config type selected for this config.
	End Rem
	Field configType:EConfigType
	Rem
	bbdoc: Registered code identifying the custom configuration.
	about: This field is optional: registered custom config.
	End Rem
	Field configCode:String           ' optional registered custom config
End Type

Rem
bbdoc: Built-in configuration families stored on a stage.
End Rem
Enum EConfigType
	League
	Group
	Bracket
	Series
    Swiss
    Heats
    StrokePlay
    Regatta
    Cycling
End Enum

' A stage race has several simultaneous classifications from the same results.
Rem
bbdoc: Rules for stage races with simultaneous rider and team classifications.
End Rem
Type TCyclingConfig Extends TConfig
	Rem
	bbdoc: #TCyclingStageRule entries associated with this cycling configuration.
	End Rem
	Field stages:TCyclingStageRule[]
	Rem
	bbdoc: Young rider IDs associated with this cycling configuration.
	End Rem
	Field youngRiderIds:Int[]
	Rem
	bbdoc: Riders per team for this cycling configuration.
	End Rem
	Field ridersPerTeam:Int = 3
	Rem
	bbdoc: Points scale for this cycling configuration.
	about: Preserves half-point awards in a dead heat.
	End Rem
	Field pointsScale:Int = 2 ' preserves half-point awards in a dead heat
	Rem
	bbdoc: Sprint points values associated with this cycling configuration.
	End Rem
	Field sprintPoints:Int[]
	Rem
	bbdoc: #TCyclingClimbRule entries associated with this cycling configuration.
	End Rem
	Field climbPoints:TCyclingClimbRule[]

	Method New()
		configType = EConfigType.Cycling
	End Method
End Type

Rem
bbdoc: Points, time bonuses, and checkpoints for one cycling stage.
End Rem
Type TCyclingStageRule
	Rem
	bbdoc: Stable identifier of this cycling stage rule.
	End Rem
	Field id:String
	Rem
	bbdoc: Whether is time trial applies to this cycling stage rule.
	End Rem
	Field isTimeTrial:Int { asBool }
	Rem
	bbdoc: Finish points values associated with this cycling stage rule.
	End Rem
	Field finishPoints:Int[]
	Rem
	bbdoc: Finish bonus seconds measured in seconds.
	End Rem
	Field finishBonusSeconds:Int[]
	Rem
	bbdoc: #TCyclingCheckpointRule entries associated with this cycling stage rule.
	End Rem
	Field checkpoints:TCyclingCheckpointRule[]
End Type

Rem
bbdoc: Points awarded at a categorised climb.
End Rem
Type TCyclingClimbRule
	Rem
	bbdoc: Category of this cycling climb rule.
	End Rem
	Field category:String
	Rem
	bbdoc: Points values associated with this cycling climb rule.
	End Rem
	Field points:Int[]
End Type

Rem
bbdoc: Sprint or climb awards at a checkpoint within a stage.
End Rem
Type TCyclingCheckpointRule
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Classification of this cycling checkpoint rule.
	about: POINTS or CLIMBER.
	End Rem
	Field classification:String ' POINTS or CLIMBER
	Rem
	bbdoc: Category of this cycling checkpoint rule.
	about: Climber point table key.
	End Rem
	Field category:String ' climber point table key
	Rem
	bbdoc: Points values associated with this cycling checkpoint rule.
	about: This field is optional: per-checkpoint override.
	End Rem
	Field points:Int[] ' optional per-checkpoint override
	Rem
	bbdoc: Bonus seconds measured in seconds.
	about: This field is optional: bonuses awarded to the first places.
	End Rem
	Field bonusSeconds:Int[] ' optional bonuses awarded to the first places
End Type

Rem
bbdoc: A rider's completion status for a cycling stage.
End Rem
Enum ECyclingRiderStatus
    Finished
    Withdrawn
    Disqualified
End Enum

Rem
bbdoc: A rider's stage place, elapsed time, and time adjustments.
End Rem
Type TCyclingRiderResult
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Place for this cycling rider result.
	End Rem
	Field place:Int
	Rem
	bbdoc: Elapsed seconds measured in seconds.
	about: Raw stage time used for the team result.
	End Rem
	Field elapsedSeconds:Long ' raw stage time used for the team result
	Rem
	bbdoc: Bonus seconds measured in seconds.
	End Rem
	Field bonusSeconds:Int
	Rem
	bbdoc: Whether bonus recorded applies to this cycling rider result.
	about: Check an official bonus against configured awards.
	End Rem
	Field bonusRecorded:Int { asBool } ' check an official bonus against configured awards
	Rem
	bbdoc: Penalty seconds measured in seconds.
	End Rem
	Field penaltySeconds:Int
	Rem
	bbdoc: Gc adjustment seconds measured in seconds.
	about: Official time credit, neutralisation etc.
	End Rem
	Field gcAdjustmentSeconds:Int ' official time credit, neutralisation etc.
	Rem
	bbdoc: Time trial hundredths measured in hundredths.
	about: GC tie breaker; does not alter whole-second total.
	End Rem
	Field timeTrialHundredths:Int ' GC tie breaker; does not alter whole-second total
	Rem
	bbdoc: Current status of this cycling rider result.
	End Rem
	Field status:ECyclingRiderStatus
End Type

Rem
bbdoc: Finishing order at a cycling checkpoint.
End Rem
Type TCyclingCheckpointResult
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Order values associated with this cycling checkpoint result.
	End Rem
	Field order:Int[]
End Type

Rem
bbdoc: Administrative change to a rider's points or climber units.
End Rem
Type TCyclingPointAdjustment
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Points stored in the configured integer scale.
	about: Signed adjustment in configured points scale.
	End Rem
	Field pointsUnits:Int ' signed adjustment in configured points scale
	Rem
	bbdoc: Climber units in the configured integer scale.
	about: Signed adjustment in configured points scale.
	End Rem
	Field climberUnits:Int ' signed adjustment in configured points scale
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: Administrative time correction to a cycling team.
End Rem
Type TCyclingTeamAdjustment
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: Signed seconds added to the team classification total.
	about: Signed correction to the cumulative team classification.
	End Rem
	Field seconds:Long ' signed correction to the cumulative team classification
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: Cumulative general, points, and climber standing for a rider.
End Rem
Type TCyclingStanding
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: Whether active applies to this cycling standing.
	End Rem
	Field active:Int { asBool }
	Rem
	bbdoc: Stages finished for this cycling standing.
	End Rem
	Field stagesFinished:Int
	Rem
	bbdoc: Elapsed seconds measured in seconds.
	End Rem
	Field elapsedSeconds:Long
	Rem
	bbdoc: Bonus seconds measured in seconds.
	End Rem
	Field bonusSeconds:Long
	Rem
	bbdoc: Penalty seconds measured in seconds.
	End Rem
	Field penaltySeconds:Long
	Rem
	bbdoc: Gc adjustment seconds measured in seconds.
	End Rem
	Field gcAdjustmentSeconds:Long
	Rem
	bbdoc: Total seconds measured in seconds.
	End Rem
	Field totalSeconds:Long
	Rem
	bbdoc: Time trial hundredths measured in hundredths.
	End Rem
	Field timeTrialHundredths:Int
	Rem
	bbdoc: Points stored in the configured integer scale.
	End Rem
	Field pointsUnits:Int
	Rem
	bbdoc: Climber units in the configured integer scale.
	End Rem
	Field climberUnits:Int
	Rem
	bbdoc: Stage wins for this cycling standing.
	End Rem
	Field stageWins:Int
	Rem
	bbdoc: Sprint wins for this cycling standing.
	End Rem
	Field sprintWins:Int
	Rem
	bbdoc: Stage place sum for this cycling standing.
	End Rem
	Field stagePlaceSum:Int
	Rem
	bbdoc: Last stage place for this cycling standing.
	End Rem
	Field lastStagePlace:Int
	Rem
	bbdoc: #TCyclingClimbWin entries associated with this cycling standing.
	End Rem
	Field climbWins:TCyclingClimbWin[]
End Type

Rem
bbdoc: Number of climbs won in one category.
End Rem
Type TCyclingClimbWin
	Rem
	bbdoc: Category of this cycling climb win.
	End Rem
	Field category:String
	Rem
	bbdoc: Wins for this cycling climb win.
	End Rem
	Field wins:Int
End Type

Rem
bbdoc: Cumulative team time and stage placements in a cycling race.
End Rem
Type TCyclingTeamStanding
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: Active riders for this cycling team standing.
	End Rem
	Field activeRiders:Int
	Rem
	bbdoc: Whether eligible applies to this cycling team standing.
	End Rem
	Field eligible:Int { asBool }
	Rem
	bbdoc: Total seconds measured in seconds.
	End Rem
	Field totalSeconds:Long
	Rem
	bbdoc: Stage wins for this cycling team standing.
	End Rem
	Field stageWins:Int
	Rem
	bbdoc: Stage places values associated with this cycling team standing.
	about: Count of first, second, etc. stage team classifications.
	End Rem
	Field stagePlaces:Int[] ' count of first, second, etc. stage team classifications
End Type

' Low-point fleet racing. All scores are exact integer units of pointScale.
Rem
bbdoc: Low-point fleet racing rules, including discards and medal races.
about: Scores are stored as integer units of `pointScale`. A medal race can use a multiplier and keep medal qualifiers ahead of nonqualifiers.
End Rem
Type TRegattaConfig Extends TConfig
	Rem
	bbdoc: Scheduled races for this regatta configuration.
	End Rem
	Field scheduledRaces:Int
	Rem
	bbdoc: Minimum races for this regatta configuration.
	End Rem
	Field minimumRaces:Int = 1
	Rem
	bbdoc: Point scale for this regatta configuration.
	End Rem
	Field pointScale:Int = 1
	Rem
	bbdoc: Offset added to fleet size for automatic penalty scores.
	about: Fleet size + offset for DNS/DNF/DSQ etc.
	End Rem
	Field penaltyOffset:Int = 1 ' fleet size + offset for DNS/DNF/DSQ etc.
	Rem
	bbdoc: Penalty codes values associated with this regatta configuration.
	about: This field is optional: codes using the automatic fleet-size penalty.
	End Rem
	Field penaltyCodes:String[] ' optional codes using the automatic fleet-size penalty
	Rem
	bbdoc: Discard after races for this regatta configuration.
	End Rem
	Field discardAfterRaces:Int = 3
	Rem
	bbdoc: Number of discard for this regatta configuration.
	End Rem
	Field discardCount:Int = 1
	Rem
	bbdoc: Medal places for this regatta configuration.
	about: Zero disables a medal race.
	End Rem
	Field medalPlaces:Int ' 0 disables a medal race
	Rem
	bbdoc: Medal multiplier for this regatta configuration.
	End Rem
	Field medalMultiplier:Int = 2
	Rem
	bbdoc: Medal ranks ahead for this regatta configuration.
	about: Medal qualifiers remain ahead of nonqualifiers.
	End Rem
	Field medalRanksAhead:Int = True ' medal qualifiers remain ahead of nonqualifiers

	Method New()
		configType = EConfigType.Regatta
	End Method
End Type

Rem
bbdoc: One entrant's place, code, or adjusted score in a sailing race.
End Rem
Type TRegattaRaceScore
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Place for this regatta race score.
	about: Positive finishing place; 0 for a code or adjusted score.
	End Rem
	Field place:Int ' positive finishing place; 0 for a code or adjusted score
	Rem
	bbdoc: Score stored in the configured integer scale.
	about: 0 derives low-point score from place or penalty code.
	End Rem
	Field scoreUnits:Int ' 0 derives low-point score from place or penalty code
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	about: For example, BFD, DNF, DNS, DPI, DNE, RDG.
	End Rem
	Field code:String ' e.g. BFD, DNF, DNS, DPI, DNE, RDG
	Rem
	bbdoc: Whether non discardable applies to this regatta race score.
	End Rem
	Field nonDiscardable:Int { asBool }
End Type

Rem
bbdoc: A stored race score with its discard and penalty status.
End Rem
Type TRegattaScore
	Rem
	bbdoc: Round for this regatta score.
	End Rem
	Field round:Int
	Rem
	bbdoc: Score stored in the configured integer scale.
	End Rem
	Field scoreUnits:Int
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Whether discarded applies to this regatta score.
	End Rem
	Field discarded:Int { asBool }
	Rem
	bbdoc: Whether non discardable applies to this regatta score.
	End Rem
	Field nonDiscardable:Int { asBool }
End Type

Rem
bbdoc: Cumulative sailing score and race history for one entrant.
End Rem
Type TRegattaStanding
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Total score stored in the configured integer scale.
	End Rem
	Field totalUnits:Int
	Rem
	bbdoc: Opening units in the configured integer scale.
	End Rem
	Field openingUnits:Int
	Rem
	bbdoc: Medal units in the configured integer scale.
	End Rem
	Field medalUnits:Int
	Rem
	bbdoc: Whether medal qualified applies to this regatta standing.
	End Rem
	Field medalQualified:Int { asBool }
	Rem
	bbdoc: #TRegattaScore entries associated with this regatta standing.
	End Rem
	Field scores:TRegattaScore[]
End Type

Rem
bbdoc: Golf round, cut, handicap, team, playoff, and countback rules.
about: Gross, net, and Stableford scoring share the same scorecard input. Team scoring can count every card or the best member score on each hole.
End Rem
Type TStrokePlayConfig Extends TConfig
	Rem
	bbdoc: #TStrokePlayRoundConfig entries associated with this stroke play configuration.
	End Rem
	Field rounds:TStrokePlayRoundConfig[]
	Rem
	bbdoc: Round after which the configured cut is applied; zero disables it.
	about: Zero disables the cut.
	End Rem
	Field cutAfterRound:Int ' 0 disables the cut
	Rem
	bbdoc: Cut places for this stroke play configuration.
	End Rem
	Field cutPlaces:Int
	Rem
	bbdoc: Number of playoff hole for this stroke play configuration.
	about: Shorthand for a gross playoff; 0 leaves ties unresolved unless countback does.
	End Rem
	Field playoffHoleCount:Int ' shorthand for a gross playoff; 0 leaves ties unresolved unless countback does
	Rem
	bbdoc: #TStrokePlayRoundConfig value used by this stroke play configuration.
	about: This field is optional: full playoff hole definition.
	End Rem
	Field playoffRound:TStrokePlayRoundConfig ' optional full playoff hole definition
	Rem
	bbdoc: Playoff scoring selected for this stroke play configuration.
	about: Defaults to gross; can be net or Stableford.
	End Rem
	Field playoffScoring:EStrokeScoringMode ' defaults to gross; can be net or Stableford
	Rem
	bbdoc: Scoring selected for this stroke play configuration.
	End Rem
	Field scoring:EStrokeScoringMode
	Rem
	bbdoc: Stableford points awarded for a net par.
	End Rem
	Field stablefordParPoints:Int = 2
	Rem
	bbdoc: #TStrokePointBand entries associated with this stroke play configuration.
	about: This field is optional: ordered score-to-par thresholds.
	End Rem
	Field stablefordBands:TStrokePointBand[] ' optional ordered score-to-par thresholds
	Rem
	bbdoc: Stableford default points for this stroke play configuration.
	End Rem
	Field stablefordDefaultPoints:Int
	Rem
	bbdoc: #TStrokeTeam entries associated with this stroke play configuration.
	about: When provided, entities in the leaderboard are teams.
	End Rem
	Field teams:TStrokeTeam[] ' when present, entities in the leaderboard are teams
	Rem
	bbdoc: Team best per hole for this stroke play configuration.
	about: 0 counts every team member; 1 gives four-ball/best ball.
	End Rem
	Field teamBestPerHole:Int ' 0 counts every team member; 1 gives four-ball/best ball
	Rem
	bbdoc: Number of back for this stroke play configuration.
	about: Ordered comparison of tied totals.
	End Rem
	Field countback:TStrokeCountbackSegment[] ' ordered comparison of tied totals
	Rem
	bbdoc: Whether cut uses countback applies to this stroke play configuration.
	End Rem
	Field cutUsesCountback:Int { asBool }

	Method New()
		configType = EConfigType.StrokePlay
	End Method
End Type

Rem
bbdoc: Hole pars, stroke indexes, and handicaps for a golf round.
End Rem
Type TStrokePlayRoundConfig
	Rem
	bbdoc: Number of hole for this stroke play round configuration.
	End Rem
	Field holeCount:Int
	Rem
	bbdoc: Pars values associated with this stroke play round configuration.
	about: This field is optional: hole pars, retained as event definition.
	End Rem
	Field pars:Int[] ' optional hole pars, retained as event definition
	Rem
	bbdoc: Stroke indexes values associated with this stroke play round configuration.
	about: 1 is hardest; needed for playingHandicap allocation.
	End Rem
	Field strokeIndexes:Int[] ' 1 is hardest; needed for playingHandicap allocation
	Rem
	bbdoc: Per-player strokes received on the round holes.
	about: Strokes received per hole, by player.
	End Rem
	Field handicaps:TStrokeHandicap[] ' strokes received per hole, by player
End Type

Rem
bbdoc: Gross, net, and Stableford golf scoring modes.
End Rem
Enum EStrokeScoringMode
    Gross
    Net
    Stableford
End Enum

Rem
bbdoc: Playing handicap or per-hole strokes for one golfer.
End Rem
Type TStrokeHandicap
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Playing handicap for this stroke handicap.
	about: Positive strokes received; negative gives strokes back.
	End Rem
	Field playingHandicap:Int ' positive strokes received; negative gives strokes back
	Rem
	bbdoc: Received values associated with this stroke handicap.
	about: This field is optional: explicit per-hole override.
	End Rem
	Field received:Int[] ' optional explicit per-hole override
End Type

Rem
bbdoc: Stableford points for a score relative to par.
End Rem
Type TStrokePointBand
	Rem
	bbdoc: Max relative to par for this stroke point band.
	End Rem
	Field maxRelativeToPar:Int
	Rem
	bbdoc: Points for this stroke point band.
	End Rem
	Field points:Int
End Type

Rem
bbdoc: A team and the golfers whose cards contribute to its score.
End Rem
Type TStrokeTeam
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: Member IDs associated with this stroke team.
	End Rem
	Field memberIds:Int[]
End Type

Rem
bbdoc: A trailing round or hole segment used to break a golf tie.
End Rem
Type TStrokeCountbackSegment
	Rem
	bbdoc: Rounds from end for this stroke countback segment.
	about: Zero means final regulation round.
	End Rem
	Field roundsFromEnd:Int ' 0 = final regulation round
	Rem
	bbdoc: Last holes for this stroke countback segment.
	End Rem
	Field lastHoles:Int
End Type

Rem
bbdoc: Stored hole values or round total used in golf ranking.
End Rem
Type TStrokeRoundValues
	Rem
	bbdoc: Round for this stroke round values.
	End Rem
	Field round:Int
	Rem
	bbdoc: Holes values associated with this stroke round values.
	about: Score used for ranking: strokes for Gross/Net; points for Stableford.
	End Rem
	Field holes:Int[] ' score used for ranking: strokes for Gross/Net; points for Stableford
	Rem
	bbdoc: Round strokes for this stroke round values.
	about: Official gross total when hole scores are unavailable.
	End Rem
	Field roundStrokes:Int ' official gross total when hole scores are unavailable
End Type

Rem
bbdoc: Completion, withdrawal, and start status of a golf card.
End Rem
Enum EStrokeCardStatus
    Completed
    Withdrawn
    Disqualified
    DidNotStart
End Enum

Rem
bbdoc: A golfer's hole scores or gross round total and status.
End Rem
Type TStrokeScorecard
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Holes values associated with this stroke scorecard.
	about: Official strokes including penalties; zero is permitted for a picked-up/uncounted hole.
	End Rem
	Field holes:Int[] ' official strokes including penalties; zero is permitted for a picked-up/uncounted hole
	Rem
	bbdoc: Round strokes for this stroke scorecard.
	about: Positive 18-hole/round gross total instead of holes; gross individuals only.
	End Rem
	Field roundStrokes:Int ' positive 18-hole/round gross total instead of holes; gross individuals only
	Rem
	bbdoc: Current status of this stroke scorecard.
	End Rem
	Field status:EStrokeCardStatus
End Type

Rem
bbdoc: Cumulative golf totals, cut status, and round values.
End Rem
Type TStrokeStanding
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Strokes for this stroke standing.
	End Rem
	Field strokes:Int
	Rem
	bbdoc: Net strokes for this stroke standing.
	End Rem
	Field netStrokes:Int
	Rem
	bbdoc: Points for this stroke standing.
	End Rem
	Field points:Int
	Rem
	bbdoc: Rounds completed for this stroke standing.
	End Rem
	Field roundsCompleted:Int
	Rem
	bbdoc: Current status of this stroke standing.
	about: Active, cut, withdrawn, disqualified, did-not-start.
	End Rem
	Field status:String ' active, cut, withdrawn, disqualified, did-not-start
	Rem
	bbdoc: #TStrokeRoundValues entries associated with this stroke standing.
	End Rem
	Field roundValues:TStrokeRoundValues[]
End Type

Rem
bbdoc: Qualifying heat, repechage, and final rules.
about: `qualifyingRounds` defines a multi-round route; when empty, the top-level fields describe one qualifying round and optional repechage. Published heat groups and lane assignments may be fixed.
End Rem
Type THeatsConfig Extends TConfig
	Rem
	bbdoc: Number of heat for this heats configuration.
	End Rem
	Field heatCount:Int
	Rem
	bbdoc: Automatic places for this heats configuration.
	End Rem
	Field automaticPlaces:Int
	Rem
	bbdoc: Fastest remaining for this heats configuration.
	End Rem
	Field fastestRemaining:Int
	Rem
	bbdoc: Cutoff tie policy selected for this heats configuration.
	End Rem
	Field cutoffTiePolicy:EHeatCutoffTiePolicy
	Rem
	bbdoc: #THeatRoundConfig value used by this heats configuration.
	about: This field is optional: for the one-round shorthand.
	End Rem
	Field repechage:THeatRoundConfig ' optional for the one-round shorthand
	Rem
	bbdoc: #THeatLanePolicy value used by this heats configuration.
	about: This field is optional: lanes for the one-round shorthand.
	End Rem
	Field lanes:THeatLanePolicy ' optional lanes for the one-round shorthand
	Rem
	bbdoc: #THeatRoundConfig entries associated with this heats configuration.
	about: When empty, use the fields above for one qualifying round.
	End Rem
	Field qualifyingRounds:THeatRoundConfig[] ' when empty, use the fields above for one qualifying round
	Rem
	bbdoc: #THeatLanePolicy value used by this heats configuration.
	End Rem
	Field finalLanes:THeatLanePolicy

	Method New()
		configType = EConfigType.Heats
	End Method
End Type

Rem
bbdoc: Qualification places, tie policy, lanes, and optional repechage for a round.
End Rem
Type THeatRoundConfig
	Rem
	bbdoc: Number of heat for this heat round configuration.
	End Rem
	Field heatCount:Int
	Rem
	bbdoc: Automatic places for this heat round configuration.
	End Rem
	Field automaticPlaces:Int
	Rem
	bbdoc: Fastest remaining for this heat round configuration.
	End Rem
	Field fastestRemaining:Int
	Rem
	bbdoc: Cutoff tie policy selected for this heat round configuration.
	End Rem
	Field cutoffTiePolicy:EHeatCutoffTiePolicy
	Rem
	bbdoc: #THeatRoundConfig value used by this heat round configuration.
	about: This field is optional: second-chance heats for nonqualifying finishers.
	End Rem
	Field repechage:THeatRoundConfig ' optional second-chance heats for nonqualifying finishers
	Rem
	bbdoc: #THeatLanePolicy value used by this heat round configuration.
	End Rem
	Field lanes:THeatLanePolicy
	Rem
	bbdoc: #THeatGroup entries associated with this heat round configuration.
	about: This field is optional: published or manually assigned heat composition.
	End Rem
	Field fixedGroups:THeatGroup[] ' optional published or manually assigned heat composition
End Type

Rem
bbdoc: A fixed set of entrants assigned to one heat.
End Rem
Type THeatGroup
	Rem
	bbdoc: IDs of the associated participants.
	End Rem
	Field participantIds:Int[]
End Type

Rem
bbdoc: Lane count, preferences, random seed, or fixed lane assignments.
End Rem
Type THeatLanePolicy
	Rem
	bbdoc: Number of lane for this heat lane policy.
	End Rem
	Field laneCount:Int
	Rem
	bbdoc: Preference values associated with this heat lane policy.
	about: Preferred lanes in entrant priority order; empty means ascending lane number.
	End Rem
	Field preference:Int[] ' preferred lanes in entrant priority order; empty means ascending lane number
	Rem
	bbdoc: Allocation selected for this heat lane policy.
	End Rem
	Field allocation:EHeatLaneAllocation
	Rem
	bbdoc: Draw seed for this heat lane policy.
	about: Used only for Random; fixture identity separates each draw.
	End Rem
	Field drawSeed:Int ' used only for Random; fixture identity separates each draw
	Rem
	bbdoc: #THeatLaneAssignment entries associated with this heat lane policy.
	about: Published participant-to-lane map for this round.
	End Rem
	Field fixedAssignments:THeatLaneAssignment[] ' published participant-to-lane map for this round
End Type

Rem
bbdoc: Methods for assigning entrants to lanes.
End Rem
Enum EHeatLaneAllocation
    Preference
    Random
End Enum

Rem
bbdoc: A published or generated participant-to-lane assignment.
End Rem
Type THeatLaneAssignment
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Lane for this heat lane assignment.
	End Rem
	Field lane:Int
End Type

Rem
bbdoc: Whether a heat belongs to the main route, repechage, or final.
End Rem
Enum EHeatPhase
    Main
    Repechage
    Final
End Enum

Rem
bbdoc: How a tied qualifying cutoff is handled.
End Rem
Enum EHeatCutoffTiePolicy
	Rem
	bbdoc: Advance every entrant tied at the qualifying cutoff.
	End Rem
    AdvanceAll
	Rem
	bbdoc: Hold advancement until the sporting tie receives a decision.
	End Rem
    RequireResolution
End Enum

Rem
bbdoc: League scoring, fixture scheduling, and postseason selection rules.
End Rem
Type TLeagueConfig Extends TConfig
	Rem
	bbdoc: #TLeagueScheduleConfig value used by this league configuration.
	End Rem
	Field schedule:TLeagueScheduleConfig
	Rem
	bbdoc: Points win for this league configuration.
	End Rem
	Field pointsWin:Int = 3
	Rem
	bbdoc: Points draw for this league configuration.
	End Rem
	Field pointsDraw:Int = 1
	Rem
	bbdoc: Points loss for this league configuration.
	End Rem
	Field pointsLoss:Int = 0
	Rem
	bbdoc: Tiebreakers selected for this league configuration.
	End Rem
	Field tiebreakers:ETiebreaker[] = [ETiebreaker.Points, ETiebreaker.GoalDifference, ETiebreaker.GoalsFor]
	Rem
	bbdoc: Whether reapply head to head applies to this league configuration.
	about: Restart the head-to-head block for a still-tied subset.
	End Rem
	Field reapplyHeadToHead:Int { asBool } ' restart the head-to-head block for a still-tied subset
	Rem
	bbdoc: #TSchedulePolicy value used by this league configuration.
	End Rem
	Field policy:TSchedulePolicy
	Rem
	bbdoc: #TScoringSystem value used by this league configuration.
	End Rem
	Field scoring:TScoringSystem
	Rem
	bbdoc: #TPostseasonConfig value used by this league configuration.
	End Rem
	Field postseason:TPostseasonConfig

	Method New()
		configType = EConfigType.League
	End Method
End Type

' Select division winners and then at-large entrants within each named pool.
' Criteria are ordered; an unresolved sporting tie raises an error.
Rem
bbdoc: Division-winner and at-large selection rules for named league pools.
about: Supply separate ordered tie criteria for division winners, at-large places, and seed order. A tie that still affects selection requires an official #TPostseasonTieDecision.
End Rem
Type TPostseasonConfig
	Rem
	bbdoc: #TPostseasonPool entries associated with this postseason configuration.
	End Rem
	Field pools:TPostseasonPool[]
	Rem
	bbdoc: Division winners per division for this postseason configuration.
	End Rem
	Field divisionWinnersPerDivision:Int = 1
	Rem
	bbdoc: At large places for this postseason configuration.
	End Rem
	Field atLargePlaces:Int
	Rem
	bbdoc: #TPostseasonTieRules value used by this postseason configuration.
	End Rem
	Field divisionTie:TPostseasonTieRules
	Rem
	bbdoc: #TPostseasonTieRules value used by this postseason configuration.
	End Rem
	Field atLargeTie:TPostseasonTieRules
	Rem
	bbdoc: #TPostseasonTieRules value used by this postseason configuration.
	End Rem
	Field seedTie:TPostseasonTieRules
	Rem
	bbdoc: #TPostseasonTieDecision entries associated with this postseason configuration.
	about: Recorded decisions when metrics cannot separate teams.
	End Rem
	Field tieDecisions:TPostseasonTieDecision[] ' recorded decisions when metrics cannot separate teams
End Type

Rem
bbdoc: An official decision for a postseason selection tie that metrics cannot resolve.
End Rem
Type TPostseasonTieDecision
	Rem
	bbdoc: Code identifying the associated pool.
	End Rem
	Field poolCode:String
	Rem
	bbdoc: IDs of the associated participants.
	about: Exact tied set, order independent.
	End Rem
	Field participantIds:Int[] ' exact tied set, order independent
	Rem
	bbdoc: ID of the winner associated with this postseason tie decision.
	End Rem
	Field winnerId:Int
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: A conference or other pool containing specified divisions.
End Rem
Type TPostseasonPool
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Division IDs associated with this postseason pool.
	End Rem
	Field divisionIds:String[]
End Type

Rem
bbdoc: Ordered tie criteria for two-team and multi-team postseason comparisons.
End Rem
Type TPostseasonTieRules
	Rem
	bbdoc: Two teams selected for this postseason tie rules.
	End Rem
	Field twoTeams:EPostseasonCriterion[]
	Rem
	bbdoc: Many teams selected for this postseason tie rules.
	End Rem
	Field manyTeams:EPostseasonCriterion[]
	Rem
	bbdoc: Whether reduce by division applies to this postseason tie rules.
	about: Compare only the highest remaining team from each division.
	End Rem
	Field reduceByDivision:Int { asBool } ' compare only the highest remaining team from each division
	Rem
	bbdoc: Whether head to head sweep applies to this postseason tie rules.
	about: Multi-team sweep rather than a mini-table.
	End Rem
	Field headToHeadSweep:Int { asBool } ' multi-team sweep rather than a mini-table
End Type

Rem
bbdoc: Metrics available when comparing postseason candidates or seeds.
End Rem
Enum EPostseasonCriterion
	HeadToHead
	DivisionRecord
	PoolRecord
	CommonOpponents
	StrengthOfVictory
	StrengthOfSchedule
	PointsScored
	PointsAllowed
	NetPoints
	CombinedPointsRankPool
	CombinedPointsRankAll
	NetPointsPool
	NetPointsCommon
End Enum

Rem
bbdoc: Round-robin group size, scoring, draw, and ranking rules.
End Rem
Type TGroupConfig Extends TConfig
	Rem
	bbdoc: Groups for this group configuration.
	End Rem
	Field groups:Int
	Rem
	bbdoc: Group size for this group configuration.
	End Rem
	Field groupSize:Int
	Rem
	bbdoc: Explicit sizes for groups that differ from the usual group size.
	about: This field is optional: pre-calculated sizes.
	End Rem
	Field groupSizes:Int[]        ' optional: pre-calculated sizes
	Rem
	bbdoc: #TPresetGroup entries associated with this group configuration.
	about: Use an already published draw instead of placing teams.
	End Rem
	Field presetGroups:TPresetGroup[] ' use an already published draw instead of placing teams
	Rem
	bbdoc: Round robin per opponent for this group configuration.
	about: 1=single, 2=home/away.
	End Rem
	Field roundRobinPerOpponent:Int     ' 1=single, 2=home/away
	Rem
	bbdoc: Points win for this group configuration.
	End Rem
	Field pointsWin:Int = 3
	Rem
	bbdoc: Points draw for this group configuration.
	End Rem
	Field pointsDraw:Int = 1
	Rem
	bbdoc: Points loss for this group configuration.
	End Rem
	Field pointsLoss:Int = 0
	Rem
	bbdoc: Tiebreakers selected for this group configuration.
	End Rem
	Field tiebreakers:ETiebreaker[]
	Rem
	bbdoc: Whether reapply head to head applies to this group configuration.
	End Rem
	Field reapplyHeadToHead:Int { asBool }
	Rem
	bbdoc: #TSchedulePolicy value used by this group configuration.
	End Rem
	Field policy:TSchedulePolicy

	Method New()
		configType = EConfigType.Group
	End Method
End Type

Rem
bbdoc: A published group assignment that bypasses the draw.
End Rem
Type TPresetGroup
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: IDs of the associated participants.
	End Rem
	Field participantIds:Int[]
End Type

Rem
bbdoc: Bracket size, elimination format, match rules, byes, and consolation.
End Rem
Type TBracketConfig Extends TConfig
	Rem
	bbdoc: Size for this bracket configuration.
	End Rem
	Field size:Int
	Rem
	bbdoc: Format selected for this bracket configuration.
	End Rem
	Field format:EBracketFormat
	Rem
	bbdoc: Whether reseed each round applies to this bracket configuration.
	End Rem
	Field reseedEachRound:Int { asBool }
	Rem
	bbdoc: Byes for this bracket configuration.
	End Rem
	Field byes:Int
	Rem
	bbdoc: #TMatchFormat value used by this bracket configuration.
	End Rem
	Field matchFormat:TMatchFormat
	Rem
	bbdoc: #TSchedulePolicy value used by this bracket configuration.
	End Rem
	Field policy:TSchedulePolicy
	Rem
	bbdoc: Consolation selected for this bracket configuration.
	End Rem
	Field consolation:EConsolation
	Rem
	bbdoc: #TDoubleElimOptions value used by this bracket configuration.
	End Rem
	Field doubleElim:TDoubleElimOptions

	Method New()
		configType = EConfigType.Bracket
	End Method
End Type

Rem
bbdoc: Grand-final reset and bronze-match options for double elimination.
End Rem
Type TDoubleElimOptions
	Rem
	bbdoc: Whether grand final reset applies to this double elim options.
	about: If Losers bracket winner must beat Winners twice.
	End Rem
	Field grandFinalReset:Int { asBool }   ' if Losers bracket winner must beat Winners twice
	Rem
	bbdoc: Whether bronze match applies to this double elim options.
	about: This field is optional: 3rd-place.
	End Rem
	Field bronzeMatch:Int { asBool }       ' optional 3rd-place
End Type

Rem
bbdoc: Single- or double-elimination bracket structure.
End Rem
Enum EBracketFormat
	SingleElim
	DoubleElim
End Enum

Rem
bbdoc: Optional placement matches after elimination.
End Rem
Enum EConsolation
	None
	ThirdPlace
	Classification
End Enum

Rem
bbdoc: Ordered criteria for ranking tied group, league, or series entrants.
End Rem
Enum ETiebreaker
    Points
    GoalDifference
    GoalsFor
    HeadToHeadPoints
    HeadToHeadGD
    FairPlay
    RandomDraw
	Wins                  ' total wins
    PointsFor             ' basket/hockey
    PointsAgainst         ' basket/hockey (lower is better; invert in comparator)
    SetsWonPct            ' tennis/volley round-robin
    GamesWonPct           ' tennis round-robin
    FinishCountback       ' series: compare counts of configured finishing positions
End Enum

Rem
bbdoc: Rounds, pairing, scoring, bye, and tie-break rules for a Swiss event.
End Rem
Type TSwissConfig Extends TConfig
	Rem
	bbdoc: Rounds for this swiss configuration.
	about: Total rounds to play.
	End Rem
	Field rounds:Int                 ' total rounds to play
	Rem
	bbdoc: Points scale for this swiss configuration.
	about: Standings units per point; 2 preserves half points.
	End Rem
	Field pointsScale:Int = 2        ' standings units per point; 2 preserves half points
	Rem
	bbdoc: Points win for this swiss configuration.
	about: Scoring basics (per sport).
	End Rem
	Field pointsWin:Float = 1.0      ' scoring basics (per sport)
	Rem
	bbdoc: Points draw for this swiss configuration.
	End Rem
	Field pointsDraw:Float = 0.5
	Rem
	bbdoc: Points loss for this swiss configuration.
	End Rem
	Field pointsLoss:Float = 0.0
	Rem
	bbdoc: Points win exact of this swiss configuration.
	about: Decimal overrides for exact scaled scoring.
	End Rem
	Field pointsWinExact:String       ' decimal overrides for exact scaled scoring
	Rem
	bbdoc: Points draw exact of this swiss configuration.
	End Rem
	Field pointsDrawExact:String
	Rem
	bbdoc: Points loss exact of this swiss configuration.
	End Rem
	Field pointsLossExact:String
	Rem
	bbdoc: Whether a Swiss fixture may end in a draw.
	End Rem
	Field allowDraws:Int = True
	Rem
	bbdoc: Whether Swiss pairings must avoid previous opponents.
	End Rem
	Field avoidRematches:Int = True
	Rem
	bbdoc: Whether home and away assignments should balance across rounds.
	about: Or home/away balance.
	End Rem
	Field colourBalance:Int = True   ' or home/away balance
	Rem
	bbdoc: Max repeat pair attempts for this swiss configuration.
	End Rem
	Field maxRepeatPairAttempts:Int = 200
	Rem
	bbdoc: #TSwissPairingPolicy value used by this swiss configuration.
	about: Optional; defaults to generic pairing.
	End Rem
	Field pairingPolicy:TSwissPairingPolicy ' optional; defaults to generic pairing
	Rem
	bbdoc: Bye points for this swiss configuration.
	End Rem
	Field byePoints:Float = 1.0
	Rem
	bbdoc: Bye points exact of this swiss configuration.
	End Rem
	Field byePointsExact:String
	Rem
	bbdoc: Initial seeding of this swiss configuration.
	about: "seed" (default) or "random" with scheduleSeed.
	End Rem
	Field initialSeeding:String      ' "seed" (default) or "random" with scheduleSeed
	Rem
	bbdoc: Tiebreaks selected for this swiss configuration.
	about: Applied in order after score.
	End Rem
	Field tiebreaks:ESwissTieBreak[] ' applied in order after score
	Rem
	bbdoc: #TSwissPlannedUnplayed entries associated with this swiss configuration.
	End Rem
	Field plannedUnplayed:TSwissPlannedUnplayed[]

	Method New()
		configType = EConfigType.Swiss
	End Method
End Type

Rem
bbdoc: Buchholz-based Swiss standings tie breakers.
End Rem
Enum ESwissTieBreak
    Buchholz
    BuchholzCut1
End Enum

Rem
bbdoc: Why a Swiss entrant did not play in a scheduled round.
End Rem
Enum ESwissUnplayedKind
    None
    PairingBye
    RequestedBye
    Withdrawal
End Enum

Rem
bbdoc: A prearranged Swiss bye or withdrawal and its awarded points.
End Rem
Type TSwissPlannedUnplayed
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Round for this swiss planned unplayed.
	End Rem
	Field round:Int
	Rem
	bbdoc: Kind of this swiss planned unplayed.
	End Rem
	Field kind:ESwissUnplayedKind
	Rem
	bbdoc: Awarded points for this swiss planned unplayed.
	End Rem
	Field awardedPoints:Float
	Rem
	bbdoc: Awarded points exact of this swiss planned unplayed.
	End Rem
	Field awardedPointsExact:String
End Type

Rem
bbdoc: Pairing system and initial colour or home orientation.
End Rem
Type TSwissPairingPolicy
	Rem
	bbdoc: System selected for this swiss pairing policy.
	End Rem
	Field system:ESwissPairingSystem
	Rem
	bbdoc: Starting home or White assignment for the top seed.
	about: 1: top seed has home/White, -1: away/Black.
	End Rem
	Field initialColour:Int = 1 ' 1: top seed has home/White, -1: away/Black
End Type

Rem
bbdoc: Generic or Dutch-style Swiss pairing behaviour.
End Rem
Enum ESwissPairingSystem
    Generic
    DutchStyle
End Enum

' ---------- Divisions / League scheduling ----------
Rem
bbdoc: A named league division, optionally nested under a conference.
End Rem
Type TDivision
	Rem
	bbdoc: Stable identifier of this division.
	End Rem
	Field id:String
	Rem
	bbdoc: Display name of this division.
	End Rem
	Field name:String
	Rem
	bbdoc: ID of the parent associated with this division.
	about: Conference id if any (or "").
	End Rem
	Field parentId:String       ' conference id if any (or "")
	Rem
	bbdoc: IDs of the associated teams.
	End Rem
	Field teamIds:Int[]
End Type

Rem
bbdoc: Matchup rules, fixed fixtures, weeks, byes, and home-away constraints.
about: Combine `matchupRules` to generate opponent sets, or provide `fixedFixtures` for a published matchup list. Week and venue placement can then be planned separately.
End Rem
Type TLeagueScheduleConfig
	' High-level rule matrix rather than hardcoding
	Rem
	bbdoc: Division membership used by opponent-selection rules.
	End Rem
	Field divisions:TDivision[]
	Rem
	bbdoc: Required number of regular-season games per team.
	End Rem
	Field totalGamesPerTeam:Int

	' Pairing rules (each entry adds to the matchup list)
	Rem
	bbdoc: Vs own division for this league schedule configuration.
	about: Matches per opponent in own division (EPL=2, NFL=2).
	End Rem
	Field vsOwnDivision:Int         ' matches per opponent in own division (EPL=2, NFL=2)
	Rem
	bbdoc: #TPoolRule entries associated with this league schedule configuration.
	about: Rules referencing other divisions in same conf.
	End Rem
	Field vsSameConference:TPoolRule[]  ' rules referencing other divisions in same conf
	Rem
	bbdoc: #TPoolRule entries associated with this league schedule configuration.
	End Rem
	Field vsOtherConference:TPoolRule[]
	Rem
	bbdoc: Whether strength schedule applies to this league schedule configuration.
	about: Activate same-rank pairings etc.
	End Rem
	Field strengthSchedule:Int { asBool }     ' activate same-rank pairings etc.
	Rem
	bbdoc: Rank buckets for this league schedule configuration.
	about: For example, , NFL ranks 1..4 per division.
	End Rem
	Field rankBuckets:Int = 4       ' e.g., NFL ranks 1..4 per division
	Rem
	bbdoc: Rotation seed for this league schedule configuration.
	about: To rotate year-to-year.
	End Rem
	Field rotationSeed:Int          ' to rotate year-to-year
	Rem
	bbdoc: Explicit matchups used when the competition supplies its own fixture list.
	End Rem
	Field fixedFixtures:TFixture[]
	Rem
	bbdoc: Ordered rules that generate opponent pairs.
	End Rem
	Field matchupRules:TMatchupRule[]
	Rem
	bbdoc: Whether balance home away applies to this league schedule configuration.
	about: Orient generated rule fixtures within one game per team.
	End Rem
	Field balanceHomeAway:Int { asBool } ' orient generated rule fixtures within one game per team
	Rem
	bbdoc: Number of league weeks, or zero to let the allocator choose enough weeks.
	End Rem
	Field weeks:Int
	Rem
	bbdoc: Weeks in which specified participants must not play.
	End Rem
	Field byeWeeks:TParticipantByeWeek[]
	Rem
	bbdoc: Minimum intervening weeks between repeat meetings; zero disables the limit.
	End Rem
	Field minWeeksBetweenMeetings:Int
End Type

Rem
bbdoc: Ways a league scheduling rule selects opponent pairs.
End Rem
Enum EMatchupMode
	Rem
	bbdoc: Add games for every pair in the selected pools.
	End Rem
    AllPairs
	Rem
	bbdoc: Pair teams with the same previous division rank.
	End Rem
    SameRank
	Rem
	bbdoc: Rotate which opposing division supplies opponents.
	End Rem
    RotatingDivision
	Rem
	bbdoc: Rotate pairs of source and target divisions together.
	End Rem
    RotatingDivisionPairs
End Enum

' A rule adds games between selected division pools. Rules can be combined.
Rem
bbdoc: One composable opponent-selection rule for league scheduling.
End Rem
Type TMatchupRule
	Rem
	bbdoc: Source division IDs associated with this matchup rule.
	about: An empty value means all participants.
	End Rem
	Field sourceDivisionIds:String[] ' empty = all participants
	Rem
	bbdoc: Target division IDs associated with this matchup rule.
	about: An empty value means source pool.
	End Rem
	Field targetDivisionIds:String[] ' empty = source pool
	Rem
	bbdoc: Mode used by this matchup rule.
	End Rem
	Field mode:EMatchupMode
	Rem
	bbdoc: Games per pair for this matchup rule.
	End Rem
	Field gamesPerPair:Int = 1
	Rem
	bbdoc: Rotation offset for this matchup rule.
	End Rem
	Field rotationOffset:Int
	Rem
	bbdoc: Whether same rank only applies to this matchup rule.
	about: Combine rank matching with another mode, including rotation.
	End Rem
	Field sameRankOnly:Int { asBool } ' combine rank matching with another mode, including rotation
	Rem
	bbdoc: Whether exclude already scheduled applies to this matchup rule.
	about: Omit pairs made by preceding rules.
	End Rem
	Field excludeAlreadyScheduled:Int { asBool } ' omit pairs made by preceding rules
End Type

Rem
bbdoc: A required bye for one participant in a league week.
End Rem
Type TParticipantByeWeek
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Week for this participant bye week.
	End Rem
	Field week:Int
End Type

Rem
bbdoc: Legacy division-pool opponent counts for league scheduling.
End Rem
Type TPoolRule
	Rem
	bbdoc: Division IDs associated with this pool rule.
	about: Which divisions this applies to.
	End Rem
	Field divisionIds:String[]      ' which divisions this applies to
	Rem
	bbdoc: Opponents per team for this pool rule.
	about: How many distinct opponents to pick.
	End Rem
	Field opponentsPerTeam:Int      ' how many distinct opponents to pick
	Rem
	bbdoc: Games per opponent for this pool rule.
	about: And how many times vs each opponent.
	End Rem
	Field gamesPerOpponent:Int      ' and how many times vs each opponent
	Rem
	bbdoc: Whether home away balance applies to this pool rule.
	about: Force balance if possible.
	End Rem
	Field homeAwayBalance:Int { asBool }      ' force balance if possible
End Type

' ---------- Series config ----------
Rem
bbdoc: Multi-event scoring rules and independent named championships.
about: `pointsScale` stores exact fractional points as integer units. An award must be representable in that scale; use decimal string `*Exact` fields for non-integer values.
End Rem
Type TSeriesConfig Extends TConfig
	Rem
	bbdoc: Events whose sessions supply championship results.
	about: Calendar of events (e.g., Grand Prix).
	End Rem
	Field events:TSeriesEvent[]      ' calendar of events (e.g., Grand Prix)
	Rem
	bbdoc: Stored standings units per point; two represents half-point awards exactly.
	End Rem
	Field pointsScale:Int = 1
	Rem
	bbdoc: Default position and bonus-point rules for the series.
	about: This field is required: position/bonus points.
	End Rem
	Field scoring:TScoringSystem     ' required: position/bonus points
	Rem
	bbdoc: Ordered rules for separating equal series totals.
	about: Points, optionally followed by Wins or FinishCountback.
	End Rem
	Field tiebreakers:ETiebreaker[]  ' Points, optionally followed by Wins or FinishCountback
	Rem
	bbdoc: Number of back for this series configuration.
	End Rem
	Field countback:TSeriesCountbackConfig
	Rem
	bbdoc: Number of back sequence for this series configuration.
	about: Ordered fallback countback blocks.
	End Rem
	Field countbackSequence:TSeriesCountbackConfig[] ' ordered fallback countback blocks
	Rem
	bbdoc: Independent standings derived from shared event results.
	about: Independent standings from shared results.
	End Rem
	Field championships:TChampionshipConfig[] ' independent standings from shared results

	Method New()
		configType = EConfigType.Series
	End Method
End Type

Rem
bbdoc: One standings board derived from selected series sessions.
End Rem
Type TChampionshipConfig
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Session codes counted by this championship; empty includes every scoring session.
	End Rem
	Field sessionCodes:String[]
	Rem
	bbdoc: Scoring rules used instead of the series default.
	End Rem
	Field scoringOverride:TScoringSystem
	Rem
	bbdoc: Tiebreakers selected for this championship configuration.
	about: This field is optional: ranking rules for this championship.
	End Rem
	Field tiebreakers:ETiebreaker[] ' optional ranking rules for this championship
	Rem
	bbdoc: Whether standings include only the selected participant kind.
	End Rem
	Field filterByKind:Int { asBool }
	Rem
	bbdoc: Team or individual kind included when filtering is enabled.
	End Rem
	Field participantKind:EParticipantKind
	Rem
	bbdoc: Whether individual points are added to each participant's parent team.
	End Rem
	Field parentTeamPoints:Int { asBool }
	Rem
	bbdoc: Number of back for this championship configuration.
	about: Overrides the series countback policy.
	End Rem
	Field countback:TSeriesCountbackConfig ' overrides the series countback policy
	Rem
	bbdoc: Number of back sequence for this championship configuration.
	about: Overrides the series countback sequence.
	End Rem
	Field countbackSequence:TSeriesCountbackConfig[] ' overrides the series countback sequence
End Type

Rem
bbdoc: Finishing positions and sessions used to break a series points tie.
End Rem
Type TSeriesCountbackConfig
	Rem
	bbdoc: Positions values associated with this series countback configuration.
	about: Priority order; empty = first place, second place, and so on.
	End Rem
	Field positions:Int[] ' priority order; empty = first place, second place, and so on
	Rem
	bbdoc: Session codes values associated with this series countback configuration.
	about: An empty value means the championship's scoring sessions.
	End Rem
	Field sessionCodes:String[] ' empty = the championship's scoring sessions
End Type

Rem
bbdoc: One event with sessions and an optional points multiplier.
End Rem
Type TSeriesEvent
	Rem
	bbdoc: Stable identifier of this series event.
	End Rem
	Field id:String
	Rem
	bbdoc: Display name of this series event.
	End Rem
	Field name:String
	Rem
	bbdoc: #TSession entries associated with this series event.
	about: For example, , "Sprint", "Grand Prix".
	End Rem
	Field sessions:TSession[]        ' e.g., "Sprint", "Grand Prix"
	Rem
	bbdoc: Points multiplier for this series event.
	about: For example, 1.5 for Indy500.
	End Rem
	Field pointsMultiplier:Float = 1.0  ' e.g. 1.5 for Indy500
	Rem
	bbdoc: Decimal points multiplier that overrides #pointsMultiplier when set.
	about: The result must be representable by the series #TSeriesConfig.pointsScale.
	End Rem
	Field pointsMultiplierExact:String
End Type

Rem
bbdoc: A scoring session within an event, such as a sprint or race.
End Rem
Type TSession
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	about: "QUALI", "SPRINT", "RACE".
	End Rem
	Field code:String                ' "QUALI", "SPRINT", "RACE"
	Rem
	bbdoc: #TScoringSystem value used by this session.
	about: This field is optional: (sprint points differ).
	End Rem
	Field scoringOverride:TScoringSystem ' optional (sprint points differ)
	Rem
	bbdoc: Laps or duration of this session.
	about: Purely metadata.
	End Rem
	Field lapsOrDuration:String      ' purely metadata
End Type

' ---------- Scoring system ----------

' Generic scoring applied by a Stage (League, Group, or custom "Series")
Rem
bbdoc: Position points, bonuses, and aggregation rules for results.
End Rem
Type TScoringSystem
	Rem
	bbdoc: Mode used by this scoring system.
	End Rem
	Field mode:EScoringMode
	Rem
	bbdoc: #TPointsTableEntry entries associated with this scoring system.
	about: For position-based systems.
	End Rem
	Field table:TPointsTableEntry[]   ' for position-based systems
	Rem
	bbdoc: #TBonusRule entries associated with this scoring system.
	End Rem
	Field bonuses:TBonusRule[]
	Rem
	bbdoc: #TAggregation value used by this scoring system.
	about: How to compute standings across events/sessions.
	End Rem
	Field aggregation:TAggregation    ' how to compute standings across events/sessions
End Type

Rem
bbdoc: Football-style, position-table, or time-based scoring.
End Rem
Enum EScoringMode
    FootballPoints      ' use pointsWin/Draw/Loss from the stage config
    PositionTable       ' award by finishing position
    TimeBased           ' rank by total time (rally, stage race); points optional
End Enum

Rem
bbdoc: Points awarded for one finishing position.
End Rem
Type TPointsTableEntry
	Rem
	bbdoc: Finishing position receiving this points award.
	about: 1..N (use 0 for DNF/DSQ mapping if needed).
	End Rem
	Field position:Int        ' 1..N (use 0 for DNF/DSQ mapping if needed)
	Rem
	bbdoc: Points for this points table entry.
	End Rem
	Field points:Int
	Rem
	bbdoc: Decimal award that overrides #points when set.
	about: The series #TSeriesConfig.pointsScale must represent this value exactly.
	End Rem
	Field pointsExact:String
End Type

Rem
bbdoc: Eligibility and points for a named result award.
End Rem
Type TBonusRule
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	about: For example, "FASTEST_LAP", "POLE".
	End Rem
	Field code:String                 ' e.g. "FASTEST_LAP", "POLE"
	Rem
	bbdoc: Points for this bonus rule.
	about: Default points for this award.
	End Rem
	Field points:Int                  ' default points for this award
	Rem
	bbdoc: Upper bound per award used by clinching analysis when overrides are allowed.
	End Rem
	Field maxPointsPerAward:Int
	Rem
	bbdoc: Points exact of this bonus rule.
	End Rem
	Field pointsExact:String
	Rem
	bbdoc: Max points per award exact of this bonus rule.
	End Rem
	Field maxPointsPerAwardExact:String
	' Enable/where/limits
	Rem
	bbdoc: Session codes in which this bonus may be awarded.
	about: For example, ["RACE","SPRINT"] (empty = any).
	End Rem
	Field allowedSessions:String[]    ' e.g. ["RACE","SPRINT"] (empty = any)
	Rem
	bbdoc: Whether unique per session applies to this bonus rule.
	about: Only one award of this code per session?.
	End Rem
	Field uniquePerSession:Int {asBool}      ' only one award of this code per session?
	Rem
	bbdoc: Whether unique per event applies to this bonus rule.
	about: Only one across all sessions of the event?.
	End Rem
	Field uniquePerEvent:Int {asBool}        ' only one across all sessions of the event?
	Rem
	bbdoc: Whether unique per participant per event applies to this bonus rule.
	about: Participant can earn it at most once per event.
	End Rem
	Field uniquePerParticipantPerEvent:Int {asBool} ' participant can earn it at most once per event
	Rem
	bbdoc: Max awards per event for this bonus rule.
	about: Zero means unlimited, else cap.
	End Rem
	Field maxAwardsPerEvent:Int       ' 0 = unlimited, else cap
	' Eligibility (typed, no magic strings)
	Rem
	bbdoc: Whether the recipient must finish to receive this bonus.
	End Rem
	Field requireFinish:Int {asBool}
	Rem
	bbdoc: Highest permitted finishing-place number; zero removes the limit.
	about: Zero means none, else must be P <= N.
	End Rem
	Field minFinishPosition:Int       ' 0 = none, else must be P <= N
	' (optional future: completedLapsMin, class/category filters, etc.)
End Type

Rem
bbdoc: How session results contribute to cumulative standings.
End Rem
Type TAggregation
	Rem
	bbdoc: Leaderboard codes values associated with this aggregation.
	about: For example, ["drivers","constructors"].
	End Rem
	Field leaderboardCodes:String[]   ' e.g. ["drivers","constructors"]
	Rem
	bbdoc: Whether sum points applies to this aggregation.
	about: Default true.
	End Rem
	Field sumPoints:Int { asBool }    ' default true
	Rem
	bbdoc: Whether sum times applies to this aggregation.
	about: For time-based competitions.
	End Rem
	Field sumTimes:Int { asBool }     ' for time-based competitions
	Rem
	bbdoc: Drop worst for this aggregation.
	about: For example, , drop worst result(s).
	End Rem
	Field dropWorst:Int               ' e.g., drop worst result(s)
End Type

Rem
bbdoc: An administrative points change for a participant.
End Rem
Type TPointAdjustment
	Rem
	bbdoc: Scope of this point adjustment.
	about: "stage:regular" or "overall".
	End Rem
	Field scope:String         ' "stage:regular" or "overall"
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Points delta for this point adjustment.
	End Rem
	Field pointsDelta:Int
	Rem
	bbdoc: Points delta exact of this point adjustment.
	End Rem
	Field pointsDeltaExact:String
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: Saved classification and status for one event session.
End Rem
Type TSessionState
	Rem
	bbdoc: ID of the event associated with this session state.
	End Rem
	Field eventId:String
	Rem
	bbdoc: Session code of this session state.
	End Rem
	Field sessionCode:String
	Rem
	bbdoc: Current status of this session state.
	End Rem
	Field status:String
	Rem
	bbdoc: #TSessionResult entries associated with this session state.
	about: Ordered by finish position.
	End Rem
	Field classification:TSessionResult[]   ' ordered by finish position
End Type

Rem
bbdoc: One participant's place, time, points, and awards in a session.
End Rem
Type TSessionResult
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Position for this session result.
	End Rem
	Field position:Int
	Rem
	bbdoc: Time millis for this session result.
	End Rem
	Field timeMillis:Long
	Rem
	bbdoc: Points awarded for this session result.
	End Rem
	Field pointsAwarded:Int
	Rem
	bbdoc: #TResultAward entries associated with this session result.
	End Rem
	Field awards:TResultAward[]
	Rem
	bbdoc: Whether classified applies to this session result.
	about: DNF/DSQ flags as needed.
	End Rem
	Field classified:Int { asBool } ' DNF/DSQ flags as needed
End Type

Rem
bbdoc: A named bonus award recorded with a result.
End Rem
Type TResultAward
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	about: "FASTEST_LAP", "POLE", "MOST_LAPS_LED".
	End Rem
	Field code:String            ' "FASTEST_LAP", "POLE", "MOST_LAPS_LED"
	Rem
	bbdoc: ID of the associated participant.
	about: Who receives it.
	End Rem
	Field participantId:Int      ' who receives it
	Rem
	bbdoc: Points override for this result award.
	about: >0 overrides table; 0 = use default from TScoringSystem.
	End Rem
	Field pointsOverride:Int     ' >0 overrides table; 0 = use default from TScoringSystem
	Rem
	bbdoc: Points override exact of this result award.
	End Rem
	Field pointsOverrideExact:String
	Rem
	bbdoc: #TAwardConditions value used by this result award.
	about: Optional, for per-award conditions.
	End Rem
	Field conditions:TAwardConditions  ' optional, for per-award conditions
End Type

Rem
bbdoc: Additional finish conditions for a result award.
End Rem
Type TAwardConditions
	Rem
	bbdoc: Min finish position for this award conditions.
	about: Require P<=N in session classification (0 = no requirement).
	End Rem
	Field minFinishPosition:Int  ' require P<=N in session classification (0 = no requirement)
	Rem
	bbdoc: Whether a DNF or disqualification makes the participant ineligible.
	about: Disallow DNF/DSQ if true.
	End Rem
	Field mustFinish:Int { asBool }   ' disallow DNF/DSQ if true
	' consider other conditions (e.g., minClassPosition, completedLaps>=X, etc.)
End Type

Rem
bbdoc: Optional JSON container for entrants, divisions, and seeding overrides.
End Rem
Type TParticipantsFile
	Rem
	bbdoc: #TParticipant entries associated with this participants file.
	End Rem
	Field participants:TParticipant[]
	Rem
	bbdoc: #TDivision entries associated with this participants file.
	End Rem
	Field divisions:TDivision[]
	Rem
	bbdoc: #TSeedingOverride entries associated with this participants file.
	End Rem
	Field seedingOverrides:TSeedingOverride[]
End Type

Rem
bbdoc: A stage-specific entrant seeding policy.
End Rem
Type TSeedingOverride
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: #TSeedingPolicy value used by this seeding override.
	End Rem
	Field seeding:TSeedingPolicy
End Type


' ---------- Runtime state (simplified from our earlier proposal) ----------
Rem
bbdoc: Serializable fixtures, standings, and action journal for a competition.
about: Results normally update this object in place. Correction, sporting tie decisions, and schedule revision return a replacement state that the caller must keep.
End Rem
Type TCompetitionState
	Rem
	bbdoc: Competition name of this competition state.
	End Rem
	Field competitionName:String
	Rem
	bbdoc: Playing state of each competition stage.
	End Rem
	Field stages:TStageState[]
	Rem
	bbdoc: Snapshot from immediately before the first journalled action.
	about: The correction replayer uses this snapshot as the starting point for rebuilding state.
	End Rem
	Field replayBaseJson:String
	Rem
	bbdoc: Replay seed for this competition state.
	End Rem
	Field replaySeed:Int
	Rem
	bbdoc: Results, schedule revisions, and tie decisions in replay order.
	End Rem
	Field actions:TRecordedAction[]
End Type

Rem
bbdoc: A saved result, schedule revision, or tie decision in replay order.
about: The engine writes these actions for correction replay. Applications should record results and revisions through engine methods rather than editing this journal directly.
End Rem
Type TRecordedAction
	Rem
	bbdoc: Action type selected for this recorded action.
	End Rem
	Field actionType:ERecordedActionType
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Kind of this recorded action.
	End Rem
	Field kind:EResultKind
	Rem
	bbdoc: Payload json of this recorded action.
	End Rem
	Field payloadJson:String
	Rem
	bbdoc: ID of the home team associated with this recorded action.
	End Rem
	Field homeTeamId:Int
	Rem
	bbdoc: ID of the away team associated with this recorded action.
	End Rem
	Field awayTeamId:Int
	Rem
	bbdoc: Entrant IDs associated with this recorded action.
	End Rem
	Field entrantIds:Int[]
	Rem
	bbdoc: IDs of the associated participants.
	End Rem
	Field participantIds:Int[]
	Rem
	bbdoc: Heat entrants values associated with this recorded action.
	End Rem
	Field heatEntrants:Int[]
	Rem
	bbdoc: Key identifying the associated group.
	End Rem
	Field groupKey:String
	Rem
	bbdoc: ID of the series event associated with this recorded action.
	End Rem
	Field seriesEventId:String
	Rem
	bbdoc: Session code of this recorded action.
	End Rem
	Field sessionCode:String
	Rem
	bbdoc: ID of the associated calendar or draw slot.
	End Rem
	Field slotId:String
	Rem
	bbdoc: Round for this recorded action.
	End Rem
	Field round:Int
	Rem
	bbdoc: Whether replan flexible applies to this recorded action.
	End Rem
	Field replanFlexible:Int { asBool }
	Rem
	bbdoc: Scope key of this recorded action.
	End Rem
	Field scopeKey:String
	Rem
	bbdoc: Decision order values associated with this recorded action.
	End Rem
	Field decisionOrder:Int[]
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: Kinds of actions in the correction journal.
End Rem
Enum ERecordedActionType
    Result
    ScheduleRevision
    TableTieDecision
End Enum

Rem
bbdoc: An official best-to-worst order for an otherwise unresolved sporting tie.
End Rem
Type TTableTieDecision
	Rem
	bbdoc: Scope key of this table tie decision.
	about: Empty for the overall table; group key for a group table.
	End Rem
	Field scopeKey:String ' empty for the overall table; group key for a group table
	Rem
	bbdoc: IDs of the associated participants.
	about: Exact tied set in decided best-to-worst order.
	End Rem
	Field participantIds:Int[] ' exact tied set in decided best-to-worst order
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

' A read-only description of a tied set that may be decided. The current row
' order is for display only; pass the desired order to RecordTableTieDecision.
Rem
bbdoc: A tied participant set awaiting an official ordering.
End Rem
Type TUnresolvedTableTie
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: Scope key of this unresolved table tie.
	End Rem
	Field scopeKey:String
	Rem
	bbdoc: IDs of the associated participants.
	End Rem
	Field participantIds:Int[]
End Type

Rem
bbdoc: A replayed action that could not be retained after a correction.
End Rem
Type TResultInvalidation
	Rem
	bbdoc: #TRecordedAction value used by this result invalidation.
	End Rem
	Field action:TRecordedAction
	Rem
	bbdoc: Explanation recorded for this decision or adjustment.
	End Rem
	Field reason:String
End Type

Rem
bbdoc: The replacement state and invalidated actions after result correction.
End Rem
Type TResultCorrection
	Rem
	bbdoc: #TCompetitionState value used by this result correction.
	End Rem
	Field state:TCompetitionState
	Rem
	bbdoc: #TResultInvalidation entries associated with this result correction.
	End Rem
	Field invalidated:TResultInvalidation[]
End Type

' Entrants delivered by a completed source stage. Persisted so a competition can
' be saved while several branches are still waiting to join.
Rem
bbdoc: Entrants and draw positions delivered by a completed source stage.
End Rem
Type TStageInputState
	Rem
	bbdoc: ID of the source stage.
	End Rem
	Field sourceStageId:String
	Rem
	bbdoc: Entrant IDs associated with this stage input state.
	End Rem
	Field entrantIds:Int[]
	Rem
	bbdoc: Slot IDs associated with this stage input state.
	about: This field is optional: draw slots, aligned with entrantIds.
	End Rem
	Field slotIds:String[]         ' optional draw slots, aligned with entrantIds
	Rem
	bbdoc: Whether reseed applies to this stage input state.
	about: Explicit Seeded route.
	End Rem
	Field reseed:Int { asBool }    ' explicit Seeded route
	Rem
	bbdoc: Seed ranks values associated with this stage input state.
	about: Stage-specific seeds aligned with entrantIds.
	End Rem
	Field seedRanks:Int[]          ' stage-specific seeds aligned with entrantIds
End Type

Rem
bbdoc: Ranked rows for one group within a stage.
End Rem
Type TGroupTable
	Rem
	bbdoc: Key of this group table.
	about: For example, "G1", "G2".
	End Rem
	Field key:String                 ' e.g. "G1", "G2"
	Rem
	bbdoc: #TLeaderboardRow entries associated with this group table.
	about: Sorted standings for that group.
	End Rem
	Field rows:TLeaderboardRow[]     ' sorted standings for that group
End Type

Rem
bbdoc: Fixtures, standings, entrants, and format-specific state for one stage.
End Rem
Type TStageState
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: #TTableTieDecision entries associated with this stage state.
	End Rem
	Field tableTieDecisions:TTableTieDecision[]
	Rem
	bbdoc: Fixtures generated for this stage and updated as results arrive.
	End Rem
	Field fixtures:TFixtureState[]
	Rem
	bbdoc: Main standings table computed by the stage scorer.
	about: Updated by scorer.
	End Rem
	Field leaderboard:TLeaderboard   ' updated by scorer
	Rem
	bbdoc: Named standings tables derived from shared results.
	End Rem
	Field championships:TNamedLeaderboard[]
	Rem
	bbdoc: Pending, running, complete, or skipped status of this stage.
	End Rem
	Field status:EStageStatus
	Rem
	bbdoc: Administrative point changes applied to this stage.
	about: Admin deltas recorded here.
	End Rem
	Field adjustments:TPointAdjustment[] ' admin deltas recorded here
	Rem
	bbdoc: Participant IDs admitted to this stage.
	about: Who is allowed in this stage.
	End Rem
	Field entrants:Int[]           ' who is allowed in this stage
	Rem
	bbdoc: #TStageInputState entries associated with this stage state.
	about: Contributions from predecessor stages.
	End Rem
	Field inputs:TStageInputState[] ' contributions from predecessor stages
	Rem
	bbdoc: Bracket bye positions values associated with this stage state.
	about: First-round match positions with a bye.
	End Rem
	Field bracketByePositions:Int[] ' first-round match positions with a bye
	Rem
	bbdoc: Bracket bye entrants values associated with this stage state.
	about: Entrants advancing from those positions.
	End Rem
	Field bracketByeEntrants:Int[]  ' entrants advancing from those positions
	Rem
	bbdoc: Separate standings tables for each group.
	about: Per-group standings.
	End Rem
	Field groups:TGroupTable[]       ' per-group standings
	Rem
	bbdoc: #TStrokeStanding entries associated with this stage state.
	End Rem
	Field strokeStandings:TStrokeStanding[]
	Rem
	bbdoc: ID of the stroke play winner associated with this stage state.
	End Rem
	Field strokePlayWinnerId:Int
	Rem
	bbdoc: #TRegattaStanding entries associated with this stage state.
	End Rem
	Field regattaStandings:TRegattaStanding[]
	Rem
	bbdoc: #TCyclingStanding entries associated with this stage state.
	End Rem
	Field cyclingStandings:TCyclingStanding[]
	Rem
	bbdoc: #TCyclingTeamStanding entries associated with this stage state.
	End Rem
	Field cyclingTeamStandings:TCyclingTeamStanding[]
End Type

Rem
bbdoc: A named championship table derived from shared results.
End Rem
Type TNamedLeaderboard
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: #TLeaderboard value used by this named leaderboard.
	End Rem
	Field leaderboard:TLeaderboard
End Type

Rem
bbdoc: Pending, running, complete, and skipped stage states.
End Rem
Enum EStageStatus
	Rem
	bbdoc: Waiting for sources or an activation condition.
	End Rem
	Pending
	Rem
	bbdoc: Fixtures have been created and may receive results.
	End Rem
	Running
	Rem
	bbdoc: The stage has finished according to its scorer.
	End Rem
	Complete
	Rem
	bbdoc: The activation condition was not met.
	End Rem
	Skipped
End Enum

Rem
bbdoc: A scheduled fixture and its recorded result in the playing state.
about: Format-specific fields store scores, classifications, scorecards, race results, or timed results. The fixture ID is the stable key used when recording and correcting a result.
End Rem
Type TFixtureState
	Rem
	bbdoc: Stable fixture ID used when recording or correcting its result.
	End Rem
	Field id:String
	Rem
	bbdoc: Round in which this fixture is played.
	End Rem
	Field round:Int
	Rem
	bbdoc: Heat entrants values associated with this fixture state.
	End Rem
	Field heatEntrants:Int[]
	Rem
	bbdoc: IDs of the associated participants.
	about: Entrants in a multi-participant round.
	End Rem
	Field participantIds:Int[] ' entrants in a multi-participant round
	Rem
	bbdoc: #THeatLaneAssignment entries associated with this fixture state.
	End Rem
	Field heatLanes:THeatLaneAssignment[]
	Rem
	bbdoc: Heat phase selected for this fixture state.
	End Rem
	Field heatPhase:EHeatPhase
	Rem
	bbdoc: Index of the heat rule for this fixture state.
	about: One-based qualifyingRounds index; same for a repechage.
	End Rem
	Field heatRuleIndex:Int ' one-based qualifyingRounds index; same for a repechage
	Rem
	bbdoc: Leg for this fixture state.
	End Rem
	Field leg:Int
	Rem
	bbdoc: Bracket position for this fixture state.
	about: First-round match position in a fixed bracket.
	End Rem
	Field bracketPosition:Int      ' first-round match position in a fixed bracket
	Rem
	bbdoc: Participant ID assigned to the home side.
	End Rem
	Field homeTeamId:Int
	Rem
	bbdoc: Participant ID assigned to the away side.
	End Rem
	Field awayTeamId:Int
	Rem
	bbdoc: Swiss unplayed kind selected for this fixture state.
	End Rem
	Field swissUnplayedKind:ESwissUnplayedKind
	Rem
	bbdoc: Swiss awarded units in the configured integer scale.
	End Rem
	Field swissAwardedUnits:Int
	Rem
	bbdoc: Playing status of this fixture.
	End Rem
	Field status:EFixtureStatus
	Rem
	bbdoc: Assigned calendar slot ID, or empty while unslotted.
	End Rem
	Field slotId:String
	Rem
	bbdoc: ID of the associated venue.
	End Rem
	Field venueId:String
	Rem
	bbdoc: Recorded score of the home side.
	End Rem
	Field scoreHome:Int
	Rem
	bbdoc: Recorded score of the away side.
	End Rem
	Field scoreAway:Int
	Rem
	bbdoc: Fair play home for this fixture state.
	about: Nonnegative disciplinary penalty units; lower ranks first.
	End Rem
	Field fairPlayHome:Int ' nonnegative disciplinary penalty units; lower ranks first
	Rem
	bbdoc: Fair play away for this fixture state.
	End Rem
	Field fairPlayAway:Int
	Rem
	bbdoc: Whether after extra time applies to this fixture state.
	End Rem
	Field afterExtraTime:Int { asBool }
	Rem
	bbdoc: Penalties home for this fixture state.
	End Rem
	Field penaltiesHome:Int
	Rem
	bbdoc: Penalties away for this fixture state.
	End Rem
	Field penaltiesAway:Int
	Rem
	bbdoc: Key identifying the associated group.
	End Rem
	Field groupKey:String
	Rem
	bbdoc: ID of the series event associated with this fixture state.
	about: For example, "E1".
	End Rem
	Field seriesEventId:String   ' e.g. "E1"
	Rem
	bbdoc: Session code of this fixture state.
	about: For example, "SPRINT", "RACE".
	End Rem
	Field sessionCode:String     ' e.g. "SPRINT", "RACE"

	Rem
	bbdoc: #TSetScore entries associated with this fixture state.
	about: Per-set results.
	End Rem
	Field setResults:TSetScore[]        ' per-set results
	Rem
	bbdoc: ID of the retired participant associated with this fixture state.
	about: Set match retirement; winner is the opponent.
	End Rem
	Field retiredParticipantId:Int      ' set match retirement; winner is the opponent
	Rem
	bbdoc: ID of the winner override associated with this fixture state.
	about: Adjudicated winner for a set match ending early.
	End Rem
	Field winnerOverrideId:Int          ' adjudicated winner for a set match ending early
	Rem
	bbdoc: Participant IDs in finishing order.
	about: Ordered participant IDs.
	End Rem
	Field classificationOrder:Int[]     ' ordered participant IDs
	Rem
	bbdoc: #TFinishStatus entries associated with this fixture state.
	End Rem
	Field finishStatuses:TFinishStatus[]
	Rem
	bbdoc: #TParticipantTime entries associated with this fixture state.
	about: Per-participant times.
	End Rem
	Field timeResults:TParticipantTime[] ' per-participant times
	Rem
	bbdoc: #TResultAward entries associated with this fixture state.
	about: Structured awards.
	End Rem
	Field awards:TResultAward[] ' structured awards

	Rem
	bbdoc: Result payloads recorded for this fixture.
	End Rem
	Field resultLog:TResultPayload[]
	Rem
	bbdoc: #TStrokeScorecard entries associated with this fixture state.
	End Rem
	Field strokeCards:TStrokeScorecard[]
	Rem
	bbdoc: #TRegattaRaceScore entries associated with this fixture state.
	End Rem
	Field regattaScores:TRegattaRaceScore[]
	Rem
	bbdoc: #TCyclingRiderResult entries associated with this fixture state.
	End Rem
	Field cyclingResults:TCyclingRiderResult[]
	Rem
	bbdoc: #TCyclingCheckpointResult entries associated with this fixture state.
	End Rem
	Field cyclingCheckpoints:TCyclingCheckpointResult[]
	Rem
	bbdoc: #TCyclingPointAdjustment entries associated with this fixture state.
	End Rem
	Field cyclingAdjustments:TCyclingPointAdjustment[]
	Rem
	bbdoc: #TCyclingTeamAdjustment entries associated with this fixture state.
	End Rem
	Field cyclingTeamAdjustments:TCyclingTeamAdjustment[]
End Type

Rem
bbdoc: Scheduling and completion states of a fixture.
End Rem
Enum EFixtureStatus
	Rem
	bbdoc: Created and awaiting a result.
	End Rem
    Scheduled
	Rem
	bbdoc: Started but not yet completed.
	End Rem
    InProgress
	Rem
	bbdoc: Finished with a valid result.
	End Rem
    Completed
	Rem
	bbdoc: Delayed for later scheduling or play.
	End Rem
    Postponed
	Rem
	bbdoc: Stopped after starting without a valid result.
	End Rem
    Abandoned
	Rem
	bbdoc: Voided without play or rescheduling.
	End Rem
    Cancelled
	Rem
	bbdoc: Awarded to a side without normal play.
	End Rem
    Forfeit
End Enum

' Legacy Swiss state declarations retained for source compatibility. The
' built-in scheduler uses TStageState.fixtures as its persisted history.
Rem
bbdoc: Legacy Swiss-specific state retained for source compatibility.
about: The built-in Swiss scheduler uses #TStageState.fixtures as its persisted pairing history.
End Rem
Type TSwissState Extends TStageState
	Rem
	bbdoc: Current round for this swiss state.
	End Rem
	Field currentRound:Int
	Rem
	bbdoc: #TPairHistory entries associated with this swiss state.
	End Rem
	Field pairHistory:TPairHistory[]
	Rem
	bbdoc: #TSwissBalance entries associated with this swiss state.
	End Rem
	Field colourBalance:TSwissBalance[]
	Rem
	bbdoc: #TSwissBye entries associated with this swiss state.
	End Rem
	Field byeHistory:TSwissBye[]
	Rem
	bbdoc: #TOpponentRecord[] entries associated with this swiss state.
	End Rem
	Field opponentHistory:TOpponentRecord[][]
End Type

Rem
bbdoc: Legacy colour-balance record for a Swiss entrant.
End Rem
Type TSwissBalance
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:String
	Rem
	bbdoc: Balance for this swiss balance.
	End Rem
	Field balance:Int
End Type

Rem
bbdoc: Legacy Swiss bye count for an entrant.
End Rem
Type TSwissBye
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:String
	Rem
	bbdoc: Byes for this swiss bye.
	End Rem
	Field byes:Int
End Type

Rem
bbdoc: Legacy record of an opponent and round in Swiss state.
End Rem
Type TOpponentRecord
	Rem
	bbdoc: ID of the opponent associated with this opponent record.
	End Rem
	Field opponentId:String
	Rem
	bbdoc: Round for this opponent record.
	End Rem
	Field round:Int
End Type

Rem
bbdoc: Legacy Swiss pairing history for one round.
End Rem
Type TPairHistory
	Rem
	bbdoc: Round for this pair history.
	End Rem
	Field round:Int
	Rem
	bbdoc: A of this pair history.
	End Rem
	Field a:String
	Rem
	bbdoc: B of this pair history.
	End Rem
	Field b:String
End Type

Rem
bbdoc: Ranked standings rows for a stage or championship.
End Rem
Type TLeaderboard
	Rem
	bbdoc: #TLeaderboardRow entries associated with this leaderboard.
	End Rem
	Field rows:TLeaderboardRow[]
End Type

Rem
bbdoc: One entrant's standing and scorer-specific ranking metrics.
about: Equal `sportingRank` values indicate a tie left unresolved by the configured sporting criteria. The row array may still have a stable display order.
End Rem
Type TLeaderboardRow
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Shared rank for rows still tied after all configured criteria.
	about: Equal for an unresolved tie after all configured criteria.
	End Rem
	Field sportingRank:Int ' equal for an unresolved tie after all configured criteria
	Rem
	bbdoc: Points for this leaderboard row.
	End Rem
	Field points:Int
	Rem
	bbdoc: Time seconds measured in seconds.
	about: This field is optional: exact time total for time-classified stages.
	End Rem
	Field timeSeconds:Long ' optional exact time total for time-classified stages
	Rem
	bbdoc: #TLeaderboardMetric entries associated with this leaderboard row.
	about: Named, exact integer metrics in the scorer's scale.
	End Rem
	Field metrics:TLeaderboardMetric[] ' named, exact integer metrics in the scorer's scale
	Rem
	bbdoc: Number of wins in the standings period.
	End Rem
	Field wins:Int
	Rem
	bbdoc: Number of draws in the standings period.
	End Rem
	Field draws:Int
	Rem
	bbdoc: Number of losses in the standings period.
	End Rem
	Field losses:Int
	Rem
	bbdoc: No results for this leaderboard row.
	End Rem
	Field noResults:Int
	Rem
	bbdoc: Net rate for this leaderboard row.
	End Rem
	Field netRate:Double
	Rem
	bbdoc: Goals or score recorded for the participant.
	End Rem
	Field gf:Int
	Rem
	bbdoc: Goals or score conceded by the participant.
	End Rem
	Field ga:Int
End Type

Rem
bbdoc: A named exact integer metric used by a scorer.
End Rem
Type TLeaderboardMetric
	Rem
	bbdoc: Code identifying this item within its containing configuration.
	End Rem
	Field code:String
	Rem
	bbdoc: Value for this leaderboard metric.
	End Rem
	Field value:Int
End Type

Rem
bbdoc: Indexed participant attributes and avoid-pair matrix for draw searches.
End Rem
Type TDrawIndex
	Rem
	bbdoc: Pids values associated with this draw index.
	about: Order-aligned with participants[].
	End Rem
	Field pids:Int[]            ' order-aligned with participants[]
	Rem
	bbdoc: Regions values associated with this draw index.
	about: Unique region values.
	End Rem
	Field regions:String[]      ' unique region values
	Rem
	bbdoc: Divisions values associated with this draw index.
	about: Unique divisionId values.
	End Rem
	Field divisions:String[]    ' unique divisionId values
	Rem
	bbdoc: Pots values associated with this draw index.
	about: Unique drawPot values.
	End Rem
	Field pots:String[]         ' unique drawPot values
	Rem
	bbdoc: Region idx values associated with this draw index.
	about: Per participant index -> region index (-1 if none).
	End Rem
	Field regionIdx:Int[]       ' per participant index -> region index (-1 if none)
	Rem
	bbdoc: Division idx values associated with this draw index.
	about: Per participant index -> division index (-1 if none).
	End Rem
	Field divisionIdx:Int[]     ' per participant index -> division index (-1 if none)
	Rem
	bbdoc: Pot idx values associated with this draw index.
	about: Per participant index -> pot index (-1 if none).
	End Rem
	Field potIdx:Int[]          ' per participant index -> pot index (-1 if none)
	Rem
	bbdoc: Avoid values associated with this draw index.
	about: [n][n] 1 if pair must be avoided.
	End Rem
	Field avoid:Int[][]        ' [n][n] 1 if pair must be avoided
End Type

' Two-leg tie resolution (aggregate + optional away-goals + ET + pens).
Rem
bbdoc: Home, away, extra-time, and penalty result for one leg of a tie.
End Rem
Type TLeg
	Rem
	bbdoc: ID of the home associated with this leg.
	End Rem
	Field homeId:Int
	Rem
	bbdoc: ID of the away associated with this leg.
	End Rem
	Field awayId:Int
	Rem
	bbdoc: Home for this leg.
	End Rem
	Field home:Int
	Rem
	bbdoc: Away for this leg.
	End Rem
	Field away:Int
	Rem
	bbdoc: Whether after et applies to this leg.
	End Rem
	Field afterET:Int {asBool}
	Rem
	bbdoc: Pens home for this leg.
	End Rem
	Field pensHome:Int
	Rem
	bbdoc: Pens away for this leg.
	End Rem
	Field pensAway:Int
End Type

Rem
bbdoc: A participant's adjusted time and finishing status.
End Rem
Type TTimedRank
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Adjusted millis for this timed rank.
	End Rem
	Field adjustedMillis:Long
	Rem
	bbdoc: Current status of this timed rank.
	End Rem
	Field status:ETimeStatus
End Type

Rem
bbdoc: The payload shape and scorer path for a recorded result.
End Rem
Enum EResultKind
	Rem
	bbdoc: A home-versus-away score, with optional extra time or penalties.
	End Rem
    HeadToHeadScore     ' football/basketball/hockey etc.
	Rem
	bbdoc: Set scores, retirement, or an adjudicated set-match winner.
	End Rem
    SetBased            ' tennis/volleyball/esports maps
	Rem
	bbdoc: An ordered finish classification and optional awards.
	End Rem
    Classification      ' motorsport/golf/athletics
	Rem
	bbdoc: Participant times and penalties.
	End Rem
    TimeBased           ' rally/stage races; lowest total time wins
	Rem
	bbdoc: An administrative change to standings points.
	End Rem
    AdminAdjustment     ' point/sanction adjustments
	Rem
	bbdoc: A fixture postponement, cancellation, abandonment, or forfeit.
	End Rem
    StatusOnly          ' postponed/abandoned/walkover etc.
	Rem
	bbdoc: A payload interpreted by a registered custom scorer.
	End Rem
    Custom              ' interpreted by a registered custom scorer
End Enum

' Limited-overs innings are kept as typed result data for serialization.
Rem
bbdoc: Win, tie, or no-result outcome of a limited-overs cricket match.
End Rem
Enum ECricketOutcome
	Win
	Tie
	NoResult
End Enum

Rem
bbdoc: Runs, wickets, and legal or credited balls for one innings.
End Rem
Type TCricketInnings
	Rem
	bbdoc: ID of the associated team.
	End Rem
	Field teamId:Int
	Rem
	bbdoc: Runs for this cricket innings.
	End Rem
	Field runs:Int
	Rem
	bbdoc: Wickets for this cricket innings.
	End Rem
	Field wickets:Int
	Rem
	bbdoc: Legal balls for this cricket innings.
	End Rem
	Field legalBalls:Int
	Rem
	bbdoc: Allocated balls for this cricket innings.
	End Rem
	Field allocatedBalls:Int
	Rem
	bbdoc: Credited runs for this cricket innings.
	End Rem
	Field creditedRuns:Int
	Rem
	bbdoc: Credited balls for this cricket innings.
	End Rem
	Field creditedBalls:Int
End Type

Rem
bbdoc: Two innings and the adjudicated limited-overs outcome.
End Rem
Type TCricketMatchResult
	Rem
	bbdoc: Outcome selected for this cricket match result.
	End Rem
	Field outcome:ECricketOutcome
	Rem
	bbdoc: ID of the winner associated with this cricket match result.
	End Rem
	Field winnerId:Int
	Rem
	bbdoc: #TCricketInnings value used by this cricket match result.
	End Rem
	Field first:TCricketInnings
	Rem
	bbdoc: #TCricketInnings value used by this cricket match result.
	End Rem
	Field second:TCricketInnings
	Rem
	bbdoc: Revised target for this cricket match result.
	End Rem
	Field revisedTarget:Int
	Rem
	bbdoc: Method of this cricket match result.
	End Rem
	Field method:String
End Type

Rem
bbdoc: Typed result submitted to #TCompetitionEngine.RecordResult.
about: Set `kind` to select the relevant fields. A custom result uses `customCode` and a registered scorer; custom payloads also need a journal converter if they must survive correction replay.
End Rem
Type TResultPayload
	Rem
	bbdoc: Result kind that selects which payload fields the scorer reads.
	End Rem
	Field kind:EResultKind
	Rem
	bbdoc: Custom result code understood by a registered format scorer.
	End Rem
	Field customCode:String
	Rem
	bbdoc: Optional sport-specific result data.
	about: Register a compatible journal converter if this object must survive result correction replay.
	End Rem
	Field meta:Object
	Rem
	bbdoc: #TCricketMatchResult value used by this result payload.
	End Rem
	Field cricket:TCricketMatchResult
	Rem
	bbdoc: Player scorecards submitted for a stroke-play round.
	End Rem
	Field strokeCards:TStrokeScorecard[]
	Rem
	bbdoc: Competitor scores submitted for a regatta race.
	End Rem
	Field regattaScores:TRegattaRaceScore[]
	Rem
	bbdoc: Rider results submitted for a cycling stage.
	End Rem
	Field cyclingResults:TCyclingRiderResult[]
	Rem
	bbdoc: #TCyclingCheckpointResult entries associated with this result payload.
	End Rem
	Field cyclingCheckpoints:TCyclingCheckpointResult[]
	Rem
	bbdoc: Signed cycling points adjustments submitted with this result.
	End Rem
	Field cyclingAdjustments:TCyclingPointAdjustment[]
	Rem
	bbdoc: Signed cycling team-time adjustments submitted with this result.
	End Rem
	Field cyclingTeamAdjustments:TCyclingTeamAdjustment[]

	' ---- HeadToHeadScore ----
	Rem
	bbdoc: Home-side score for a head-to-head result.
	End Rem
	Field scoreHome:Int
	Rem
	bbdoc: Away-side score for a head-to-head result.
	End Rem
	Field scoreAway:Int
	Rem
	bbdoc: Fair play home for this result payload.
	End Rem
	Field fairPlayHome:Int
	Rem
	bbdoc: Fair play away for this result payload.
	End Rem
	Field fairPlayAway:Int
	Rem
	bbdoc: Whether the score followed extra time.
	End Rem
	Field afterExtraTime:Int {asBool}
	Rem
	bbdoc: Penalties home for this result payload.
	End Rem
	Field penaltiesHome:Int
	Rem
	bbdoc: Penalties away for this result payload.
	End Rem
	Field penaltiesAway:Int
	Rem
	bbdoc: Whether the head-to-head result was awarded by forfeit.
	End Rem
	Field forfeit:Int {asBool}
	Rem
	bbdoc: Whether disqualification affected the result.
	End Rem
	Field disqualification:Int {asBool}

	' ---- SetBased ----
	Rem
	bbdoc: #TSetScore entries associated with this result payload.
	about: For example, , [{home:6,away:4},{home:3,away:6},{home:7,away:6}].
	End Rem
	Field sets:TSetScore[]        ' e.g., [{home:6,away:4},{home:3,away:6},{home:7,away:6}]
	Rem
	bbdoc: ID of the retired participant associated with this result payload.
	about: Set match only; 0 means play completed normally.
	End Rem
	Field retiredParticipantId:Int ' set match only; 0 means play completed normally
	Rem
	bbdoc: Maps won home for this result payload.
	about: This field is optional: shortcut for esports.
	End Rem
	Field mapsWonHome:Int         ' optional shortcut for esports
	Rem
	bbdoc: Maps won away for this result payload.
	End Rem
	Field mapsWonAway:Int

	' ---- Classification ----
	Rem
	bbdoc: Participant IDs in classification finishing order.
	about: Participant IDs in finishing order.
	End Rem
	Field order:Int[]             ' participant IDs in finishing order
	Rem
	bbdoc: #TFinishStatus entries associated with this result payload.
	about: This field is optional: parallel array for DNF/DNS/DSQ etc.
	End Rem
	Field statuses:TFinishStatus[] ' optional parallel array for DNF/DNS/DSQ etc.
	Rem
	bbdoc: #TResultAward entries associated with this result payload.
	End Rem
	Field awards:TResultAward[]

	' ---- TimeBased ----
	Rem
	bbdoc: Per-participant times for a time-based result.
	about: Per participant times/penalties.
	End Rem
	Field times:TParticipantTime[] ' per participant times/penalties

	' ---- AdminAdjustment ----
	Rem
	bbdoc: Administrative point adjustments submitted with this result.
	about: Reuse your state type.
	End Rem
	Field adjustments:TPointAdjustment[] ' reuse your state type

	' ---- StatusOnly ----
	Rem
	bbdoc: Status code selected for this result payload.
	about: "postponed","abandoned","cancelled","walkover".
	End Rem
	Field statusCode:EFixtureStatus       ' "postponed","abandoned","cancelled","walkover"
End Type

Rem
bbdoc: Classification status such as finish, DNF, DNS, or disqualification.
End Rem
Enum EFinishFlag
    OK
    DNF
    DNS
    DSQ
End Enum

Rem
bbdoc: Games or points won by both sides in one set.
End Rem
Type TSetScore
	Rem
	bbdoc: Home for this set score.
	End Rem
	Field home:Int
	Rem
	bbdoc: Away for this set score.
	End Rem
	Field away:Int
End Type

Rem
bbdoc: One participant's classification flag and laps down.
End Rem
Type TFinishStatus
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Flag selected for this finish status.
	End Rem
	Field flag:EFinishFlag
	Rem
	bbdoc: Laps down for this finish status.
	End Rem
	Field lapsDown:Int
End Type

Rem
bbdoc: Elapsed time, penalty, place, and status for a timed entrant.
End Rem
Type TParticipantTime
	Rem
	bbdoc: ID of the associated participant.
	End Rem
	Field participantId:Int
	Rem
	bbdoc: Millis for this participant time.
	End Rem
	Field millis:Long
	Rem
	bbdoc: Penalty millis for this participant time.
	End Rem
	Field penaltyMillis:Long
	Rem
	bbdoc: Place for this participant time.
	about: This field is optional: official place within a timed heat or final.
	End Rem
	Field place:Int ' optional official place within a timed heat or final
	Rem
	bbdoc: Current status of this participant time.
	End Rem
	Field status:ETimeStatus = ETimeStatus.Finished
End Type

Rem
bbdoc: Finish, DNF, DNS, or disqualification status for a timed result.
End Rem
Enum ETimeStatus
    Finished
    DNF        ' did not finish
    DSQ        ' disqualified
    DNS        ' did not start (optional)
End Enum

Rem
bbdoc: Definition-time opponent pairing and round.
End Rem
Type TFixture
	Rem
	bbdoc: Round for this fixture.
	End Rem
	Field round:Int
	Rem
	bbdoc: Leg for this fixture.
	about: One means first leg (for double RR), 2 = second leg.
	End Rem
	Field leg:Int            ' 1 = first leg (for double RR), 2 = second leg
	Rem
	bbdoc: ID of the home team associated with this fixture.
	End Rem
	Field homeTeamId:Int
	Rem
	bbdoc: ID of the away team associated with this fixture.
	End Rem
	Field awayTeamId:Int
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
End Type

' ---------- Playable fixture (for scheduling/presentation) ----------
Rem
bbdoc: Presentation-ready fixture with assigned teams, names, and slot time.
End Rem
Type TPlayableFixture
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: ID of the associated fixture.
	End Rem
	Field fixtureId:String
	Rem
	bbdoc: Round for this playable fixture.
	End Rem
	Field round:Int
	Rem
	bbdoc: ID of the group associated with this playable fixture.
	about: "" if not grouped.
	End Rem
	Field groupId:String          ' "" if not grouped
	Rem
	bbdoc: ID of the home associated with this playable fixture.
	End Rem
	Field homeId:Int
	Rem
	bbdoc: ID of the away associated with this playable fixture.
	End Rem
	Field awayId:Int
	Rem
	bbdoc: Home of this playable fixture.
	about: Team/participant name.
	End Rem
	Field home:String             ' team/participant name
	Rem
	bbdoc: Away of this playable fixture.
	End Rem
	Field away:String
	Rem
	bbdoc: Current status of this playable fixture.
	End Rem
	Field status:EFixtureStatus
	Rem
	bbdoc: ID of the associated calendar or draw slot.
	about: "" if unslotted.
	End Rem
	Field slotId:String           ' "" if unslotted
	Rem
	bbdoc: Slot time for this playable fixture.
	about: Epoch millis or 0 if n/a.
	End Rem
	Field slotTime:Long           ' epoch millis or 0 if n/a
End Type

Rem
bbdoc: Filters and ordering options when retrieving playable fixtures.
End Rem
Type TPlayableQuery
	Rem
	bbdoc: ID of the associated stage.
	about: This field is optional: restrict to a stage.
	End Rem
	Field stageId:String          ' optional: restrict to a stage
	Rem
	bbdoc: Whether postponed fixtures may appear in the query result.
	about: Default 0 -> exclude Postponed.
	End Rem
	Field includePostponed:Int    ' default 0 -> exclude Postponed
	Rem
	bbdoc: Whether to require a slot time no later than the current time.
	about: Default 0 -> ignore times; if 1, require slotTime>0 and slotTime <= now.
	End Rem
	Field onlyCurrentlyDue:Int    ' default 0 -> ignore times; if 1, require slotTime>0 and slotTime <= now
	Rem
	bbdoc: Whether to skip fixtures with unknown participants or byes.
	about: Default 1 -> skip TBD / byes.
	End Rem
	Field requireAssignedTeams:Int = 1 ' default 1 -> skip TBD / byes
	Rem
	bbdoc: Whether to alternate fixtures from different groups.
	about: 1=on (default), 0=off.
	End Rem
	Field interleaveAcrossGroups:Int = 1 ' 1=on (default), 0=off
	Rem
	bbdoc: Maximum number of fixtures returned; zero removes the limit.
	about: Zero means no limit.
	End Rem
	Field limit:Int               ' 0 = no limit
End Type
