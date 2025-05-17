
local Lexer = require("src.lexer.lexer")
local Parser = require("src.parser.parser")
local Interpreter = require("src.interpeter.interpeter")


local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    error("Failed to open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function main()
  local source_path = "./test/test1.luascript"
  local source = read_file(source_path)

  -- Lexing
  local lexer = Lexer.new(source)
  local tokens = lexer:tokenize()
  -- Parsing
  local parser = Parser.new(tokens)
  local ast = parser:parse_program()

  -- Interpreting
  local interpreter = Interpreter.new()

  -- Add built-ins
  interpreter:add_builtin("print", function(...)
    local args = {...}
    for i=1,#args do
      io.write(tostring(args[i]))
      if i < #args then io.write("\t") end
    end
    io.write("\n")
  end)

  -- Execute
  local status, err = pcall(function()
    interpreter:evaluate(ast)
  end)

  if not status then
    print("Runtime error: " .. err)
  end
end

main()