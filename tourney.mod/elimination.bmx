' Builds an explicit stage graph for a knockout tree. The resulting stages use
' the ordinary bracket scheduler, scorer, and winner/loser advancement routes.
Rem
bbdoc: Single- or double-elimination tree structure.
End Rem
Enum EEliminationTreeKind
	SingleElimination
	DoubleElimination
End Enum

Rem
bbdoc: Options for generated bracket stages and placement matches.
about: `size` must be a power of two. A single-elimination tree can add a third-place match or classify places through a requested rank; a double-elimination tree can require a grand-final reset.
End Rem
Type TEliminationTreeOptions
	Rem
	bbdoc: Id prefix of this elimination tree options.
	End Rem
	Field idPrefix:String
	Rem
	bbdoc: Size for this elimination tree options.
	End Rem
	Field size:Int
	Rem
	bbdoc: Kind of this elimination tree options.
	End Rem
	Field kind:EEliminationTreeKind
	Rem
	bbdoc: Whether third place applies to this elimination tree options.
	End Rem
	Field thirdPlace:Int { asBool }
	Rem
	bbdoc: Placement through rank for this elimination tree options.
	about: 0 leaves eliminated entrants tied; size classifies everyone.
	End Rem
	Field placementThroughRank:Int ' 0 leaves eliminated entrants tied; size classifies everyone
	Rem
	bbdoc: Whether grand final reset applies to this elimination tree options.
	End Rem
	Field grandFinalReset:Int { asBool }
	Rem
	bbdoc: ID of the source stage.
	End Rem
	Field fromStageId:String
	Rem
	bbdoc: #TSeedingPolicy value used by this elimination tree options.
	End Rem
	Field seeding:TSeedingPolicy
	Rem
	bbdoc: #TMatchFormat value used by this elimination tree options.
	End Rem
	Field matchFormat:TMatchFormat
	Rem
	bbdoc: #TSchedulePolicy value used by this elimination tree options.
	End Rem
	Field policy:TSchedulePolicy

	Method New()
		grandFinalReset = True
	End Method
End Type

Rem
bbdoc: Generated stage IDs and placement queries for an elimination event.
End Rem
Type TEliminationTree
	Rem
	bbdoc: Size for this elimination tree.
	End Rem
	Field size:Int
	Rem
	bbdoc: Winner rounds values associated with this elimination tree.
	End Rem
	Field winnerRounds:String[]
	Rem
	bbdoc: Loser rounds values associated with this elimination tree.
	End Rem
	Field loserRounds:String[]
	Rem
	bbdoc: Classification stages values associated with this elimination tree.
	End Rem
	Field classificationStages:String[]
	Rem
	bbdoc: #TPlacementMatch entries associated with this elimination tree.
	End Rem
	Field placementMatches:TPlacementMatch[]
	Rem
	bbdoc: ID of the final stage associated with this elimination tree.
	End Rem
	Field finalStageId:String
	Rem
	bbdoc: ID of the reset stage associated with this elimination tree.
	End Rem
	Field resetStageId:String
	Rem
	bbdoc: ID of the third place stage associated with this elimination tree.
	End Rem
	Field thirdPlaceStageId:String

	Rem
	bbdoc: Finds the entrant assigned to a final placing.
	param: Competition definition containing the generated stages.
	param: Current playing state.
	param: One-based final rank.
	returns: Participant ID, or zero while the place is undecided or not configured.
	End Rem
	Method PlacementId:Int(comp:TCompetition, state:TCompetitionState, rank:Int)
		If rank < 1 Or rank > size Then
			Return 0
		End If

		If rank = 1 Then
			Return ChampionId(comp, state)
		End If

		If comp = Null Or state = Null Then
			Return 0
		End If

		Local decidingId:String = finalStageId
		If resetStageId <> "" Then
			For Local stageState:TStageState = EachIn state.stages
				If stageState.stageId <> resetStageId Then
					Continue
				End If

				If stageState.status = EStageStatus.Complete Then
					decidingId = resetStageId
				End If

				If stageState.status <> EStageStatus.Complete And stageState.status <> EStageStatus.Skipped Then
					Return 0
				End If

				Exit
			Next
		End If

		If rank = 2 Then
			Return DecidingParticipant(comp, state, decidingId, False)
		End If

		For Local placement:TPlacementMatch = EachIn placementMatches
			If rank = placement.winnerRank Then
				Return DecidingParticipant(comp, state, placement.stageId, True)
			End If

			If rank = placement.loserRank Then
				Return DecidingParticipant(comp, state, placement.stageId, False)
			End If
		Next

		Return 0
	End Method

	Rem
	bbdoc: Returns participant IDs in final-rank order.
	param: Competition definition containing the generated stages.
	param: Current playing state.
	returns: An array of `size` IDs; unresolved places contain zero.
	End Rem
	Method Placements:Int[](comp:TCompetition, state:TCompetitionState)
		Local ids:Int[] = New Int[size]
		For Local rank:Int = 1 To size
			ids[rank - 1] = PlacementId(comp, state, rank)
		Next

		Return ids
	End Method

	Rem
	bbdoc: Resolves the winner of the final or required reset match.
	param: Competition definition containing the generated stages.
	param: Current playing state.
	returns: Champion participant ID, or zero until decided.
	End Rem
	Method ChampionId:Int(comp:TCompetition, state:TCompetitionState)
		If comp = Null Or state = Null Then
			Return 0
		End If

		Local decidingId:String = finalStageId
		If resetStageId <> "" Then
			For Local stageState:TStageState = EachIn state.stages
				If stageState.stageId <> resetStageId Then
					Continue
				End If

				If stageState.status = EStageStatus.Complete Then
					decidingId = resetStageId
				End If

				If stageState.status <> EStageStatus.Complete And stageState.status <> EStageStatus.Skipped Then
					Return 0
				End If

				Exit
			Next
		End If

		Return DecidingParticipant(comp, state, decidingId, True)
	End Method

	Method DecidingParticipant:Int(comp:TCompetition, state:TCompetitionState, stageId:String, winner:Int)
		For Local index:Int = 0 Until comp.stages.Length
			If comp.stages[index].id <> stageId Then
				Continue
			End If

			If index >= state.stages.Length Or state.stages[index].status <> EStageStatus.Complete Then
				Return 0
			End If

			Local resolver:TBracketAdvancer = New TBracketAdvancer
			Local ids:Int[]
			If winner Then
				ids = resolver.DetermineWinners(comp, comp.stages[index], state.stages[index], 1)
			Else
				ids = resolver.DetermineLosers(comp.stages[index], state.stages[index], 1)
			End If

			If ids.Length = 1 Then
				Return ids[0]
			End If

			Return 0
		Next

		Return 0
	End Method
End Type

Rem
bbdoc: A generated match assigning a final place.
End Rem
Type TPlacementMatch
	Rem
	bbdoc: ID of the associated stage.
	End Rem
	Field stageId:String
	Rem
	bbdoc: Winner rank for this placement match.
	End Rem
	Field winnerRank:Int
	Rem
	bbdoc: Loser rank for this placement match.
	End Rem
	Field loserRank:Int
End Type

Rem
bbdoc: Appends a connected elimination-stage graph to a competition.
End Rem
Type TEliminationTreeBuilder
	Rem
	bbdoc: Appends an elimination tree and its advancement routes.
	param: Competition definition to extend.
	param: Draw size, format, seeding, and placement options.
	returns: A #TEliminationTree with generated stage IDs and placement queries.
	about: The generated stages use the normal bracket scheduler and scorer. Register those handlers before initializing the extended competition.
	End Rem
	Method Append:TEliminationTree(comp:TCompetition, options:TEliminationTreeOptions)
		If comp = Null Or options = Null Then
			Throw "Elimination tree needs a competition and options"
		End If

		If options.idPrefix = "" Then
			Throw "Elimination tree needs an id prefix"
		End If

		If options.size < 2 Or (options.size & (options.size - 1)) <> 0 Then
			Throw "Elimination tree size must be a power of two"
		End If

		If options.kind = EEliminationTreeKind.DoubleElimination And options.size < 4 Then
			Throw "Double elimination needs at least four entrants"
		End If

		If options.kind = EEliminationTreeKind.DoubleElimination And options.thirdPlace Then
			Throw "Third-place match is only available for single elimination"
		End If

		If options.thirdPlace And options.size < 4 Then
			Throw "Third-place match needs at least four entrants"
		End If

		If options.placementThroughRank < 0 Or options.placementThroughRank > options.size Then
			Throw "Placement rank must be within the draw"
		End If

		If options.kind = EEliminationTreeKind.DoubleElimination And options.placementThroughRank > 2 Then
			Throw "Placement ladder is only available for single elimination"
		End If

		If options.fromStageId = "" And comp.participants.Length <> options.size Then
			Throw "Direct elimination tree size must equal the participant count"
		End If

		If options.fromStageId <> "" Then
			Local found:Int = False
			For Local stage:TStage = EachIn comp.stages
				If stage.id = options.fromStageId Then found = True; Exit
			Next

			If Not found Then
				Throw "Unknown elimination tree source stage: " + options.fromStageId
			End If
		End If

		Local rounds:Int = 0
		Local count:Int = options.size
		While count > 1
			rounds :+ 1
			count :/ 2
		Wend

		Local tree:TEliminationTree = New TEliminationTree
		tree.size = options.size
		Local generated:TStage[]
		For Local round:Int = 1 To rounds
			Local id:String = options.idPrefix + "_W" + round
			Local stage:TStage = MakeStage(id, options.size Shr (round - 1), options)
			If round = 1 Then
				If options.fromStageId <> "" Then
					stage.input.fromStageId = options.fromStageId
				Else
					stage.independent = True
				End If
			Else
				stage.input.fromStageId = tree.winnerRounds[round - 2]
			End If

			generated :+ [stage]
			tree.winnerRounds :+ [id]
		Next

		For Local round:Int = 1 Until rounds
			AddRoute(generated[round - 1], tree.winnerRounds[round], EAdvancementOutcome.Winner, Null)
		Next

		If options.kind = EEliminationTreeKind.SingleElimination Then
			tree.finalStageId = tree.winnerRounds[rounds - 1]
			Local limit:Int = options.placementThroughRank
			If options.thirdPlace Then
				limit = Max(limit, 4)
			End If

			For Local round:Int = 1 Until rounds
				Local count:Int = options.size Shr round
				If count + 1 > limit Then
					Continue
				End If

				generated = AddClassification(generated[round - 1], count, count + 1, EAdvancementOutcome.Loser, limit, options, tree, generated)
			Next
		Else
			Local lowerSize:Int = options.size / 2
			For Local round:Int = 1 To 2 * rounds - 2
				If round > 1 And round Mod 2 = 1 Then
					lowerSize :/ 2
				End If

				Local id:String = options.idPrefix + "_L" + round
				Local lower:TStage = MakeStage(id, lowerSize, options)
				If round = 1 Then
					lower.input.fromStageId = tree.winnerRounds[0]
				ElseIf round Mod 2 = 0 Then
					lower.input.fromStageIds = [tree.loserRounds[round - 2], tree.winnerRounds[round / 2]]
				Else
					lower.input.fromStageId = tree.loserRounds[round - 2]
				End If

				generated :+ [lower]
				tree.loserRounds :+ [id]
			Next

			AddRoute(generated[0], tree.loserRounds[0], EAdvancementOutcome.Loser, Null)
			For Local round:Int = 2 To rounds
				Local destination:TStage = generated[rounds + 2 * round - 3]
				AddRoute(generated[round - 1], destination.id, EAdvancementOutcome.Loser, AlternateSlots(destination.config, False))
			Next

			For Local round:Int = 1 Until tree.loserRounds.Length
				Local from:TStage = generated[rounds + round - 1]
				Local to:TStage = generated[rounds + round]
				Local slots:String[] = Null
				If round Mod 2 = 1 Then
					slots = AlternateSlots(to.config, True)
				End If

				AddRoute(from, to.id, EAdvancementOutcome.Winner, slots)
			Next

			Local finalStage:TStage = MakeStage(options.idPrefix + "_GF", 2, options)
			finalStage.input.fromStageIds = [tree.winnerRounds[rounds - 1], tree.loserRounds[tree.loserRounds.Length - 1]]
			AddRoute(generated[rounds - 1], finalStage.id, EAdvancementOutcome.Winner, ["1"])
			AddRoute(generated[generated.Length - 1], finalStage.id, EAdvancementOutcome.Winner, ["2"])
			generated :+ [finalStage]
			tree.finalStageId = finalStage.id
			If options.grandFinalReset Then
				Local reset:TStage = MakeStage(options.idPrefix + "_RESET", 2, options)
				reset.input.fromStageId = finalStage.id
				reset.activation = New TStageActivation
				reset.activation.kind = EStageActivationKind.IfReferenceEntrantLoses
				reset.activation.referenceSourceId = tree.winnerRounds[rounds - 1]
				AddRoute(finalStage, reset.id, EAdvancementOutcome.AllEntrants, ["1", "2"])
				generated :+ [reset]
				tree.resetStageId = reset.id
			End If
		End If

		For Local stage:TStage = EachIn generated
			For Local existing:TStage = EachIn comp.stages
				If existing.id = stage.id Then
					Throw "Elimination tree stage already exists: " + stage.id
				End If
			Next
		Next

		comp.stages :+ generated
		Return tree
	End Method

	Method AddClassification:TStage[](source:TStage, count:Int, firstRank:Int, outcome:EAdvancementOutcome, limit:Int, options:TEliminationTreeOptions, tree:TEliminationTree, generated:TStage[])
		If count < 2 Or firstRank > limit Then
			Return generated
		End If

		Local id:String = options.idPrefix + "_P" + firstRank + "_" + (firstRank + count - 1)
		If firstRank = 3 And count = 2 And options.thirdPlace Then
			id = options.idPrefix + "_THIRD"
		End If

		Local stage:TStage = MakeStage(id, count, options)
		stage.input.fromStageId = source.id
		AddRoute(source, id, outcome, Null)
		generated :+ [stage]
		tree.classificationStages :+ [id]
		If firstRank = 3 And count = 2 Then
			tree.thirdPlaceStageId = id
		End If

		If count = 2 Then
			Local placement:TPlacementMatch = New TPlacementMatch
			placement.stageId = id
			placement.winnerRank = firstRank
			placement.loserRank = firstRank + 1
			tree.placementMatches :+ [placement]
			Return generated
		End If

		generated = AddClassification(stage, count / 2, firstRank, EAdvancementOutcome.Winner, limit, options, tree, generated)
		generated = AddClassification(stage, count / 2, firstRank + count / 2, EAdvancementOutcome.Loser, limit, options, tree, generated)
		Return generated
	End Method

	Method MakeStage:TStage(id:String, size:Int, options:TEliminationTreeOptions)
		Local stage:TStage = New TStage
		stage.id = id
		stage.stageType = EStageType.Bracket
		stage.input = New TEntrySource
		stage.input.seeding = options.seeding
		stage.config = New TBracketConfig
		Local config:TBracketConfig = TBracketConfig(stage.config)
		config.size = size
		config.matchFormat = options.matchFormat
		config.policy = options.policy
		Return stage
	End Method

	Method AddRoute(source:TStage, destination:String, outcome:EAdvancementOutcome, slots:String[])
		Local route:TAdvancement = New TAdvancement
		route.toStageId = destination
		route.outcome = outcome
		If slots <> Null Then
			route.mapping = New TAdvancementMapping
			route.mapping.mode = EAdvMappingMode.FixedSlots
			route.mapping.toSlots = slots
		End If

		source.advancement :+ [route]
	End Method

	Method AlternateSlots:String[](config:TConfig, odd:Int)
		Local size:Int = TBracketConfig(config).size
		Local slots:String[]
		Local start:Int = 2
		If odd Then
			start = 1
		End If

		For Local position:Int = start To size Step 2
			slots :+ [String(position)]
		Next

		Return slots
	End Method
End Type
