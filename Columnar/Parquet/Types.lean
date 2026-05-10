namespace Columnar.Parquet

/-- Physical `Type` enum from parquet.thrift -/
abbrev PhysType := Nat

def PhysType.boolean : Nat := 0
def PhysType.int32 : Nat := 1
def PhysType.int64 : Nat := 2
def PhysType.int96 : Nat := 3
def PhysType.float : Nat := 4
def PhysType.double : Nat := 5
def PhysType.byteArray : Nat := 6
def PhysType.fixedLenByteArray : Nat := 7

/-- `Encoding` enum (parquet.thrift) -/
abbrev Encoding := Nat
def Encoding.plain : Nat := 0
def Encoding.plainDictionary : Nat := 2
def Encoding.rle : Nat := 3
def Encoding.bitPackedDeprecated : Nat := 4
def Encoding.deltaBinaryPacked : Nat := 5
def Encoding.deltaLengthByteArray : Nat := 6
def Encoding.deltaByteArray : Nat := 7
def Encoding.rleDictionary : Nat := 8
def Encoding.byteStreamSplit : Nat := 9

/-- `PageType` enum -/
abbrev PageType := Nat
def PageType.dataPage : Nat := 0
def PageType.dataPageV2 : Nat := 3
def PageType.dictionaryPage : Nat := 2

end Columnar.Parquet
