local Parser = {}
Parser.__index = Parser

-- Utility to check token type
local function is_keyword(token, kw)
    return token and token.type == "keyword" and token.value == kw
end

local function is_punct(token, val)
    return token and token.type == "punctuation" and token.value == val
end

local function is_operator(token, val)
    return token and token.type == "operator" and token.value == val
end

local function is_identifier(token)
    return token and token.type == "identifier"
end

local function is_literal(token)
    return token and (token.type == "number" or token.type == "string" or
        (token.type == "keyword" and (token.value == "true" or token.value == "false" or token.value == "nil")))
end

-- New AST node utilities
local function new_node(type, props)
    local node = { type = type }
    if props then
        for k, v in pairs(props) do node[k] = v end
    end
    return node
end

function Parser.new(tokens)
    local self = setmetatable({}, Parser)
    self.tokens = tokens
    self.pos = 1
    self.len = #tokens
    return self
end

function Parser:peek(offset)
    offset = offset or 0
    return self.tokens[self.pos + offset]
end

function Parser:next()
    local token = self:peek()
    if token then self.pos = self.pos + 1 end
    return token
end

function Parser:eat(type, val)
    local token = self:peek()
    if not token or token.type ~= type or (val and token.value ~= val) then
        error(string.format("Expected %s '%s', got %s '%s' at token %d", type, val or "",
            token and token.type or "<eof>", token and token.value or "<eof>", self.pos))
    end
    self.pos = self.pos + 1
    return token
end

function Parser:check(type, val)
    local token = self:peek()
    return token and token.type == type and (not val or token.value == val)
end

-- Parsing Helpers for Expressions --
-- Implement Pratt parser for expressions to handle precedence

local precedences = {
    ["or"] = 1,
    ["and"] = 2,
    ["=="] = 3,
    ["!="] = 3,
    ["<"] = 3,
    [">"] = 3,
    ["<="] = 3,
    [">="] = 3,
    [".."] = 4,
    ["+"] = 4,
    ["-"] = 4,
    ["*"] = 5,
    ["/"] = 5,
    ["%"] = 5,
    ["^"] = 6,
}



function Parser:parse_primary()
    local token = self:peek()
    if not token then
        error("Unexpected end of input")
    end

    if is_literal(token) then
        self.pos = self.pos + 1
        local val
        if token.type == "number" then
            val = tonumber(token.value)
        elseif token.type == "string" then
            val = token.value
        elseif token.type == "keyword" then
            if token.value == "true" then
                val = true
            elseif token.value == "false" then
                val = false
            else
                val = nil
            end
        end
        return new_node("Literal", { value = val })
    elseif is_identifier(token) then
        self.pos = self.pos + 1
        local node = new_node("Identifier", { name = token.value })

        -- Handle member access or function call
        while true do
            local next_tok = self:peek()
            if is_punct(next_tok, ".") then
                self.pos = self.pos + 1 -- eat '.'
                local prop = self:eat("identifier")
                node = new_node("MemberExpression",
                    { object = node, property = new_node("Identifier", { name = prop.value }) })
            elseif is_punct(next_tok, "(") then
                -- function call
                self.pos = self.pos + 1 -- eat '('
                local args = {}
                if not is_punct(self:peek(), ")") then
                    repeat
                        local expr = self:parse_expression()
                        table.insert(args, expr)
                        if is_punct(self:peek(), ",") then
                            self.pos = self.pos + 1
                        else
                            break
                        end
                    until false
                end
                self:eat("punctuation", ")")
                node = new_node("CallExpression", { callee = node, arguments = args })
            else
                break
            end
        end

        return node
    elseif is_punct(token, "(") then
        self.pos = self.pos + 1 -- eat '('
        local expr = self:parse_expression()
        self:eat("punctuation", ")")
        return expr
    elseif is_operator(token, "-") or is_keyword(token, "not") then
        self.pos = self.pos + 1
        local operator = token.value
        local argument = self:parse_primary()
        return new_node("UnaryExpression", { operator = operator, argument = argument })
    else
        error("Unexpected token (" .. token.type .. ") '" .. token.value .. "' at position " .. self.pos)
    end
end




-- Parsing Statements --

-- Parsing Helpers for Expressions --
-- Implement Pratt parser for expressions to handle precedence

local precedences = {
    ["or"] = 1,
    ["and"] = 2,
    ["=="] = 3,
    ["!="] = 3,
    ["<"] = 3,
    [">"] = 3,
    ["<="] = 3,
    [">="] = 3,
    [".."] = 3,
    ["+"] = 4,
    ["-"] = 4,
    ["*"] = 5,
    ["/"] = 5,
    ["%"] = 5,
    ["^"] = 6,
}

function Parser:get_precedence()
    local token = self:peek()
    if not token or token.type ~= "operator" then return 0 end
    return precedences[token.value] or 0
end


function Parser:parse_expression(precedence)
    precedence = precedence or 0
    local left = self:parse_primary()

    while true do
        local token = self:peek()
        if not token or token.type ~= "operator" then break end
        local token_precedence = precedences[token.value] or 0
        if token_precedence <= precedence then break end

        self.pos = self.pos + 1
        local operator = token.value


        local right = self:parse_expression(token_precedence)

        left = new_node("BinaryExpression", { operator = operator, left = left, right = right })

    end

    return left
end

function Parser:parse_block()
    local body = {}
    while true do
        local token = self:peek()
        if not token or is_punct(token, "}") then
            break
        end
        local stmt = self:parse_statement()
        table.insert(body, stmt)
    end
    return body
end

function Parser:parse_function()
    self:eat("keyword", "fn")
    local name_tok = self:eat("identifier")
    local name = name_tok.value

    self:eat("punctuation", "(")
    local params = {}
    local return_type = nil -- Added before param_type declaration

    if not is_punct(self:peek(), ")") then
        repeat
            local param_name = self:eat("identifier").value
            local param_type = nil
            if is_punct(self:peek(), ":") then
                self.pos = self.pos + 1
                param_type = self:eat("type").value -- Now correctly expecting "type" token
            end
            table.insert(params, { name = param_name, type = param_type })
            if is_punct(self:peek(), ",") then
                self.pos = self.pos + 1
            else
                break
            end
        until false
    end

    -- Added after the loop:
    if self:check("type") then
        return_type = self:eat("type").value
    end
    self:eat("punctuation", ")")

    -- Optional return type
    local return_type = nil
    if is_identifier(self:peek()) then
        return_type = self:eat("identifier").value
    end

    self:eat("punctuation", "{")
    local body = self:parse_block()
    self:eat("punctuation", "}")

    return new_node("FunctionDeclaration", {
        name = name,
        params = params,
        returnType = return_type,
        body = body
    })
end

function Parser:parse_variable_declaration()
    -- local or const
    local kind = self:eat("keyword").value -- "local" or "const"

    local var_type = self:eat("type").value -- First identifier is the type
    self:eat("punctuation", ":")                 -- Expect the colon
    local name = self:eat("identifier").value    -- Second identifier is the name

    local init = nil
    if is_operator(self:peek(), "=") then
        self.pos = self.pos + 1
        init = self:parse_expression()
    end

    return new_node("VariableDeclaration", {
        kind = kind,
        varType = var_type,
        name = name,
        init = init
    })
end

function Parser:parse_class()
    self:eat("keyword", "class")
    local name = self:eat("identifier").value

    self:eat("punctuation", "{")
    local body = {}
    while not is_punct(self:peek(), "}") do
        local token = self:peek()
        if is_keyword(token, "fn") then
            local method = self:parse_function()
            table.insert(body, method)
        else
            error("Unexpected token in class body: " .. token.type .. " '" .. token.value .. "'")
        end
    end
    self:eat("punctuation", "}")

    return new_node("ClassDeclaration", { name = name, body = body })
end

function Parser:parse_if()
    self:eat("keyword", "if")
    local test = self:parse_expression()
    self:eat("punctuation", "{")
    local consequent = self:parse_block()
    self:eat("punctuation", "}")

    local alternate = nil
    if is_keyword(self:peek(), "elseif") then
        self.pos = self.pos + 1
        alternate = { self:parse_if() }
    elseif is_keyword(self:peek(), "else") then
        self.pos = self.pos + 1
        self:eat("punctuation", "{")
        alternate = self:parse_block()
        self:eat("punctuation", "}")
    end

    return new_node("IfStatement", {
        test = test,
        consequent = consequent,
        alternate = alternate
    })
end

function Parser:parse_for()
    self:eat("keyword", "for")
    local var = self:eat("identifier").value
    local rangeType = nil
    if is_keyword(self:peek(), "in") then
        self.pos = self.pos + 1 -- eat 'in'
        local iterator = self:parse_expression()
        self:eat("punctuation", "{")
        local body = self:parse_block()
        self:eat("punctuation", "}")
        return new_node("ForInStatement", { var = var, iterator = iterator, body = body })
    else
        -- classical for numeric
        self:eat("operator", "=")
        local start_expr = self:parse_expression()
        self:eat("punctuation", ",")
        local end_expr = self:parse_expression()
        local step_expr = nil
        if is_punct(self:peek(), ",") then
            self.pos = self.pos + 1
            step_expr = self:parse_expression()
        end
        self:eat("punctuation", "{")
        local body = self:parse_block()
        self:eat("punctuation", "}")
        return new_node("ForStatement", {
            var = var,
            start = start_expr,
            end_ = end_expr,
            step = step_expr,
            body = body
        })
    end
end

function Parser:parse_while()
    self:eat("keyword", "while")
    local test = self:parse_expression()
    self:eat("punctuation", "{")
    local body = self:parse_block()
    self:eat("punctuation", "}")
    return new_node("WhileStatement", { test = test, body = body })
end

function Parser:parse_return()
    self:eat("keyword", "return")
    local argument = nil
    if not is_punct(self:peek(), ";") and not is_punct(self:peek(), "}") and self:peek() then
        argument = self:parse_expression()
    end
    return new_node("ReturnStatement", { argument = argument })
end

function Parser:parse_expression_statement()
    local expr = self:parse_expression()
    return new_node("ExpressionStatement", { expression = expr })
end

function Parser:parse_statement()
    local token = self:peek()
    if not token then return nil end

    if is_keyword(token, "fn") then
        return self:parse_function()
    elseif is_keyword(token, "local") or is_keyword(token, "const") then
        return self:parse_variable_declaration()
    elseif is_keyword(token, "class") then
        return self:parse_class()
    elseif is_keyword(token, "if") then
        return self:parse_if()
    elseif is_keyword(token, "for") then
        return self:parse_for()
    elseif is_keyword(token, "while") then
        return self:parse_while()
    elseif is_keyword(token, "return") then
        return self:parse_return()
    elseif is_keyword(token, "print") then -- Handle the 'print' keyword
        return self:parse_print_statement()
    else
        -- Expression statement
        return self:parse_expression_statement()
    end
end

function Parser:parse_print_statement()
    self:eat("keyword", "print")
    self:eat("punctuation", "(")
    local argument = self:parse_expression()
    self:eat("punctuation", ")")
    return new_node("PrintStatement", { argument = argument })
end

function Parser:parse_program()
    local body = {}
    while self.pos <= self.len do
        local stmt = self:parse_statement()
        if not stmt then break end
        table.insert(body, stmt)
    end
    return new_node("Program", { body = body })
end

return Parser
