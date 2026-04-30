namespace Columnar.Avro

/-- Parsed Avro schema (Phase 3). -/
inductive AvroType where
  | null | boolean | int | long | float | double | string | bytes
  | array (elem : AvroType)
  | map (values : AvroType)
  | record (name : String) (fields : List (String × AvroType))
  deriving Repr

def parseSchemaJsonString (_ : String) : Except String AvroType :=
  throw "Avro schema: Phase 3"

end Columnar.Avro
