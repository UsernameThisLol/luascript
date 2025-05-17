local Interpreter = {}
Interpreter.__index = Interpreter

function Interpreter.new()
  local self = setmetatable({}, Interpreter)
  self.environment = {}
  return self
end

function Interpreter:lookup(name)
  local value = self.environment[name]
  if value == nil then
    error("Undefined variable: " .. name)
  end
  return value
end

function Interpreter:define(name, value)
  self.environment[name] = value
end


function Interpreter:evaluate(node)
    if not node then return nil end

    if node.type == "Program" then
        local result = nil
        for _, stmt in ipairs(node.body) do
            result = self:evaluate(stmt)
        end
        return result

    elseif node.type == "FunctionDeclaration" then
        self:define(node.name, node)
        return nil

    elseif node.type == "VariableDeclaration" then
        local value = nil
        if node.init then
            value = self:evaluate(node.init)
        end
        self:define(node.name, value)
        return nil

    elseif node.type == "BinaryExpression" then
        local left = self:evaluate(node.left)
        local right = self:evaluate(node.right)
        return self:apply_operator(node.operator, left, right)

    elseif node.type == "UnaryExpression" then
        local argument = self:evaluate(node.argument)
        return self:apply_unary_operator(node.operator, argument)

    elseif node.type == "Literal" then
        return node.value

    elseif node.type == "Identifier" then
        return self:lookup(node.name)

    elseif node.type == "CallExpression" then
        local callee = node.callee
        local func_node = nil

        if callee.type == "Identifier" then
            func_node = self:lookup(callee.name)
        elseif callee.type == "MemberExpression" then
            local object = self:evaluate(callee.object)
            local method_name = callee.property.name
            func_node = object[method_name]
            -- Handle method calls and 'self' binding if needed
        else
            error("TypeError: Attempt to call non-function")
            return nil
        end

        if type(func_node) == "table" and func_node.type == "FunctionDeclaration" then
            local args = {}
            for _, arg in ipairs(node.arguments) do
                table.insert(args, self:evaluate(arg))
            end

            -- Type checking for arguments (as discussed before)
            if #args ~= #func_node.params then
                error("TypeError: Incorrect number of arguments for function '" .. func_node.name .. "'")
                return nil
            end

            for i, param in ipairs(func_node.params) do
                local arg_value = args[i]
                if param.type == "string" and type(arg_value) ~= "string" then
                    error("TypeError: Argument " .. i .. " of '" .. func_node.name .. "' expected 'string', got '" .. type(arg_value) .. "'")
                    return nil
                elseif param.type == "number" and type(arg_value) ~= "number" then
                    error("TypeError: Argument " .. i .. " of '" .. func_node.name .. "' expected 'number', got '" .. type(arg_value) .. "'")
                    return nil
                elseif param.type == "bool" and type(arg_value) ~= "boolean" then
                    error("TypeError: Argument " .. i .. " of '" .. func_node.name .. "' expected 'bool', got '" .. type(arg_value) .. "'")
                    return nil
                elseif param.type == "nil" and arg_value ~= nil then
                    error("TypeError: Argument " .. i .. " of '" .. func_node.name .. "' expected 'nil', got '" .. type(arg_value) .. "'")
                    return nil
                end
            end

            return self:call_function(func_node, args)
        else
            error("TypeError: Attempt to call non-function")
            return nil
        end

    elseif node.type == "IfStatement" then
        local test = self:evaluate(node.test)
        if test then
            local result = nil
            for _, stmt in ipairs(node.consequent) do
                result = self:evaluate(stmt)
            end
            return result
        elseif node.alternate then
            local result = nil
            if type(node.alternate) == "table" then
                for _, stmt in ipairs(node.alternate) do
                    result = self:evaluate(stmt)
                end
                return result
            else
                return self:evaluate(node.alternate)
            end
        else
            return nil
        end

    elseif node.type == "ForStatement" then
        self:define(node.var, self:evaluate(node.start))
        while self:lookup(node.var) <= self:evaluate(node.end_) do
            for _, stmt in ipairs(node.body) do
                self:evaluate(stmt)
            end
            if node.step then
                self:define(node.var, self:lookup(node.var) + self:evaluate(node.step))
            else
                self:define(node.var, self:lookup(node.var) + 1)
            end
        end
        return nil

    elseif node.type == "ForInStatement" then
        local iterator = self:evaluate(node.iterator)
        if type(iterator) ~= "table" then
            error("For-in iterator must be a table")
        end
        for _, value in ipairs(iterator) do
            self:define(node.var, value)
            for _, stmt in ipairs(node.body) do
                self:evaluate(stmt)
            end
        end
        return nil

    elseif node.type == "WhileStatement" then
        while self:evaluate(node.test) do
            for _, stmt in ipairs(node.body) do
                self:evaluate(stmt)
            end
        end
        return nil

    elseif node.type == "ReturnStatement" then
        if node.argument then
            return self:evaluate(node.argument)
        else
            return nil
        end

    elseif node.type == "ExpressionStatement" then
        return self:evaluate(node.expression)

    elseif node.type == "ClassDeclaration" then
        local classObj = {}
        for _, member in ipairs(node.body) do
            if member.type == "FunctionDeclaration" then
                classObj[member.name] = member
            else
                error("Unsupported class member type: " .. member.type)
            end
        end
        self:define(node.name, classObj)
        return nil

    elseif node.type == "MemberExpression" then
        local obj = self:evaluate(node.object)
        local prop = node.property.name
        return obj[prop]

    elseif node.type == "PrintStatement" then
        local value = self:evaluate(node.argument)
        print(value)
        return nil

    else
        error("Unknown node type: " .. tostring(node.type))
    end
end

function Interpreter:apply_operator(operator, left, right)
    if operator == "+" then
        if type(left) == "number" and type(right) == "number" then
            return left + right
        elseif type(left) == "string" and type(right) == "string" then
            return left .. right
        else
            error("TypeError: Operands of '+' must be numbers or strings")
            return nil
        end
    elseif operator == ".." then -- Handle the concatenation operator
        local newLeft = tostring(left)
        local newRight = tostring(right)

        
        return newLeft .. newRight
        
    elseif operator == "-" then
        if type(left) == "number" and type(right) == "number" then
            return left - right
        else
            error("TypeError: Operands of '-' must be numbers")
            return nil
        end
    elseif operator == "*" then
        if type(left) == "number" and type(right) == "number" then
            return left * right
        else
            error("TypeError: Operands of '*' must be numbers")
            return nil
        end
    elseif operator == "/" then
        if type(left) == "number" and type(right) == "number" then
            return left / right
        else
            error("TypeError: Operands of '/' must be numbers")
            return nil
        end
    elseif operator == "%" then
        if type(left) == "number" and type(right) == "number" then
            return left % right
        else
            error("TypeError: Operands of '%' must be numbers")
            return nil
        end
    elseif operator == "^" then
        if type(left) == "number" and type(right) == "number" then
            return left ^ right
        else
            error("TypeError: Operands of '^' must be numbers")
            return nil
        end
    elseif operator == "==" then
        return left == right
    elseif operator == "!=" then
        return left ~= right
    elseif operator == "<" then
        return left < right
    elseif operator == ">" then
        return left > right
    elseif operator == "<=" then
        return left <= right
    elseif operator == ">=" then
        return left >= right
    elseif operator == "and" then
        return left and right
    elseif operator == "or" then
        return left or right
    else
        error("Unknown binary operator: " .. operator)
        return nil
    end
end

function Interpreter:apply_unary_operator(operator, argument)
  if operator == "-" then return -argument
  elseif operator == "not" then return not argument
  else error("Unknown unary operator: " .. operator) end
end

function Interpreter:call_function(func, args)
  if type(func) == "function" then
    return func(table.unpack(args))
  elseif func.type == "FunctionDeclaration" then
    local new_env = setmetatable({}, {__index = self.environment})
    for i, param in ipairs(func.params) do
      new_env[param.name] = args[i]
    end
    
    local previous_env = self.environment
    self.environment = new_env

    local result = nil
    for _, stmt in ipairs(func.body) do
      local val = self:evaluate(stmt)
      if val ~= nil then
        result = val
        break
      end
    end
    self.environment = previous_env
    return result
  else
    error("Call of non-function value")
  end
end

-- Built-in functions
function Interpreter:add_builtin(name, fn)
  self.environment[name] = fn
end

return Interpreter
