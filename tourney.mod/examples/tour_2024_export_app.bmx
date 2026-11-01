SuperStrict

Framework BRL.StandardIO
Import toolkit.tourney
Include "tour_2024_replay.bmx"
Include "tour_2024_snapshot_export.bmx"

Local outputPath:String = AppDir + "/tour_2024_snapshots.tsv"
If AppArgs.Length > 1 Then
	outputPath = AppArgs[1]
End If

Local finishers:Int = TTourSnapshotExport.Export(AppDir + "/tour_2024_official.tsv", outputPath)
Print "Exported 21 Tour stages and " + finishers + " final GC riders to " + outputPath
