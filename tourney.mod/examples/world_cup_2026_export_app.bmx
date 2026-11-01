SuperStrict

Framework BRL.StandardIO
Import toolkit.tourney
Include "world_cup_2026_replay.bmx"
Include "world_cup_2026_snapshot_export.bmx"

Local outputPath:String = AppDir + "/world_cup_2026_snapshots.tsv"
If AppArgs.Length > 1 Then outputPath = AppArgs[1]
Local matches:Int = TWorldCup2026SnapshotExport.Export(AppDir + "/world_cup_2026.tsv", outputPath)
Print "Exported " + matches + " World Cup matches to " + outputPath
