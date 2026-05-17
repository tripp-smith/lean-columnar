import Init.System.FilePath

namespace Tests.Fixtures

/-- Path to `vendor/parquet-testing/data/<name>`. -/
def parquetTesting (name : String) : System.FilePath :=
  System.mkFilePath ["vendor", "parquet-testing", "data", name]

def parquetTestingRoot : System.FilePath :=
  System.mkFilePath ["vendor", "parquet-testing"]

/-- Repository fixture: two uncompressed row groups, single INT32 column `x` (see `scripts/gen_two_row_fixture.py`). -/
def twoRowGroupsPlain : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "two_row_groups_plain.parquet"]

/-- Checked-in compressed blobs + plaintext for `Tests.Unit.CodecContract` (see `scripts/gen_codec_contract_fixtures.py`). -/
def codecContractDir : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "codecs"]

def avroShareTest : System.FilePath :=
  System.mkFilePath ["vendor", "avro", "share", "test"]

def orcExamples : System.FilePath :=
  System.mkFilePath ["vendor", "orc", "examples"]

def arrowIpcIntegration : System.FilePath :=
  System.mkFilePath ["vendor", "arrow-testing", "data", "arrow-ipc-stream", "integration"]

def interopMinimalAvro : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "interop_minimal.avro"]

def interopMinimalAvroSnappy : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "interop_minimal_snappy.avro"]

def interopOrcInt32 : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "interop_orc_int32.orc"]

def interopArrowInt32Stream : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "interop_arrow_int32_stream.arrow"]

def interopArrowInt32File : System.FilePath :=
  System.mkFilePath ["Tests", "fixtures", "interop_arrow_int32_file.arrow"]

def avroVendorSimple : System.FilePath :=
  System.mkFilePath ["vendor", "avro", "share", "test", "data", "schemas", "simple", "data.avro"]

def orcTest1 : System.FilePath :=
  System.mkFilePath ["vendor", "orc", "examples", "TestOrcFile.test1.orc"]

def arrowSchemaV6 : System.FilePath :=
  System.mkFilePath ["vendor", "arrow-testing", "data", "forward-compatibility", "schema_v6.arrow"]

end Tests.Fixtures
