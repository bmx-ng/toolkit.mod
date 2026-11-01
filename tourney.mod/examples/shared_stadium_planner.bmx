SuperStrict

Framework BRL.StandardIO
Import Toolkit.Tourney

Function Team:TParticipant(id:Int, name:String, homeVenue:String = "")
	Local participant:TParticipant = New TParticipant
	participant.id = id
	participant.name = name
	participant.homeVenueId = homeVenue
	participant.kind = EParticipantKind.Team
	Return participant
End Function

Function Slot:TSlot(id:String, time:String)
	Local slot:TSlot = New TSlot
	slot.id = id
	slot.dateTime = time
	slot.venueId = "shared-stadium"
	slot.round = 1
	Return slot
End Function

Function HomeGame:TStage(id:String, home:Int, away:Int, slots:TSlot[])
	Local stage:TStage = New TStage
	stage.id = id
	stage.stageType = EStageType.League
	stage.independent = True
	Local config:TLeagueConfig = New TLeagueConfig
	config.schedule = New TLeagueScheduleConfig
	config.schedule.weeks = 1
	Local fixture:TFixture = New TFixture
	fixture.round = 1
	fixture.homeTeamId = home
	fixture.awayTeamId = away
	config.schedule.fixedFixtures = [fixture]
	stage.config = config
	stage.schedule = New TSchedulePolicy
	stage.schedule.calendar = New TCalendar
	stage.schedule.calendar.slots = slots
	Return stage
End Function

Local comp:TCompetition = New TCompetition
comp.name = "Shared stadium example"
comp.participants = [Team(1, "Jets", "shared-stadium"), Team(2, "Giants", "shared-stadium"), Team(3, "Patriots"), Team(4, "Cowboys")]
Local early:TSlot = Slot("early", "2026-10-22T12:00:00Z")
Local late:TSlot = Slot("late", "2026-10-22T16:00:00Z")
comp.stages = [HomeGame("JETS", 1, 3, [early, late]), HomeGame("GIANTS", 2, 4, [early])]

Local engine:TCompetitionEngine = New TCompetitionEngine
engine.RegisterScheduler(EStageType.League, New TLeagueScheduler)
Local state:TCompetitionState = engine.Initialize(comp, True)
Print "Jets vs Patriots: " + state.stages[0].fixtures[0].slotId
Print "Giants vs Cowboys: " + state.stages[1].fixtures[0].slotId
