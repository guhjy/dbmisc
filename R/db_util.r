


#' Insert row(s) into table
#'
#' @param conn dbi database connection
#' @param table name of the table
#' @param vals named list of values to be inserted
#' @param schema a table schema that can be used to convert values
#' @param sql optional a parameterized sql string
#' @param run if FALSE only return parametrized SQL string
#' @param mode "insert" or "replace", should have no effect so far
#' @param rclass the r class of the table columns, is extracted from schema
#' @param convert if rclass is given shall results automatically be converted to these classes?
#' @param primary.key name of the primary key column (if the table has one)
#' @param get.key if TRUE return the created primary key value
dbInsert = function(conn, table, vals,schema=NULL, sql=NULL,run=TRUE, mode=c("insert","replace")[1], rclass=schema$rclass, convert=!is.null(rclass), primary.key = schema$primary_key, get.key=FALSE, null.as.na=TRUE) {
  restore.point("dbInsert")

  # Update vals based on table schema
  if (isTRUE(convert)) {
    vals = convert.r.to.db(vals=vals,rclass = rclass,schema = schema,null.as.na = null.as.na)
  }
  cols = names(vals)

  if (is.null(sql)) {
    sql <- paste0(mode, " into ", table," values (",
      paste0(":",cols,collapse=", "),")")
  }
  if (!run) return(sql)

  if (length(vals[[1]])>1) {
    vals = as.data.frame(vals,stringsAsFactors = FALSE)
    dbWriteTable(conn, table, value=vals, append=TRUE)
  } else {
    ret = dbSendQuery(conn, sql, params=vals)
  }

  if (!is.null(primary.key) & get.key) {
    rs = dbSendQuery(conn, "select last_insert_rowid()")
    pk = dbFetch(rs)
    vals[[primary.key]] = pk[,1]
  }


  invisible(list(values=vals))
}

#' Delete row(s) from table
#'
#' @param conn dbi database connection
#' @param table name of the table
#' @param params named list of values for key fields that identify the rows to be deleted
#' @param sql optional a parameterized sql string
#' @param run if FALSE only return parametrized SQL string
dbDelete = function(conn, table, params, sql=NULL, run = TRUE) {
  restore.point("dbDelete")
  if (is.null(sql)) {
    if (length(params)==0) {
      where = ""
    } else {
      where = paste0(" where ", paste0(names(params)," = :",names(params), collapse= " AND "))
    }
    sql = paste0('delete from ', table, where)
  }
  if (!run)
    return(sql)
  rs = dbSendQuery(conn, sql, params=params)
  rs
}

#' Get rows from a table
#'
#' @param db dbi database connection
#' @param table name of the table
#' @param params named list of values for key fields that identify the rows to be deleted
#' @param sql optional a parameterized sql string
#'        if you want to insert into the sql string
#'        the value from a provided parameter mypar
#'        write :mypar in the SQL string at the corresponding position.
#'        Example:
#'
#'        select * from mytable where name = :myname
#'
#' @param run if FALSE only return parametrized SQL string
#' @param schema a table schema that can be used to convert values
#' @param rclass the r class of the table columns, is extracted from schema
#' @param convert if rclass is given shall results automatically be converted to these classes?
#' @param orderby names of columns the results shall be ordered by as character vector. Add "DESC" or "ASC" after column name to sort descending or ascending. Example: `orderby = c("pos DESC","hp ASC")`
#' @param null.as.na shall NULL values be converted to NA values?
#' @param origin the origin date for DATE and DATETIME conversion
dbGet = function(db, table=NULL,params=NULL, sql=NULL, run = TRUE, schema=NULL, rclass=schema$rclass, convert = !is.null(rclass), orderby=NULL, null.as.na=TRUE, origin = "1970-01-01") {
  restore.point("dbGet")
  if (is.null(sql)) {
    if (tolower(substring(table,1,7))=="select ") {
      sql = table
    } else {
      if (length(params)==0) {
        where = ""
      } else {
        where = paste0(" where ", paste0(names(params)," = :",names(params), collapse= " AND "))
      }
      if (!is.null(orderby)) {
        orderby = paste0(" order by ",paste0(orderby, collapse=", "))
      }
      sql = paste0('select * from ', table, where, orderby)
    }
  }
  if (!run) return(sql)
  rs = dbSendQuery(db, sql, params=params)
  res = dbFetch(rs)
  if (NROW(res)==0) return(NULL)

  if (isTRUE(convert)) {
    res = convert.db.to.r(res,rclass=rclass, schema=schema, null.as.na=null.as.na, origin=origin)
  }

  res
}

#' Convert data from a database table to R format
#'
#' @param vals the values loaded from the database table
#' @param schema a table schema that can be used to convert values
#' @param rclass the r class of the table columns, is extracted from schema
#' @param null.as.na shall NULL values be converted to NA values?
#' @param origin the origin date for DATE and DATETIME conversion
convert.db.to.r = function(vals, rclass=schema$rclass, schema=NULL, as.data.frame=is.data.frame(vals), null.as.na=TRUE, origin = "1970-01-01") {
  restore.point("convert.db.to.r")


  names = names(rclass)
  res = suppressWarnings(lapply(names, function(name) {
    val = vals[[name]]
    if (is.null(val) & null.as.na) val = NA

    # If DATE and DATETIME are stored as numeric, we need an origin for conversion
    if ((is.numeric(val) | is.na(val)) & (rclass[[name]] =="Date" | rclass[[name]] =="POSIXct")) {
      if (is.na(val)) val = NA_real_
      if (rclass[[name]]=="Date") {
        as.Date(val,  origin = origin)
      } else {
        as.POSIXct(val, origin = origin)
      }
    } else {
      as(val,rclass[[name]])
    }
  }))
  names(res) = names
  if (as.data.frame)
    res = as.data.frame(res,stringsAsFactors=FALSE)
  res
}

#' Convert data from a database table to R format
#'
#' @param vals the values loaded from the database table
#' @param schema a table schema that can be used to convert values
#' @param rclass the r class of the table columns, is extracted from schema
#' @param null.as.na shall NULL values be converted to NA values?
#' @param origin the origin date for DATE and DATETIME conversion
convert.r.to.db = function(vals, rclass=schema$rclass, schema=NULL, null.as.na=TRUE, origin = "1970-01-01", add.missing=TRUE) {
  restore.point("convert.r.to.db")

  if (add.missing) {
    names = names(rclass)
  } else {
    names = intersect(names(rclass),names(vals))
  }
  res = suppressWarnings(lapply(names, function(name) {
    val = vals[[name]]
    if (is.null(val) & null.as.na) val = NA

    # If DATE and DATETIME are NA, we need an origin for conversion
    if ( ((is.na(val)) | is.numeric(val)) & (rclass[[name]] =="Date" | rclass[[name]] =="POSIXct")) {
      if (rclass[[name]]=="Date") {
        as.Date(val,  origin = origin)
      } else {
        as.POSIXct(val, origin = origin)
      }
    } else {
      as(val,rclass[[name]])
    }
  }))
  names(res) = names
  res
}



#' Update a row in a database table
#'
#' @param conn dbi database connection
#' @param table name of the table
#' @param vals named list of values to be inserted
#' @param where named list that specifies the keys where to update
#' @param schema a schema as R list, can be used to automatically convert types
#' @param sql optional a parameterized sql string
#' @param run if FALSE only return parametrized SQL string
#' @param rclass the r class of the table columns, is extracted from schema
#' @param convert if rclass is given shall results automatically be converted to these classes?
#' @param null.as.na shall NULL values be converted to NA values?
dbUpdate = function(conn, table, vals,where=NULL, schema=NULL, sql=NULL,run=TRUE,  rclass=schema$rclass, convert=!is.null(rclass), null.as.na=TRUE) {
  restore.point("dbUpdate")

  # Update vals based on table schema
  if (isTRUE(convert)) {
    vals = convert.r.to.db(vals,rclass = rclass,schema = schema,null.as.na = null.as.na, add.missing=FALSE)
    where = convert.r.to.db(where,rclass = rclass,schema = schema,null.as.na = null.as.na, add.missing=FALSE)

  }
  cols = names(vals)

  if (is.null(sql)) {
    sql <- paste0("UPDATE ", table," SET ",
      paste0(cols, " = :",cols,collapse=", "))
    if (!is.null(where)) {
      sql <- paste0(sql," WHERE ",
        paste0(names(where), " = :",names(where),collapse=" AND "))
    }
  }
  if (!run) return(sql)
  ret = dbSendQuery(conn, sql, params=c(vals,where))
  invisible(list(values=vals))
}


#' Create database tables and possible indices from a simple yaml schema
#'
#' @param conn dbi database connection
#' @param schema a schema as R list
#' @param schema.yaml alternatively a schema as yaml text
#' @param schema.file alternatively a file name of a schema yaml file
#' @param overwrite shall existing tables be overwritten?
#' @param silent if TRUE don't show messages
dbCreateSchemaTables = function(conn,schema=NULL, schema.yaml=NULL, schema.file=NULL, overwrite=FALSE,silent=FALSE) {
  restore.point("dbCreateSchemaTables")

  if (is.null(schema)) {
    if (is.null(schema.yaml))
      schema.yaml = readLines(schema.file,warn = FALSE)
    schema.yaml = paste0(schema.yaml, collapse = "\n")
    schema = yaml.load(schema.yaml)
  }

  tables = names(schema)
  lapply(tables, function(table) {
    s = schema[[table]]
    if (overwrite)
      try(dbRemoveTable(conn, table), silent=silent)
    if (!dbExistsTable(conn, table)) {
      # create table
      sql = paste0("CREATE TABLE ", table,"(",
        paste0(names(s$table), " ", s$table, collapse=",\n"),
        ")"
      )
      dbSendQuery(conn,sql)

      # create indexes
      for (index in s$indexes) {
        err = try(dbSendQuery(conn,index), silent=TRUE)
        if (is(err,"try-error")) {
          msg = as.character(err)
          msg = str.right.of(msg,"Error :")
          msg = paste0("When running \n", index,"\n:\n",msg)
          stop(msg)
        }
      }
    }
  })
  invisible(schema)
}

#' Load and init database table schemas from yaml file
#'
#' @param file file name
#' @param yaml yaml as text
load.and.init.schemas = function(file=NULL, yaml=NULL) {
  if (is.null(file)) {
    schemas = yaml.load(paste0(yaml, collapse="\n"))
  } else {
    schemas = yaml.load_file(file)
  }
  names = names(schemas)
  schemas = lapply(names, function(name) {
    init.schema(schemas[[name]],name=name)
  })
  names(schemas) = names
  schemas
}

#' Init a schema by parsing table definition and store info
#' in easy accessibale R format
#'
#' Create rclasses of each column and primary keys
#'
#' @param schema the table schema as an R list
#' @param name of the table
init.schema = function(schema, name=NULL) {
  schema$rclass = schema.r.classes(schema)
  schema$name = name

  cols = sapply(schema$table, tolower)
  rows = grep("integer primary key", cols,fixed = TRUE)
  if (length(rows)>0)
    schema$primary_key = names(schema$table)[rows[1]]
  schema
}

#' Get a vector of R classes of the database columns described in a schema
#'
#' @param schema the schema
schema.r.classes = function(schema) {
  str = tolower(substring(schema$table,1,5))

  classes =c(
    chara = "character",
    text = "character",
    varch = "character",
    boole = "logical",
    integ = "integer",
    numer = "numeric",
    real = "numeric",
    date = "Date",
    datet = "POSIXct"
  )
  res = classes[str]
  names(res) = names(schema$table)
  res
}

example.empty.row.schema = function() {
  setwd("D:/libraries/dbmisc/dbmisc/inst/examples/dbschema")
  schemas = yaml.load_file("strattourndb.yaml")
  row = empty.row.from.schema(schemas$userstrats)
  lapply(row, class)
  list.to.schema.template(row)
}

#' Create an example schema from a list of R objects
#'
#' The output is shown per cat and copied to the clipboard.
#' It can be used as a template for the .yaml schema file
#'
#' @param li The R list for which the schema shall be created
#' @param name optional a name of the table
#' @param toCliboard shall the created text be copied to the clipboard
schema.template = function(li, name="mytable", toClipboard=TRUE) {
  templ = c(
    "character" = "VARCHAR(255)",
    "integer" = "INTEGER",
    "numeric" = "NUMERIC",
    "logical" = "BOOLEAN",
    "POSIXct" = "DATETIME"
  )

  is.subli = sapply(li, function(el) is.list(el))

  eli = li[!is.subli]
  cols = lapply(eli, function(el) {
    cl = class(el)[[1]]
    if (cl %in% names(templ)) {
      return(templ[cl])
    }
    return("UNKNOWN")
  })
  cols = paste0("    ",names(eli),": ", cols)
  txt = paste0('
',name,':
  descr:
  table:
',paste0(cols,collapse='\n'),'
  indexes:
')

  stxt = sapply(names(li)[is.subli], function(name) {
    list.to.schema.template(li[[name]],name, toClipboard=FALSE)
  })
  txt = paste0(c(txt,stxt), collapse="\n")
  if (toClipboard) {
    writeClipboard(txt)
  }
  cat(txt)
  invisible(txt)
}

#' Creates an example row from a database schema table
#' using provided column values and default values specified in schema
empty.row.from.schema = function(.schema, ..., .use.defaults = TRUE) {
  restore.point("schema.value.list")

  empty = list(
    "logical" = NA,
    "numeric" = NA_real_,
    "character" = '',
    "integer" = NA_integer_,
    "datetime" = NA_real_
  )
  if (is.null(.schema$rclass)) {
    classes = schema.r.classes(.schema)
  } else {
    classes = .schema$rclass
  }

  vals = empty[classes]
  table = .schema$table
  names(vals) = names(table)
  if (.use.defaults & !is.null(.schema$defaults)) {
    vals[names(.schema$defaults)] = .schema$defaults
  }
  args = list(...)
  vals[names(args)] = args
  vals
}

#' Creates an example data frame from a database schema table
#' using provided column values and default values specified in schema
empty.df.from.schema = function(.schema,.nrows=1, ..., .use.defaults = TRUE) {
  restore.point("empty.df.from.schema")
  li = empty.row.from.schema(.schema, ..., .use.defaults=.use.defaults)
  if (.nrows==1) return(as.data.frame(li))

  df = as.data.frame(lapply(li, function(col) rep(col,length.out = .nrows)))
  df
}
