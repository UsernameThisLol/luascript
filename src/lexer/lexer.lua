-- Lexer

local Lexer = {}
Lexer.__index = Lexer

-- Define token patterns
local patterns = {
    whitespace = "^%s+",
    comment = "^//[^\n]*",
    number = "^%d+%.?%d*",
    identifier = "^[%a_][%w_]*",
    string = [["([^"\$*(\\.[^"\$*)*)"]],
    operator_concat = "^%.%.",
    operator_single = "^[%+%-%*%/%=]", -- Pattern for other single-char operators
    punctuation = "^[%[%]%(%){}:,%.]"
}

-- Types for type checking / Regular use
local types = {
    ["number"] = true,
    ["string"] = true,
    ["bool"] = true,
    ["nil"] = true,
    ["array"] = true,
    ["Class"] = true,
    ["function"] = true,
    ["table"] = true,
}

-- Keywords
local keywords = {
    ["fn"] = true,
    ["return"] = true,
    ["local"] = true,
    ["const"] = true,
    ["print"] = true,
    ["class"] = true,
    ["if"] = true,
    ["and"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["for"] = true,
    ["while"] = true,
    ["until"] = true,
    ["goto"] = true,
    ["or"] = true,
    ["not"] = true,
    ["true"] = true,
    ["false"] = true,
    ["nil"] = true,
    ["in"] = true,
    ["new"] = true,
    ["break"] = true,
    ["continue"] = true,
    ["switch"] = true,
    ["case"] = true,
    ["default"] = true,
}

-- Create separate Lexer
function Lexer.new(source)
    local self = setmetatable({}, Lexer)
    self.source = source
    self.pos = 1
    self.len = #source
    self.line = 1
    self.col = 1
    return self
end

function Lexer:is_at_end()
    return self.pos > self.len
end

function Lexer:peek(n)
    n = n or 0
    return self.source:sub(self.pos + n, self.pos + n)
end

function Lexer:advance(n)
    n = n or 1
    for i = 1, n do
        if self:peek() == "\n" then
            self.line = self.line + 1
            self.col = 1
        else
            self.col = self.col + 1
        end
        self.pos = self.pos + 1
    end
end

function Lexer:match_pattern(pattern)
    local s, e = self.source:find(pattern, self.pos)
    if s == self.pos then
        return self.source:sub(s, e)
    end
end

function Lexer:next_token()
    if self:is_at_end() then return nil end

    -- Skip whitespace
    while true do
        local ws = self:match_pattern(patterns.whitespace)
        if not ws then break end
        self:advance(#ws)
        if self:is_at_end() then return nil end
    end

    -- Check comments
    local comment = self:match_pattern(patterns.comment)
    if comment then
        self:advance(#comment)
        return { type = "comment", value = comment }
    end

    -- Check string literal
    local c = self:peek()
    if c == '"' then
        local pattern = '"(.-)"'
        local s, e = self.source:find(pattern, self.pos)
        if s == self.pos then
            local str_val = self.source:sub(s + 1, e - 1)
            self:advance(e - s + 1)
            return { type = "string", value = str_val }
        else
            error("Unterminated string literal at line " .. self.line)
        end
    end

    -- Check number
    local number = self:match_pattern(patterns.number)
    if number then
        self:advance(#number)
        return { type = "number", value = number }
    end

    -- Check identifiers and keywords
    local id = self:match_pattern(patterns.identifier)
    if id then
        self:advance(#id)
        if types[id] then
            return { type = "type", value = id }
        elseif keywords[id] then
            return { type = "keyword", value = id }
        else
            return { type = "identifier", value = id }
        end
    end

    -- Check for the concatenation operator ".."
    local concat_op = self:match_pattern(patterns.operator_concat)
    if concat_op then
        self:advance(#concat_op)
        return { type = "operator", value = concat_op }
    end

    -- Check for other single-character operators
    local op = self:match_pattern(patterns.operator_single)
    if op then
        self:advance(#op)
        return { type = "operator", value = op }
    end

    -- Check punctuation
    local punct = self:match_pattern(patterns.punctuation)
    if punct then
        self:advance(#punct)
        return { type = "punctuation", value = punct }
    end

    error("Unexpected character '" .. c .. "' at line " .. self.line)
end

function Lexer:tokenize()
    local tokens = {}
    while true do
        local token = self:next_token()
        if not token then break end
        table.insert(tokens, token)
    end
    return tokens
end

return Lexer