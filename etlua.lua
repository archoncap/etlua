local VERSION = "1.0.2"
local insert, concat
do
  local _obj_0 = table
  insert, concat = _obj_0.insert, _obj_0.concat
end
local load, setfenv, assert, type, error, tostring, tonumber, setmetatable
do
  local _obj_0 = _G
  load, setfenv, assert, type, error, tostring, tonumber, setmetatable = _obj_0.load, _obj_0.setfenv, _obj_0.assert, _obj_0.type, _obj_0.error, _obj_0.tostring, _obj_0.tonumber, _obj_0.setmetatable
end
setfenv = setfenv or function(fn, env)
  local name
  local i = 1
  while true do
    name = debug.getupvalue(fn, i)
    if not name or name == "_ENV" then
      break
    end
    i = i + 1
  end
  if name then
    debug.upvaluejoin(fn, i, (function()
      return env
    end), 1)
  end
  return fn
end
local html_escape_entities = {
  ['&'] = '&amp;',
  ['<'] = '&lt;',
  ['>'] = '&gt;',
  ['"'] = '&quot;',
  ["'"] = '&#039;'
}
local html_escape
html_escape = function(str)
  return (str:gsub([=[["><'&]]=], html_escape_entities))
end
local get_line
get_line = function(str, line_num)
  for line in str:gmatch("([^\n]*)\n?") do
    if line_num == 1 then
      return line
    end
    line_num = line_num - 1
  end
end
local pos_to_line
pos_to_line = function(str, pos)
  local line = 1
  for _ in str:sub(1, pos):gmatch("\n") do
    line = line + 1
  end
  return line
end
local Renderer
do
  local _base_0 = {
    render = function(self)
      return table.concat(self.buffer)
    end,
    push = function(self, str, ...)
      local i = self.i + 1
      self.buffer[i] = str
      self.i = i
      if ... then
        return self:push(...)
      end
    end,
    header = function(self)
      return self:push("local _b, _b_i, _tostring, _concat, _escape = ...\n")
    end,
    footer = function(self)
      return self:push("return _b")
    end,
    increment = function(self)
      return self:push("_b_i = _b_i + 1\n")
    end,
    mark = function(self, pos)
      return self:push("--[[", tostring(pos), "]] ")
    end,
    assign = function(self, ...)
      self:push("_b[_b_i] = ", ...)
      if ... then
        return self:push("\n")
      end
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self)
      self.buffer = { }
      self.i = 0
    end,
    __base = _base_0,
    __name = "Renderer"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Renderer = _class_0
end
local Parser
do
  local _base_0 = {
    open_tag = "<%",
    close_tag = "%>",
    modifiers = "^[=-]",
    html_escape = true,
    next_tag = function(self)
      local start, stop = self.str:find(self.open_tag, self.pos, true)
      if not (start) then
        self:push_raw(self.pos, #self.str)
        return false
      end
      if not (start == self.pos) then
        self:push_raw(self.pos, start - 1)
      end
      self.pos = stop + 1
      local modifier
      if self.str:match(self.modifiers, self.pos) then
        do
          local _with_0 = self.str:sub(self.pos, self.pos)
          self.pos = self.pos + 1
          modifier = _with_0
        end
      end
      local close_start, close_stop = self.str:find(self.close_tag, self.pos, true)
      if not (close_start) then
        return nil, self:error_for_pos(start, "failed to find closing tag")
      end
      while self:in_string(self.pos, close_start) do
        close_start, close_stop = self.str:find(self.close_tag, close_stop, true)
      end
      local trim_newline
      if "-" == self.str:sub(close_start - 1, close_start - 1) then
        close_start = close_start - 1
        trim_newline = true
      end
      self:push_code(modifier or "code", self.pos, close_start - 1)
      self.pos = close_stop + 1
      if trim_newline then
        do
          local match = self.str:match("^\n", self.pos)
          if match then
            self.pos = self.pos + #match
          end
        end
      end
      return true
    end,
    in_string = function(self, start, stop)
      local in_string = false
      local end_delim = nil
      local escape = false
      local pos = 0
      local skip_until = nil
      local chunk = self.str:sub(start, stop)
      for char in chunk:gmatch(".") do
        local _continue_0 = false
        repeat
          pos = pos + 1
          if skip_until then
            if pos <= skip_until then
              _continue_0 = true
              break
            end
            skip_until = nil
          end
          if end_delim then
            if end_delim == char and not escape then
              in_string = false
              end_delim = nil
            end
          else
            if char == "'" or char == '"' then
              end_delim = char
              in_string = true
            end
            if char == "[" then
              do
                local lstring = chunk:match("^%[=*%[", pos)
                if lstring then
                  local lstring_end = lstring:gsub("%[", "]")
                  local lstring_p1, lstring_p2 = chunk:find(lstring_end, pos, true)
                  if not (lstring_p1) then
                    return true
                  end
                  skip_until = lstring_p2
                end
              end
            end
          end
          escape = char == "\\"
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return in_string
    end,
    push_raw = function(self, start, stop)
      return insert(self.chunks, self.str:sub(start, stop))
    end,
    push_code = function(self, kind, start, stop)
      return insert(self.chunks, {
        kind,
        self.str:sub(start, stop),
        start
      })
    end,
    compile = function(self, str)
      local success, err = self:parse(str)
      if not (success) then
        return nil, err
      end
      local fn
      fn, err = self:load(self:chunks_to_lua())
      if not (fn) then
        return nil, err
      end
      return function(...)
        local buffer
        buffer, err = self:run(fn, ...)
        if buffer then
          return concat(buffer)
        else
          return nil, err
        end
      end
    end,
    parse = function(self, str)
      self.str = str
      assert(type(self.str) == "string", "expecting string for parse")
      self.pos = 1
      self.chunks = { }
      while true do
        local found, err = self:next_tag()
        if err then
          return nil, err
        end
        if not (found) then
          break
        end
      end
      return true
    end,
    parse_error = function(self, err, code)
      local line_no, err_msg = err:match("%[.-%]:(%d+): (.*)$")
      line_no = tonumber(line_no)
      if not (line_no) then
        return 
      end
      local line = get_line(code, line_no)
      local source_pos = tonumber(line:match("^%-%-%[%[(%d+)%]%]"))
      if not (source_pos) then
        return 
      end
      return self:error_for_pos(source_pos, err_msg)
    end,
    error_for_pos = function(self, source_pos, err_msg)
      local source_line_no = pos_to_line(self.str, source_pos)
      local source_line = get_line(self.str, source_line_no)
      return tostring(err_msg) .. " [" .. tostring(source_line_no) .. "]: " .. tostring(source_line)
    end,
    load = function(self, code, name)
      if name == nil then
        name = "etlua"
      end
      local code_fn
      do
        local code_ref = code
        code_fn = function()
          do
            local ret = code_ref
            code_ref = nil
            return ret
          end
        end
      end
      local fn, err = load(code_fn, name)
      if not (fn) then
        do
          local err_msg = self:parse_error(err, code)
          if err_msg then
            return nil, err_msg
          end
        end
        return nil, err
      end
      return fn
    end,
    run = function(self, fn, env, buffer)
      if env == nil then
        env = { }
      end
      if buffer == nil then
        buffer = { }
      end
      local combined_env = setmetatable({ }, {
        __index = function(self, name)
          local val = env[name]
          if val == nil then
            val = _G[name]
          end
          return val
        end
      })
      setfenv(fn, combined_env)
      return fn(buffer, #buffer, tostring, concat, html_escape)
    end,
    compile_to_lua = function(self, str)
      local success, err = self:parse(str)
      if not (success) then
        return nil, err
      end
      return self:chunks_to_lua()
    end,
    chunks_to_lua = function(self)
      local r = Renderer()
      r:header()
      local _list_0 = self.chunks
      for _index_0 = 1, #_list_0 do
        local chunk = _list_0[_index_0]
        local t = type(chunk)
        if t == "table" then
          t = chunk[1]
        end
        local _exp_0 = t
        if "string" == _exp_0 then
          r:increment()
          r:assign(("%q"):format(chunk))
        elseif "code" == _exp_0 then
          r:mark(chunk[3])
          r:push(chunk[2], "\n")
        elseif "=" == _exp_0 or "-" == _exp_0 then
          r:increment()
          r:mark()
          r:assign()
          if t == "=" and self.html_escape then
            r:push("_escape(_tostring(", chunk[2], "))\n")
          else
            r:push("_tostring(", chunk[2], ")\n")
          end
        else
          error("unknown type " .. tostring(t))
        end
      end
      r:footer()
      return r:render()
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "Parser"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Parser = _class_0
end
local compile
do
  local _base_0 = Parser()
  local _fn_0 = _base_0.compile
  compile = function(...)
    return _fn_0(_base_0, ...)
  end
end
local render
render = function(str, ...)
  local fn, err = compile(str)
  if fn then
    return fn(...)
  else
    return nil, err
  end
end
return {
  compile = compile,
  render = render,
  Parser = Parser,
  Renderer = Renderer,
  _version = VERSION
}
