local Parser = {}
Parser.__index = Parser

-- Utility to check token type and value
local function is_token(token, kind, value)
    return token and token.type == kind and (not value or token.value == value)
end

-- Create new AST node helper
local function new_node(type, props)
    local node = { type = type }
    if props then
        for k, v in pairs(props) do node[k] = v end
    end
    return node
end

function Parser.new(tokens)
    return setmetatable({ tokens = tokens, pos = 1, len = #tokens }, Parser)
end

function Parser:peek(offset)
    return self.tokens[self.pos + (offset or 0)]
end

function Parser:next()
    local token = self:peek()
    if token then self.pos = self.pos + 1 end
    return token
end

function Parser:eat(type, val)
    local token = self:peek()
    if not token or token.type ~= type or (val and token.value ~= val) then
        error(("Expected %s '%s', got %s '%s' at token %d"):format(
            type, val or "", token and token.type or "<eof>", token and token.value or "<eof>", self.pos))
    end
    self.pos = self.pos + 1
    return token
end

function Parser:check(type, val)
    local token = self:peek()
    return is_token(token, type, val)
end

-- Operator precedences
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

function Parser:get_precedence()
    local token = self:peek()
    if not token or token.type ~= "operator" then return 0 end
    return precedences[token.value] or 0
end

-- Parse literal values: numbers, strings, booleans, nil
function Parser:parse_literal()
    local token = self:peek()
    local val
    if token.type == "number" then
        val = tonumber(token.value)
    elseif token.type == "string" then
        val = token.value
    elseif token.type == "keyword" then
        if token.value == "true" then val = true
        elseif token.value == "false" then val = false
        else val = nil
        end
    else
        error("Invalid literal at token " .. self.pos)
    end
    self.pos = self.pos + 1
    return new_node("Literal", { value = val })
end

-- Parse identifiers and member access, call expressions
function Parser:parse_identifier()
    local id_token = self:eat("identifier")
    local node = new_node("Identifier", { name = id_token.value })

    while true do
        local next_tok = self:peek()
        if is_token(next_tok, "punctuation", ".") then
            self.pos = self.pos + 1 -- eat '.'
            local prop = self:eat("identifier")
            node = new_node("MemberExpression", { object = node, property = new_node("Identifier", { name = prop.value }) })
        elseif is_token(next_tok, "punctuation", "(") then
            self.pos = self.pos + 1 -- eat '('
            local args = {}
            if not is_token(self:peek(), "punctuation", ")") then
                repeat
                    table.insert(args, self:parse_expression())
                    if is_token(self:peek(), "punctuation", ",") then
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
end

-- Parse primary expressions: literals, identifiers, grouping, unary
function Parser:parse_primary()
    local token = self:peek()
    if not token then error("Unexpected end of input") end

    if token.type == "number" or token.type == "string" or (token.type == "keyword" and (token.value == "true" or token.value == "false" or token.value == "nil")) then
        return self:parse_literal()
    elseif token.type == "identifier" then
        return self:parse_identifier()
    elseif is_token(token, "punctuation", "(") then
        self.pos = self.pos + 1 -- eat '('
        local expr = self:parse_expression()
        self:eat("punctuation", ")")
        return expr
    elseif is_token(token, "operator", "-") or is_token(token, "keyword", "not") then
        self.pos = self.pos + 1
        return new_node("UnaryExpression", { operator = token.value, argument = self:parse_primary() })
    else
        error(("Unexpected token (%s) '%s' at position %d"):format(token.type, token.value, self.pos))
    end
end

-- Pratt parser for binary expressions based on operator precedence
function Parser:parse_expression(precedence)
    precedence = precedence or 0
    local left = self:parse_primary()

    while true do
        local token = self:peek()
        if not token or token.type ~= "operator" then break end
        local token_prec = precedences[token.value] or 0
        if token_prec <= precedence then break end

        self.pos = self.pos + 1
        local operator = token.value
        local right = self:parse_expression(token_prec)

        left = new_node("BinaryExpression", { operator = operator, left = left, right = right })
    end

    return left
end

-- Parse block enclosed in braces { ... }
function Parser:parse_block()
    local body = {}
    while true do
        local token = self:peek()
        if not token or is_token(token, "punctuation", "}") then break end
        table.insert(body, self:parse_statement())
    end
    return body
end

-- Parse function declarations
function Parser:parse_function()
    self:eat("keyword", "fn")
    local name = self:eat("identifier").value

    self:eat("punctuation", "(")
    local params = {}
    if not is_token(self:peek(), "punctuation", ")") then
        repeat
            local param_name = self:eat("identifier").value
            local param_type = nil
            if is_token(self:peek(), "punctuation", ":") then
                self.pos = self.pos + 1
                param_type = self:eat("type").value
            end
            table.insert(params, { name = param_name, type = param_type })
            if not is_token(self:peek(), "punctuation", ",") then break end
            self.pos = self.pos + 1
        until false
    end
    self:eat("punctuation", ")")

    local return_type = nil
    if is_token(self:peek(), "type") then
        return_type = self:eat("type").value
    end

    self:eat("punctuation", "{")
    local body = self:parse_block()
    self:eat("punctuation", "}")

    return new_node("FunctionDeclaration", { name = name, params = params, returnType = return_type, body = body })
end

-- Parse variable declarations: local or const with optional initialization
function Parser:parse_variable_declaration()
    local kind = self:eat("keyword").value -- 'local' or 'const'
    local var_type = self:eat("type").value
    self:eat("punctuation", ":")
    local name = self:eat("identifier").value

    local init = nil
    if is_token(self:peek(), "operator", "=") then
        self.pos = self.pos + 1
        init = self:parse_expression()
    end

    return new_node("VariableDeclaration", { kind = kind, varType = var_type, name = name, init = init })
end

-- Parse class declarations with methods
function Parser:parse_class()
    self:eat("keyword", "class")
    local name = self:eat("identifier").value

    self:eat("punctuation", "{")
    local body = {}
    while not is_token(self:peek(), "punctuation", "}") do
        local token = self:peek()
        if is_token(token, "keyword", "fn") then
            table.insert(body, self:parse_function())
        else
            error(("Unexpected token in class body: %s '%s'"):format(token.type, token.value))
        end
    end
    self:eat("punctuation", "}")

    return new_node("ClassDeclaration", { name = name, body = body })
end

-- Parse if statements with elseif and else branches
function Parser:parse_if()
    self:eat("keyword", "if")
    local test = self:parse_expression()
    self:eat("punctuation", "{")
    local consequent = self:parse_block()
    self:eat("punctuation", "}")

    local alternate = nil
    while true do
        local token = self:peek()
        if is_token(token, "keyword", "elseif") then
            self.pos = self.pos + 1
            local elif_test = self:parse_expression()
            self:eat("punctuation", "{")
            local elif_consequent = self:parse_block()
            self:eat("punctuation", "}")
            alternate = new_node("IfStatement", { test = elif_test, consequent = elif_consequent, alternate = alternate })
        elseif is_token(token, "keyword", "else") then
            self.pos = self.pos + 1
            self:eat("punctuation", "{")
            local else_block = self:parse_block()
            self:eat("punctuation", "}")
            alternate = else_block
            break
        else
            break
        end
    end

    return new_node("IfStatement", { test = test, consequent = consequent, alternate = alternate })
end

-- Parse for loops: both for-in and classical numeric for
function Parser:parse_for()
    self:eat("keyword", "for")
    local var = self:eat("identifier").value

    if is_token(self:peek(), "keyword", "in") then
        self.pos = self.pos + 1
        local iterator = self:parse_expression()
        self:eat("punctuation", "{")
        local body = self:parse_block()
        self:eat("punctuation", "}")
        return new_node("ForInStatement", { var = var, iterator = iterator, body = body })
    else
        self:eat("operator", "=")
        local start_expr = self:parse_expression()
        self:eat("punctuation", ",")
        local end_expr = self:parse_expression()
        local step_expr = nil
        if is_token(self:peek(), "punctuation", ",") then
            self.pos = self.pos + 1
            step_expr = self:parse_expression()
        end
        self:eat("punctuation", "{")
        local body = self:parse_block()
        self:eat("punctuation", "}")
        return new_node("ForStatement", { var = var, start = start_expr, ["end"] = end_expr, step = step_expr, body = body })
    end
end

-- Parse while loops
function Parser:parse_while()
    self:eat("keyword", "while")
    local test = self:parse_expression()
    self:eat("punctuation", "{")
    local body = self:parse_block()
    self:eat("punctuation", "}")
    return new_node("WhileStatement", { test = test, body = body })
end

-- Parse return statement with optional expression
function Parser:parse_return()
    self:eat("keyword", "return")
    local argument = nil
    local token = self:peek()
    if token and not (is_token(token, "punctuation", ";") or is_token(token, "punctuation", "}")) then
        argument = self:parse_expression()
    end
    return new_node("ReturnStatement", { argument = argument })
end

-- Parse print statement
function Parser:parse_print_statement()
    self:eat("keyword", "print")
    self:eat("punctuation", "(")
    local argument = self:parse_expression()
    self:eat("punctuation", ")")
    return new_node("PrintStatement", { argument = argument })
end

-- Parse statements fallback (expression statement)
function Parser:parse_expression_statement()
    local expr = self:parse_expression()
    return new_node("ExpressionStatement", { expression = expr })
end

-- Main statement parser routing based on token
function Parser:parse_statement()
    local token = self:peek()
    if not token then return nil end

    if is_token(token, "keyword", "fn") then
        return self:parse_function()
    elseif is_token(token, "keyword", "local") or is_token(token, "keyword", "const") then
        return self:parse_variable_declaration()
    elseif is_token(token, "keyword", "class") then
        return self:parse_class()
    elseif is_token(token, "keyword", "if") then
        return self:parse_if()
    elseif is_token(token, "keyword", "for") then
        return self:parse_for()
    elseif is_token(token, "keyword", "while") then
        return self:parse_while()
    elseif is_token(token, "keyword", "return") then
        return self:parse_return()
    elseif is_token(token, "keyword", "print") then
        return self:parse_print_statement()
    else
        return self:parse_expression_statement()
    end
end

-- Entry point: parse entire program as a list of statements
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
