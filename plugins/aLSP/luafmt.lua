local function printHelp()
	print("usage:")
	print("\tlua " .. arg[0] .. " <lua file> [column hint]")
	print("\t\tto print formatted version to standard out")
	print("usage:\n\tlua " .. arg[0] .. " --f <lua file> [column hint]")
	print("\t\tto reformat the file in-place")
end

--check tmp/luafmt_errors.txt and delete if exists
local errorFile = "tmp/luafmt_errors.txt"
if fs.exists(errorFile) then
	fs.delete(errorFile)
end

--function to save error to errorFile with a 40-column limit
	local function saveError(error)
		local file = io.open(errorFile, "a")
		
		-- Function to split the error message into chunks of 40 characters
		local function splitError(error, limit)
			local lines = {}
			for i = 1, #error, limit do
				table.insert(lines, error:sub(i, i + limit - 1))
			end
			return lines
		end
	
		local lines = splitError(error, 30)
		for _, line in ipairs(lines) do
			file:write(line .. "\n")
		end
		
		file:write("\n") -- Add an additional newline after the error message
		file:close()
	end
	
--------------------------------------------------------------------------------

local COLUMN_LIMIT = 40
local TAB_COLUMNS = 4

--------------------------------------------------------------------------------

-- RETURNS a string representing a literal 'equivalent' to the object
-- (excluding references and non-serializable objects like functions)
local show
do
	local specialRepresentation = {
		["\a"] = [[\a]],
		["\b"] = [[\b]],
		["\f"] = [[\f]],
		["\n"] = [[\n]],
		["\r"] = [[\r]],
		["\t"] = [[\t]],
		["\v"] = [[\v]],
		["\\"] = [[\\]],
		["\""] = [[\"]],
		["\0"] = [[\0]],
	}
	for i = 0, 31 do
		local c = string.char(i)
		if not specialRepresentation[c] then
			local m = tostring(i)
			specialRepresentation[c] = "\\" .. string.rep("0", 3 - #m) .. m
		end
	end
	for i = 128, 255 do
		specialRepresentation[string.char(i)] = "\\" .. tostring(i)
	end

	-- RETURNS nothing
	-- MODIFIES out by appending strings to it
	local function showAdd(object, indent, out)
		if indent > 10 then
			table.insert(out, "...")
		elseif type(object) == "string" then
			-- Turn into a string literal
			table.insert(out, [["]])
			for character in object:gmatch "." do
				table.insert(out, specialRepresentation[character] or character)
			end
			table.insert(out, [["]])
		elseif type(object) == "table" or type(object) == "userdata" then
			table.insert(out, "{")
			for key, value in pairs(object) do
				table.insert(out, "\n" .. string.rep("\t", indent) .. "\t[")
				showAdd(key, indent + 1, out)
				table.insert(out, "] = ")
				showAdd(value, indent + 1, out)
				table.insert(out, ",")
			end
			table.insert(out, "\n" .. string.rep("\t", indent) .. "}")
		else
			table.insert(out, tostring(object))
		end
	end

	-- RETURNS a nearly-valid Lua expression literal representing the
	-- (acyclic) Lua value
	show = function(value)
		local out = {}
		showAdd(value, 0, out)
		return table.concat(out)
	end
end

--------------------------------------------------------------------------------

local function matcher(pattern, tag)
	if type(tag) ~= "string" then
		saveError("Tag must be a string")
		assert(false, "Tag must be a string")
	end
	return function(text, offset)
		local from, to = text:find("^" .. pattern, offset)
		if from then
			return to, tag
		end
	end
end

local IS_KEYWORD = {
	["if"] = true,
	["then"] = true,
	["elseif"] = true,
	["else"] = true,
	["end"] = true,
	["for"] = true,
	["in"] = true,
	["do"] = true,
	["repeat"] = true,
	["until"] = true,
	["while"] = true,
	["function"] = true,

	-- in line
	["local"] = true,
	["return"] = true,
	["break"] = true,
}

local TOKENS = {
	-- string literals
	function(text, offset)
		local quote = text:sub(offset, offset)
		if quote == "\"" or quote == "'" then
			local back = false
			for i = offset + 1, #text do
				if back then
					back = false
				elseif text:sub(i, i) == "\\" then
					back = true
				elseif text:sub(i, i) == quote then
					return i, "string"
				end
			end
			saveError("Unclosed string literal starting at offset " .. offset)
			error("Unclosed string literal starting at offset " .. offset, 2)
		end
	end,

	-- long string literals
	function(text, offset)
		local from, to = text:find("^%[=*%[", offset)
		if from then
			local size = to - from - 1
			local _, stop = text:find(
				"%]" .. string.rep("=", size) .. "%]",
				offset
			)
			if not stop then
				saveError("Unclosed long string literal starting at offset " .. offset)
				error("Unclosed long string literal starting at offset " .. offset, 2)
			end
			return stop, "string"
		end
	end,

	-- comments
	function(text, offset)
		if text:sub(offset, offset + 1) == "--" then
			local start, startLen = text:find("^%[=*%[", offset + 2)
			if start then
				local size = startLen - start - 1
				local _, stop = text:find(
					"%]" .. string.rep("=", size) .. "%]",
					offset
				)
				if not stop then
					saveError("Unclosed long comment starting at offset " .. offset)
					error("Unclosed long comment starting at offset " .. offset, 2)
				end
				return stop, "comment"
			end
			return (text:find("\n", offset) or #text + 1) - 1, "comment"
		end
	end,

	-- whitespace
	function(text, offset)
		local _, space = text:find("^%s+", offset)
		if space then
			local breaks = 0
			for _ in text:sub(offset, space):gmatch("\n") do
				breaks = breaks + 1
			end
			if breaks > 1 then
				return space, "blank"
			end
			return space, "whitespace"
		end
	end,

	-- number
	function(text, offset)
		local _, limit = text:find("^[0-9.-+eExa-fA-F]+", offset)
		local last
		for i = offset, limit or offset do
			if tonumber(text:sub(offset, i)) then
				last = i
			end
		end
		if last then
			return last, "number"
		end
	end,

	-- dots
	matcher("%.%.%.", "name"),

	-- concat
	matcher("%.%.", "operator"),

	-- identifiers and keywords
	function(text, offset)
		local from, to = text:find("^[a-zA-Z0-9_]+", offset)
		if to then
			local word = text:sub(from, to)
			local size = #word

			if IS_KEYWORD[word] then
				return to, word
			elseif word == "not" or word == "or" or word == "and" then
				return to, "operator"
			end
			return to, "word"
		end
	end,

	-- accessors
	matcher("[:.]", "access"),

	-- entry separator
	matcher("[;,]", "separator"),

	-- opening brace
	matcher("[%[{(]", "open"),

	-- closing brace
	matcher("[%]})]", "close"),

	-- operators
	function(text, offset)
		local operators = {
			"==",
			"<=",
			">=",
			"~=",
			"^",
			"*",
			"/",
			"%",
			"<",
			">",
			"+",
			"-",
			"#",
		}
		for _, op in ipairs(operators) do
			local to = offset + #op - 1
			if text:sub(offset, to) == op then
				return to, "operator"
			end
		end
	end,

	-- assignment
	matcher("=", "assign"),

	-- other
	matcher(".", "other"),
}

-- RETURNS a list of tokens
local function tokenize(blob)
    if type(blob) ~= "string" then
        saveError("Input must be a string")
        assert(false, "Input must be a string")
    end

    local tokens = {}
    local offset = 1
    while offset <= #blob do
        local didCut = false
        for _, t in ipairs(TOKENS) do
            local cut, tag = t(blob, offset)
            if cut then
                if type(cut) ~= "number" then
                    saveError("Tokenizer function returned invalid cut position: " .. tostring(cut))
                    assert(false, "Tokenizer function returned invalid cut position: " .. tostring(cut))
                end
                if cut < offset then
                    saveError("Tokenizer cut position is before the current offset")
                    assert(false, "Tokenizer cut position is before the current offset")
                end
                if not tag then
                    saveError("Tokenizer did not return a valid tag for the token")
                    assert(false, "Tokenizer did not return a valid tag for the token")
                end

                if tag ~= "whitespace" then
                    table.insert(tokens, {
                        tag = tag,
                        text = blob:sub(offset, cut),
                        offset = offset,
                    })
                end

                offset = cut + 1
                didCut = true
                break
            end
        end

        if not didCut then
            -- Identify the location of the error
            local lineNumber = select(2, blob:sub(1, offset):gsub("\n", "\n"))
            local lineStart = blob:sub(1, offset):match("([^\n]*)$")
            local lineEnd = blob:sub(offset):match("^([^\n]*)")

            -- Create a detailed error message
            local errorMessage = string.format(
                "Syntax Error at line %d, offset %d: Could not tokenize near '%s'.\nContext: %s%s",
                lineNumber, offset, blob:sub(offset, offset + 10), lineStart, lineEnd
            )

            -- Save and raise the error
            saveError(errorMessage)
            error(errorMessage, 2)
        end
    end

    return tokens
end


local function catchGap(obj)
	local out = {}
	for k, v in pairs(obj) do
		out[k] = v
	end
	return setmetatable(out, {
		__index = function(_, key)
			if obj[key] == nil then
				saveError("No such key `" .. tostring(key) .. "`")
				error("No such key `" .. tostring(key) .. "`", 2)
			end
			return obj[key]
		end,
	})
end

local function filterBlanks(tokens)
	-- Insert breaks before comments
	-- Remove breaks at the beginning and ends of blocks
	-- Mark () as part of function parameters
	-- Distinguish do as either the beginning of a block or end of a control

	local NO_BLANK_AFTER = {
		["do"] = true,
		["lone-do"] = true,
		["then"] = true,
		["else"] = true,
		["open"] = true,
		["function-close"] = true,
	}

	local out = {}
	local forFunction = false
	local forControl = false
	local wasObject = false
	for _, token in ipairs(tokens) do
		token = catchGap(token)

		if token.tag == "do" then
			-- Distinguish the `do` in `while do` or `for do` from `do end`
			if not forControl then
				table.insert(out, catchGap {
					tag = "lone-do",
					text = token.text,
				})
			else
				table.insert(out, token)
				forControl = false
			end
		elseif token.tag == "for" then
			table.insert(out, token)
			forControl = true
		elseif token.tag == "while" then
			table.insert(out, token)
			forControl = true
		elseif token.tag == "function" then
			forFunction = true
			table.insert(out, token)
		elseif token.tag == "comment" then
			if out[#out] and out[#out].tag == "blank" then
				-- Do nothing
			elseif out[#out] and out[#out].tag == "comment" then
				-- Do nothing
			elseif out[#out] and not NO_BLANK_AFTER[out[#out].tag] then
				table.insert(out, catchGap {
					tag = "blank",
					text = "\n\n",
				})
			end
			table.insert(out, token)
		elseif token.tag == "close" then
			if out[#out] and out[#out].tag == "blank" then
				table.remove(out)
			end

			-- Distinguish () used in function parameter definitions
			if forFunction then
				forFunction = false
				table.insert(out, catchGap {
					tag = "function-close",
					text = token.text,
				})
			else
				table.insert(out, token)
			end
		elseif token.tag == "open" then
			-- Distinguish () used in function parameter definitions
			if forFunction then
				table.insert(out, catchGap {
					tag = "function-open",
					text = token.text,
				})
			else
				table.insert(out, token)
			end
		elseif token.tag == "blank" then
			-- Don't insert blanks after an opening of a block
			if #out > 0 then
				if not NO_BLANK_AFTER[out[#out].tag] then
					table.insert(out, token)
				end
			end
		elseif token.text == "-" and not wasObject then
			table.insert(out, {
				tag = "unm",
				text = token.text,
			})
		else
			-- Remove blanks before a close of a block
			if #out > 0 and out[#out].tag == "blank" then
				-- Clear blanks at closing
				if token.tag == "end" or token.tag == "else" or token.tag == "elseif" or token.tag == "until" then
					table.remove(out)
				end
			end
			table.insert(out, token)
		end

		wasObject = token.tag == "close" or token.tag == "number" or token.tag == "word" or token.tag == "string"
	end

	return out
end

--------------------------------------------------------------------------------

local function groupTokens(tokens)
	-- Rules:
	-- There are mandatory breaks between statements and around comments
	-- There are optional breaks around , and ; in {} and ()
	-- There are optional breaks in a one-statement anonymous function
	-- There are mandatory breaks around `blank` tokens, but blank tokens
	-- are only allowed in some places

	local OPENS = {
		["if"] = "code",
		["while"] = "code",
		["for"] = "code",
		["lone-do"] = "code",
		["function"] = "code",
		["open"] = "group",
	}

	local CLOSES = {
		["end"] = "code",
		["close"] = "group",
	}

	-- Group tokens into groups () {} and statements
	local context = {tag = "code", children = {}}
	local stack = {}
	for _, token in ipairs(tokens) do
		if not token.text then
			saveError("Token text is missing")
			assert(false, "Token text is missing")
		end
		token.headText = token.text
		token.tailText = token.text
		token.tailTag = token.tag
		token.headTag = token.tag
		if not token.headText then
			saveError("Token headText is missing")
			assert(false, "Token headText is missing")
		end
		if OPENS[token.tag] then
			table.insert(stack, context)
			local newContext = {tag = OPENS[token.tag], children = {token}}
			table.insert(context.children, newContext)
			context = newContext
		elseif CLOSES[token.tag] then
			if context.tag ~= CLOSES[token.tag] then
				saveError("Mismatched closing token: " .. tostring(token.text))
				assert(false, "Mismatched closing token: " .. tostring(token.text))
			end
			table.insert(context.children, token)
			context.tailTag = context.children[#context.children].tailTag
			context.tailText = context.children[#context.children].tailText
			context.headTag = context.children[1].headTag
			context.headText = context.children[1].headText
			context = table.remove(stack)
			if not context then
				saveError("Unexpected end of stack")
				assert(false, "Unexpected end of stack")
			end
		else
			table.insert(context.children, token)
		end
	end

	if #stack ~= 0 then
		saveError("Unclosed token groups remaining in stack")
		assert(false, "Unclosed token groups remaining in stack")
	end
	return context
end

local STATEMENT_SEPARATOR = {
	{"*", "return"},
	{"*", "break"},
	{"*", "comment"},
	{"then", "*"},
	{"*", "else"},
	{"else", "*"},
	{"*", "elseif"},
	{"*", "if"},
	{"*", "repeat"},
	{"repeat", "*"},
	{"*", "until"},
	{"*", "while"},
	{"*", "end"},
	{"end", "*"},
	{"do", "*"},
	{"lone-do", "*"},
	{"*", "lone-do"},
	{"*", "for"},
	{"word", "word"},
	{"number", "word"},
	{"string", "word"},
	{"separator", ";"},
	{"*", "comment"},
	{"comment", "*"},
	{"blank", "*"},
	{"*", "blank"},
	{"close", "word"},
	{"*", "local"},
	{"string", "function"},
	{"word", "function"},
	{"number", "function"},
	{"close", "function"},

	-- Only for long functions
	{"function-close", "*"},

	-- Only in statement mode
	{"`;", "*"},
}

local GLUE = {
	{"open", "*"},
	{"function-open", "*"},
	{"*", "close"},
	{"*", "function-close"},
	{"*", "separator"},

	-- TODO: EXCEPT for `{`
	{"word", "open"},
	{"*", "function-open"},

	{"*", "access"},
	{"access", "*"},

	{"`#", "*"},
	{"unm", "number"},
	{"unm", "string"},
	{"unm", "word"},
	{"close", "`["},
	{"close", "`("},
}

local UNGLUE = {
	{"word", "`{"},
}

local function matchLeft(m, t)
	if type(m) ~= "string" then
		saveError("Invalid match left string")
		assert(false, "Invalid match left string")
	end

	if m == "*" then
		return true
	elseif m:sub(1, 1) == "`" then
		return m:sub(2) == t.tailText
	end
	return m == t.tailTag
end

local function matchRight(m, t)
	if type(m) ~= "string" then
		saveError("Invalid match right string")
		assert(false, "Invalid match right string")
	end

	if m == "*" then
		return true
	elseif m:sub(1, 1) == "`" then
		return m:sub(2) == t.headText
	end
	return m == t.headTag
end

local function matchRule(rule, a, b)
	return matchLeft(rule[1], a) and matchRight(rule[2], b)
end

-- RETURNS (multiline) text
local function renderTokens(tree, column, indent)
	if type(column) ~= "number" then
		saveError("Column must be a number")
		assert(false, "Column must be a number")
	end
	if type(indent) ~= "number" then
		saveError("Indent must be a number")
		assert(false, "Indent must be a number")
	end

	local INDENT_AFTER = {
		["then"] = true,
		["else"] = true,
		["function-close"] = true,
		["repeat"] = true,
		["do"] = true,
		["lone-do"] = true,
	}

	local DEDENT_BEFORE = {
		["end"] = true,
		["else"] = true,
		["elseif"] = true,
		["until"] = true,
	}

	-- TODO: Indent after function only necessary when newline
	-- TODO: Ident after () {} only necessary when newline

	local function renderCode(tree, column, indent)
		-- (1) attempt to render without breaks
		local out = ""
		for i, child in ipairs(tree.children) do
			local space = ""
			local previous = tree.children[i - 1]
			if previous then
				space = " "
				for _, rule in ipairs(STATEMENT_SEPARATOR) do
					if matchRule(rule, previous, child) then
						if INDENT_AFTER[previous.tailTag] then
							indent = indent + 1
						end
						if DEDENT_BEFORE[child.headTag] then
							indent = indent - 1
						end

						-- A `space` is always followed by a non-blank, so
						-- indenting here is fine
						space = "\n" .. string.rep("\t", indent)
						break
					end
				end
				if space == " " then
					for _, rule in ipairs(GLUE) do
						if matchRule(rule, previous, child) then
							space = ""
						end
					end
					for _, rule in ipairs(UNGLUE) do
						if matchRule(rule, previous, child) then
							space = " "
						end
					end
				end
			end

			if child.headTag == "blank" then
				-- Don't insert tabs before a blank line
				space = space:gsub("[^\n]", "")
			end

			out = out .. space
			local finalLineLength = 2 * COLUMN_LIMIT
			local finalLine = out:match "[^\n]*$"
			if #finalLine < finalLineLength then
				finalLineLength = #finalLine:gsub(
					"\t",
					string.rep(" ", TAB_COLUMNS)
				)
			end
			out = out .. renderTokens(child, finalLineLength, indent)
		end
		return out
	end

	local function renderObject(tree, column, indent, sepBreak)
		if type(sepBreak) ~= "boolean" then
			saveError("sepBreak must be boolean")
			assert(false, "sepBreak must be boolean")
		end
		if type(indent) ~= "number" then
			saveError("indent must be number")
			assert(false, "indent must be number")
		end

		local out = ""
		for i, child in ipairs(tree.children) do
			local previous = tree.children[i - 1]
			local space = ""
			local BRK = "\n" .. string.rep("\t", indent)
			if previous then
				space = " "
				if sepBreak and i == 2 then
					assert(tree.children[1].tag == "open")
					space = BRK .. "\t"
					indent = indent + 1
				elseif sepBreak and i == #tree.children then
					space = BRK:sub(1, -2)
					indent = indent - 1
				elseif previous.tailTag == "comment" then
					space = BRK
				elseif child.headTag == "comment" then
					space = BRK
				elseif sepBreak and previous.tailTag == "separator" then
					assert(previous.tag == "separator")
					space = BRK
				elseif previous.tag == "blank" then
					space = BRK
				elseif child.tag == "blank" then
					space = "\n"
				end

				if space == " " then
					for _, rule in ipairs(GLUE) do
						if matchRule(rule, previous, child) then
							space = ""
						end
					end
					for _, rule in ipairs(UNGLUE) do
						if matchRule(rule, previous, child) then
							space = " "
						end
					end
				end
			end

			-- Don't insert tabs before a blank
			if child.headTag == "blank" then
				space = space:gsub("[^\n]", "")
			end

			out = out .. space
			local finalLine = out:match "[^\n]*$"
			local finalLineLength = COLUMN_LIMIT * 2
			if #finalLine < finalLineLength then
				finalLineLength = #finalLine:gsub(
					"\t",
					string.rep(" ", TAB_COLUMNS)
				)
			end
			local result = renderTokens(child, finalLineLength, indent)
			out = out .. result
		end
		return out
	end

	if tree.tag == "code" then
		return renderCode(tree, column, indent)
	elseif tree.tag == "group" then
		local c = renderObject(tree, column, indent, false)
		local tooLong = (column + #c > COLUMN_LIMIT or c:find("\n"))
		local notEmpty = #tree.children > 2
		local trailingComma = notEmpty and tree.children[#tree.children - 1].tailTag == "separator"

		if trailingComma then
			return renderObject(tree, column, indent, true)
		elseif tooLong and notEmpty then
			-- Don't break empty (); always break with trailing comma
			-- Must break at local separators

			if tree.headText == "(" then
				-- If only the final entry is too long, then only the final
				-- entry should be broken

				-- Find the last separator
				local lastSeparator = false
				for i = #tree.children, 1, -1 do
					if tree.children[i].tailTag == "separator" then
						lastSeparator = i
						break
					end
				end

				if not lastSeparator then
					-- ({
					--     stuff
					-- })

					-- TODO: but may be too long: (asdofijasdofijasdfoijasodifja)
					return c
				end

				local withoutLast = {
					tag = tree.tag,
					tailTag = tree.tailTag,
					tailText = tree.tailText,
					headTag = tree.headTag,
					headText = tree.headText,
					children = {},
				}
				for i = 1, lastSeparator - 1 do
					table.insert(withoutLast.children, tree.children[i])
				end

				-- If only the last element pushes it too long, then
				-- we don't need to break at separators in this tree
				-- (only in the final subtree)
				local r = renderObject(withoutLast, column, indent, false)
				local rTooLong = (column + #r > COLUMN_LIMIT or r:find("\n"))
				if not rTooLong then
					local firstLine = c:match "^[^\n]*"
					if column + #firstLine <= COLUMN_LIMIT then
						-- The final element may be a word that doesn't fit
						-- in the line
						return c
					end
				end
			end

			return renderObject(tree, column, indent, true)
		end
		return c
	elseif tree.tag == "blank" then
		return ""
	end
	if type(tree.text) ~= "string" then
		saveError("Tree text is missing")
		assert(false, "Tree text is missing")
	end
	return tree.text
end

--------------------------------------------------------------------------------

-- Get command line arguments
local filename = arg[1]
local inplace = filename == "--f"
if not filename then
	printHelp()
end

-- Get column limit hint
COLUMN_LIMIT = (arg[2] and tonumber(arg[2])) or 80

if inplace then
	filename = arg[2]
	COLUMN_LIMIT = (arg[3] and tonumber(arg[3])) or 80
	if not filename then
		printHelp()
	end
end

-- Read input
local file = io.open(filename, "rb")
if not file then
	saveError("Cannot open file `" .. filename .. "`")
	error("Cannot open file `" .. filename .. "`", 2)
end

local tokens = filterBlanks(tokenize(file:read("*all")))
local tree = groupTokens(tokens)
local rendered = (renderTokens(tree, 0, 0))

file:close()

-- Write output
if inplace then
	-- Update the file
	local out = io.open(filename, "wb")
	if not out then
		saveError("Cannot open file `" .. filename .. "` for writing")
		error("Cannot open file `" .. filename .. "` for writing", 2)
	end

	out:write(rendered)
	out:write("\n")
	out:close()
else
	-- Print to standard out
	print(rendered)
end

return true
