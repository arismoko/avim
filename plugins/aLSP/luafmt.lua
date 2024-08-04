local LuaFmt = {}
LuaFmt.__index = LuaFmt

-- Constructor
function LuaFmt:new(columnLimit)
    local self = setmetatable({}, LuaFmt)
    self.COLUMN_LIMIT = columnLimit or 80
    self.TAB_COLUMNS = 4
    self:initSpecialRepresentation()
    self:initTokens()
    return self
end

-- Initialize special character representations
function LuaFmt:initSpecialRepresentation()
    self.specialRepresentation = self:generateSpecialRepresentation()
end

function LuaFmt:generateSpecialRepresentation()
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
            specialRepresentation[c] = "\\" .. string.format("%03d", i)
        end
    end

    for i = 128, 255 do
        specialRepresentation[string.char(i)] = "\\" .. tostring(i)
    end

    return specialRepresentation
end

-- Create a matcher function
function LuaFmt:matcher(pattern, tag)
    return function(text, offset)
        local from, to = text:find("^" .. pattern, offset)
        if from then return to, tag end
    end
end

-- Initialize token patterns
function LuaFmt:initTokens()
    self.TOKENS = self:generateTokens()
end

function LuaFmt:generateTokens()
    local IS_KEYWORD = {
        ["if"] = true, ["then"] = true, ["elseif"] = true, ["else"] = true, ["end"] = true,
        ["for"] = true, ["in"] = true, ["do"] = true, ["repeat"] = true, ["until"] = true,
        ["while"] = true, ["function"] = true, ["local"] = true, ["return"] = true, ["break"] = true,
    }

    return {
        -- Strings
        function(text, offset)
            local quote = text:sub(offset, offset)
            if quote == "\"" or quote == "'" then
                return self:findStringEnd(text, offset, quote), "string"
            end
        end,
        -- Long strings
        function(text, offset)
            return self:findLongStringEnd(text, offset), "string"
        end,
        -- Comments
        function(text, offset)
            if text:sub(offset, offset + 1) == "--" then
                return self:findCommentEnd(text, offset), "comment"
            end
        end,
        -- Whitespace
        function(text, offset)
            return self:findWhitespace(text, offset)
        end,
        -- Numbers
        function(text, offset)
            return self:findNumber(text, offset)
        end,
        -- Keywords and identifiers
        function(text, offset)
            return self:findKeywordOrIdentifier(text, offset, IS_KEYWORD)
        end,
        -- Operators and other symbols
        self:matcher("[:.]", "access"),
        self:matcher("[;,]", "separator"),
        self:matcher("[%[{(]", "open"),
        self:matcher("[%]})]", "close"),
        self:matcher("==", "operator"),
        self:matcher("<=", "operator"),
        self:matcher(">=", "operator"),
        self:matcher("~=", "operator"),
        self:matcher("^", "operator"),
        self:matcher("[*%/%-%+%%#]", "operator"),
        self:matcher("=", "assign"),
        self:matcher(".", "other"),
    }
end

function LuaFmt:findStringEnd(text, offset, quote)
    local back = false
    for i = offset + 1, #text do
        if back then
            back = false
        elseif text:sub(i, i) == "\\" then
            back = true
        elseif text:sub(i, i) == quote then
            return i
        end
    end
end

function LuaFmt:findLongStringEnd(text, offset)
    local from, to = text:find("^%[=*%[", offset)
    if from then
        local size = to - from - 1
        local _, stop = text:find("%]" .. string.rep("=", size) .. "%]", offset)
        return stop
    end
end

function LuaFmt:findCommentEnd(text, offset)
    local start, startLen = text:find("^%[=*%[", offset + 2)
    if start then
        local size = startLen - start - 1
        local _, stop = text:find("%]" .. string.rep("=", size) .. "%]", offset)
        return stop
    end
    return (text:find("\n", offset) or #text + 1) - 1
end

function LuaFmt:findWhitespace(text, offset)
    local _, space = text:find("^%s+", offset)
    if space then
        local breaks = 0
        for _ in text:sub(offset, space):gmatch("\n") do
            breaks = breaks + 1
        end
        if breaks > 1 then return space, "blank" end
        return space, "whitespace"
    end
end

function LuaFmt:findNumber(text, offset)
    local _, limit = text:find("^[0-9.-+eExa-fA-F]+", offset)
    if limit then
        for i = offset, limit do
            if tonumber(text:sub(offset, i)) then
                return i, "number"
            end
        end
    end
end

function LuaFmt:findKeywordOrIdentifier(text, offset, IS_KEYWORD)
    local from, to = text:find("^[a-zA-Z_][a-zA-Z0-9_]*", offset)
    if to then
        local word = text:sub(from, to)
        if IS_KEYWORD[word] then
            return to, word
        elseif word == "not" or word == "or" or word == "and" then
            return to, "operator"
        else
            return to, "word"
        end
    end
end

-- Tokenization process
function LuaFmt:tokenize(buffer)
    assert(type(buffer) == "table", "Expected buffer to be a table")
    local tokens = {}
    for lineNumber, line in ipairs(buffer) do
        self:tokenizeLine(line, lineNumber, tokens)
    end
    return tokens
end

function LuaFmt:tokenizeLine(line, lineNumber, tokens)
    local offset = 1
    while offset <= #line do
        local didCut = false
        for _, t in ipairs(self.TOKENS) do
            local cut, tag = t(line, offset)
            if cut then
                if tag ~= "whitespace" then
                    table.insert(tokens, {
                        tag = tag,
                        text = line:sub(offset, cut),
                        offset = offset,
                        line = lineNumber,
                    })
                end
                offset = cut + 1
                didCut = true
                break
            end
        end
        if not didCut then
            error("Failed to tokenize at: " .. line:sub(offset, offset + 50))
        end
    end
end

-- Filter out unnecessary tokens (e.g., blanks)
function LuaFmt:filterBlanks(tokens)
    local NO_BLANK_AFTER = {
        ["do"] = true, ["lone-do"] = true, ["then"] = true, ["else"] = true,
        ["open"] = true, ["function-close"] = true,
    }

    local filtered = {}
    local forControl, forFunction, wasObject = false, false, false

    for _, token in ipairs(tokens) do
        filtered = self:processToken(token, filtered, NO_BLANK_AFTER, forControl, forFunction, wasObject)
    end

    return filtered
end

function LuaFmt:processToken(token, filtered, NO_BLANK_AFTER, forControl, forFunction, wasObject)
    if token.tag == "do" then
        return self:handleDoToken(token, filtered, forControl)
    elseif token.tag == "for" or token.tag == "while" then
        forControl = true
    elseif token.tag == "function" then
        forFunction = true
    elseif token.tag == "comment" then
        return self:handleCommentToken(token, filtered, NO_BLANK_AFTER)
    elseif token.tag == "close" then
        return self:handleCloseToken(token, filtered, forFunction)
    elseif token.tag == "open" then
        return self:handleOpenToken(token, filtered, forFunction)
    elseif token.tag == "blank" then
        if not self:shouldInsertBlank(filtered, NO_BLANK_AFTER) then
            return filtered
        end
    elseif token.text == "-" and not wasObject then
        token.tag = "unm"
    end

    wasObject = token.tag == "close" or token.tag == "number" or token.tag == "word" or token.tag == "string"
    table.insert(filtered, token)
    return filtered
end

function LuaFmt:handleDoToken(token, filtered, forControl)
    if not forControl then
        table.insert(filtered, { tag = "lone-do", text = token.text })
    else
        table.insert(filtered, token)
        forControl = false
    end
    return filtered
end

function LuaFmt:handleCommentToken(token, filtered, NO_BLANK_AFTER)
    if #filtered > 0 then
        if filtered[#filtered].tag == "blank" or filtered[#filtered].tag == "comment" then
            return filtered
        elseif not NO_BLANK_AFTER[filtered[#filtered].tag] then
            table.insert(filtered, { tag = "blank", text = "\n\n" })
        end
    end
    table.insert(filtered, token)
    return filtered
end

function LuaFmt:handleCloseToken(token, filtered, forFunction)
    if #filtered > 0 and filtered[#filtered].tag == "blank" then
        table.remove(filtered)
    end
    if forFunction then
        forFunction = false
        token.tag = "function-close"
    end
    table.insert(filtered, token)
    return filtered
end

function LuaFmt:handleOpenToken(token, filtered, forFunction)
    if forFunction then
        token.tag = "function-open"
    end
    table.insert(filtered, token)
    return filtered
end

function LuaFmt:shouldInsertBlank(filtered, NO_BLANK_AFTER)
    return #filtered > 0 and not NO_BLANK_AFTER[filtered[#filtered].tag]
end

-- Group tokens into a syntax tree
function LuaFmt:groupTokens(tokens)
    local OPENS = {
        ["if"] = "code", ["while"] = "code", ["for"] = "code", ["lone-do"] = "code",
        ["function"] = "code", ["open"] = "group",
    }

    local CLOSES = {
        ["end"] = "code", ["close"] = "group",
    }

    local context = { tag = "code", children = {} }
    local stack = {}

    for _, token in ipairs(tokens) do
        context = self:groupToken(token, context, stack, OPENS, CLOSES)
    end

    if #stack > 0 then
        error("Unclosed contexts in stack at the end of grouping")
    end

    return context
end

function LuaFmt:groupToken(token, context, stack, OPENS, CLOSES)
    token.headText, token.tailText = token.text, token.text
    token.headTag, token.tailTag = token.tag, token.tag

    if OPENS[token.tag] then
        table.insert(stack, context)
        local newContext = { tag = OPENS[token.tag], children = { token } }
        table.insert(context.children, newContext)
        context = newContext
    elseif CLOSES[token.tag] then
        if context.tag ~= CLOSES[token.tag] then
            error(string.format("Mismatched close token '%s' on line %d, expected context '%s'", 
                token.text, token.line, context.tag))
        end
        table.insert(context.children, token)
        context.tailTag, context.tailText = context.children[#context.children].tailTag, context.children[#context.children].tailText
        context.headTag, context.headText = context.children[1].headTag, context.children[1].headText
        context = table.remove(stack)
    else
        table.insert(context.children, token)
    end

    return context
end

-- Match rules for rendering
function LuaFmt:matchRule(rule, a, b)
    return self:matchLeft(rule[1], a) and self:matchRight(rule[2], b)
end

function LuaFmt:matchLeft(m, t)
    if m == "*" then
        return true
    elseif m:sub(1, 1) == "`" then
        return m:sub(2) == t.tailText
    end
    return m == t.tailTag
end

function LuaFmt:matchRight(m, t)
    if m == "*" then
        return true
    elseif m:sub(1, 1) == "`" then
        return m:sub(2) == t.headText
    end
    return m == t.headTag
end

-- Render tokens into formatted code
function LuaFmt:renderTokens(tree, column, indent, buffer)
    if tree.tag == "group" then
        return self:renderGroup(tree, column, indent, buffer)
    end

    return self:renderCode(tree, column, indent, buffer)
end

function LuaFmt:renderGroup(tree, column, indent, buffer)
    local content = self:renderObject(tree, column, indent, false)
    local tooLong = (column + #content > self.COLUMN_LIMIT or content:find("\n"))
    local notEmpty = #tree.children > 2
    local trailingComma = notEmpty and tree.children[#tree.children - 1].tailTag == "separator"

    if trailingComma or (tooLong and notEmpty) then
        return self:renderObject(tree, column, indent, true)
    end

    return content
end

function LuaFmt:renderCode(tree, column, indent, buffer)
	print("tree.children: ", tree.children)
	if tree.children == nil then
		return buffer
	end
    for i, child in ipairs(tree.children) do
		print("Child: ", child.tag)
        local space = self:determineSpace(tree, i, indent)
        buffer = self:appendToBuffer(buffer, space)
        buffer = self:renderTokens(child, column + #space, indent, buffer)
    end
    return buffer
end

function LuaFmt:determineSpace(tree, index, indent)
    local previous = tree.children[index - 1]
    local child = tree.children[index]
    local space = previous and " " or ""

    if previous then
        space = self:adjustSpaceForRules(previous, child, indent, space)
    end

    if child.headTag == "blank" then
        space = space:gsub("[^\n]", "")
    end

    return space
end

function LuaFmt:adjustSpaceForRules(previous, child, indent, space)
    for _, rule in ipairs(self.STATEMENT_SEPARATOR) do
        if self:matchRule(rule, previous, child) then
            if self.INDENT_AFTER[previous.tailTag] then
                indent = indent + 1
            end
            if self.DEDENT_BEFORE[child.headTag] then
                indent = indent - 1
            end
            return "\n" .. string.rep("\t", indent)
        end
    end

    if space == " " then
        for _, rule in ipairs(self.GLUE) do
            if self:matchRule(rule, previous, child) then
                space = ""
            end
        end
        for _, rule in ipairs(self.UNGLUE) do
            if self:matchRule(rule, previous, child) then
                space = " "
            end
        end
    end

    return space
end

function LuaFmt:appendToBuffer(buffer, space)
    if #buffer == 0 or space:find("\n") then
        table.insert(buffer, space:match("[^\n]*"))
    else
        buffer[#buffer] = buffer[#buffer] .. space
    end
    return buffer
end

-- Render grouped objects
function LuaFmt:renderObject(tree, column, indent, sepBreak)
    local buffer = {}
    for i, child in ipairs(tree.children) do
        local space = self:determineObjectSpace(tree, i, indent, sepBreak)
        buffer = self:appendToBuffer(buffer, space)
        buffer = self:renderTokens(child, column + #space, indent, buffer)
    end
    return buffer
end

function LuaFmt:determineObjectSpace(tree, index, indent, sepBreak)
    local previous = tree.children[index - 1]
    local child = tree.children[index]
    local BRK = "\n" .. string.rep("\t", indent)
    local space = " "

    if sepBreak then
        space = self:adjustObjectSpaceForBreak(tree, index, indent, space, BRK)
    elseif previous then
        space = self:adjustObjectSpaceForPrevious(previous, child, space, BRK)
    end

    return space
end

function LuaFmt:adjustObjectSpaceForBreak(tree, index, indent, space, BRK)
    if index == 2 then
        space = BRK .. "\t"
        indent = indent + 1
    elseif index == #tree.children then
        space = BRK:sub(1, -2)
        indent = indent - 1
    end
    return space
end

function LuaFmt:adjustObjectSpaceForPrevious(previous, child, space, BRK)
    if previous.tailTag == "comment" or child.headTag == "comment" then
        return BRK
    elseif previous.tag == "blank" then
        return BRK
    elseif child.tag == "blank" then
        return "\n"
    end

    if space == " " then
        for _, rule in ipairs(self.GLUE) do
            if self:matchRule(rule, previous, child) then
                space = ""
            end
        end
        for _, rule in ipairs(self.UNGLUE) do
            if self:matchRule(rule, previous, child) then
                space = " "
            end
        end
    end

    return space
end

-- Format a buffer of Lua code
function LuaFmt:formatBuffer(buffer)
    assert(type(buffer) == "table", "Expected buffer to be a table")
    if #buffer == 0 then return {} end

    for i, line in ipairs(buffer) do
        assert(type(line) == "string", string.format("Invalid line at index %d: Expected a string, got %s", i, type(line)))
    end

    local tokens = self:filterBlanks(self:tokenize(buffer))
    local tree = self:groupTokens(tokens)
	print(tree)
	for i, v in ipairs(tree.children) do
		print(i, v.tag)
	end
	if #tree.children == 0 then
	    print("Tree children is empty")
	end
	print("Tree.children before assertion: " , tree.children )
    local formattedBuffer = self:renderTokens(tree, 2, 2, {})

    return formattedBuffer
end

return LuaFmt
