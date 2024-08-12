local tokenizer = {}

-- Token types
tokenizer.TOKEN_TYPES = {
	KEYWORD = "keyword",
	IDENTIFIER = "identifier",
	STRING = "string",
	NUMBER = "number",
	OPERATOR = "operator",
	SEPARATOR = "separator",
	COMMENT = "comment",
	LABEL = "label",
	VARARG = "vararg",
	LINE_BREAK = "line_break", -- Special token for line breaks
}

local keywords = {
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["until"] = true,
	["while"] = true,
	["goto"] = true,
}

-- Helper functions
local function isAlpha(char)
	return char:match("%a") ~= nil
end

local function isDigit(char)
	return char:match("%d") ~= nil
end

local function isHexDigit(char)
	return char:match("[%da-fA-F]") ~= nil
end

local function isBinaryDigit(char)
	return char == "0" or char == "1"
end

local function isAlphanumeric(char)
	return isAlpha(char) or isDigit(char)
end

local function isWhitespace(char)
	return char:match("%s") ~= nil
end

local function startsWith(str, prefix)
	return str:sub(1, #prefix) == prefix
end

local function advance(code, position)
	return position + 1, code:sub(position + 1, position + 1)
end

-- Tokenize function
function tokenizer.tokenize(code)
	local tokens = {}
	local position = 1
	local char = code:sub(position, position)

	while position <= #code do
		if char == "\n" then
			-- Handle line breaks by inserting a LINE_BREAK token
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.LINE_BREAK, value = "<LINE_BREAK>" })
			position, char = advance(code, position)
		elseif isWhitespace(char) then
			-- Skip other whitespace
			position, char = advance(code, position)
		elseif startsWith(code:sub(position), "--[[") then
			-- Multi-line comment
			local start = position
			position = position + 4 -- Skip '--[['
			while not startsWith(code:sub(position), "]]") and position <= #code do
				position = position + 1
			end
			position = position + 2 -- Skip closing ']]'
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.COMMENT, value = code:sub(start, position - 1) })
		elseif startsWith(code:sub(position), "--") then
			-- Single-line comment
			local start = position
			while char ~= "\n" and position <= #code do
				position, char = advance(code, position)
			end
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.COMMENT, value = code:sub(start, position - 1) })
		elseif startsWith(code:sub(position), "[[") or code:sub(position, position + 2):match("^%[%=+%[") then
			-- Multi-line string
			local start = position
			local level = code:match("^%[%=*(%[)", position):len() - 1
			position = position + level + 2
			while
				not code:sub(position, position + level + 1):match("^%]" .. string.rep("=", level) .. "%]")
				and position <= #code
			do
				position = position + 1
			end
			position = position + level + 2 -- Skip closing brackets
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.STRING, value = code:sub(start, position - 1) })
		elseif char == '"' or char == "'" then
			-- Parse string
			local start = position
			local quote = char
			position, char = advance(code, position) -- Move past the opening quote

			while position <= #code do
				if char == "\\" then
					position, char = advance(code, position) -- Move past the backslash
					if position > #code then
						break -- Handle edge case where backslash is at the end of the string
					end
				elseif char == quote then
					break -- Found the closing quote, end the loop
				end

				position, char = advance(code, position)
			end

			if char == quote then
				position = position + 1 -- Move past the closing quote
			end

			local string_value = code:sub(start, position - 1)
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.STRING, value = string_value })
		elseif isAlpha(char) or char == "_" then
			-- Parse identifier, keyword, or literal
			local start = position
			while isAlphanumeric(char) or char == "_" do
				position, char = advance(code, position)
			end
			local value = code:sub(start, position - 1)
			if value == "true" or value == "false" or value == "nil" then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.LITERAL, value = value })
			elseif keywords[value] then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.KEYWORD, value = value })
			elseif value == "and" or value == "or" or value == "not" then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = value }) -- Recognize as operator
			else
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.IDENTIFIER, value = value })
			end
		elseif startsWith(code:sub(position), "0x") or startsWith(code:sub(position), "0X") then
			-- Parse hexadecimal number
			local start = position
			position, char = advance(code, position + 1) -- Skip '0x'
			while isHexDigit(char) do
				position, char = advance(code, position)
			end
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.NUMBER, value = code:sub(start, position - 1) })
		elseif startsWith(code:sub(position), "0b") or startsWith(code:sub(position), "0B") then
			-- Parse binary number
			local start = position
			position, char = advance(code, position + 1) -- Skip '0b'
			while isBinaryDigit(char) do
				position, char = advance(code, position)
			end
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.NUMBER, value = code:sub(start, position - 1) })
		elseif isDigit(char) or (char == "." and isDigit(code:sub(position + 1, position + 1))) then
			-- Parse number
			local start = position
			local hasDecimal = false
			while isDigit(char) or (char == "." and not hasDecimal) do
				if char == "." then
					hasDecimal = true
				end
				position, char = advance(code, position)
			end
			if char == "e" or char == "E" then
				position, char = advance(code, position)
				if char == "+" or char == "-" then
					position, char = advance(code, position)
				end
				while isDigit(char) do
					position, char = advance(code, position)
				end
			end
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.NUMBER, value = code:sub(start, position - 1) })
		elseif char == "=" then
			if code:sub(position + 1, position + 1) == "=" then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "==" })
				position = position + 2
			else
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "=" })
				position = position + 1
			end
		elseif char == "~" and code:sub(position + 1, position + 1) == "=" then
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "~=" })
			position = position + 2
		elseif code:sub(position, position + 1) == "<<" then
			-- Parse bitwise left shift
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "<<" })
			position = position + 2
		elseif code:sub(position, position + 1) == ">>" then
			-- Parse bitwise right shift
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = ">>" })
			position = position + 2
		elseif char == "<" then
			if code:sub(position + 1, position + 1) == "=" then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "<=" })
				position = position + 2
			else
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "<" })
				position = position + 1
			end
		elseif char == ">" then
			if code:sub(position + 1, position + 1) == "=" then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = ">=" })
				position = position + 2
			else
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = ">" })
				position = position + 1
			end
		elseif char == "/" and code:sub(position + 1, position + 1) == "/" then
			-- Floor division
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = "//" })
			position = position + 2
		elseif char == "." then
			if code:sub(position + 1, position + 2) == ".." then
				-- Handle the case of '..' (concatenation)
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.VARARG, value = "..." })
				position = position + 3
			elseif code:sub(position + 1, position + 1) == "." then
				-- Handle the case of '...' (vararg or other special meaning)
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = ".." })
				position = position + 2
			else
				-- Handle single '.' as a separator
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.SEPARATOR, value = "." })
				position = position + 1
			end
		elseif char == ":" then
			if code:sub(position + 1, position + 1) == ":" then
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.LABEL, value = "::" })
				position = position + 2
			else
				table.insert(tokens, { type = tokenizer.TOKEN_TYPES.SEPARATOR, value = ":" })
				position = position + 1
			end
		elseif
			char == "+"
			or char == "-"
			or char == "*"
			or char == "/"
			or char == "%"
			or char == "^"
			or char == "#"
			or char == "&" -- Bitwise AND
			or char == "|"
			or char == "~" -- Bitwise XOR (and NOT when unary)
		then
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.OPERATOR, value = char })
			position, char = advance(code, position)
		elseif
			char == "{"
			or char == "}"
			or char == "("
			or char == ")"
			or char == "["
			or char == "]"
			or char == ";"
			or char == ","
		then
			table.insert(tokens, { type = tokenizer.TOKEN_TYPES.SEPARATOR, value = char })
			position, char = advance(code, position)
		else
			error("Unexpected character '" .. char .. "' at position " .. position)
		end

		char = code:sub(position, position)
	end

	-- Final check to remove any comment tokens (if any slipped through)
	local filtered_tokens = {}
	for _, token in ipairs(tokens) do
		if token.type ~= tokenizer.TOKEN_TYPES.COMMENT then
			table.insert(filtered_tokens, token)
		end
	end

	return filtered_tokens
end

return tokenizer
