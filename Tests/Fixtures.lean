import Init.System.FilePath

namespace Tests.Fixtures

/-- Path to `vendor/parquet-testing/data/<name>`. -/
def parquetTesting (name : String) : System.FilePath :=
  System.mkFilePath ["vendor", "parquet-testing", "data", name]

def parquetTestingRoot : System.FilePath :=
  System.mkFilePath ["vendor", "parquet-testing"]

def avroShareTest : System.FilePath :=
  System.mkFilePath ["vendor", "avro", "share", "test"]

def orcExamples : System.FilePath :=
  System.mkFilePath ["vendor", "orc", "examples"]

def arrowIpcIntegration : System.FilePath :=
  System.mkFilePath ["vendor", "arrow-testing", "data", "arrow-ipc-stream", "integration"]

end Tests.Fixtures
