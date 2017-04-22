-- A very fast Lua linked list implementation that can only add a number of
-- items equal to the maximum integer that can be held in a lua number.

-- The reference counting O(n) for length of remaining list when doing cdr or
-- cons.

local utils = require("leftry").utils
local vector = require("l2l.vector")
local lua = require("l2l.lua")
local ipairs = require("l2l.iterator")
local len = require("l2l.len")

local data = setmetatable({n=0, free=0}, {})
local retains = {}

local function retain(n)
  retains[n] = (retains[n] or 0) + 1
  local rest = data[n+1]
  if rest then
    return retain(rest)
  end
end

local function release(n)
  retains[n] = retains[n] - 1
  if retains[n] == 0 then
    retains[n] = nil
    data[n] = nil
    data[n+1] = nil
    data.free = data.free + 1
  end
  if data.free == data.n then
    -- Take the opportunity to reset `data`.
    data = setmetatable({n=0, free=0}, {})
  end
  local rest = data[n+1]
  if rest then
    return release(rest)
  end
end

local list = utils.prototype("list", function(list, ...)
  if select("#", ...) == 0 then
    return vector()
  end
  local self = setmetatable({position = data.n + 1, contiguous = true}, list)
  local count = select("#", ...)
  local index = self.position
  for i=1, count do
    local datum = (select(i, ...))
    data.n = data.n + 1
    data[data.n] = datum
    data.n = data.n + 1
    if i < count then
      data[data.n] = index + i * 2
    end
  end
  retain(self.position)
  return self
end)

function list:__index(key)
  if type(key) ~= "number" then
    return rawget(list, key)
  end

  if self.contiguous then
    return data[self.position + 2 * key]
  end

  -- safe but slower and generates extra garbage, since cdr creates tables
  -- while t and key > 0 do
  --     t = t:cdr()
  --     key = key - 1
  -- end
  -- return t and t:car()

  -- not as safe? but much more efficient, does not create tables
  local position = self.position
  while position and key > 0 do
      position = data[position + 1]
      key = key - 1
  end
  return position and data[position]
end

function list:__gc()
  release(self.position)
end

function list:repr()
  local parameters = {}
  local cdr = self
  local i = 0
  while cdr do
    i = i + 1
    local car = cdr:car()
    if type(car) == "string" then
      car = utils.escape(car)
    end
    parameters[i] = car
    cdr = cdr:cdr()
  end
  return lua.lua_functioncall.new(lua.lua_name("list"),
    lua.lua_args.new(
      lua.lua_explist(parameters)))
end

function list:__tostring()
  local text = {}
  local cdr = self
  local i = 0
  while cdr do
    i = i + 1
    local car = cdr:car()
    if type(car) == "string" then
      car = utils.escape(car)
    end
    text[i] = tostring(car)
    cdr = cdr:cdr()
  end
  return "list("..table.concat(text, ", ")..")"
end

-- function list:__ipairs()
--   local cdr = self
--   local i = 0
--   return function()
--     if not cdr then
--       return
--     end
--     i = i + 1
--     local car = cdr:car()
--     cdr = cdr:cdr()
--     return i, car
--   end, self, 0
-- end

function list:__ipairs()
  local position = self.position
  local i = 0
  return function()
    if not position then
      return
    end
    i = i + 1
    local car = data[position]
    position = data[position + 1]
    return i, car
  end, self, 0
end

function list:__len()
  if not self then
    return 0
  end
  local cdr = self:cdr()
  local count = 1
  while cdr do
    count = count + 1
    cdr = cdr:cdr()
  end
  return count
end

function list:car()
  return data[self.position]
end

function list:cdr()
  local position = data[self.position + 1]
  if position then
    retain(position)
    return setmetatable({position = position, contiguous = self.contiguous}, list)
  end
end

function list:__eq(l)
  return getmetatable(self) == getmetatable(l) and
    self:car() == l:car() and self:cdr() == l:cdr()
end

function list:unpack()
  if not self then
    return
  end
  local car, cdr = self:car(), self:cdr()
  if cdr then
    return car, cdr:unpack()
  end
  return car
end

function list.sub(t, from, to)
  to = to or len(t)
  from = from or 1
  return list.cast(t, function(i)
    return i >= from and i <= to
  end)
end

function list.cast(t, f)
  -- Cast an ipairs-enumerable object into a list.
  local count = len(t)
  if not t or count == 0 then
    return nil
  end
  local self = setmetatable({position = data.n + 1, contiguous = true}, list)
  local n = data.n
  data.n = data.n + count * 2
  for i, v in ipairs(t) do
    n = n + 1
    if f then
      data[n] = f(v, i)
    else
      data[n] = v
    end
    n = n + 1
    if i < count then
      data[n] = n + 1
    end
  end
  retain(self.position)
  return self
end

function list:cons(car)
  -- Prepend car to the list and return a new head.
  data.n = data.n + 1
  local position = data.n
  data[data.n] = car
  data.n = data.n + 1
  if self then
    data[data.n] = self.position
  end
  retain(position)
  return setmetatable({position = position, contiguous = false}, list)  
end

return list
