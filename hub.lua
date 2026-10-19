local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/iqoow/reverb-hub/main/"

local games = {
    [111543903102439] = "1_Stone_Skipping.lua",
    [100753254401525] = "1_DMG_FPS.lua",
    [87299448877557] = "1_DMG_FPS.lua",
    [120252007682677] = "SurfAndRescue_Dump.lua",
    [116223724643557] = "1_Magic_Evolution.lua",
    [140070560575882] = "1_Magic_Evolution.lua",
    [121125129560252] = "Mine_a_Planet.lua",
    [90568084448279] = "OneTap_Dump.lua",
    [142823291] = "MM2_Dump.lua",
    [72920620366355] = "operation_one_Dump.lua",
    [115681808123944] = "throw_a_coin_Dump.lua",
    [72042130041700] = "throw_a_coin_Dump.lua",
    [100875131717601] = "throw_a_coin_Dump.lua",
    [86259628805375] = "1_Strength_to_Grow_Your_Arm.lua",
    [92648272637932] = "1_Mog_Evolution.lua",
    [123720558354386] = "Build_the_Pyramid.lua"
}

local placeId = game.PlaceId
print("[Hub] Current PlaceId: " .. tostring(placeId))

local fileName = games[placeId]

if not fileName then
    warn("[Hub] This game (" .. tostring(placeId) .. ") is not supported. Script not found in list.")
    return 
end

local scriptUrl = GITHUB_RAW_BASE .. fileName
print("[Hub] Found script: " .. fileName)
print("[Hub] Loading from URL: " .. scriptUrl)

local success, err = pcall(function()
    local source = game:HttpGet(scriptUrl)
    
    if not source or source == "" then
        warn("[Hub] Error: Server returned an empty response.")
        return
    end
    
    if string.find(source, "404: Not Found") then
        warn("[Hub] 404 Error: File not found on GitHub. Check the filename and branch (main).")
        return
    end
    
    -- Sometimes GitHub returns HTML if the repo is private or the link is broken
    if string.find(source, "<!DOCTYPE html>") or string.find(source, "<html") then
        warn("[Hub] Error: GitHub returned an HTML page instead of code. Make sure the repository is Public.")
        return
    end

    local func, compileError = loadstring(source)
    if func then
        print("[Hub] Compilation successful. Executing...")
        func()
    else
        warn("[Hub] Lua compilation error: " .. tostring(compileError))
    end
end)

if not success then
    warn("[Hub] Critical error: " .. tostring(err))
end
