--- aws.nvim – DynamoDB table item scan / query buffer
---
--- Supports:
---   Scan   – optional FilterExpression + ExpressionAttributeValues
---   Query  – guided PK / SK / FilterExpression + optional GSI/LSI
---
--- Results are paginated; press <scan_next> to fetch the next page.
--- Press <scan_json> to toggle between table view and raw JSON view.
local M = {}

local spawn   = require("aws.spawn")
local buf_mod = require("aws.buffer")
local keymaps = require("aws.keymaps")
local config  = require("aws.config")

local FILETYPE = "aws-dynamodb"

---@class DynamoDbScanState
---@field table_name    string
---@field mode          "scan"|"query"
---@field pk_name       string|nil      partition key attribute name (query)
---@field pk_value      string|nil      partition key value (query)
---@field pk_type       string          "S"|"N"|"B"  (default "S")
---@field sk_name       string|nil      sort key attribute name (query, optional)
---@field sk_op         string|nil      comparison op for SK: "="|"<"|"<="|">"|">="|"begins_with"|"between"
---@field sk_value      string|nil      sort key value (or first value for between)
---@field sk_value2     string|nil      second value for between
---@field sk_type       string          "S"|"N"|"B"
---@field natural_filter string|nil     raw user input for the smart filter prompt
---@field filter_expr   string|nil      FilterExpression (both modes, optional)
---@field filter_vals   table|nil       ExpressionAttributeValues for filter (#name -> {:T val})
---@field filter_names  table|nil       ExpressionAttributeNames for filter (#alias -> attrName)
---@field index_name    string|nil      GSI/LSI name (optional)
---@field items         table[]         current page of decoded items
---@field last_key      string|nil      pagination token; nil = no more pages
---@field page          integer         current page number (1-based)
---@field fetching      boolean
---@field json_view     boolean         toggle: raw JSON vs table view
---@field region        string
---@field profile       string|nil

local _state = {}  -- table_name -> DynamoDbScanState

local function buf_name(table_name)
  return "aws://dynamodb/scan/" .. table_name
end

-------------------------------------------------------------------------------
-- View helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local display_len = vim.fn.strdisplaywidth(s)
  if display_len >= width then return s end
  return s .. string.rep(" ", width - display_len)
end

---@param s   string
---@param max integer
---@return string
local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then return s end
  local result = ""
  local cols   = 0
  local nchars = vim.fn.strchars(s)
  for i = 0, nchars - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w  = vim.fn.strdisplaywidth(ch)
    if cols + w > max - 1 then break end
    result = result .. ch
    cols   = cols + w
  end
  return result .. "…"
end

--- Convert a DynamoDB typed attribute value to a human-readable string.
--- e.g. { S = "hello" } -> "hello",  { N = "42" } -> "42",  { SS = {...} } -> "{a, b}"
---@param attr table
---@return string
local function fmt_attr(attr)
  if type(attr) ~= "table" then return tostring(attr) end
  if attr.S    ~= nil then return tostring(attr.S) end
  if attr.N    ~= nil then return tostring(attr.N) end
  if attr.BOOL ~= nil then return tostring(attr.BOOL) end
  if attr.NULL ~= nil then return "NULL" end
  if attr.B    ~= nil then return "<Binary>" end
  if attr.SS   ~= nil then
    return "{" .. table.concat(type(attr.SS) == "table" and attr.SS or {}, ", ") .. "}"
  end
  if attr.NS   ~= nil then
    return "{" .. table.concat(type(attr.NS) == "table" and attr.NS or {}, ", ") .. "}"
  end
  if attr.BS   ~= nil then return "<BinarySet[" .. #(attr.BS or {}) .. "]>" end
  if attr.L    ~= nil then
    local parts = {}
    for _, v in ipairs(type(attr.L) == "table" and attr.L or {}) do
      table.insert(parts, fmt_attr(v))
    end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  if attr.M    ~= nil then
    local parts = {}
    for k, v in pairs(type(attr.M) == "table" and attr.M or {}) do
      table.insert(parts, k .. ": " .. fmt_attr(v))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return vim.inspect(attr)
end

---@param item      table   map of attr-name -> typed-value
---@param key_width integer
---@return string[]
local function fmt_item_table(item, key_width)
  local keys = {}
  for k in pairs(item) do table.insert(keys, k) end
  table.sort(keys)
  local lines = {}
  for _, k in ipairs(keys) do
    local val = fmt_attr(item[k])
    table.insert(lines, "  " .. pad_right(k, key_width) .. truncate(val, 120))
  end
  return lines
end

---@param item table
---@return string[]   indented JSON lines
local function fmt_item_json(item)
  -- Convert typed DynamoDB attribute map to plain Lua table first,
  -- then JSON-encode it for a clean JSON view.
  local function unwrap(attr)
    if type(attr) ~= "table" then return attr end
    if attr.S    ~= nil then return attr.S end
    if attr.N    ~= nil then return tonumber(attr.N) end
    if attr.BOOL ~= nil then return attr.BOOL end
    if attr.NULL ~= nil then return vim.NIL end
    if attr.B    ~= nil then return "<Binary>" end
    if attr.SS   ~= nil then return attr.SS end
    if attr.NS   ~= nil then
      local out = {}
      for _, v in ipairs(type(attr.NS) == "table" and attr.NS or {}) do
        table.insert(out, tonumber(v))
      end
      return out
    end
    if attr.BS   ~= nil then return attr.BS end
    if attr.L    ~= nil then
      local out = {}
      for _, v in ipairs(type(attr.L) == "table" and attr.L or {}) do
        table.insert(out, unwrap(v))
      end
      return out
    end
    if attr.M    ~= nil then
      local out = {}
      for k, v in pairs(type(attr.M) == "table" and attr.M or {}) do
        out[k] = unwrap(v)
      end
      return out
    end
    return attr
  end

  local plain = {}
  for k, v in pairs(item) do
    plain[k] = unwrap(v)
  end

  local ok, encoded = pcall(vim.json.encode, plain)
  if not ok then
    return { "  <json encode error>" }
  end

  -- Pretty-print: indent 2 spaces.  vim.json.encode returns minified JSON so
  -- we do a simple manual pass.
  local pretty_ok, pretty = pcall(function()
    -- Re-decode then re-encode with vim's pretty printer isn't available in all
    -- nvim 0.9 builds, so we do a simple character-by-character indent.
    local out   = {}
    local depth = 0
    local i     = 1
    local len   = #encoded
    local line  = ""
    local in_str = false

    local function flush()
      if line ~= "" then
        table.insert(out, string.rep("  ", depth + 1) .. vim.trim(line))
        line = ""
      end
    end

    while i <= len do
      local c = encoded:sub(i, i)
      if in_str then
        line = line .. c
        if c == '"' and encoded:sub(i - 1, i - 1) ~= "\\" then
          in_str = false
        end
      elseif c == '"' then
        line  = line .. c
        in_str = true
      elseif c == "{" or c == "[" then
        flush()
        table.insert(out, string.rep("  ", depth + 1) .. c)
        depth = depth + 1
      elseif c == "}" or c == "]" then
        flush()
        depth = depth - 1
        table.insert(out, string.rep("  ", depth + 1) .. c)
      elseif c == "," then
        line = line .. c
        flush()
      elseif c == ":" then
        line = line .. c .. " "
      elseif c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
        line = line .. c
      end
      i = i + 1
    end
    flush()
    return out
  end)

  if pretty_ok and #pretty > 0 then
    return pretty
  end
  -- Fallback: single indented line
  return { "  " .. encoded }
end

--- Split any lines that contain embedded newlines so nvim_buf_set_lines never
--- receives a string with '\n' inside it.
---@param raw_lines string[]
---@return string[]
local function safe_lines(raw_lines)
  local out = {}
  for _, l in ipairs(raw_lines) do
    for _, sl in ipairs(vim.split(l, "\n", { plain = true })) do
      table.insert(out, sl)
    end
  end
  return out
end

--- DynamoDB reserved words that commonly appear as user attribute names.
--- Using any of these bare in an expression causes a CLI error, so we
--- auto-alias them with a "#" prefix.
local RESERVED = {
  ABORT=1, ABSOLUTE=1, ACTION=1, ADD=1, AFTER=1, AGENT=1, ALL=1, ALLOCATE=1,
  ALTER=1, ANALYZE=1, AND=1, ANY=1, ARCHIVE=1, ARE=1, ARRAY=1, AS=1, ASC=1,
  ASCII=1, ASENSITIVE=1, ASSERTION=1, ASYMMETRIC=1, AT=1, ATOMIC=1, ATTACH=1,
  ATTRIBUTE=1, AUTH=1, AUTHORIZATION=1, AUTHORIZE=1, AUTO=1, AVG=1,
  BACK=1, BACKUP=1, BASE=1, BATCH=1, BEFORE=1, BEGIN=1, BETWEEN=1, BIGINT=1,
  BINARY=1, BIT=1, BLOB=1, BLOCK=1, BOOLEAN=1, BOTH=1, BREADTH=1, BUCKET=1,
  BULK=1, BY=1,
  CALL=1, CALLED=1, CALLING=1, CASCADE=1, CASCADED=1, CASE=1, CAST=1,
  CATALOG=1, CHAR=1, CHARACTER=1, CHECK=1, CLASS=1, CLOB=1, CLOSE=1,
  CLUSTER=1, CLUSTERED=1, CLUSTERING=1, CLUSTERS=1, COALESCE=1, COLLATE=1,
  COLUMN=1, COLUMNS=1, COMBINE=1, COMMENT=1, COMMIT=1, COMPACT=1,
  COMPILE=1, COMPRESS=1, CONDITION=1, CONFLICT=1, CONNECT=1, CONNECTION=1,
  CONSISTENCY=1, CONSISTENT=1, CONSTRAINT=1, CONSTRAINTS=1, CONTINUE=1,
  CONVERT=1, COPY=1, CORRESPONDING=1, COUNT=1, COUNTER=1, CREATE=1,
  CROSS=1, CUBE=1, CURRENT=1, CURSOR=1, CYCLE=1,
  DATA=1, DATABASE=1, DATE=1, DATETIME=1, DAY=1, DEALLOCATE=1, DEC=1,
  DECIMAL=1, DECLARE=1, DEFAULT=1, DEFERRABLE=1, DEFERRED=1, DELETE=1,
  DEPTH=1, DEREF=1, DESC=1, DESCRIBE=1, DESCRIPTOR=1, DETACH=1,
  DETERMINISTIC=1, DIAGNOSTICS=1, DIRECTORIES=1, DISABLE=1, DISCONNECT=1,
  DISTINCT=1, DISTRIBUTE=1, DO=1, DOUBLE=1, DROP=1, DUMP=1, DURATION=1,
  DYNAMIC=1,
  EACH=1, ELEMENT=1, ELSE=1, ELSEIF=1, EMPTY=1, ENABLE=1, END=1,
  EQUAL=1, ERROR=1, ESCAPE=1, EVAL=1, EVALUATE=1, EXCEEDED=1, EXCEPT=1,
  EXCLUSIVE=1, EXEC=1, EXECUTE=1, EXISTS=1, EXPLAIN=1, EXPLODE=1,
  EXPORT=1, EXPRESSION=1, EXTENDED=1, EXTERNAL=1,
  FAIL=1, FINAL=1, FINISH=1, FIRST=1, FIXED=1, FLATTERN=1, FLOAT=1,
  FOR=1, FORCE=1, FOREIGN=1, FORMAT=1, FORWARD=1, FOUND=1, FREE=1,
  FROM=1, FULL=1, FUNCTION=1, FUNCTIONS=1,
  GENERAL=1, GENERATE=1, GET=1, GLOB=1, GLOBAL=1, GO=1, GOTO=1,
  GRANT=1, GREATER=1, GROUP=1, GROUPING=1,
  HANDLER=1, HASH=1, HAVE=1, HAVING=1, HEAP=1, HIDDEN=1, HOLD=1, HOUR=1,
  IDENTIFIED=1, IDENTITY=1, IF=1, IGNORE=1, IMMEDIATE=1, IMPORT=1,
  IN=1, INCLUDING=1, INCLUSIVE=1, INCREMENT=1, INCREMENTAL=1, INDEX=1,
  INDEXED=1, INDEXES=1, INDICATOR=1, INFINITE=1, INITIALLY=1, INLINE=1,
  INNER=1, INNTER=1, INOUT=1, INPUT=1, INSENSITIVE=1, INSERT=1,
  INSTEAD=1, INT=1, INTEGER=1, INTERSECT=1, INTERVAL=1, INTO=1,
  INVALIDATE=1, IS=1, ISOLATION=1, ITEM=1, ITEMS=1, ITERATE=1,
  JOIN=1,
  KEY=1, KEYS=1,
  LAG=1, LANGUAGE=1, LARGE=1, LAST=1, LATERAL=1, LEAD=1, LEADING=1,
  LEAVE=1, LEFT=1, LENGTH=1, LESS=1, LEVEL=1, LIKE=1, LIMIT=1,
  LIMITED=1, LINES=1, LIST=1, LOAD=1, LOCAL=1, LOCALTIME=1,
  LOCALTIMESTAMP=1, LOCATION=1, LOCATOR=1, LOCK=1, LOCKS=1, LOG=1,
  LOGED=1, LONG=1, LOOP=1, LOWER=1,
  MAP=1, MATCH=1, MATERIALIZED=1, MAX=1, MAXLEN=1, MEMBER=1, MERGE=1,
  METHOD=1, METRICS=1, MIN=1, MINUS=1, MINUTE=1, MISSING=1, MOD=1,
  MODE=1, MODIFIES=1, MODIFY=1, MODULE=1, MONTH=1, MULTI=1, MULTISET=1,
  NAME=1, NAMES=1, NATIONAL=1, NATURAL=1, NCHAR=1, NCLOB=1, NEW=1,
  NEXT=1, NO=1, NONE=1, NOT=1, NULL=1, NULLIF=1, NUMBER=1, NUMERIC=1,
  OBJECT=1, OF=1, OFFLINE=1, OFFSET=1, OLD=1, ON=1, ONLINE=1, ONLY=1,
  OPAQUE=1, OPEN=1, OPERATOR=1, OPTION=1, OR=1, ORDER=1, ORDINALITY=1,
  OTHER=1, OTHERS=1, OUT=1, OUTER=1, OUTPUT=1, OVER=1, OVERLAPS=1,
  OVERRIDE=1, OWNER=1,
  PAD=1, PARALLEL=1, PARAMETER=1, PARAMETERS=1, PARTIAL=1, PARTITION=1,
  PARTITIONED=1, PARTITIONS=1, PATH=1, PERCENT=1, PERCENTILE=1,
  PERMISSION=1, PERMISSIONS=1, PIPE=1, PIPELINED=1, PLAN=1, POOL=1,
  POSITION=1, PRECISION=1, PREPARE=1, PRESERVE=1, PRIMARY=1, PRIOR=1,
  PRIVATE=1, PRIVILEGES=1, PROCEDURE=1, PROCESSED=1, PROJECT=1,
  PROJECTION=1, PROPERTY=1, PROVISIONING=1, PUBLIC=1, PUT=1,
  QUERY=1, QUIT=1, QUORUM=1,
  RAISE=1, RANDOM=1, RANGE=1, RANK=1, RAW=1, READ=1, READS=1, REAL=1,
  REBUILD=1, RECORD=1, RECURSIVE=1, REDUCE=1, REF=1, REFERENCE=1,
  REFERENCES=1, REFERENCING=1, REGEXP=1, REGION=1, REINDEX=1,
  RELATIVE=1, RELEASE=1, REMAINDER=1, RENAME=1, REPEAT=1, REPLACE=1,
  REQUEST=1, RESET=1, RESIGNAL=1, RESOURCE=1, RESPONSE=1, RESTORE=1,
  RESTRICT=1, RESULT=1, RETURN=1, RETURNING=1, RETURNS=1, REVERSE=1,
  RIGHT=1, ROLE=1, ROLES=1, ROLLBACK=1, ROLLUP=1, ROUTINE=1, ROW=1,
  ROWS=1, RULE=1,
  SAVEPOINT=1, SCROLL=1, SEARCH=1, SECOND=1, SECTION=1, SEGMENT=1,
  SELECT=1, SELF=1, SENSITIVE=1, SEQUENCE=1, SERIALIZABLE=1, SESSION=1,
  SET=1, SETS=1, SIGNAL=1, SIMILAR=1, SIZE=1, SKEWED=1, SMALLINT=1,
  SNAPSHOT=1, SOME=1, SPACE=1, SPECIFIC=1, SPECIFICTYPE=1, SPLIT=1,
  SQL=1, SQLCODE=1, SQLERROR=1, SQLEXCEPTION=1, SQLSTATE=1,
  SQLWARNING=1, START=1, STATE=1, STATIC=1, STATUS=1, STORAGE=1,
  STORE=1, STORED=1, STREAM=1, STRING=1, STRUCT=1, STYLE=1,
  SUB=1, SUBMULTISET=1, SUBPARTITION=1, SUBSTRING=1, SUBTYPE=1,
  SUM=1, SUPER=1, SYMMETRIC=1, SYNONYM=1, SYSTEM=1,
  TABLE=1, TABLESAMPLE=1, TEMP=1, TEMPORARY=1, TERMINATED=1, TEXT=1,
  THAN=1, THEN=1, TIME=1, TIMESTAMP=1, TIMEZONE=1, TINYINT=1, TO=1,
  TOKEN=1, TOTAL=1, TOUCH=1, TRAILING=1, TRANSACTION=1, TRANSFORM=1,
  TRANSLATE=1, TRANSLATION=1, TREAT=1, TRIGGER=1, TRIM=1, TRUE=1,
  TRUNCATE=1, TTL=1, TUPLE=1, TYPE=1, TYPES=1,
  UNDER=1, UNION=1, UNIQUE=1, UNIT=1, UNKNOWN=1, UNLOGGED=1,
  UNNEST=1, UNPROCESSED=1, UNSIGNED=1, UNTIL=1, UPDATE=1, UPPER=1,
  URL=1, USAGE=1, USE=1, USER=1, USERS=1, USING=1,
  UUID=1,
  VACUUM=1, VALUE=1, VALUED=1, VALUES=1, VARCHAR=1, VARIABLE=1,
  VARIANCE=1, VARINT=1, VARYING=1, VIEW=1, VIEWS=1, VIRTUAL=1, VOID=1,
  WAIT=1, WHEN=1, WHENEVER=1, WHERE=1, WHILE=1, WINDOW=1, WITH=1,
  WITHIN=1, WITHOUT=1, WORK=1, WRAPPED=1, WRITE=1,
  YEAR=1,
  ZONE=1,
}

--- Parse a natural-language filter expression like "status = ERROR" or
--- "createdAt >= 2025-01-01 AND status = READY".
---
--- Rules:
---   - Attribute names that are DynamoDB reserved words are auto-aliased (#attr)
---   - Values that look like numbers get type N, everything else gets type S
---   - Operators supported: =  <>  <  <=  >  >=  begins_with  contains
---   - AND / OR are passed through verbatim (they don't need substitution)
---   - If the user already typed a proper DynamoDB expression (contains # or :)
---     it is passed through unchanged with empty EAN/EAV (advanced mode)
---
--- Returns:
---   filter_expr  string   DynamoDB expression string
---   filter_names table    EAN map  { ["#attr"] = "attr" }
---   filter_vals  table    EAV map  { [":attr0"] = { S|N = "val" } }
---@param input string
---@return string, table, table
local function parse_natural_filter(input)
  -- Pass-through: user is writing a real DynamoDB expression themselves
  if input:find("[#:]") then
    return input, {}, {}
  end

  local names = {}
  local vals   = {}
  local counters = {}  -- attr -> count, for deduplication

  -- Tokenise into clauses split on AND/OR (case-insensitive)
  -- We process each comparison individually then reassemble.
  local function alias_name(attr)
    local up = attr:upper()
    if RESERVED[up] then
      local alias = "#" .. attr:lower():gsub("[^%w_]", "_")
      names[alias] = attr
      return alias
    end
    return attr
  end

  local function alias_value(attr_raw, val)
    local base = attr_raw:lower():gsub("[^%w_]", "_")
    counters[base] = (counters[base] or -1) + 1
    local placeholder = ":" .. base .. (counters[base] > 0 and tostring(counters[base]) or "")
    local typ = (val:match("^%-?%d+%.?%d*$")) and "N" or "S"
    vals[placeholder] = { [typ] = val }
    return placeholder
  end

  -- Split on AND/OR boundaries, preserving the connectors
  local parts  = {}
  local connectors = {}
  -- Split by AND/OR (with surrounding spaces), case-insensitive
  local remainder = input
  while true do
    local s, e, conn = remainder:find("%s+(AND)%s+", 1)
    if not s then s, e, conn = remainder:find("%s+(OR)%s+", 1) end
    if not s then
      table.insert(parts, vim.trim(remainder))
      break
    end
    table.insert(parts, vim.trim(remainder:sub(1, s - 1)))
    table.insert(connectors, conn)
    remainder = remainder:sub(e + 1)
  end

  local expr_parts = {}
  for _, clause in ipairs(parts) do
    -- begins_with(attr, value)
    local bw_attr, bw_val = clause:match("^begins_with%s*%(%s*([%w_.]+)%s*,%s*(.-)%s*%)$")
    if bw_attr then
      local an = alias_name(bw_attr)
      local vn = alias_value(bw_attr, bw_val)
      table.insert(expr_parts, "begins_with(" .. an .. ", " .. vn .. ")")
    else
      -- contains(attr, value)
      local ct_attr, ct_val = clause:match("^contains%s*%(%s*([%w_.]+)%s*,%s*(.-)%s*%)$")
      if ct_attr then
        local an = alias_name(ct_attr)
        local vn = alias_value(ct_attr, ct_val)
        table.insert(expr_parts, "contains(" .. an .. ", " .. vn .. ")")
      else
        -- standard:  attr OP value   (OP = = <> < <= > >=)
        -- Lua patterns don't support alternation, so match op manually.
        local attr, op, val
        for _, op_try in ipairs({ "<>", "<=", ">=", "<", ">", "=" }) do
          attr, val = clause:match("^([%w_.]+)%s*" .. op_try:gsub("<", "<"):gsub(">", ">") .. "%s*(.+)$")
          if attr then op = op_try break end
        end
        if attr and op and val then
          local an = alias_name(attr)
          local vn = alias_value(attr, vim.trim(val))
          table.insert(expr_parts, an .. " " .. op .. " " .. vn)
        else
          -- Unrecognised clause — pass through as-is
          table.insert(expr_parts, clause)
        end
      end
    end
  end

  -- Reassemble with connectors
  local expr = expr_parts[1] or ""
  for i, conn in ipairs(connectors) do
    expr = expr .. " " .. conn .. " " .. (expr_parts[i + 1] or "")
  end

  return expr, names, vals
end

---@param buf integer
---@param st  DynamoDbScanState
local function render(buf, st)
  local km      = config.values.keymaps.dynamodb
  local region  = st.region
  local profile = st.profile

  -- ── Title ───────────────────────────────────────────────────────────────
  local mode_label = st.mode == "query" and "Query" or "Scan"
  local view_label = st.json_view and "JSON" or "Table"
  local title = "DynamoDB  >>  " .. st.table_name
    .. "  (" .. mode_label .. " / " .. view_label .. " view)"
    .. "   [region: " .. region .. "]"
    .. (profile and ("   [profile: " .. profile .. "]") or "")
    .. (st.fetching and "  [loading…]" or "")

  local sep_len = math.max(vim.fn.strdisplaywidth(title), 72)
  local sep     = string.rep("-", sep_len)

  local hints = {}
  if km.scan_run  then table.insert(hints, km.scan_run  .. " run/rebuild") end
  if km.scan_next then table.insert(hints, km.scan_next .. " next page")   end
  local json_key = km.scan_json or "J"
  table.insert(hints, json_key .. " toggle JSON/table view")

  local lines = { "", title, "", sep }
  table.insert(lines, table.concat(hints, "  |  "))
  table.insert(lines, sep)

  -- ── Parameters ──────────────────────────────────────────────────────────
  if st.mode == "query" then
    table.insert(lines, "  Mode            Query")
    if st.pk_name then
      local pk_str = st.pk_name .. " = " .. (st.pk_value or "?")
        .. "  (" .. st.pk_type .. ")"
      table.insert(lines, "  Partition Key   " .. pk_str)
    end
    if st.sk_name and st.sk_op then
      local sk_str = st.sk_name .. " " .. st.sk_op .. " " .. (st.sk_value or "?")
        .. (st.sk_op == "between" and " AND " .. (st.sk_value2 or "?") or "")
        .. "  (" .. st.sk_type .. ")"
      table.insert(lines, "  Sort Key        " .. sk_str)
    end
    if st.natural_filter and st.natural_filter ~= "" then
      table.insert(lines, "  Filter          " .. st.natural_filter)
    elseif st.filter_expr then
      -- advanced pass-through (user typed # or : directly)
      table.insert(lines, "  Filter Expr     " .. st.filter_expr)
    end
  else
    table.insert(lines, "  Mode            Scan")
    if st.natural_filter and st.natural_filter ~= "" then
      table.insert(lines, "  Filter          " .. st.natural_filter)
    elseif st.filter_expr then
      -- advanced pass-through
      table.insert(lines, "  Filter Expr     " .. st.filter_expr)
    else
      table.insert(lines, "  Filter          (none — full table scan)")
    end
  end
  if st.index_name then
    table.insert(lines, "  Index           " .. st.index_name)
  end
  table.insert(lines, "  Page            " .. st.page)
  table.insert(lines, sep)

  -- ── Items ────────────────────────────────────────────────────────────────
  if st.fetching then
    table.insert(lines, "  [loading…]")
  elseif #st.items == 0 then
    table.insert(lines, "  (no items returned)")
  else
    table.insert(lines,
      "  Items (" .. #st.items .. " on this page)"
      .. (st.last_key and "  [more pages available]" or ""))
    table.insert(lines, sep)

    if st.json_view then
      -- ── JSON view ──────────────────────────────────────────────────────
      for i, item in ipairs(st.items) do
        table.insert(lines, "  ── item " .. i .. " ──")
        for _, l in ipairs(safe_lines(fmt_item_json(item))) do
          table.insert(lines, l)
        end
      end
    else
      -- ── Table view (key-value aligned) ─────────────────────────────────
      local key_width = 8
      for _, item in ipairs(st.items) do
        for k in pairs(item) do
          local w = vim.fn.strdisplaywidth(k)
          if w > key_width then key_width = w end
        end
      end
      key_width = key_width + 2

      for i, item in ipairs(st.items) do
        table.insert(lines, "  ── item " .. i .. " ──")
        for _, row_line in ipairs(safe_lines(fmt_item_table(item, key_width))) do
          table.insert(lines, row_line)
        end
      end
    end
  end

  table.insert(lines, "")
  buf_mod.set_lines(buf, lines)
end

-------------------------------------------------------------------------------
-- Expression builder helpers
-------------------------------------------------------------------------------

--- Prompt for attribute type.
---@param prompt  string
---@param default string  "S"|"N"|"B"
---@param cb      fun(t: string)
local function pick_type(prompt, default, cb)
  local choices = { "S  (String)", "N  (Number)", "B  (Binary)" }
  local default_idx = default == "N" and 2 or default == "B" and 3 or 1
  -- pre-select the default by listing it first
  local ordered = { choices[default_idx] }
  for i, c in ipairs(choices) do
    if i ~= default_idx then table.insert(ordered, c) end
  end
  vim.ui.select(ordered, { prompt = prompt }, function(_, idx)
    if not idx then cb(default) return end
    local selected = ordered[idx]
    if selected:sub(1, 1) == "N" then cb("N")
    elseif selected:sub(1, 1) == "B" then cb("B")
    else cb("S") end
  end)
end

--- Prompt for SK comparison operator.
---@param cb fun(op: string|nil)  nil = skip SK
local function pick_sk_op(cb)
  local ops = {
    "=        exact match",
    "<        less than",
    "<=       less than or equal",
    ">        greater than",
    ">=       greater than or equal",
    "begins_with",
    "between  (inclusive range)",
    "-- skip sort key --",
  }
  vim.ui.select(ops, { prompt = "Sort key condition:" }, function(_, idx)
    if not idx then cb(nil) return end
    if idx == #ops then cb(nil) return end  -- skip
    local op_map = { "=", "<", "<=", ">", ">=", "begins_with", "between" }
    cb(op_map[idx])
  end)
end

--- Build ExpressionAttributeValues from the current state.
--- Returns a JSON-encoded string suitable for --expression-attribute-values.
---@param st DynamoDbScanState
---@return string|nil  nil when no values are needed
local function build_eav(st)
  local eav = {}

  if st.mode == "query" and st.pk_name and st.pk_value then
    eav[":pk"] = { [st.pk_type] = st.pk_value }
  end

  if st.mode == "query" and st.sk_name and st.sk_op and st.sk_value then
    eav[":sk"] = { [st.sk_type] = st.sk_value }
    if st.sk_op == "between" and st.sk_value2 then
      eav[":sk2"] = { [st.sk_type] = st.sk_value2 }
    end
  end

  -- Parse user-supplied filter values.  Accept simple colon-separated pairs:
  --   :val1=S:hello  :val2=N:42
  -- If st.filter_vals is already a table (set programmatically) use it directly.
  if type(st.filter_vals) == "table" then
    for k, v in pairs(st.filter_vals) do
      eav[k] = v
    end
  end

  if not next(eav) then return nil end
  local ok, encoded = pcall(vim.json.encode, eav)
  return ok and encoded or nil
end

--- Build the key condition expression string for a query.
---@param st DynamoDbScanState
---@return string|nil
local function build_kce(st)
  if not st.pk_name or not st.pk_value then return nil end

  -- Use expression attribute names to avoid conflicts with reserved words.
  local expr = "#pk = :pk"

  if st.sk_name and st.sk_op and st.sk_value then
    if st.sk_op == "begins_with" then
      expr = expr .. " AND begins_with(#sk, :sk)"
    elseif st.sk_op == "between" and st.sk_value2 then
      expr = expr .. " AND #sk BETWEEN :sk AND :sk2"
    else
      expr = expr .. " AND #sk " .. st.sk_op .. " :sk"
    end
  end

  return expr
end

--- Build --expression-attribute-names JSON.
--- For query mode: always maps #pk/#sk to the key attribute names.
--- For both modes: merges any user-supplied filter_names (#alias -> attrName).
---@param st DynamoDbScanState
---@return string|nil
local function build_ean(st)
  local ean = {}

  -- Query key aliases
  if st.mode == "query" and st.pk_name then
    ean["#pk"] = st.pk_name
    if st.sk_name then ean["#sk"] = st.sk_name end
  end

  -- User-supplied filter aliases (both scan and query)
  if type(st.filter_names) == "table" then
    for alias, name in pairs(st.filter_names) do
      ean[alias] = name
    end
  end

  if not next(ean) then return nil end
  local ok, encoded = pcall(vim.json.encode, ean)
  return ok and encoded or nil
end

-------------------------------------------------------------------------------
-- Fetch
-------------------------------------------------------------------------------

---@param st      DynamoDbScanState
---@param last_key string|nil  pagination token
---@return string[]  CLI args
local function build_args(st, last_key)
  local args
  if st.mode == "query" then
    args = { "dynamodb", "query", "--table-name", st.table_name }
    local kce = build_kce(st)
    if kce then
      vim.list_extend(args, { "--key-condition-expression", kce })
    end
    local ean = build_ean(st)
    if ean then
      vim.list_extend(args, { "--expression-attribute-names", ean })
    end
    if st.filter_expr and st.filter_expr ~= "" then
      vim.list_extend(args, { "--filter-expression", st.filter_expr })
    end
  else
    args = { "dynamodb", "scan", "--table-name", st.table_name }
    if st.filter_expr and st.filter_expr ~= "" then
      vim.list_extend(args, { "--filter-expression", st.filter_expr })
    end
    local ean = build_ean(st)
    if ean then
      vim.list_extend(args, { "--expression-attribute-names", ean })
    end
  end

  if st.index_name and st.index_name ~= "" then
    vim.list_extend(args, { "--index-name", st.index_name })
  end

  local eav = build_eav(st)
  if eav then
    vim.list_extend(args, { "--expression-attribute-values", eav })
  end

  vim.list_extend(args, { "--max-items", "50", "--output", "json" })

  if last_key then
    vim.list_extend(args, { "--starting-token", last_key })
  end

  -- DEBUG: remove after confirming EAN/EAV are correct
  vim.notify("[aws.nvim debug] args: " .. vim.inspect(args), vim.log.levels.WARN)

  return args
end

---@param table_name string
---@param buf        integer
---@param call_opts  AwsCallOpts|nil
---@param last_key   string|nil
local function fetch(table_name, buf, call_opts, last_key)
  local st = _state[table_name]
  if not st then return end

  st.fetching = true
  render(buf, st)

  local args = build_args(st, last_key)

  spawn.run(args, function(ok, lines)
    if not st or _state[table_name] ~= st then return end
    st.fetching = false
    if not ok then
      buf_mod.set_error(buf, lines)
      return
    end
    local raw = table.concat(lines, "\n")
    local ok2, data = pcall(vim.json.decode, raw)
    if not ok2 or type(data) ~= "table" then
      buf_mod.set_error(buf, { "Failed to parse JSON", raw })
      return
    end
    st.items    = type(data.Items) == "table" and data.Items or {}
    st.last_key = type(data.NextToken) == "string" and data.NextToken
      or (type(data.LastEvaluatedKey) == "table"
          and vim.json.encode(data.LastEvaluatedKey) or nil)
    render(buf, st)
  end, call_opts)
end

-------------------------------------------------------------------------------
-- Interactive query builder
-- Walks the user through PK, optional SK, optional filter, optional index.
-------------------------------------------------------------------------------

--- Shared tail of every wizard: single natural-language filter prompt → index → fetch.
--- Auto-generates EAN/EAV via parse_natural_filter.
--- Clears last_key and resets page before fetching.
---@param st        DynamoDbScanState
---@param buf       integer
---@param call_opts AwsCallOpts|nil
---@param filter_prompt string   prompt text for the filter expression step
local function ask_filter_then_fetch(st, buf, call_opts, filter_prompt)
  vim.ui.input(
    { prompt = filter_prompt, default = st.natural_filter or "" },
    function(input)
      if input == nil then return end  -- cancelled
      if input == "" then
        st.filter_expr    = nil
        st.filter_names   = nil
        st.filter_vals    = nil
        st.natural_filter = nil
      else
        st.natural_filter = input
        vim.notify("[aws.nvim debug] ask_filter input=" .. vim.inspect(input), vim.log.levels.WARN)
        local expr, names, vals = parse_natural_filter(input)
        vim.notify("[aws.nvim debug] parsed expr=" .. vim.inspect(expr) .. " names=" .. vim.inspect(names) .. " vals=" .. vim.inspect(vals), vim.log.levels.WARN)
        st.filter_expr  = expr
        st.filter_names = next(names) and names or nil
        st.filter_vals  = next(vals)  and vals  or nil
      end

      vim.ui.input(
        { prompt = "Index name (GSI/LSI, leave blank for base table): ",
          default = st.index_name or "" },
        function(idx_name)
          st.index_name = (idx_name and idx_name ~= "") and idx_name or nil
          st.last_key   = nil
          st.page       = 1
          fetch(st.table_name, buf, call_opts, nil)
        end
      )
    end
  )
end

---@param st        DynamoDbScanState
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function run_query_wizard(st, buf, call_opts)
  -- Step 1: partition key name
  vim.ui.input(
    { prompt = "Partition key attribute name: ", default = st.pk_name or "" },
    function(pk_name)
      if not pk_name or pk_name == "" then return end
      st.pk_name = pk_name

      -- Step 2: partition key type
      pick_type("Partition key type:", st.pk_type or "S", function(pk_type)
        st.pk_type = pk_type

        -- Step 3: partition key value
        vim.ui.input(
          { prompt = "Partition key value: ", default = st.pk_value or "" },
          function(pk_value)
            if not pk_value or pk_value == "" then return end
            st.pk_value = pk_value

            -- Step 4: sort key operator (or skip)
            pick_sk_op(function(sk_op)
              if not sk_op then
                -- No sort key — go straight to filter + index
                st.sk_name   = nil
                st.sk_op     = nil
                st.sk_value  = nil
                st.sk_value2 = nil
                ask_filter_then_fetch(st, buf, call_opts,
                  "Filter Expression (optional, leave blank to skip): ")
                return
              end

              -- Has sort key — need name, type, value(s)
              vim.ui.input(
                { prompt = "Sort key attribute name: ", default = st.sk_name or "" },
                function(sk_name)
                  if not sk_name or sk_name == "" then return end
                  st.sk_name = sk_name
                  st.sk_op   = sk_op

                  pick_type("Sort key type:", st.sk_type or "S", function(sk_type)
                    st.sk_type = sk_type

                    local sk_prompt = sk_op == "between"
                      and "Sort key value (lower bound): "
                      or  "Sort key value: "
                    vim.ui.input(
                      { prompt = sk_prompt, default = st.sk_value or "" },
                      function(sk_value)
                        if not sk_value or sk_value == "" then return end
                        st.sk_value = sk_value

                        local function after_sk()
                          ask_filter_then_fetch(st, buf, call_opts,
                            "Filter Expression (optional): ")
                        end

                        if sk_op == "between" then
                          vim.ui.input(
                            { prompt = "Sort key upper bound: ",
                              default = st.sk_value2 or "" },
                            function(sk_value2)
                              if not sk_value2 or sk_value2 == "" then return end
                              st.sk_value2 = sk_value2
                              after_sk()
                            end
                          )
                        else
                          st.sk_value2 = nil
                          after_sk()
                        end
                      end
                    )
                  end)
                end
              )
            end)
          end
        )
      end)
    end
  )
end

--- Prompt for scan mode with optional filter expression + index.
---@param st        DynamoDbScanState
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function run_scan_wizard(st, buf, call_opts)
  ask_filter_then_fetch(st, buf, call_opts,
    "Filter Expression (leave blank for full table scan): ")
end

--- Top-level wizard: choose scan vs query then branch.
---@param st        DynamoDbScanState
---@param buf       integer
---@param call_opts AwsCallOpts|nil
local function run_wizard(st, buf, call_opts)
  vim.ui.select(
    { "Scan  (full table, optional filter + index)",
      "Query (guided PK / SK / filter / index)" },
    { prompt = "DynamoDB operation:" },
    function(_, idx)
      if not idx then return end
      if idx == 2 then
        st.mode = "query"
        run_query_wizard(st, buf, call_opts)
      else
        st.mode = "scan"
        run_scan_wizard(st, buf, call_opts)
      end
    end
  )
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------

---@param table_name string
---@param call_opts  AwsCallOpts|nil
function M.open(table_name, call_opts)
  local buf = buf_mod.get_or_create(buf_name(table_name), FILETYPE)
  buf_mod.open_split(buf)

  if not _state[table_name] then
    _state[table_name] = {
      table_name  = table_name,
      mode        = "scan",
      pk_name     = nil,
      pk_value    = nil,
      pk_type     = "S",
      sk_name     = nil,
      sk_op       = nil,
      sk_value    = nil,
      sk_value2   = nil,
      sk_type     = "S",
      filter_expr = nil,
      filter_vals = nil,
      filter_names = nil,
      natural_filter = nil,
      index_name  = nil,
      items       = {},
      last_key    = nil,
      page        = 1,
      fetching    = false,
      json_view   = false,
      region      = config.resolve_region(call_opts),
      profile     = config.resolve_profile(call_opts),
    }
  else
    -- Migration: state was created before the smart filter parser existed.
    -- filter_expr may be a raw (unaliased) expression with no EAN.
    -- Clear it so the next wizard run starts clean.
    local st = _state[table_name]
    if st.filter_expr and not st.natural_filter then
      st.filter_expr  = nil
      st.filter_names = nil
      st.filter_vals  = nil
    end
  end
  local st = _state[table_name]

  keymaps.apply_dynamodb_section(buf, {
    refresh = function()
      run_wizard(st, buf, call_opts)
    end,

    scan_run = function()
      run_wizard(st, buf, call_opts)
    end,

    scan_next = function()
      if not st.last_key then
        vim.notify("aws.nvim: no more pages", vim.log.levels.INFO)
        return
      end
      st.page = st.page + 1
      fetch(table_name, buf, call_opts, st.last_key)
    end,

    scan_json = function()
      st.json_view = not st.json_view
      render(buf, st)
    end,
  })

  -- Open immediately with a full-table scan (no prompts).
  render(buf, st)
  fetch(table_name, buf, call_opts, nil)
end

return M
