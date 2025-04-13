local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Teams = game:GetService("Teams")

-- File paths for logging and server data
local LOG_FILE = "police_money_log.txt"
local SERVER_DATA_FILE = "server_data.txt"

-- Custom logging function to append to file
local function logToFile(message)
    pcall(function()
        appendfile(LOG_FILE, os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(message) .. "\n")
    end)
end

-- Define the script to queue as a string
local scriptToRun = [[
    -- Wait until the game is fully loaded
    game.Loaded:Wait()
    
    -- Once the game is loaded, run the external script
    wait(2)
    loadstring(game:HttpGet("https://raw.githubusercontent.com/mrricky22/testdijskfb/refs/heads/main/new.lua"))()
]]

-- Function to calculate total money for Police team
local function getPoliceTeamMoney()
    local totalMoney = 0
    local policeTeam = Teams:FindFirstChild("Police") -- Assumes Jailbreak has a team named "Police"

    if not policeTeam then
        logToFile("Police team not found!")
        return 0
    end

    -- Loop through all players
    for _, player in pairs(Players:GetPlayers()) do
        if player.Team == policeTeam then
            -- Check for leaderstat named "Money"
            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local cash = leaderstats:FindFirstChild("Money")
                if cash and cash:IsA("IntValue") then
                    totalMoney = totalMoney + cash.Value
                end
            end
        end
    end

    return totalMoney
end

-- Function to save server data to file
local function saveServerData(servers, currentIndex)
    pcall(function()
        local dataToSave = {
            servers = servers,
            currentIndex = currentIndex,
            timestamp = os.time()
        }
        writefile(SERVER_DATA_FILE, HttpService:JSONEncode(dataToSave))
        logToFile("Saved server data with " .. #servers .. " servers, current index: " .. currentIndex)
    end)
end

-- Function to load server data from file
local function loadServerData()
    local success, data = pcall(function()
        if isfile(SERVER_DATA_FILE) then
            local content = readfile(SERVER_DATA_FILE)
            return HttpService:JSONDecode(content)
        end
        return nil
    end)
    
    if success and data then
        logToFile("Loaded server data with " .. #data.servers .. " servers, current index: " .. data.currentIndex)
        return data
    end
    return nil
end

-- Function to fetch a new list of servers
local function fetchServerList(placeId)
    logToFile("Fetching a new list of servers...")
    
    local success, servers = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
        local response = game:HttpGet(url)
        local data = HttpService:JSONDecode(response)
        return data.data
    end)
    
    if not success or not servers or #servers == 0 then
        logToFile("Failed to fetch servers: " .. tostring(servers))
        return nil
    end
    
    logToFile("Successfully fetched " .. #servers .. " servers")
    return servers
end

-- Function to attempt teleporting to a server with error handling
local function attemptTeleport(placeId, serverId)
    local teleportSuccess, teleportError = pcall(function()
        queue_on_teleport(scriptToRun)
        TeleportService:TeleportToPlaceInstance(placeId, serverId, Players.LocalPlayer)
    end)
    
    if not teleportSuccess then
        logToFile("Teleport failed: " .. tostring(teleportError))
        return false
    end
    
    return true
end

-- Function to join the next server from the list with better error handling
local function joinNextServer(placeId, serverData)
    wait(3)
    local currentJobId = game.JobId
    local servers = serverData.servers
    local currentIndex = serverData.currentIndex
    
    -- Track servers we've tried to join
    local triedServers = {}
    
    -- Check if we need to refresh the server list
    if currentIndex > #servers then
        logToFile("Reached the end of the server list. Fetching new servers...")
        local newServers = fetchServerList(placeId)
        if not newServers or #newServers == 0 then
            logToFile("Failed to get new servers. Using default teleport.")
            pcall(function() 
                queue_on_teleport(scriptToRun)
                TeleportService:Teleport(placeId, Players.LocalPlayer)
            end)
            return
        end
        
        servers = newServers
        currentIndex = 1
        saveServerData(servers, currentIndex)
    end
    
    -- Try to join servers until we succeed or exhaust the list
    local maxAttempts = #servers
    local attempts = 0
    
    while attempts < maxAttempts do
        -- Get the next server to try
        local server = servers[currentIndex]
        
        -- Update the index for next attempt
        local nextIndex = currentIndex + 1
        if nextIndex > #servers then nextIndex = 1 end
        
        -- Validate the server
        if server and server.id ~= currentJobId and server.playing < server.maxPlayers and server.playing < 27 and not triedServers[server.id] then
            logToFile("Attempting to join server with JobId: " .. server.id .. " (Players: " .. server.playing .. "/" .. server.maxPlayers .. ")")
            
            -- Mark this server as tried
            triedServers[server.id] = true
            
            -- Try to teleport
            local success = attemptTeleport(placeId, server.id)
            
            if success then
                -- Save the next index in case teleport still fails after success
                saveServerData(servers, nextIndex)
                wait(5) -- Give time for teleport to happen
                
                -- If we're still here, teleport might have silently failed
                logToFile("Teleport didn't complete after 5 seconds, trying next server")
            end
        end
        
        -- Move to the next server
        currentIndex = nextIndex
        attempts = attempts + 1
        
        -- Small wait between attempts
        wait(1)
    end
    
    -- If we get here, we've exhausted our options
    logToFile("Failed to join any server after " .. attempts .. " attempts. Using default teleport.")
    pcall(function() 
        queue_on_teleport(scriptToRun)
        TeleportService:Teleport(placeId, Players.LocalPlayer)
    end)
end

-- Event handler for teleport failures
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == Players.LocalPlayer then
        logToFile("Teleport failed: " .. teleportResult.Name .. " - " .. tostring(errorMessage))
        
        -- Load the latest server data
        local serverData = loadServerData()
        if not serverData then
            local placeId = game.PlaceId
            local servers = fetchServerList(placeId)
            if not servers then
                logToFile("Failed to fetch servers after teleport error. Using default teleport.")
                queue_on_teleport(scriptToRun)
                TeleportService:Teleport(placeId, Players.LocalPlayer)
                return
            end
            serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
        else
            -- Increment the index to try the next server
            serverData.currentIndex = serverData.currentIndex + 1
            if serverData.currentIndex > #serverData.servers then
                serverData.currentIndex = 1
            end
        end
        
        -- Save updated index and try again
        saveServerData(serverData.servers, serverData.currentIndex)
        wait(2) -- Brief delay before trying again
        joinNextServer(game.PlaceId, serverData)
    end
end)

-- Main function to check Police team money and hop servers
local function main()
    local success, errorMsg = pcall(function()
        local placeId = game.PlaceId
        
        -- Check total Police team money
        local policeMoneySuccess, policeMoneyResult = pcall(function()
            logToFile("Checking total Police team money...")
            local totalMoney = getPoliceTeamMoney()
            logToFile("Total Police team money: $" .. totalMoney)
            return totalMoney
        end)
        
        if not policeMoneySuccess then
            logToFile("Error checking Police team money: " .. tostring(policeMoneyResult))
            
            -- Get or initialize server data
            local serverData = loadServerData()
            if not serverData then
                local servers = fetchServerList(placeId)
                if not servers then
                    logToFile("Failed to fetch initial servers. Using default teleport.")
                    queue_on_teleport(scriptToRun)
                    TeleportService:Teleport(placeId, Players.LocalPlayer)
                    return
                end
                serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
                saveServerData(servers, 1)
            end
            
            joinNextServer(placeId, serverData)
            return
        end
        
        local totalPoliceMoney = policeMoneyResult
        
        -- Check if total money is under 200,000
        if totalPoliceMoney < 100000 then
            logToFile("Total Police money ($" .. totalPoliceMoney .. ") is under $100000. Staying in server.")
            -- Stay in the server, don't hop
            return
        end
        
        -- Get or initialize server data if we need to hop
        local serverData = loadServerData()
        if not serverData then
            local servers = fetchServerList(placeId)
            if not servers then
                logToFile("Failed to fetch initial servers. Using default teleport.")
                queue_on_teleport(scriptToRun)
                TeleportService:Teleport(placeId, Players.LocalPlayer)
                return
            end
            serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
            saveServerData(servers, 1)
        end
        
        -- Hop to the next server since total money is $200,000 or more
        logToFile("Total Police money ($" .. totalPoliceMoney .. ") is $100000 or more. Hopping to the next server...")
        joinNextServer(placeId, serverData)
    end)
    
    if not success then
        logToFile("Main function error: " .. tostring(errorMsg))
        pcall(function()
            local placeId = game.PlaceId
            
            -- Get or initialize server data
            local serverData = loadServerData()
            if not serverData then
                local servers = fetchServerList(placeId)
                if not servers then
                    logToFile("Failed to fetch initial servers after error. Using default teleport.")
                    queue_on_teleport(scriptToRun)
                    TeleportService:Teleport(placeId, Players.LocalPlayer)
                    return
                end
                serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
                saveServerData(servers, 1)
            end
            
            joinNextServer(placeId, serverData)
        end)
    end
end

-- Wrap the entire execution in pcall
pcall(function()
    -- Start the script with error handling
    main()
end)

-- Fallback in case the entire script fails
pcall(function()
    logToFile("Script execution completed or failed. Ensuring queue_on_teleport is set.")
end)
