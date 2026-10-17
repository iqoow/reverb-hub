local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/iqoow/reverb-hub/main/"

local games = {
    [111543903102439] = "+1 Stone Skipping.lua",
    [100753254401525] = "+1 DMG FPS.lua",
    [87299448877557] = "+1 DMG FPS.lua",
    [120252007682677] = "SurfAndRescue_Dump.lua",
    [116223724643557] = "+1 Magic Evolution.lua",
    [140070560575882] = "+1 Magic Evolution.lua",
    [121125129560252] = "Mine a Planet.lua",
    [90568084448279] = "OneTap_Dump.lua",
    [142823291] = "MM2_Dump.lua",
    [72920620366355] = "operation_one_Dump.lua",
    [115681808123944] = "throw_a_coin_Dump.lua",
    [72042130041700] = "throw_a_coin_Dump.lua",
    [100875131717601] = "throw_a_coin_Dump.lua",
    [86259628805375] = "+1 Strength to Grow Your Arm.lua",
    [92648272637932] = "+1 Mog Evolution.lua",
    [123720558354386] = "Build the Pyramid!.lua"
}

local placeId = game.PlaceId
local fileName = games[placeId]

if not fileName then
    return 
end

local scriptUrl = GITHUB_RAW_BASE .. fileName
print("[Hub] Loading script: " .. fileName)

local success, err = pcall(function()
    local source = game:HttpGet(scriptUrl)
    if source and source ~= "" and not string.find(source, "404: Not Found") then
        local func, compileError = loadstring(source)
        if func then
            func()
        else
            warn("[Hub] Compilation error: " .. tostring(compileError))
        end
    else
        warn("[Hub] File not found.")
    end
end)

if not success then
    warn("[Hub] Error: " .. tostring(err))
end
