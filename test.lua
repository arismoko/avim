local code = [[
local a = 42
local b = "Hello, World!"
local c = a + b
function foo(x, y)
    local result = x * y
    return result
end
]]

local tokenizer = require("plugins.easyLanguageServer.lua.tokenizer")
local tokens = tokenizer.tokenize(code)

local Parser = require("plugins.easyLanguageServer.lua.parser")
local parser = Parser:new(tokens) -- Create a new parser instance with the tokens
local ast = parser:parse() -- Call the parse method on the parser instance

-- Function to print the AST for visualization
local function printAST(node, indent)
	indent = indent or 0
	local padding = string.rep("  ", indent)
	print(padding .. node.type .. (node.value and ": " .. node.value or ""))
	for _, child in ipairs(node.children) do
		printAST(child, indent + 1)
	end
end

printAST(ast)
