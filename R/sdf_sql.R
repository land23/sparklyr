
sdf_sql_schema <- function(sqlResult) {
  invoke(
    sqlResult,
    "schema"
  )
}

sdf_sql_object_method <- function(object, property) {
  invoke(
    object,
    property
  )
}

sdf_sql_field <- function(field) {
  name <- sdf_sql_object_method(field, "name")
  dataType <- sdf_sql_object_method(field, "dataType")
  longType <- sdf_sql_object_method(dataType, "toString")
  shortType <- sdf_sql_object_method(dataType, "simpleString")

  list(
    name = name,
    longType = longType,
    shortType = shortType
  )
}

sdf_sql_schema_fields <- function(schemaResult) {
  lapply(
    invoke(
      schemaResult,
      "fields"
    ),
    function (field) {
      sdf_sql_field(field)
    }
  )
}

# See https://github.com/apache/spark/tree/branch-1.6/sql/catalyst/src/main/scala/org/apache/spark/sql/types
sdf_sql_default_type <- function(field) {
  switch(field$shortType,
         tinyint = integer(),
         bigint = integer(),
         smallint = integer(),
         string = character(),
         double = double(),
         int = integer(),
         character())
}

# Retrives a typed column for the given dataframe
sdf_sql_columns_typed <- function(col, stringData, fields, rows) {
  shortType <- fields[[col]]$shortType

  result <- lapply(seq_len(rows), function(row) {
    raw <- stringData[[(col - 1) * rows + row]]

    switch(shortType,
           tinyint = as.integer(raw),
           bigint = as.numeric(raw),
           smallint = as.integer(raw),
           string = raw,
           double = as.double(raw),
           int = as.integer(raw),
           boolean = as.logical(raw),
           vector = invoke(raw, "toArray"),
           raw)
  })

  if (!shortType %in% c("vector")) unlist(result) else result
}

df_from_sql <- function(sc, sql) {
  sdf <- invoke(hive_context(sc), "sql", as.character(sql))
  df_from_sdf(sc, sdf)
}

df_from_sdf <- function(sc, sdf, take = -1) {
  schema <- sdf_sql_schema(sdf)
  fields <- sdf_sql_schema_fields(schema)

  if (take >= 0) {
    sdf <- invoke(sdf, "limit", as.integer(take))
  }

  df <- invoke_static(
    spark_connection(sdf),

    "org.apache.spark.sql.api.r.SQLUtils",
    "dfToCols",

    sdf
  )

  dfNames <- lapply(fields, function(x) x$name)
  rows <- if (length(df) > 0) length(df[[1]]) else 0

  # If this is a resultset with no rows...
  if (rows == 0) {
    # Remove invalid fields that have zero length
    fields <- Filter(function(e) nchar(e$name) > 0, fields)
    dfNames <- Filter(function(e) nchar(e) > 0, dfNames)

    dfEmpty <- lapply(fields, function(field) {
      sdf_sql_default_type(field)
    })
    names(dfEmpty) <- dfNames

    df <- data.frame(dfEmpty, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    stringData <- unlist(df)
    df <- as.data.frame(seq_len(rows))

    lapply(seq_along(fields), function(col) {
      df[[dfNames[[col]]]] <<- sdf_sql_columns_typed(
        col,
        stringData,
        fields,
        rows)
    })

    df[[1]] <- NULL
  }

  df
}

