local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")

repeat task.wait(0.5) until game:IsLoaded()
repeat task.wait(0.5) until Players.LocalPlayer

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    API_URL = "https://backend-o675.onrender.com",
    SECRET_KEY = "b9f7e2a1d4c8f3e6a9b2d5c8e1f4a7b0c3d6e9f2a5b8c1d4e7f0a3b6c9d2e5f8",
    ENCRYPTION_KEY = "rO5C282n71X8SuE0hFNRtfqSjHEQZac4bhcyc98FCOJzzPBfP7oVezwy7ytKpUSPHFYnTBct81dR8SOf4KtwQt8AfNY0SJtFWHMY",
    MIN_GEN_VALUE = 1000000,
    SCAN_DELAY = 1,
}

local b64lookup = {}
for i = 1, 64 do b64lookup[string.byte('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', i)] = i - 1 end

local function fastBase64Decode(e)
    local l, r, ri = #e, table.create(math.floor(#e * 0.75)), 1
    for i = 1, l, 4 do
        local b1, b2, b3, b4 = string.byte(e, i, i + 3)
        local a, b, c, d = b64lookup[b1] or 0, b64lookup[b2] or 0, b64lookup[b3] or 0, b64lookup[b4] or 0
        local n = a * 262144 + b * 4096 + c * 64 + d
        r[ri] = bit32.rshift(n, 16) ri = ri + 1
        if b3 ~= 61 then r[ri] = bit32.band(bit32.rshift(n, 8), 0xFF) ri = ri + 1 end
        if b4 ~= 61 then r[ri] = bit32.band(n, 0xFF) ri = ri + 1 end
    end
    return string.char(table.unpack(r, 1, ri - 1))
end

local function fastDecrypt(e, k)
    local b, kl, dl = fastBase64Decode(e), #k, #fastBase64Decode(e)
    local r, kb = table.create(dl), table.create(kl)
    for i = 1, kl do kb[i] = string.byte(k, i) end
    for i = 1, dl do r[i] = bit32.bxor(string.byte(b, i), kb[((i - 1) % kl) + 1]) end
    return string.char(table.unpack(r))
end

local function cleanRichText(text)
    if not text or text == "" then return "" end
    
    text = string.gsub(text, "<[^>]+>", "")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    
    return text
end

local function parseGenValue(genText)
    if not genText or genText == "" then return 0 end
    
    local cleaned = string.gsub(genText, "%$", "")
    cleaned = string.gsub(cleaned, "/s", "")
    cleaned = string.gsub(cleaned, "%s+", "")
    
    local num = string.match(cleaned, "([%d%.]+)")
    local suffix = string.match(cleaned, "([kmbtKMBT])$")
    
    if not num then return 0 end
    
    local value = tonumber(num) or 0
    
    if suffix then
        suffix = string.lower(suffix)
        if suffix == "k" then value = value * 1e3
        elseif suffix == "m" then value = value * 1e6
        elseif suffix == "b" then value = value * 1e9
        elseif suffix == "t" then value = value * 1e12
        end
    end
    
    return math.floor(value)
end

local function formatNum(n)
    if n >= 1e12 then return string.format("$%.2fT/s", n/1e12)
    elseif n >= 1e9 then return string.format("$%.2fB/s", n/1e9)
    elseif n >= 1e6 then return string.format("$%.2fM/s", n/1e6)
    elseif n >= 1e3 then return string.format("$%.2fK/s", n/1e3)
    else return "$"..math.floor(n).."/s" end
end

local function generateSignature()
    local t, d = os.time() * 1000, CONFIG.SECRET_KEY .. os.time() * 1000
    local h = 0
    for i = 1, #d do h = (h * 31 + string.byte(d, i)) % 2147483647 end
    return "RBX_" .. string.format("%08x", h), t
end

local HttpClient = {}
HttpClient.__index = HttpClient
function HttpClient.new()
    local self = setmetatable({}, HttpClient)
    self.request = syn and syn.request or http_request or (http and http.request) or (fluxus and fluxus.request) or request
    return self
end

function HttpClient:makeRequest(url, method, body)
    local headers = {["Content-Type"] = "application/json"}
    if method == "POST" and body then
        local sig, ts = generateSignature()
        headers["X-Roblox-Signature"] = sig
        headers["X-Timestamp"] = tostring(ts)
    end
    local success, response = pcall(self.request, {Url = url, Method = method or "GET", Headers = headers, Body = body and HttpService:JSONEncode(body) or nil})
    if success and response.Success and response.Body and response.Body ~= "" then
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body)
        return ok and decoded or nil
    end
    return nil
end

local httpClient = HttpClient.new()

local ServerAPI = {}
function ServerAPI.getBots()
    local response = httpClient:makeRequest(CONFIG.API_URL .. "/bots", "GET")
    if not response or not response.data then return {} end
    local success, decrypted = pcall(fastDecrypt, response.data, CONFIG.ENCRYPTION_KEY)
    if not success or not decrypted then return {} end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, decrypted)
    return ok and data or {}
end

function ServerAPI.addBot(userId)
    return httpClient:makeRequest(CONFIG.API_URL .. "/bots", "POST", {user_id = tostring(userId)}) ~= nil
end

function ServerAPI.reportBrainrot(data)
    return httpClient:makeRequest(CONFIG.API_URL .. "/brainrots", "POST", data) ~= nil
end

local kickDetected = false
local function monitorConsole()
    LogService.MessageOut:Connect(function(message, messageType)
        if string.find(message, "Server Kick Message") or string.find(message, "You have been kicked") then
            kickDetected = true
        end
    end)
end

local Scanner = {}
Scanner.__index = Scanner
function Scanner.new()
    return setmetatable({animalsCache = {}, Debris = workspace:WaitForChild("Debris")}, Scanner)
end

function Scanner:scanAll()
    task.wait(CONFIG.SCAN_DELAY)
    
    local debrisChildren = self.Debris:GetChildren()
    local scannedCount = 0
    
    for _, obj in ipairs(debrisChildren) do
        task.spawn(function()
            local overhead = obj:FindFirstChild("AnimalOverhead")
            if overhead then
                local genLabel = overhead:FindFirstChild("Generation")
                local nameLabel = overhead:FindFirstChild("DisplayName")
                local mutLabel = overhead:FindFirstChild("Mutation")
                
                if genLabel and nameLabel and mutLabel then
                    local genText = genLabel.Text
                    local animalName = nameLabel.Text
                    local mutation = cleanRichText(mutLabel.Text)
                    
                    if genText and string.sub(genText, 1, 1) == "$" then
                        local genValue = parseGenValue(genText)
                        
                        if genValue >= CONFIG.MIN_GEN_VALUE and mutation and mutation ~= "" and mutation ~= "None" then
                            table.insert(self.animalsCache, {
                                name = animalName,
                                genValue = genValue,
                                genText = formatNum(genValue),
                                rarity = mutation
                            })
                        end
                    end
                end
            end
            scannedCount = scannedCount + 1
        end)
    end
    
    local timeout = os.clock() + 15
    while scannedCount < #debrisChildren and os.clock() < timeout and not kickDetected do
        task.wait(0.1)
    end
    
    return #self.animalsCache
end

local function checkForBots()
    local botList = ServerAPI.getBots()
    if not botList or type(botList) ~= "table" or #botList == 0 then return false end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local userId = tostring(player.UserId)
            for _, botId in ipairs(botList) do
                if userId == tostring(botId) then return true end
            end
        end
    end
    return false
end

local function serverHop()
    loadstring(game:HttpGet('https://raw.githubusercontent.com/Cesare0328/my-scripts/refs/heads/main/CachedServerhop.lua'))()
end

local function initialize()
    monitorConsole()
    
    task.spawn(function()
        while task.wait(1) do
            if kickDetected then
                serverHop()
                return
            end
        end
    end)
    
    ServerAPI.addBot(LocalPlayer.UserId)
    
    if checkForBots() then 
        task.wait(1) 
        serverHop() 
        return 
    end
    
    local scanner = Scanner.new()
    scanner:scanAll()
    
    if #scanner.animalsCache > 0 then
        table.sort(scanner.animalsCache, function(a, b) return a.genValue > b.genValue end)
        
        local playerCount = #Players:GetPlayers() - 1
        
        for _, animal in ipairs(scanner.animalsCache) do
            if animal.genValue >= CONFIG.MIN_GEN_VALUE then
                ServerAPI.reportBrainrot({
                    job_id = game.JobId, 
                    animal_name = animal.name, 
                    generation = animal.genText, 
                    gen_value = animal.genValue, 
                    rarity = animal.rarity, 
                    players = playerCount
                })
                task.wait(0.1)
            end
        end
    end
    
    task.wait(2)
    serverHop()
end

task.spawn(function()
    local success, err = pcall(initialize)
    if not success then 
        task.wait(5) 
        serverHop() 
    end
end)
