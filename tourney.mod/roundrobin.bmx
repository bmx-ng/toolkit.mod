Rem
bbdoc: Generates repeated round-robin fixtures, alternating home sides on later legs.
param: Stage ID stored on each fixture.
param: Participant IDs to pair.
param: Games per opponent pair; values below one are treated as one.
param: First round number.
returns: Definition-time #TFixture records, with byes omitted for odd fields.
End Rem
Function GenerateRoundRobinFixturesN:TFixture[](stageId:String, teamIds:Int[], perOpp:Int, startRound:Int = 1)
	If perOpp < 1 Then
		perOpp = 1
	End If

	' --- Build base (single) round-robin using your existing logic (doubleRound=False) ---
	Local base:TFixture[] = GenerateRoundRobinBase(stageId, teamIds, startRound)

	' How many distinct rounds in the base?
	Local roundsInBase:Int = 0
	For Local f:TFixture = EachIn base
		If f.round > roundsInBase Then
			roundsInBase = f.round
		End If
	Next
	' base rounds are startRound..roundsInBase inclusive
	Local baseRoundCount:Int = roundsInBase - startRound + 1

	' --- Repeat base perOpp times, flipping H/A on odd repetitions ---
	Local out:TFixture[] = []
	For Local rep:Int = 0 Until perOpp
		Local flipHA:Int = rep Mod 2 ' flip on odd reps
		Local roundOffset:Int = rep * baseRoundCount
		For Local i:Int = 0 Until base.Length
			Local b:TFixture = base[i]
			Local f:TFixture = New TFixture
			f.stageId = stageId
			f.leg = rep + 1
			f.round = (b.round + roundOffset)
			If flipHA = 0 Then
				f.homeTeamId = b.homeTeamId
				f.awayTeamId = b.awayTeamId
			Else
				f.homeTeamId = b.awayTeamId
				f.awayTeamId = b.homeTeamId
			End If

			out :+ [f]
		Next
	Next

	Return out
End Function

' Generates a single round-robin (each team plays each other once) for the given teamIds.
' Uses the "circle method" for round-robin generation.
' If odd number of teams, one team has a bye each round (teamId=0).
' Rounds are numbered starting from startRound.
' Returns TFixture[] with stageId, round, leg=1, homeTeamId, awayTeamId set.
' Does NOT balance home/away streaks; use BalanceVenueStreaks_Fixture()
Rem
bbdoc: Generates one round robin using the circle method.
param: Stage ID stored on each fixture.
param: Participant IDs to pair once each.
param: First round number.
returns: Definition-time #TFixture records; an odd field receives one bye per round.
about: This function does not optimise home-away streaks. Use #BalanceVenueStreaks_Fixture when the schedule needs that preference.
End Rem
Function GenerateRoundRobinBase:TFixture[](stageId:String, teamIds:Int[], startRound:Int = 1)
	Local teams:Int[] = teamIds[..]
	If teams.Length Mod 2 = 1 Then
		teams :+ [0] ' 0 = bye
	End If

	Local n:Int = teams.Length
	Local rounds:Int = n - 1
	Local fixtures:TFixture[]

	For Local r:Int = 0 Until rounds
		Local roundNum:Int = startRound + r

		' pair i with n-1-i
		For Local i:Int = 0 Until n / 2
			Local a:Int = teams[i]
			Local b:Int = teams[n - 1 - i]
			If a = 0 Or b = 0 Then
				Continue ' bye
			End If

			Local f:TFixture = New TFixture
			f.stageId = stageId
			f.round = roundNum
			f.leg = 1

			' Alternating home/away to reduce streaks
			If (r + i) Mod 2 = 0 Then
				f.homeTeamId = a
				f.awayTeamId = b
			Else
				f.homeTeamId = b
				f.awayTeamId = a
			End If

			fixtures :+ [f]
		Next

		' rotate array [0, 1, 2, ..., n-2, n-1] -> [0, n-1, 1, 2, ..., n-2]
		If n > 2 Then
			Local last:Int = teams[n - 1]
			For Local k:Int = n - 1 To 2 Step -1
				teams[k] = teams[k - 1]
			Next

			teams[1] = last
		End If
	Next

	Return fixtures
End Function

' Balances home/away venue streaks for a set of fixtures.
Rem
bbdoc: Attempts to reduce excessive home and away streaks in generated fixtures.
param: Fixtures to adjust in place.
param: Preferred maximum consecutive home games.
param: Preferred maximum consecutive away games.
param: Games per opponent pair, used when preserving return legs.
End Rem
Function BalanceVenueStreaks_Fixture(fixtures:TFixture[], maxH:Int, maxA:Int, perOpp:Int)
	If fixtures = Null Or fixtures.Length = 0 Then
		Return
	End If

	If maxH <= 0 And maxA <= 0 Then
		Return
	End If

	' Stable traversal
	Local fx:TFixture[] = fixtures[..]
	SortFixturesByRoundLeg(fx)

	' Build team -> indices list
	Local teamIdx:TIntMap = New TIntMap ' pid -> Int[] of indices into fx
	For Local i:Int = 0 Until fx.Length
		Local f:TFixture = fx[i]
		If f.homeTeamId > 0 Then
			AppendTeamIndex(teamIdx, f.homeTeamId, i)
		End If

		If f.awayTeamId > 0 Then
			AppendTeamIndex(teamIdx, f.awayTeamId, i)
		End If
	Next

	For Local k:TIntKey = EachIn teamIdx.Keys()
		Local arr:Int[] = Int[](teamIdx.ValueForKey(k.value))
		SortTeamIndexByRoundLeg(arr, fx)
		teamIdx.Insert(k.value, arr)
	Next

	' Precompute baseline total cost
	Local baseCost:Int = TotalCostAllTeams(fx, teamIdx, maxH, maxA)

	Local improved:Int = True
	Local iter:Int = 0
	Local MAX_ITERS:Int = 24 ' generous but bounded

	While improved And iter < MAX_ITERS
		improved = False
		iter :+ 1

		' Greedy pass: try each fixture; commit the first flip that reduces total cost
		For Local i:Int = 0 Until fx.Length
			Local a:Int = fx[i].homeTeamId
			Local b:Int = fx[i].awayTeamId
			If a = 0 Or b = 0 Then
				Continue
			End If

			If perOpp >= 2 Then
				' paired flip over both legs (if counter leg exists)
				Local j:Int = FindCounterLegIndex_Fixture(i, fx)
				' compute delta considering (i,j) flipped
				Local delta:Int = DeltaCostTwoTeams(fx, teamIdx, a, b, maxH, maxA, i, j)
				If delta < 0 Then
					' apply the paired flip(s)
					SwapHomeAwayInPlace_Fixture(fx[i])
					If j <> -1 Then
						SwapHomeAwayInPlace_Fixture(fx[j])
					End If

					baseCost :+ delta
					improved = True
					Exit
				End If
			Else
				' single flip
				Local delta:Int = DeltaCostTwoTeams(fx, teamIdx, a, b, maxH, maxA, i, -1)
				If delta < 0 Then
					SwapHomeAwayInPlace_Fixture(fx[i])
					baseCost :+ delta
					improved = True
					Exit
				End If
			End If
		Next
	Wend

	' write back
	For Local i:Int = 0 Until fixtures.Length
		fixtures[i] = fx[i]
	Next
End Function

' ---------- Cost helpers ----------

' Total cost across all teams
Function TotalCostAllTeams:Int(fx:TFixture[], teamIdx:TIntMap, maxH:Int, maxA:Int)
	Local sum:Int = 0
	For Local k:TIntKey = EachIn teamIdx.Keys()
		Local pid:Int = k.value
		sum :+ TeamCostWithHypo(fx, Int[](teamIdx.ValueForKey(pid)), pid, maxH, maxA, -1, -1)
	Next

	Return sum
End Function

' Delta cost when hypothetically flipping fixture fi (and optionally fj) for teams a & b
Function DeltaCostTwoTeams:Int(fx:TFixture[], teamIdx:TIntMap, a:Int, b:Int, maxH:Int, maxA:Int, fi:Int, fj:Int)
	Local aList:Int[] = Int[](teamIdx.ValueForKey(a))
	Local bList:Int[] = Int[](teamIdx.ValueForKey(b))

	Local curA:Int = TeamCostWithHypo(fx, aList, a, maxH, maxA, -1, -1)
	Local curB:Int = TeamCostWithHypo(fx, bList, b, maxH, maxA, -1, -1)

	Local newA:Int = TeamCostWithHypo(fx, aList, a, maxH, maxA, fi, fj)
	Local newB:Int = TeamCostWithHypo(fx, bList, b, maxH, maxA, fi, fj)

	Return (newA + newB) - (curA + curB)
End Function

' Compute a single team’s streak overage with optional hypothetical flips at fi and fj
' overage = max(0, longestHomeStreak-maxH) + max(0, longestAwayStreak-maxA)
Function TeamCostWithHypo:Int(fx:TFixture[], ilist:Int[], pid:Int, maxH:Int, maxA:Int, fi:Int, fj:Int)
	If ilist = Null Or ilist.Length = 0 Then
		Return 0
	End If

	Function getHA:Int(idx:Int, ilist:Int[], fx:TFixture[], fi:Int, fj:Int, pid:Int)
		If idx < 0 Or idx >= ilist.Length Then
			Return 0
		End If

		Local g:TFixture = fx[ilist[idx]]
		Local ha:Int = TeamHA_Fixture(pid, g)
		If ilist[idx] = fi Or ilist[idx] = fj Then
			ha = -ha ' hypothetical flip
		End If

		Return ha
	End Function

	Local longestH:Int = 0, longestA:Int = 0
	Local curType:Int = 0, curLen:Int = 0

	For Local i:Int = 0 Until ilist.Length
		Local t:Int = getHA(i, ilist, fx, fi, fj, pid)
		If t = 0 Then
			Continue
		End If

		If curLen = 0 Then
			curType = t
			curLen = 1
		ElseIf t = curType Then
			curLen :+ 1
		Else
			If curType = 1 Then
				If curLen > longestH Then
					longestH = curLen
				End If
			ElseIf curType = -1 Then
				If curLen > longestA Then
					longestA = curLen
				End If
			End If

			curType = t
			curLen = 1
		End If
	Next
	' tail
	If curLen > 0 Then
		If curType = 1 Then
			If curLen > longestH Then
				longestH = curLen
			End If
		ElseIf curType = -1 Then
			If curLen > longestA Then
				longestA = curLen
			End If
		End If
	End If

	Local overH:Int = 0
	Local overA:Int = 0
	If maxH > 0 And longestH > maxH Then
		overH = longestH - maxH
	End If

	If maxA > 0 And longestA > maxA Then
		overA = longestA - maxA
	End If

	Return overH + overA
End Function

' ---------- Existing helpers you already have (fixture versions) ----------

Function TeamHA_Fixture:Int(pid:Int, f:TFixture)
	If f.homeTeamId = pid Then
		Return 1
	End If

	If f.awayTeamId = pid Then
		Return -1
	End If

	Return 0
End Function

Function FindCounterLegIndex_Fixture:Int(fi:Int, fx:TFixture[])
	Local a:Int = fx[fi].homeTeamId, b:Int = fx[fi].awayTeamId
	If a = 0 Or b = 0 Then
		Return -1
	End If

	For Local j:Int = 0 Until fx.Length
		If j = fi Then
			Continue
		End If

		Local g:TFixture = fx[j]
		If (g.homeTeamId = a And g.awayTeamId = b) Or (g.homeTeamId = b And g.awayTeamId = a) Then
			Return j
		End If
	Next

	Return -1
End Function

Function SwapHomeAwayInPlace_Fixture(f:TFixture)
	Local t:Int = f.homeTeamId
	f.homeTeamId = f.awayTeamId
	f.awayTeamId = t
End Function

Function SortFixturesByRoundLeg(a:TFixture[])
	For Local i:Int = 0 Until a.Length - 1
		For Local j:Int = i + 1 Until a.Length
			If a[i].round > a[j].round Or (a[i].round = a[j].round And a[i].leg > a[j].leg) Then
				Local t:TFixture = a[i]
				a[i] = a[j]
				a[j] = t
			End If
		Next
	Next
End Function

Function AppendTeamIndex(m:TIntMap, pid:Int, idx:Int)
	Local arr:Int[] = Int[](m.ValueForKey(pid))
	If arr = Null Then
		arr = []
	End If

	arr :+ [idx]
	m.Insert(pid, arr)
End Function

Function SortTeamIndexByRoundLeg(arr:Int[], fx:TFixture[])
	For Local i:Int = 0 Until arr.Length - 1
		For Local j:Int = i + 1 Until arr.Length
			Local fi:Int = arr[i]
			Local fj:Int = arr[j]
			If fx[fi].round > fx[fj].round Or (fx[fi].round = fx[fj].round And fx[fi].leg > fx[fj].leg) Then
				Local t:Int = arr[i]
				arr[i] = arr[j]
				arr[j] = t
			End If
		Next
	Next
End Function

Function TryFlipFixtureIfSafe_Fixture:Int(pid:Int, fi:Int, fx:TFixture[], teamIdx:TIntMap, maxH:Int, maxA:Int)
	Local f:TFixture = fx[fi]
	If f.homeTeamId = 0 Or f.awayTeamId = 0 Then
		Return False
	End If

	Local opp:Int
	If f.homeTeamId = pid Then
		opp = f.awayTeamId
	Else
		opp = f.homeTeamId
	End If

	If Not CheckFlipKeepsWithin_Fixture(pid, fi, fx, teamIdx, maxH, maxA) Then
		Return False
	End If

	If Not CheckFlipKeepsWithin_Fixture(opp, fi, fx, teamIdx, maxH, maxA) Then
		Return False
	End If

	SwapHomeAwayInPlace_Fixture(f)
	Return True
End Function

Function TryPairedFlipIfSafe_Fixture:Int(pid:Int, fi:Int, fx:TFixture[], teamIdx:TIntMap, maxH:Int, maxA:Int)
	Local cj:Int = FindCounterLegIndex_Fixture(fi, fx)
	If cj = -1 Then
		Return TryFlipFixtureIfSafe_Fixture(pid, fi, fx, teamIdx, maxH, maxA)
	End If

	Local opp:Int
	If fx[fi].homeTeamId = pid Then
		opp = fx[fi].awayTeamId
	Else
		opp = fx[fi].homeTeamId
	End If

	If Not CheckFlipKeepsWithin_Fixture(pid, fi, fx, teamIdx, maxH, maxA) Then
		Return False
	End If

	If Not CheckFlipKeepsWithin_Fixture(opp, fi, fx, teamIdx, maxH, maxA) Then
		Return False
	End If

	If Not CheckFlipKeepsWithin_Fixture(pid, cj, fx, teamIdx, maxH, maxA) Then
		Return False
	End If

	If Not CheckFlipKeepsWithin_Fixture(opp, cj, fx, teamIdx, maxH, maxA) Then
		Return False
	End If

	SwapHomeAwayInPlace_Fixture(fx[fi])
	SwapHomeAwayInPlace_Fixture(fx[cj])
	Return True
End Function

Function CheckFlipKeepsWithin_Fixture:Int(pid:Int, fi:Int, fx:TFixture[], teamIdx:TIntMap, maxH:Int, maxA:Int)
	Local ilist:Int[] = Int[](teamIdx.ValueForKey(pid))
	If ilist = Null Then
		Return True
	End If

	Local pos:Int = -1
	For Local i:Int = 0 Until ilist.Length
		If ilist[i] = fi Then
			pos = i
			Exit
		End If
	Next

	If pos = -1 Then
		Return True
	End If

	function getHA:Int(idx:Int, ilist:Int[], fx:TFixture[], pid:Int, fi:Int)
		If idx < 0 Or idx >= ilist.Length Then
			Return 0
		End If

		Local g:TFixture = fx[ilist[idx]]
		Local ha:Int = TeamHA_Fixture(pid, g)
		If ilist[idx] = fi Then
			ha = -ha
		End If

		Return ha
	End Function

	Local prevType:Int = getHA(pos - 1, ilist, fx, pid, fi), prevLen:Int = 0, i:Int
	i = pos - 1
	While i >= 0 And getHA(i, ilist, fx, pid, fi) = prevType And prevType <> 0
		prevLen :+ 1
		i :- 1
	Wend

	Local curType:Int = getHA(pos, ilist, fx, pid, fi)
	If curType = 0 Then
		Return True
	End If

	Local fwdLen:Int = 0; i = pos + 1
	While i < ilist.Length And getHA(i, ilist, fx, pid, fi) = curType
		fwdLen :+ 1
		i :+ 1
	Wend

	Local total:Int = 1 + fwdLen
	If prevType = curType Then
		total :+ prevLen
	End If

	If curType = 1 And maxH > 0 And total > maxH Then
		Return False
	End If

	If curType = -1 And maxA > 0 And total > maxA Then
		Return False
	End If

	Return True
End Function


' -------- BRACKET SCHEDULER --------
