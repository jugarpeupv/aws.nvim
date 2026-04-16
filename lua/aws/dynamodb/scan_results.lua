--- aws.nvim – DynamoDB scan/query: results rendering helpers
local M = {}

-------------------------------------------------------------------------------
-- String helpers
-------------------------------------------------------------------------------

---@param s     string
---@param width integer
---@return string
local function pad_right(s, width)
  local d = vim.fn.strdisplaywidth(s)
  if d >= width then
    return s
  end
  return s .. string.rep(" ", width - d)
end

---@param s   string
---@param max integer
---@return string
local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then
    return s
  end
  local result = ""
  local cols = 0
  local nchars = vim.fn.strchars(s)
  for i = 0, nchars - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if cols + w > max - 1 then
      break
    end
    result = result .. ch
    cols = cols + w
  end
  return result .. "…"
end

--- Split embedded newlines so nvim_buf_set_lines never receives them.
---@param raw string[]
---@return string[]
local function safe_lines(raw)
  local out = {}
  for _, l in ipairs(raw) do
    for _, sl in ipairs(vim.split(l, "\n", { plain = true })) do
      table.insert(out, sl)
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- DynamoDB typed-value formatter
-------------------------------------------------------------------------------

---@param attr table
---@return string
local function fmt_attr(attr)
  if type(attr) ~= "table" then
    return tostring(attr)
  end
  if attr.S ~= nil then
    return tostring(attr.S)
  end
  if attr.N ~= nil then
    return tostring(attr.N)
  end
  if attr.BOOL ~= nil then
    return tostring(attr.BOOL)
  end
  if attr.NULL ~= nil then
    return "NULL"
  end
  if attr.B ~= nil then
    return "<Binary>"
  end
  if attr.SS ~= nil then
    return "{" .. table.concat(type(attr.SS) == "table" and attr.SS or {}, ", ") .. "}"
  end
  if attr.NS ~= nil then
    return "{" .. table.concat(type(attr.NS) == "table" and attr.NS or {}, ", ") .. "}"
  end
  if attr.BS ~= nil then
    return "<BinarySet[" .. #(attr.BS or {}) .. "]>"
  end
  if attr.L ~= nil then
    local parts = {}
    for _, v in ipairs(type(attr.L) == "table" and attr.L or {}) do
      table.insert(parts, fmt_attr(v))
    end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  if attr.M ~= nil then
    local parts = {}
    for k, v in pairs(type(attr.M) == "table" and attr.M or {}) do
      table.insert(parts, k .. ": " .. fmt_attr(v))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return vim.inspect(attr)
end

---@param item      table
---@param key_width integer
---@return string[]
local function fmt_item_table(item, key_width)
  local keys = {}
  for k in pairs(item) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local lines = {}
  for _, k in ipairs(keys) do
    local val = fmt_attr(item[k])
    table.insert(lines, "  " .. pad_right(k, key_width) .. truncate(val, 120))
  end
  return lines
end

---@param item table
---@return string[]
local function fmt_item_json(item)
  local function unwrap(attr)
    if type(attr) ~= "table" then
      return attr
    end
    if attr.S ~= nil then
      return attr.S
    end
    if attr.N ~= nil then
      return tonumber(attr.N)
    end
    if attr.BOOL ~= nil then
      return attr.BOOL
    end
    if attr.NULL ~= nil then
      return vim.NIL
    end
    if attr.B ~= nil then
      return "<Binary>"
    end
    if attr.SS ~= nil then
      return attr.SS
    end
    if attr.NS ~= nil then
      local out = {}
      for _, v in ipairs(type(attr.NS) == "table" and attr.NS or {}) do
        table.insert(out, tonumber(v))
      end
      return out
    end
    if attr.BS ~= nil then
      return attr.BS
    end
    if attr.L ~= nil then
      local out = {}
      for _, v in ipairs(type(attr.L) == "table" and attr.L or {}) do
        table.insert(out, unwrap(v))
      end
      return out
    end
    if attr.M ~= nil then
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

  -- Simple manual pretty-printer (nvim 0.9 has no native one).
  local pretty_ok, pretty = pcall(function()
    local out = {}
    local depth = 0
    local i = 1
    local len = #encoded
    local line = ""
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
        line = line .. c
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
  return { "  " .. encoded }
end

-------------------------------------------------------------------------------
-- Results section renderer
-------------------------------------------------------------------------------

--- Append the results section (items) to `lines`.
---@param st    DynamoDbScanState
---@param lines string[]
function M.render_results(st, lines)
  local function L(s)
    table.insert(lines, s or "")
  end
  local sep = "  " .. string.rep("─", 72)

  -- Status bar (mirrors the AWS console yellow bar)
  if st.fetching then
    L("  [loading…]")
    L(sep)
    return
  end

  local count = #st.items
  local more = st.last_key and "  [more pages — press n for next]" or ""
  L(
    "  Items returned: "
      .. count
      .. "   Page: "
      .. st.page
      .. (st.json_view and "   [JSON view — J to toggle]" or "   [Table view — J to toggle]")
      .. more
  )
  L(sep)

  if count == 0 then
    L("  (no items returned)")
    L("")
    return
  end

  if st.json_view then
    for i, item in ipairs(st.items) do
      L("  ── item " .. i .. " ──")
      for _, row in ipairs(safe_lines(fmt_item_json(item))) do
        L(row)
      end
    end
  else
    -- Compute max key width across all items for alignment.
    local kw = 8
    for _, item in ipairs(st.items) do
      for k in pairs(item) do
        local w = vim.fn.strdisplaywidth(k)
        if w > kw then
          kw = w
        end
      end
    end
    kw = kw + 2

    for i, item in ipairs(st.items) do
      L("  ── item " .. i .. " ──")
      for _, row in ipairs(safe_lines(fmt_item_table(item, kw))) do
        L(row)
      end
    end
  end

  L("")
end

return M
