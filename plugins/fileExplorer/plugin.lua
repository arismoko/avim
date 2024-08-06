local function init(components)
    local View = components.view
    local BufferHandler = components.bufferHandler
    local InputHandler = components.inputHandler

    local function openFileExplorer()
        -- Get the list of files and directories in the current directory
        local function getFiles()
            local currentDir = shell.dir()
            local files = fs.list(currentDir)
            table.sort(files)
            if currentDir ~= "/" then
                table.insert(files, 1, "..")  -- Add option to go up one directory if not at the root
            end
            return files
        end

        local files = getFiles()

        local fileExplorerWindow = View:createWindow(1, 1, SCREENWIDTH, SCREENHEIGHT - 1, colors.lightGray, colors.black)
        local startIndex = 1
        local selectedIndex = 1
        local itemsPerPage = fileExplorerWindow.height - 4  -- Adjust based on available window height
        local showingControls = false

        local function displayFiles(startIndex, selectedIndex)
            fileExplorerWindow:clear()
            fileExplorerWindow:print("File Explorer:")
            for i = startIndex, math.min(#files, startIndex + itemsPerPage - 1) do
                if i == selectedIndex then
                    fileExplorerWindow:writeline("-> " .. files[i])
                else
                    fileExplorerWindow:writeline("   " .. files[i])
                end
            end
            fileExplorerWindow:print("")  -- Blank line
            fileExplorerWindow:print("[/]: Show Controls")
            fileExplorerWindow:show()
        end

        local function displayControls()
            fileExplorerWindow:clear()
            fileExplorerWindow:print("File Explorer Controls:")
            fileExplorerWindow:print("")
            fileExplorerWindow:print("[c] Create File/Directory")
            fileExplorerWindow:print("[d] Delete File/Directory (Requires 'CONFIRM')")
            fileExplorerWindow:print("[m] Move File/Directory")
            fileExplorerWindow:print("[r] Rename File/Directory")
            fileExplorerWindow:print("[y] Copy File/Directory")
            fileExplorerWindow:print("[p] Paste Copied File/Directory")
            fileExplorerWindow:print("[x] Duplicate File/Directory")
            fileExplorerWindow:print("[Enter] Open File/Directory")
            fileExplorerWindow:print("[q] Quit")
            fileExplorerWindow:print("[/] Return to File Explorer")
            fileExplorerWindow:show()
        end

        local copiedFilePath = nil

        local function refreshFiles()
            files = getFiles()
            startIndex = 1
            selectedIndex = 1
            displayFiles(startIndex, selectedIndex)
        end

        local function duplicateFileOrDirectory(srcPath)
            local destPath = srcPath
            local count = 1
            while fs.exists(destPath) do
                destPath = srcPath .. " (copy" .. (count > 1 and " " .. count or "") .. ")"
                count = count + 1
            end
            fs.copy(srcPath, destPath)
        end

        displayFiles(startIndex, selectedIndex)

        -- Function to capture user input
        local function captureInput(prompt)
            fileExplorerWindow:print(prompt)
            fileExplorerWindow:show()
            local input = ""
            local firstInput = true

            while true do
                local event, key = os.pullEvent()
                if event == "char" then
                    if firstInput then
                        firstInput = false  -- Discard the first character (initial keypress)
                    else
                        input = input .. key
                        fileExplorerWindow:write(key) 
                        fileExplorerWindow:show()
                    end
                elseif event == "key" and (key == keys.enter or key == keys.backspace) then
                    if key == keys.enter then
                        return input
                    elseif key == keys.backspace then
                        -- Cancel the input prompt if backspace is pressed
                        fileExplorerWindow:print("\nInput cancelled.")
                        return nil
                    end
                end
            end
        end

        -- Listen for input to navigate and open files or toggle controls
        while true do
            local event, key = os.pullEvent("key")
            if key == keys.slash then
                if showingControls then
                    showingControls = false
                    displayFiles(startIndex, selectedIndex)
                else
                    showingControls = true
                    displayControls()
                end
            elseif not showingControls then
                if key == keys.down or key == keys.j then
                    if selectedIndex < #files then
                        selectedIndex = selectedIndex + 1
                        if selectedIndex > startIndex + itemsPerPage - 1 then
                            startIndex = startIndex + 1
                        end
                        displayFiles(startIndex, selectedIndex)
                    end
                elseif key == keys.up or key == keys.k then
                    if selectedIndex > 1 then
                        selectedIndex = selectedIndex - 1
                        if selectedIndex < startIndex then
                            startIndex = startIndex - 1
                        end
                        displayFiles(startIndex, selectedIndex)
                    end
                elseif key == keys.enter then
                    local selectedFile = files[selectedIndex]
                    local fullPath = fs.combine(shell.dir(), selectedFile)
                    if selectedFile == ".." then
                        shell.setDir(fs.getDir(shell.dir()))
                        refreshFiles()
                    elseif fs.isDir(fullPath) then
                        shell.setDir(fullPath)
                        refreshFiles()
                    else
                        BufferHandler.filename = fullPath
                        BufferHandler:loadFile(fullPath)
                        fileExplorerWindow:close()
                        return
                    end
                elseif key == keys.q then
                    fileExplorerWindow:close()
                    return
                elseif key == keys.c then
                    -- Create a new file or directory
                    local newName = captureInput("Enter new file/directory name: ")
                    if newName and newName ~= "" then
                        local newPath = fs.combine(shell.dir(), newName)
                        if not fs.exists(newPath) then
                            if string.sub(newName, -1) == "/" then
                                fs.makeDir(newPath)
                            else
                                local file = fs.open(newPath, "w")
                                file.close()
                            end
                            refreshFiles()
                        else
                            fileExplorerWindow:print("File/Directory already exists!")
                        end
                    else
                        fileExplorerWindow:print("Creation cancelled.")
                    end
                elseif key == keys.d then
                    -- Delete the selected file or directory with confirmation
                    local selectedFile = files[selectedIndex]
                    if selectedFile == ".." then
                        fileExplorerWindow:print("Cannot delete the parent directory entry!")
                    else
                        local fullPath = fs.combine(shell.dir(), selectedFile)
                        local confirmation = captureInput("Type 'CONFIRM' to delete '" .. selectedFile .. "' (or press Enter to cancel): ")
                        if confirmation == "CONFIRM" then
                            if fs.exists(fullPath) then
                                fs.delete(fullPath)
                                refreshFiles()
                            else
                                fileExplorerWindow:print("File/Directory does not exist!")
                            end
                        else
                            fileExplorerWindow:print("Deletion cancelled.")
                        end
                    end
                elseif key == keys.m then
                    -- Move the selected file or directory
                    local selectedFile = files[selectedIndex]
                    if selectedFile == ".." then
                        fileExplorerWindow:print("Cannot move the parent directory entry!")
                    else
                        local fullPath = fs.combine(shell.dir(), selectedFile)
                        local destDir = captureInput("Enter destination directory (or press Enter to cancel): ")
                        if destDir and destDir ~= "" then
                            local destPath = fs.combine(shell.dir(), destDir, selectedFile)
                            if fs.exists(fullPath) and fs.isDir(fs.combine(shell.dir(), destDir)) then
                                fs.move(fullPath, destPath)
                                refreshFiles()
                            else
                                fileExplorerWindow:print("Invalid move operation!")
                            end
                        else
                            fileExplorerWindow:print("Move cancelled.")
                        end
                    end
                elseif key == keys.r then
                    -- Rename the selected file or directory
                    local selectedFile = files[selectedIndex]
                    if selectedFile == ".." then
                        fileExplorerWindow:print("Cannot rename the parent directory entry!")
                    else
                        local fullPath = fs.combine(shell.dir(), selectedFile)
                        local newName = captureInput("Enter new name for '" .. selectedFile .. "' (or press Enter to cancel): ")
                        if newName and newName ~= "" then
                            local newPath = fs.combine(shell.dir(), newName)
                            if not fs.exists(newPath) then
                                fs.move(fullPath, newPath)
                                refreshFiles()
                            else
                                fileExplorerWindow:print("A file or directory with that name already exists!")
                            end
                        else
                            fileExplorerWindow:print("Rename cancelled.")
                        end
                    end
                elseif key == keys.y then
                    -- Copy the selected file or directory
                    local selectedFile = files[selectedIndex]
                    if selectedFile == ".." then
                        fileExplorerWindow:print("Cannot copy the parent directory entry!")
                    else
                        copiedFilePath = fs.combine(shell.dir(), selectedFile)
                        fileExplorerWindow:print("File/Directory copied!")
                    end
                elseif key == keys.p then
                    -- Paste the copied file or directory to the current directory
                    if copiedFilePath then
                        local filename = fs.getName(copiedFilePath)
                        local destPath = fs.combine(shell.dir(), filename)
                        fs.copy(copiedFilePath, destPath)
                        refreshFiles()
                    else
                        fileExplorerWindow:print("No file/directory copied!")
                    end
                elseif key == keys.x then
                    -- Duplicate the selected file or directory
                    local selectedFile = files[selectedIndex]
                    if selectedFile == ".." then
                        fileExplorerWindow:print("Cannot duplicate the parent directory entry!")
                    else
                        local fullPath = fs.combine(shell.dir(), selectedFile)
                        duplicateFileOrDirectory(fullPath)
                        refreshFiles()
                    end
                end
            end
        end
    end

    -- Register a keybinding to open the file explorer
    InputHandler:map({"normal"}, {"backslash"}, "open_file_explorer", function()
        openFileExplorer()
    end, "Open File Explorer")
end

return {
    init = init
}
