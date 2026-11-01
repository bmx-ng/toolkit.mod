' Convert authored decimal points to the integer units stored in standings.
' This is the only conversion path for exact point configuration.
Rem
bbdoc: Converts an exact decimal point value to integer standings units.
param: Decimal value to convert.
param: Number of stored units per point.
returns: The exact scaled integer value.
about: Throws if the value cannot be represented at the given scale or exceeds the supported integer range.
End Rem
Function ExactPointUnits:Int(value:String, scale:Int)
	If scale < 1 Then
		Throw "pointsScale must be positive"
	End If

	Local scaled:TDecimal = Decimal(value) * Decimal(scale)
	If scaled > Decimal(2000000000) Or scaled < Decimal(-2000000000) Then
		Throw "Points exceed integer range"
	End If

	Local units:Int = scaled.ToInt()
	If scaled <> Decimal(units) Then
		Throw "pointsScale cannot represent points exactly: " + value
	End If

	Return units
End Function

Rem
bbdoc: Resolves an optional decimal override into standings units.
param: Whole-point fallback used when the exact value is empty.
param: Exact decimal override, or an empty string.
param: Number of stored units per point.
returns: The chosen value in exact integer units.
End Rem
Function ConfigPointUnits:Int(whole:Int, exact:String, scale:Int)
	If exact <> "" Then
		Return ExactPointUnits(exact, scale)
	End If

	Return ExactPointUnits(String(whole), scale)
End Function
