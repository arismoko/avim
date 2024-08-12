local Parser = {}
Parser.__index = Parser

Tokenizer = require("plugins.easyLanguageServer.lua.tokenizer")

local function print_node(node, indent)
	indent = indent or 0
	local indent_str = string.rep("  ", indent)

	-- Collect and sort keys
	local keys = {}
	for k in pairs(node) do
		table.insert(keys, k)
	end
	table.sort(keys) -- This sorts the keys alphabetically

	-- Iterate over sorted keys
	for _, k in ipairs(keys) do
		local v = node[k]
		if type(v) == "table" then
			print(indent_str .. k .. ":")
			print_node(v, indent + 1)
		else
			print(indent_str .. k .. ": " .. tostring(v))
		end
	end
end

local PRECEDENCE = {
	["or"] = 1,
	["and"] = 2,
	["=="] = 3,
	["~="] = 3,
	["<"] = 3,
	[">"] = 3,
	["<="] = 3,
	[">="] = 3,
	["|"] = 4, -- Bitwise OR
	["~"] = 5, -- Bitwise XOR (binary)
	["&"] = 6, -- Bitwise AND
	["+"] = 7,
	["-"] = 7,
	["*"] = 8,
	["/"] = 8,
	["#"] = 8,
	["%"] = 8,
	["<<"] = 9, -- Bitwise left shift
	[">>"] = 9, -- Bitwise right shift
	[".."] = 10,
	["^"] = 11,
	["not"] = 12,
}

function Parser:new(tokens)
	--remove all LINE_BREAK tokens
	for i = #tokens, 1, -1 do
		if tokens[i].type == Tokenizer.TOKEN_TYPES.LINE_BREAK then
			table.remove(tokens, i)
		end
	end
	local instance = {
		tokens = tokens,
		position = 1,
	}
	setmetatable(instance, Parser)
	return instance
end

function Parser:loadFile(filename)
	local success, msg = pcall(function()
		local code = fs.open(filename, "r").readAll()
		local tokens = Tokenizer.tokenize(code)
		local parser = Parser:new(tokens)
		local ast = parser:parse()
		return ast
	end)
	return success, msg
end

function Parser:getIdentifiersAsList(filename)
	local identifiers = {}

	local code = fs.open(filename, "r").readAll()
	if code then -- Check if the file exists
		local tokens = Tokenizer.tokenize(code)
		local parser = Parser:new(tokens)
		local ast = parser:parse()
		local function traverse(node)
			if node.type == "identifier" then
				table.insert(identifiers, node.value)
			end
			for _, v in pairs(node) do
				if type(v) == "table" then
					traverse(v)
				end
			end
		end
		traverse(ast)
	end

	return identifiers
end

function Parser:require(expected_type, expected_value)
	local token = self:current_token()
	if expected_type and token.type ~= expected_type then
		error(
			"Expected token type " .. expected_type .. ", but found " .. token.type .. " at position " .. self.position
		)
	end
	if expected_value and token.value ~= expected_value then
		error(
			"Expected token value '"
				.. expected_value
				.. "', but found '"
				.. token.value
				.. "' at position "
				.. self.position
		)
	end
	self:advance() -- Move to the next token after checking
	return token -- Return the token that just passed the check
end

function Parser:advance()
	self.position = self.position + 1
	return self.tokens[self.position]
end

function Parser:peek(n)
	n = n or 1 -- Default to peaking one token ahead if no argument is provided
	local peek_position = self.position + n
	if peek_position <= #self.tokens then
		return self.tokens[peek_position]
	else
		return nil -- Return nil if the peek goes beyond the available tokens
	end
end

function Parser:current_token()
	return self.tokens[self.position]
end

function Parser:parse()
	return self:parse_block()
end

function Parser:parse_identifier()
	local token = self:current_token()
	if token.type ~= Tokenizer.TOKEN_TYPES.IDENTIFIER then
		error("Expected identifier at position " .. self.position .. ", found: " .. token.value)
	end
	self:advance()
	return { type = "identifier", value = token.value, position = token.position }
end

function Parser:parse_table()
	local table_elements = {}
	self:advance() -- Move past the initial '{'

	-- Check if the first token is '...'
	if self:current_token().type == Tokenizer.TOKEN_TYPES.VARARG then
		self:advance() -- Move past '...'

		-- Peek ahead to ensure that no other tokens follow '...'
		if self:current_token().type ~= Tokenizer.TOKEN_TYPES.SEPARATOR or self:current_token().value ~= "}" then
			error("Varargs (...) must be the only element in the table constructor")
		end
		self:advance() -- Move past the closing '}'

		-- Return the node early as the table only contains '...'
		local node = { type = "table", position = self.position, elements = { { key = nil, value = "..." } } }
		return node
	end

	while self.position <= #self.tokens do
		local token = self:current_token()
		if token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "}" then
			self:advance() -- Move past the closing '}'
			break
		end

		local key, value

		-- Check for explicit keys defined using brackets or implicit keys
		if token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "[" then
			self:advance() -- Move past '['
			key = self:parse_expression() -- Dynamic key
			if self:current_token().type ~= Tokenizer.TOKEN_TYPES.SEPARATOR or self:current_token().value ~= "]" then
				error("Expected ']' after table key expression at position " .. self.position)
			end
			self:advance() -- Move past ']'
			if self:current_token().type ~= Tokenizer.TOKEN_TYPES.OPERATOR or self:current_token().value ~= "=" then
				error("Expected '=' after table key at position " .. self.position)
			end
			self:advance() -- Move past '='
			value = self:parse_expression() -- Parse the value as an expression
		elseif
			token.type == Tokenizer.TOKEN_TYPES.IDENTIFIER
			or token.type == Tokenizer.TOKEN_TYPES.STRING
			or token.type == Tokenizer.TOKEN_TYPES.NUMBER
			or token.type == Tokenizer.TOKEN_TYPES.LITERAL
		then
			-- Implicit key or array-style index
			key = self:parse_primary_expression() -- Parse the key as a primary expression
			if self:current_token().type == Tokenizer.TOKEN_TYPES.OPERATOR and self:current_token().value == "=" then
				self:advance() -- Move past '='
				value = self:parse_expression() -- Parse the value as an expression
			else
				value = key -- If no '=', treat it as an array element
				key = nil
			end
		elseif token.type == Tokenizer.TOKEN_TYPES.VARARG then
			error("Varargs (...) can only be used as the sole element in a table constructor")
		else
			error("Invalid token in table constructor: " .. token.value)
		end

		-- Store the key-value pair
		table.insert(table_elements, { key = key, value = value })

		-- Handle comma or end of table
		if self:current_token().type == Tokenizer.TOKEN_TYPES.SEPARATOR and self:current_token().value == "," then
			self:advance() -- Continue to the next element
		elseif self:current_token().type ~= Tokenizer.TOKEN_TYPES.SEPARATOR or self:current_token().value ~= "}" then
			error("Expected ',' or '}' after table element at position " .. self.position)
		end
	end

	local node = { type = "table", elements = table_elements, position = self.position }
	return node
end

function Parser:parse_function_call(fn)
	self:advance() -- Skip the '(' starting the argument list

	local args = self:parse_expression_list()

	-- Use direct string values for type and token value
	self:require("separator", ")") -- Ensure the next token is ')' and advance

	local node = {
		type = "function_call",
		fn = fn,
		args = args,
		position = self.position,
	}

	return node
end

function Parser:parse_literal()
	local token = self:current_token()
	local node

	if
		token.type == Tokenizer.TOKEN_TYPES.NUMBER
		or token.type == Tokenizer.TOKEN_TYPES.STRING
		or token.type == Tokenizer.TOKEN_TYPES.LITERAL
	then
		-- Handle literals: numbers, strings, boolean, and nil
		node = { type = "literal", value = token.value, position = token.position }
		self:advance()
	elseif token.type == Tokenizer.TOKEN_TYPES.IDENTIFIER then
		-- Handle identifiers and check if it leads to a function call
		node = self:parse_identifier()
	elseif token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "{" then
		-- Handle table constructors
		node = self:parse_table()
	else
		error("Unexpected token in literal: " .. token.value .. " at position " .. self.position)
	end
	return node
end

function Parser:is_unary_operator(token)
	return token.type == Tokenizer.TOKEN_TYPES.OPERATOR
		and (token.value == "-" or token.value == "not" or token.value == "#" or token.value == "~")
end

function Parser:parse_unary_expression()
	local token = self:current_token()
	if not self:is_unary_operator(token) then
		error("Expected unary operator at position " .. self.position)
	end
	self:advance()
	return {
		type = "unary_expression",
		operator = token.value,
		operand = self:parse_primary_expression(),
		position = self.position,
	}
end

function Parser:parse_primary_expression()
	local token = self:current_token()
	local node

	-- Handle unary operators (`not`, unary `-`, `#`)
	if self:is_unary_operator(token) then
		self:advance() -- Move past the unary operator
		local operand = self:parse_primary_expression() -- Recursively parse the operand
		node = { type = "unary_expression", operator = token.value, operand = operand, position = self.position }
	elseif
		token.type == Tokenizer.TOKEN_TYPES.NUMBER
		or token.type == Tokenizer.TOKEN_TYPES.STRING
		or token.type == Tokenizer.TOKEN_TYPES.LITERAL
	then
		self:advance()
		node = { type = "literal", value = token.value, position = self.position }
	elseif token.type == Tokenizer.TOKEN_TYPES.IDENTIFIER then
		local name = token.value
		self:advance() -- Move past the identifier
		node = { type = "identifier", value = name, position = self.position }
	elseif token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "(" then
		self:advance() -- Move past '('
		node = self:parse_expression()
		self:require("separator", ")") -- Ensure closing ')'
	elseif token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "{" then
		-- Handle table constructors
		node = self:parse_table()
	elseif token.type == Tokenizer.TOKEN_TYPES.KEYWORD and token.value == "function" then
		self:advance()
		self:require("separator", "(")
		local args = self:parse_expression_list()
		self:require("separator", ")")
		local block = self:parse_block()
		self:require("keyword", "end")
		node = { type = "function", args = args, block = block, position = self.position }
	else
		node = self:parse_literal()
	end

	-- Handle possible subsequent member access, indexing, method calls, or function calls
	while true do
		token = self:current_token()
		if token == nil then
			break
		end

		if token.type == Tokenizer.TOKEN_TYPES.SEPARATOR then
			if token.value == "." then
				self:advance() -- Move past '.'
				local property = self:require("identifier").value
				node = {
					type = "access",
					access_type = "property",
					table = node,
					property = property,
					position = self.position,
				}
			elseif token.value == "[" then
				self:advance() -- Move past '['
				local index = self:parse_expression()
				self:require("separator", "]") -- Ensure closing ']'
				node = { type = "access", access_type = "index", table = node, index = index, position = self.position }
			elseif token.value == ":" then
				self:advance() -- Move past ':'
				local method = self:require("identifier").value
				self:require("separator", "(") -- Ensure method call has '('
				local args = self:parse_expression_list()
				self:require("separator", ")") -- Ensure closing ')'
				node = { type = "method_call", method = method, object = node, args = args, position = self.position }
			elseif token.value == "(" then
				node = self:parse_function_call(node)
			else
				break
			end
		else
			break
		end
	end

	return node
end

function Parser:should_apply_operator(precedence, token)
	if token.type == Tokenizer.TOKEN_TYPES.OPERATOR and PRECEDENCE[token.value] then
		if self:is_unary_operator(token) then
			-- Unary operators should have higher precedence than the current precedence level to apply
			return PRECEDENCE[token.value] > precedence
		else
			-- Binary operators should have precedence greater than or equal to the current precedence level
			return PRECEDENCE[token.value] > precedence
		end
	else
		return false
	end
end

function Parser:parse_expression(precedence)
	precedence = precedence or 0
	local left = self:parse_primary_expression()

	while true do
		local token = self:current_token()
		if token == nil then -- End of tokens
			break
		end

		-- Check if the current token is an operator with higher precedence
		if token.type == Tokenizer.TOKEN_TYPES.OPERATOR and self:should_apply_operator(precedence, token) then
			self:advance()
			local right = self:parse_expression(PRECEDENCE[token.value])
			left = { type = "binary_expression", operator = token.value, left = left, right = right }
		else
			break
		end
	end

	return left
end

function Parser:parse_expression_list()
	local expressions = {}
	while true do
		local current_token = self:current_token()

		if current_token.type == Tokenizer.TOKEN_TYPES.KEYWORD and not (current_token.value == "function") then
			break
		end
		if current_token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and current_token.value == ")" then
			break
		end
		if current_token.type == "vararg" then
			table.insert(expressions, { type = "vararg", value = "..." })
			self:advance()
			break
		end

		local expr = self:parse_expression()
		table.insert(expressions, expr)

		local next_token = self:current_token()
		if next_token == nil then
			break
		end
		if next_token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and next_token.value == "," then
			self:advance() -- Move past the comma
		else
			break -- End of the list
		end
	end
	return expressions
end

function Parser:parse_assignment(is_local)
	local exprs = self:parse_expression_list()
	local current_token = self:current_token()
	if not current_token or current_token.type ~= Tokenizer.TOKEN_TYPES.OPERATOR or current_token.value ~= "=" then
		if #exprs > 1 then
			error("Was expecting multiple assignments but did not find = operator at" .. self.position)
		end
		local node = { type = "primary_expression", value = exprs[1], position = self.position }
		return node
	end
	self:require("operator", "=")
	local expressions = self:parse_expression_list()
	local node =
		{ type = "assignment", left = exprs, expressions = expressions, is_local = is_local, position = self.position }
	-- check if the next token is an assignment operator =
	return node
end

function Parser:parse_function(is_local)
	self:advance()

	local name_node
	if self:current_token().type == Tokenizer.TOKEN_TYPES.IDENTIFIER then
		name_node = self:parse_primary_expression()
	end
	if not name_node and name_node.access ~= nil then
		error("Expected function name at position " .. self.position)
	end

	local args = {}
	if self:current_token().type == Tokenizer.TOKEN_TYPES.SEPARATOR and self:current_token().value == "(" then
		self:advance()
		args = self:parse_expression_list()
		self:advance() -- Move past the closing ')'
	end

	local body = self:parse_block()

	if self:current_token().type ~= Tokenizer.TOKEN_TYPES.KEYWORD or self:current_token().value ~= "end" then
		error("Expected 'end' to close function body at position " .. self.position)
	end
	self:advance()

	return {
		type = "function",
		identifier = name_node,
		args = args,
		block = body,
		is_local = is_local or false,
		position = self.position,
	}
end

function Parser:parse_control_structure(
	start_token,
	parse_condition,
	end_token,
	parse_body,
	finish_token,
	parse_post_body_condition
)
	self:advance()

	local condition = nil
	if parse_condition and parse_condition ~= "" then
		condition = parse_condition(self)
	end

	if end_token and end_token ~= "" and (self:current_token().value ~= end_token) then
		error("Expected keyword after condition at position " .. self.position)
	elseif end_token and end_token ~= "" then
		self:advance()
	end
	local body = parse_body(self)

	local current_token = self:current_token()

	if current_token and finish_token then
		-- Added additional debugging here
		if current_token.type ~= Tokenizer.TOKEN_TYPES.KEYWORD or current_token.value ~= finish_token then
			error(
				"Expected '" .. finish_token .. "' to close '" .. start_token .. "' block at position " .. self.position
			)
		end
	elseif finish_token ~= nil and current_token == nil then
		error(
			"Expected '"
				.. finish_token
				.. "' to close '"
				.. start_token
				.. "' block at position "
				.. self.position
				.. " instead we reached the end of the file"
		)
	elseif finish_token == nil then
		local node = {
			type = start_token .. "_structure",
			condition = condition,
			structure = body,
			position = self.position,
		}
		return node
	end
	self:advance()
	if parse_post_body_condition then
		condition = parse_post_body_condition(self)
	end
	local node = {
		type = start_token .. "_structure",
		condition = condition,
		block = body,
		position = self.position,
	}
	return node
end

function Parser:parse_if_statement(else_if)
	local function parse_condition(parser)
		return parser:parse_expression()
	end

	local function parse_body(parser)
		local body = parser:parse_block()
		local current_token = parser:current_token()

		if current_token and current_token.type == Tokenizer.TOKEN_TYPES.KEYWORD then
			if current_token.value == "else" then
				parser:advance()
				body["else"] = parser:parse_block()
			elseif current_token.value == "elseif" then
				body["elif"] = parser:parse_if_statement(true)
			end
		end
		return body
	end
	local fin_token
	local start_token
	if else_if then
		fin_token = nil
		start_token = "elseif"
	else
		fin_token = "end"
		start_token = "if"
	end
	return self:parse_control_structure(start_token, parse_condition, "then", parse_body, fin_token)
end

function Parser:parse_while_loop()
	local while_loop = self:parse_control_structure(
		"while",
		function(parser)
			return parser:parse_expression()
		end,
		"do",
		function(parser)
			return parser:parse_block()
		end,
		"end"
	)
	return while_loop
end

function Parser:parse_do_end()
	return self:parse_control_structure("do", nil, "", function(parser)
		return parser:parse_block()
	end, "end")
end

function Parser:parse_repeat_until()
	return self:parse_control_structure(
		"repeat",
		nil,
		nil,
		function(parser)
			return parser:parse_block()
		end,
		"until",
		function(parser)
			return parser:parse_expression()
		end
	)
end

function Parser:parse_for_loop()
	-- This function will handle the initialization part of the for loop
	local parse_init = function(parser)
		local loop_info = {}

		--peek forward until we find in or do
		local in_present = false
		local i = 1
		while true do
			local token = parser:peek(i)
			if token.type == Tokenizer.TOKEN_TYPES.KEYWORD and token.value == "in" then
				in_present = true
				break
			elseif token.type == Tokenizer.TOKEN_TYPES.KEYWORD and token.value == "do" then
				break
			end
			i = i + 1
		end
		-- Check if it is a generic for loop
		if in_present then
			local expressions = parser:parse_expression_list()
			-- Generic for loop
			parser:advance() -- Consume 'in'
			loop_info.type = "generic"
			loop_info.left = expressions
			loop_info.iterator = parser:parse_expression_list() -- Parsing the iterator expression
		else
			-- Numeric for loop; expecting: i = start, stop[, step]
			local assignment = parser:parse_assignment(true) -- Parse the assignment
			local start_expr = assignment.expressions[1]
			local stop_expr = assignment.expressions[2]
			local step_expr = nil -- Initialize step_expr as nil to handle optional nature

			if assignment.type ~= "assignment" then
				error("Expected assignment in numeric for loop")
			end

			if #assignment.expressions > 2 then
				step_expr = assignment.expressions[3] -- Assign step_expr only if a third expression exists
			end

			loop_info.type = "numeric"
			loop_info.start_left = assignment.left
			loop_info.start_expr = start_expr
			loop_info.stop_expr = stop_expr
			loop_info.step_expr = step_expr
		end

		return loop_info
	end

	-- Use parse_control_structure to manage the structure
	local for_loop = self:parse_control_structure(
		"for", -- Start keyword
		parse_init, -- Initializer function
		"do", -- Middle keyword
		function(parser)
			return parser:parse_block() -- Parse the body of the loop
		end,
		"end" -- End keyword
	)

	return for_loop
end

function Parser:parse_goto()
	self:advance()
	local token = self:current_token()

	if token.type ~= Tokenizer.TOKEN_TYPES.IDENTIFIER then
		return { type = "error", message = "Expected label name after 'goto'" }
	end

	local node = {
		type = "goto",
		label = token.value,
		position = token.position,
	}

	self:advance()

	return node
end

function Parser:parse_label()
	local label_start = self:current_token()

	if label_start.type ~= Tokenizer.TOKEN_TYPES.LABEL then
		error("Expected '::' at position " .. self.position)
	end

	self:advance()
	local token = self:current_token()
	if token.type ~= Tokenizer.TOKEN_TYPES.IDENTIFIER then
		error("Expected label name at position " .. self.position)
	end

	local node = {
		type = "label",
		value = token.value,
		position = token.position,
	}

	self:advance()
	local label_end = self:current_token()
	if label_end.type ~= Tokenizer.TOKEN_TYPES.LABEL then
		error(
			"Expected '::' to close label at position "
				.. self.position
				.. ", found "
				.. label_end.type
				.. " "
				.. label_end.value
				.. " instead"
		)
	end

	self:advance()

	return node
end

function Parser:parse_return()
	self:advance()
	local expressions = {}

	while self.position <= #self.tokens do
		local token = self:current_token()

		if token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "," then
			self:advance()
		elseif token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == ")" then
			break
		else
			table.insert(expressions, self:parse_expression())
		end

		token = self:current_token()
		if
			not token
			or token.type == Tokenizer.TOKEN_TYPES.KEYWORD
				and (token.value == "end" or token.value == "else" or token.value == "elseif" or token.value == "until")
		then
			break
		elseif token.type == Tokenizer.TOKEN_TYPES.SEPARATOR and token.value == "," then
			self:advance()
		else
			break
		end
	end

	return { type = "return", expressions = expressions, position = self.position }
end

function Parser:parse_break()
	-- First, advance past the 'break' keyword
	self:advance()

	-- There are no expressions or additional tokens to consume in a 'break' statement,
	-- so we can directly return the node representing the break.
	return { type = "break", position = self.position }
end

function Parser:parse_statement(is_local)
	local token = self:current_token()

	if token.type == Tokenizer.TOKEN_TYPES.KEYWORD then
		if token.value == "if" then
			return self:parse_if_statement()
		elseif token.value == "while" then
			return self:parse_while_loop()
		elseif token.value == "do" then
			return self:parse_do_end()
		elseif token.value == "repeat" then
			return self:parse_repeat_until()
		elseif token.value == "for" then
			return self:parse_for_loop()
		elseif token.value == "function" then
			return self:parse_function(is_local)
		elseif token.value == "goto" then
			return self:parse_goto()
		elseif token.value == "return" then
			return self:parse_return()
		elseif token.value == "break" then
			return self:parse_break()
		elseif token.value == "local" then
			self:advance()
			return self:parse_statement(true)
		end
	elseif token.type == Tokenizer.TOKEN_TYPES.IDENTIFIER then
		-- Possible variable assignment or function call
		local next_token = self:peek()
		if not next_token then
			error("Unexpected end of input after identifier at position " .. self.position)
		end
		if next_token and next_token.type == Tokenizer.TOKEN_TYPES.OPERATOR then
			return self:parse_assignment(is_local)
		elseif next_token and next_token.type == Tokenizer.TOKEN_TYPES.SEPARATOR then
			if next_token.value ~= "{" and next_token.value ~= "(" then
				-- It's an assignment statement
				return self:parse_assignment(is_local)
			else
				return self:parse_primary_expression()
			end
		else
			error("Unexpected token: " .. token.value .. "after identifier at position " .. self.position)
		end
	elseif token.type == Tokenizer.TOKEN_TYPES.LABEL then
		return self:parse_label()
	else
		error("Unexpected token '" .. token.value .. "' at position " .. self.position)
	end
end

function Parser:parse_block()
	local statements = {}
	while self.position <= #self.tokens do
		local token = self:current_token()

		if
			token.type == Tokenizer.TOKEN_TYPES.KEYWORD
			and (token.value == "end" or token.value == "else" or token.value == "elseif" or token.value == "until")
		then
			break
		end

		local statement = self:parse_statement()
		if statement then
			table.insert(statements, statement)
		else
			error("Invalid statement at position " .. self.position)
		end
	end

	return { type = "block", body = statements }
end

return Parser
-- local code = [=[
-- -- -- ===========================
-- -- -- Variable Declarations and Assignments
-- -- -- ===========================
-- x = 10
-- local y = 20
-- local t = {key1 = "value1", key2 = "value2"}
-- t.key1 = "new value"
-- t["key1"] = "new value"
-- t[1] = "value3"
-- t[x] = value4
-- x = x + 1
-- local x,y = 1,2
-- x = x * y + 10 / 2
-- x = 10 / 2 + x * y
-- x = 10 / (2 + x) * y
-- --
-- -- -- ===========================
-- -- -- Control Structures
-- -- -- ===========================
-- --
-- while x < 5 do
--   print(x)
--   x = x + 1
-- end
--
-- repeat
--   print("This will print once")
-- until false
--
-- repeat a = a + 1 until a > 10
--
-- if true then
--   return 3
-- end
--
-- if a < 5 then
-- print("a is less than 5")
-- elseif a == 5 then
-- print("a is equal to 5")
-- end
--
-- if a < 69 then
--   print("a is less than 69")
-- else
--   print("a is greater than 69")
-- end
--
-- if a > 420 then
--   print("a is greater than 420")
-- elseif a < 420 then
--   print("a is less than 420")
--   x = 10
--   if x == 10 then
--     print("x is 10")
--   end
-- else
--   print("a is equal to 420")
-- end
--
-- --Testing for loop
-- for stuff in pairs(t) do
--   print(stuff)
-- end
-- for stuff, value in pairs(t) do
--   print(stuff, value)
-- end
--
-- -- Testing numeric for loop
-- for i = 1, 10 do
--  print(i)
-- end
--
-- --Testing numeric for loop with step
-- for i = 1, 10, 2 do
--   print(i)
-- end
--
-- -- Using do-end block for local scoping
-- do
--   local x = 10
--   print(x)
-- end
--
-- -- Goto statement and label
-- goto test_label
-- print("This will be skipped")
-- ::test_label::
-- print("This will be printed")
--
-- -- ===========================
-- -- Functions and Function Calls
-- -- ===========================
--
-- function test_function(a, b)
--   return a + b
-- end
-- --Testing functions with variable arguments
-- function varargs_example(...)
--   args = {...}
--   for i, v in ipairs(args) do
--     print(i, v)
--   end
-- end
-- varargs_example(1, 2, 3, "hello")
-- -- Anonymous functions
-- local anonymous = function()
--   print("WHAT IS THIS????!")
-- end
-- local anonwithargs = function(a, b)
--   print(a + b)
-- end
-- -- Nested functions
-- function test()
--   print("Hello, World!")
--   function test_two()
--     print("Hello again!")
--   end
--   local function test_three()
--     print("Hello for the third time!")
--   end
-- end
--
-- -- -- ===========================
-- -- -- Table Operations
-- -- -- ===========================
--
-- -- Complex table with various key types
-- local complex_table = {
--   [1] = "one",
--   ["key"] = "value",
--   [x + 1] = "expr"
-- }
-- -- Function setting a metatable
-- setmetatable(complex_table, {
--   __index = function(table, key)
--     return "default"
--   end
-- })
-- --
-- -- -- ===========================
-- -- -- Metamethods and Metatables
-- -- -- ===========================
--
-- --Testing metamethods with a metatable
-- local mt = {
--   __add = function(a, b)
--     return a.value + b.value
--   end
-- }
-- local obj1 = { value = 10 }
-- local obj2 = { value = 20 }
-- setmetatable(obj1, mt)
-- setmetatable(obj2, mt)
-- local result = obj1 + obj2 -- Should use __add metamethod
-- print(result) -- Should print 30
--
-- -- -- ===========================
-- -- -- Coroutines
-- -- -- ===========================
-- --
-- -- Testing coroutine with yield and resume
-- function coroutine_example()
--   local x = 0
--   while true do
--     x = x + 1
--     coroutine.yield(x)
--   end
-- end
-- local co = coroutine.create(coroutine_example)
-- print(coroutine.resume(co)) -- Should print true, 1
--
-- -- -- ===========================
-- -- -- Nested Tables
-- -- -- ===========================
-- local nested_table = { key1 = { key2 = { key3 = "value" } } }
-- print(nested_table.key1.key2.key3) -- Should print "value"
-- --
-- -- -- ===========================
-- -- -- Custom Environment
-- -- -- ===========================
-- --
-- -- Testing custom environment (Lua 5.1 style)
-- local env = { x = 10 }
-- setfenv(1, env) -- Set custom environment
-- print(x) -- Should print 10
--
-- setfenv(1, {}) -- Empty environment
-- print(x) -- Should error, as x is not defined
-- --
-- -- -- ===========================
-- -- -- Strings and Comments
-- -- -- ===========================
-- --
-- -- -- Testing multi-line strings
-- local multiline_str = [[
-- This is a
-- multi-line
-- string.
-- ]]
-- print(multiline_str) -- Should print the multi-line string
--
-- -- Testing multi-line comments
-- --[[
-- print("This line is commented out")
-- ]]
-- --
-- -- -- ===========================
-- -- -- Garbage Collection
-- -- -- ===========================
-- --
-- -- -- Testing garbage collection
-- collectgarbage("collect") -- Force a garbage collection cycle
-- print("Garbage collection cycle completed")
-- --
-- -- -- ===========================
-- -- -- File I/O (requires an actual Lua environment with file access)
-- -- -- ===========================
-- --
-- -- Testing file I/O
-- local file = io.open("test.txt", "w")
-- file:write("Hello, file!")
-- file:close()
--
-- file = io.open("test.txt", "r")
-- local content = file:read("*all")
-- print(content) -- Should print "Hello, file!"
-- file:close()
-- --
-- -- -- ===========================
-- -- -- String Formatting
-- -- -- ===========================
--
-- --String concatenation
-- local name = "Lua"
-- local greeting = "Hello, " .. name .. "!"
-- print(greeting)  -- Should print: Hello, Lua!
--
-- --String formatting with string.format
-- local version = 5.4
-- local formatted = string.format("Welcome to %s version %.1f", name, version)
-- print(formatted)  -- Should print: Welcome to Lua version 5.4
--
-- local num = 42
-- local hex = string.format("Number in hex: %x", num)
-- print(hex)  -- Should print: Number in hex: 2a
--
-- --Using custom string interpolation
-- local function interp(s, tab)
--     return (s:gsub('($%b{})', function(w) return tab[w:sub(3, -2)] or w end))
-- end
--
-- local result = interp("Welcome to ${name} version ${version}", {name = name, version = version})
-- print(result)  -- Should print: Welcome to Lua version 5.4
-- -- -- ===========================
-- -- -- Object Methods
-- -- -- ===========================
-- local object = {
-- child = { cry = function() print("WAAAAAAH!") end, brother = { name = "Bob", wave = function() print("HELLO") end } },
--   add = function(self, x)
--     return self.value + x
--   end
-- }
-- object.child:cry() -- Should print "WAAAAAAH!"
-- print(object.child.brother.name) -- Should print "Bob"
-- object.child.brother:wave() -- Should print "HELLO"
-- 	Person.__index = Person
--
-- 		function Person:new(name, age)
-- 			local self = setmetatable({}, Person)
-- 			self.name = name
-- 			self.age = age
-- 			return self
-- 		end
--
-- 		function Person:greet()
-- 			return "Hello, my name is " .. self.name
-- 		end
--
-- 		local p = Person:new("Alice", 30)
-- 		print(p:greet())
-- ]=]

-- local tokens = Tokenizer.tokenize(code)
-- print("============================================")
-- print("Tokens:")
-- for _, token in ipairs(tokens) do
-- 	print(token.type, token.value)
-- end
-- local parser = Parser:new(tokens)
-- local ast = parser:parse()
-- --print a seperator line
-- print("============================================")
-- print("Final AST:")
-- print_node(ast)
--
-- local function run_tests()
-- 	local successes = {} -- Table to store successful test cases
-- 	local failures = {} -- Table to store failed test cases
--
-- 	-- Helper function to parse and check the type of the resulting AST node
-- 	local function assert_parse_type(code, expected_type)
-- 		print("-----------------------------------")
-- 		print("START OF NEW TEST CASE: ", code)
-- 		print("-----------------------------------")
-- 		local success, error_msg = pcall(function()
-- 			local tokens = Tokenizer.tokenize(code)
-- 			local parser = Parser:new(tokens)
-- 			local ast = parser:parse()
-- 			assert(ast.type == expected_type, "Expected type: " .. expected_type .. ", but got: " .. ast.type)
-- 			-- Store the AST node instead of the code
-- 			table.insert(successes, ast)
-- 			-- Print AST node on success
-- 			print("AST: ")
-- 			print_node(ast)
-- 		end)
-- 		if not success then
-- 			table.insert(failures, { code = code, error = error_msg })
-- 		end
-- 		print("Finished test case: ", code)
-- 		print("Success: ", success)
-- 		print("Error message: ", error_msg)
-- 	end
-- 	-- 1. Basic Literal Types
-- 	assert_parse_type("return 10", "block")
-- 	assert_parse_type("return 'hello'", "block")
-- 	assert_parse_type("return true", "block")
-- 	assert_parse_type("return nil", "block")
--
-- 	-- 2. Variable Assignments
-- 	assert_parse_type("x = 5", "block")
-- 	assert_parse_type("x, y = 5, 10", "block")
-- 	assert_parse_type("x, y, z = 1, 2, 3", "block")
--
-- 	-- 3. Table Construction and Access
-- 	assert_parse_type("t = {}", "block")
-- 	assert_parse_type("t = {key = 'value', [1] = true}", "block")
-- 	assert_parse_type("print(t['key'])", "block")
-- 	assert_parse_type("t.method:call()", "block")
--
-- 	-- 4. Function Definitions and Calls
-- 	assert_parse_type("function f() end", "block")
-- 	assert_parse_type("local function g(x) return x end", "block")
-- 	assert_parse_type("f()", "block")
-- 	assert_parse_type("return function(x) return x end", "block")
-- 	assert_parse_type("function varargs(...) end", "block")
--
-- 	-- 5. Control Structures
-- 	assert_parse_type("if x then y() end", "block")
-- 	assert_parse_type("while true do break end", "block")
-- 	assert_parse_type("repeat until false", "block")
-- 	assert_parse_type("for i = 1, 10 do print(i) end", "block")
-- 	assert_parse_type("for k, v in pairs(t) do end", "block")
--
-- 	-- 6. Operator Precedence and Expression Parsing
-- 	assert_parse_type("return 1 + 2 * 3", "block")
-- 	assert_parse_type("return (1 + 2) * 3", "block")
-- 	assert_parse_type("return a and b or c", "block")
-- 	assert_parse_type("return not false", "block")
-- 	-- 9. Nested Function Calls and Variable Scoping
-- 	assert_parse_type(
-- 		[[
--     print(math.abs(-1))
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local x = math.max(1, 2, 3)
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local y = string.sub('hello', 2, 4)
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local x = 5
--     do
--         local x = 10
--     end
--     return x
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     do
--         local a = 1
--         local function f() return a end
--     end
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local x = 0
--     for i = 1, 5 do
--         local x = i
--     end
--     return x
-- ]],
-- 		"block"
-- 	)
--
-- 	-- 10. Advanced Control Structures
-- 	assert_parse_type(
-- 		[[
--     if x then y = 1 elseif z then y = 2 else y = 3 end
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     if a then
--         if b then c = 1 else c = 2 end
--     else
--         c = 3
--     end
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     for i = 1, 5 do
--         for j = 1, 5 do
--             print(i, j)
--         end
--     end
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     while x < 10 do
--         x = x + 1
--         while y < 5 do
--             y = y + 1
--         end
--     end
-- ]],
-- 		"block"
-- 	)
--
-- 	-- 11. Table Constructors and Metatables
-- 	assert_parse_type(
-- 		[[
--     local t = {1, 2, 'three', true, false, nil}
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local t = {a = 1, b = 'two', c = {nested = true}}
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local t = {}
--     setmetatable(t, {__index = function() return 42 end})
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local t = {}
--     t.__index = t
--     setmetatable(t, t)
-- ]],
-- 		"block"
-- 	)
--
-- 	-- 12. Function Variants and Return Types
-- 	assert_parse_type(
-- 		[[
--     function f() return 1, 2, 3 end
--     local a, b, c = f()
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     function f() return 'a', true, nil end
--     local x, y, z = f()
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local function f(a, b, c)
--         b = b or 10
--         c = c or 20
--         return a + b + c
--     end
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local function counter()
--         local count = 0
--         return function()
--             count = count + 1
--             return count
--         end
--     end
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local c = counter()
--     print(c())
--     print(c())
-- ]],
-- 		"block"
-- 	)
--
-- 	-- 13. Edge Cases and Error Handling
-- 	assert_parse_type(
-- 		[[
--     local t = {}
--     print(t.nonexistent)
-- ]],
-- 		"block"
-- 	)
--
-- 	-- 14. Miscellaneous Cases
-- 	assert_parse_type(
-- 		[[
--     -- This is a comment
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     x = 10 -- Assign 10 to x
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[=[
--     --[[
--     This is a
--     multi-line comment
--     ]]
-- ]=],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     print('Hello, world!')
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     require('module')
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local m = require('module')
--     m.doSomething()
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local s = 'This is a \'quoted\' string'
-- ]],
-- 		"block"
-- 	)
-- 	assert_parse_type(
-- 		[[
--     local s = "This is a \\ string with two backslashes"
-- ]],
-- 		"block"
-- 	)
--
-- 	-- 13. Metatables and Metamethods
-- 	assert_parse_type(
-- 		[[local t = {}
-- 		local mt = {
-- 			__index = function(table, key)
-- 				return key .. "_not_found"
-- 			end
-- 		}
-- 		setmetatable(t, mt)
-- 		print(t.missing_key)]],
-- 		"block"
-- 	)
--
-- 	assert_parse_type(
-- 		[[local t = setmetatable({}, {
-- 			__add = function(a, b)
-- 				return a.value + b.value
-- 			end
-- 		})
-- 		local t2 = {value = 10}
-- 		print(t + t2)]],
-- 		"block"
-- 	)
--
-- 	-- 14. Coroutines
-- 	assert_parse_type(
-- 		[[local co = coroutine.create(function()
-- 			for i = 1, 5 do
-- 				print("Coroutine iteration: ", i)
-- 				coroutine.yield()
-- 			end
-- 		end)
-- 		coroutine.resume(co)
-- 		coroutine.resume(co)]],
-- 		"block"
-- 	)
--
-- 	assert_parse_type(
-- 		[[local co = coroutine.wrap(function()
-- 			for i = 1, 3 do
-- 				coroutine.yield(i)
-- 			end
-- 		end)
-- 		for i = 1, 3 do
-- 			print(co())
-- 		end]],
-- 		"block"
-- 	)
--
-- 	-- 15. String Manipulation
-- 	assert_parse_type(
-- 		[[local s = "hello"
-- 		local s2 = s .. " world"
-- 		print(s2:upper())
-- 		print(s2:sub(1, 5))]],
-- 		"block"
-- 	)
--
-- 	-- 16. File I/O
-- 	assert_parse_type(
-- 		[[local file = io.open("test.txt", "w")
-- 		file:write("Hello, world!")
-- 		file:close()
--
-- 		file = io.open("test.txt", "r")
-- 		local content = file:read("*all")
-- 		print(content)
-- 		file:close()]],
-- 		"block"
-- 	)
--
-- 	-- 17. Advanced Function Usage
-- 	assert_parse_type(
-- 		[[local function make_counter()
-- 			local count = 0
-- 			return function()
-- 				count = count + 1
-- 				return count
-- 			end
-- 		end
--
-- 		local counter = make_counter()
-- 		print(counter()) -- 1
-- 		print(counter()) -- 2]],
-- 		"block"
-- 	)
--
-- 	assert_parse_type(
-- 		[[local function map(func, array)
-- 			local new_array = {}
-- 			for i, v in ipairs(array) do
-- 				new_array[i] = func(v)
-- 			end
-- 			return new_array
-- 		end
--
-- 		local squared = map(function(x) return x * x end, {1, 2, 3, 4})
-- 		for _, v in ipairs(squared) do
-- 			print(v)
-- 		end]],
-- 		"block"
-- 	)
--
-- 	-- 18. Object-Oriented Programming Style
-- 	assert_parse_type(
-- 		[[local Person = {}
-- 		Person.__index = Person
--
-- 		function Person:new(name, age)
-- 			local self = setmetatable({}, Person)
-- 			self.name = name
-- 			self.age = age
-- 			return self
-- 		end
--
-- 		function Person:greet()
-- 			return "Hello, my name is " .. self.name
-- 		end
--
-- 		local p = Person:new("Alice", 30)
-- 		print(p:greet())]],
-- 		"block"
-- 	)
--
-- 	-- 19. Recursive Functions and Deep Recursion
-- 	assert_parse_type(
-- 		[[local function factorial(n)
-- 			if n == 0 then
-- 				return 1
-- 			else
-- 				return n * factorial(n - 1)
-- 			end
-- 		end
-- 		print(factorial(5))]],
-- 		"block"
-- 	)
--
-- 	assert_parse_type(
-- 		[[local function fibonacci(n)
-- 			if n <= 1 then
-- 				return n
-- 			else
-- 				return fibonacci(n - 1) + fibonacci(n - 2)
-- 			end
-- 		end
-- 		print(fibonacci(10))]],
-- 		"block"
-- 	)
--
-- 	-- 20. Error Handling with pcall and xpcall
-- 	assert_parse_type(
-- 		[[local function faulty()
-- 			error("An intentional error")
-- 		end
--
-- 		local status, err = pcall(faulty)
-- 		if not status then
-- 			print("Caught error: " .. err)
-- 		end]],
-- 		"block"
-- 	)
--
-- 	-- 21. Multiple Return Values and Unpacking
-- 	assert_parse_type(
-- 		[[local function faulty()
-- 			error("An intentional error")
-- 		end
--
-- 		local function errorHandler(err)
-- 			print("Handled error: " .. err)
-- 		end
--
-- 		xpcall(faulty, errorHandler)]],
-- 		"block"
-- 	)
--
-- 	-- 22. Multiple Return Values and Unpacking
-- 	assert_parse_type(
-- 		[[function multiple_returns()
-- 	           return 1, 2, 3
-- 	       end
--
-- 	       local a, b, c = multiple_returns()
-- 	       print(a, b, c)]],
-- 		"block"
-- 	)
--
-- 	-- 23. Functions with Default Argument Values (via `or`)
-- 	assert_parse_type(
-- 		[[local function greet(name)
-- 	           name = name or "World"
-- 	           print("Hello, " .. name)
-- 	       end
--
-- 	       greet() -- Should print "Hello, World"
-- 	       greet("Lua") -- Should print "Hello, Lua"]],
-- 		"block"
-- 	)
--
-- 	-- 24. Deeply Nested Functions
-- 	assert_parse_type(
-- 		[[local function outer()
-- 	           local function middle()
-- 	               local function inner()
-- 	                   print("Deeply nested")
-- 	               end
-- 	               inner()
-- 	           end
-- 	           middle()
-- 	       end
-- 	       outer()]],
-- 		"block"
-- 	)
--
-- 	-- 25. Handling Large Numbers
-- 	assert_parse_type(
-- 		[[local huge_number = 9223372036854775807
-- 	       print(huge_number)]],
-- 		"block"
-- 	)
--
-- 	-- 26. Advanced Table Manipulation
-- 	assert_parse_type(
-- 		[[local tbl = {1, 2, 3, 4, 5}
-- 	       table.insert(tbl, 3, 99) -- Insert 99 at position 3
-- 	       print(table.remove(tbl, 1)) -- Remove and print the first element
-- 	       for k, v in ipairs(tbl) do
-- 	           print(k, v)
-- 	       end]],
-- 		"block"
-- 	)
--
-- 	-- 27. Variable Shadowing and Scoping
-- 	assert_parse_type(
-- 		[[local x = 5
-- 	       do
-- 	           local x = 10
-- 	           print(x) -- Should print 10
-- 	       end
-- 	       print(x) -- Should print 5]],
-- 		"block"
-- 	)
--
-- 	-- 28. Escaped Characters in Strings
-- 	assert_parse_type(
-- 		[[local str = "This is a backslash: \\\\ and a newline: \\n"
-- 	       print(str)]],
-- 		"block"
-- 	)
-- 	assert_parse_type(" local str = 'This is a backslash: \\\\ and a newline: \\n' print(str)", "block")
--
-- 	assert_parse_type(" local str = ' \" ' print(str)", "block")
--
-- 	-- 29. Error Handling with Custom Error Messages
-- 	assert_parse_type(
-- 		[[local function faulty()
-- 	           error("Custom error message")
-- 	       end
--
-- 	       local status, err = pcall(faulty)
-- 	       if not status then
-- 	           print("Caught error: " .. err)
-- 	       end]],
-- 		"block"
-- 	)
--
-- 	-- 30. Logical Operators and Short-Circuit Evaluation
-- 	assert_parse_type(
-- 		[[local x = false and error("This won't happen")
-- 	       local y = true or error("This won't happen either")
-- 	       print(x, y)]],
-- 		"block"
-- 	)
--
-- 	-- 31. Custom Iterators
-- 	assert_parse_type(
-- 		[[local function squares(max)
-- 	           local i = 0
-- 	           return function()
-- 	               i = i + 1
-- 	               if i <= max then
-- 	                   return i, i * i
-- 	               end
-- 	           end
-- 	       end
--
-- 	       for n, sq in squares(5) do
-- 	           print(n, sq)
-- 	       end]],
-- 		"block"
-- 	)
-- 	-- Test binary notation
-- 	assert_parse_type(
-- 		[[
--     local bin1 = 0b1010
--     local bin2 = 0b1100
--     local binSum = bin1 + bin2
--     print(binSum) -- Expected output: 22 (in decimal)
--     ]],
-- 		"block"
-- 	)
--
-- 	-- Test bitwise operations
-- 	assert_parse_type(
-- 		[[
--     local bitAnd = 0b1010 & 0b1100
--     print(bitAnd) -- Expected output: 8 (in decimal, which is 0b1000)
--
--     local bitOr = 0b1010 | 0b1100
--     print(bitOr) -- Expected output: 14 (in decimal, which is 0b1110)
--
--     local bitNot = ~0b1010
--     print(bitNot) -- Expected output: -11 (in decimal, bitwise NOT of 0b1010)
--
--     local bitShiftLeft = 0b1010 << 2
--     print(bitShiftLeft) -- Expected output: 40 (in decimal, which is 0b101000)
--
--     local bitShiftRight = 0b1100 >> 1
--     print(bitShiftRight) -- Expected output: 6 (in decimal, which is 0b0110)
--     ]],
-- 		"block"
-- 	)
--
-- 	-- Test weak table with weak keys
-- 	assert_parse_type(
-- 		[[
--     local weakKeyTable = {}
--     setmetatable(weakKeyTable, {__mode = "k"}) -- Weak keys
--     local key = {}
--     weakKeyTable[key] = "value"
--     key = nil -- Allow key to be garbage collected
--     collectgarbage() -- Force garbage collection
--     for k, v in pairs(weakKeyTable) do
--         print(k, v) -- This might print nothing if the key was collected
--     end
--     ]],
-- 		"block"
-- 	)
--
-- 	-- Test weak table with weak values
-- 	assert_parse_type(
-- 		[[
--     local weakValueTable = {}
--     setmetatable(weakValueTable, {__mode = "v"}) -- Weak values
--     local value = {}
--     weakValueTable["key"] = value
--     value = nil -- Allow value to be garbage collected
--     collectgarbage() -- Force garbage collection
--     for k, v in pairs(weakValueTable) do
--         print(k, v) -- This might print nothing if the value was collected
--     end
--     ]],
-- 		"block"
-- 	)
-- 	-- Print the results
-- 	if #failures > 0 then
-- 		print("# Test cases passed: " .. #successes)
-- 		print("Passed test cases:")
-- 		for i, node in ipairs(successes) do
-- 			print(i .. ": AST Node")
-- 			print_node(node)
-- 		end
-- 		print("-------------------------------")
-- 		print("\n# Test cases failed: " .. #failures)
-- 		for i, failure in ipairs(failures) do
-- 			print(i .. ": " .. failure.code)
-- 			print("Error message: " .. failure.error)
-- 			print("Tokens: ")
-- 			local tokens = Tokenizer.tokenize(failure.code)
-- 			for i, token in ipairs(tokens or {}) do
-- 				print(i .. ":", token.type, token.value)
-- 			end
-- 			local parser = Parser:new(tokens)
--
-- 			print("AST: ")
-- 			-- Call parser:parse using pcall
-- 			local success, ast = pcall(function()
-- 				return parser:parse()
-- 			end)
-- 			if success then
-- 				print_node(ast)
-- 			else
-- 				print("Parsing failed.")
-- 			end
-- 		end
-- 		print("Some tests failed.")
-- 	else
-- 		print("All tests passed!")
-- 		print("# Test cases passed: " .. #successes)
-- 		for i, node in ipairs(successes) do
-- 			print(i .. ": AST Node")
-- 			print_node(node)
-- 		end
-- 	end
-- end
--
-- run_tests()
