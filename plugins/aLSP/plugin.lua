local function init(components)
    local bufferHandler = components.bufferHandler
    local KeyHandler = components.KeyHandler
    local viewInstance = components.View

    -- Save the current working directory
    local originalDir = shell.dir()

    -- Get the directory of the currently running script
    local scriptPath = fs.getDir(shell.getRunningProgram())
    shell.setDir(scriptPath)

    -- Resolve paths based on the script's directory
    local errorFile = fs.combine(scriptPath, "tmp/luafmt_errors.txt")
    local formatterScript = fs.combine(scriptPath, "plugins/aLSP/luafmt.lua")

    -- Function to check if the error file exists and return its content
    local function getErrorContent()
        if fs.exists(errorFile) then
            local file = io.open(errorFile, "r")
            local content = file:read("*all")
            file:close()
            if content and #content > 0 then
                return content
            end
        end
        return nil
    end

    local function formatBuffer()
        bufferHandler:saveFile()
        local file = bufferHandler.filename
        -- Copy the file to tmp/ to avoid overwriting the original file
        local tempFile = fs.combine(scriptPath, "tmp/" .. fs.getName(file))
        
        -- Remove any previous error file
        if fs.exists(errorFile) then
            fs.delete(errorFile)
        end
        
        -- Copy the file to the temporary location
        if fs.exists(tempFile) then
            fs.delete(tempFile)
        end
        fs.copy(file, tempFile)
        if not fs.exists(tempFile) then
            bufferHandler:updateStatusBar("Error: Failed to copy buffer to temporary location")
            return
        end

        -- Construct the command to run the formatter
        local command = " --f " .. tempFile .. " 40"

        -- Use xpcall to run the formatter script and handle errors
        local status, result = pcall(function()
            return shell.run(formatterScript, command)
        end)

        if not status then
            viewInstance:showPopup("An error occurred while running the formatter: " .. result)
            return
        end

        -- Check if the error file has any content
        local errorContent = getErrorContent()
        if errorContent then
            viewInstance:showPopup("Formatting failed:\n" .. errorContent)
            return
        end

        if type(result) == "table" then
            -- If result is a table, it's an error list
            for _, error in ipairs(result) do
                viewInstance:showPopup(error)
            end
        elseif result == true then
            -- If result is true, formatting was successful
            -- Copy the formatted file back to the original location and back up the original file
            if fs.exists(file .. ".bak") then
                fs.delete(file .. ".bak")
            end
            fs.copy(file, file .. ".bak")
            fs.delete(file)
            fs.copy(tempFile, file)
            bufferHandler:loadFile(file)
            -- Update the status bar to indicate success
            bufferHandler:updateStatusBar("Buffer formatted successfully!")
        else
            -- Handle any other unexpected cases
            viewInstance:showPopup("Unexpected result from formatter.")
        end

        -- Clean up the temporary file regardless of success or failure
        fs.delete(tempFile)
    end

    -- Restore the original working directory
    shell.setDir(originalDir)

    -- Map the formatting function to a keybinding
    KeyHandler:map("n", "leader + f", function()
        formatBuffer()
    end, "Format Lua Buffer")
end

return {
    init = init
}
