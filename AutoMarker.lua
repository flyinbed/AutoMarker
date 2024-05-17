-- || Made by and for Weird Vibes of Turtle WoW || --

BINDING_HEADER_AUTOMARK = "|cff22CC00 - AutoMark Bindings -";
BINDING_NAME_MOUSEOVERKEY = "Keys to hold to activate mouseover mark";
BINDING_NAME_RUNKEY = "Mark mouseover or target";


-- Utility -------------------

local color = {
  white = "|cffffffff",
  red = "|cffff0000",
  green = "|cff00ff00",
  blue = "|cff0000ff",
  yellow = "|cffffff00",
  cyan = "|cff00ffff",
  magenta = "|cffff00ff",
  grey = "|cff808080",
  orange = "|cffff8000",
  purple = "|cffff00ff"}

local function c(text, color)
  return color..text.."|r"
end

if not SetAutoloot then
  DEFAULT_CHAT_FRAME:AddMessage(c("AutoMarker",color.yellow)..c(" requires SuperWoW to operate.",color.red))
  return
end

local function auto_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function tsize(t)
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c
end

local function sortTableByKey(tbl)
  local sortedKeys = {}
  for key in pairs(tbl) do
      table.insert(sortedKeys, key)
  end
  table.sort(sortedKeys)

  local sortedTable = {}
  for _, key in ipairs(sortedKeys) do
      sortedTable[key] = tbl[key]
  end
  return sortedTable
end

--[[[
This lines up the mob tables and the update table and picks out what's newer:
Say we have
  ["spider_anubrekhan"] = {
    ["0x101"] = 6, -- spider 1
    ["0x102"] = 7, -- spider 2
    ["0x10"] = 8, -- anub
  },
And
  update = {
    ["0x105"] = 6, -- spider 1
    ["0x106"] = 7, -- spider 2
  },
We get
  updated = {
    ["0x105"] = 6, -- spider 1
    ["0x106"] = 7, -- spider 2
    ["0x10"] = 8, -- anub
  },
--]]
local function sortAndReplaceKeys(defaultTable, updateTable)
  local keys = {}
  for key in pairs(defaultTable) do
      table.insert(keys, key)
  end
  table.sort(keys, function(a, b) return a > b end)

  local values = {}
  for _, value in pairs(updateTable) do
      table.insert(values, value)
  end
  table.sort(values, function(a, b) return a > b end)

  local updatedTable = {}
  local i = 1

  for _, key in ipairs(keys) do
      if values[i] then
          updatedTable[values[i]] = defaultTable[key]
          i = i + 1
      else
          updatedTable[key] = defaultTable[key]
      end
  end

  return updatedTable
end

-- Addon ---------------------

local raidMarks = {"Unmarked", "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"}

local defaultSettings = {
  debug = false,
}

local currentNpcsToMark = {}

local autoMarkerFrame = CreateFrame("Frame","AutoMarkerFrame")
autoMarkerFrame:RegisterEvent("ADDON_LOADED")
autoMarkerFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
autoMarkerFrame:RegisterEvent("UNIT_MODEL_CHANGED") -- mob respawn
autoMarkerFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- mob respawn

local function guidToPack(id, zone)
  if not currentNpcsToMark or not currentNpcsToMark[zone] then
    return
  end
  for packName, packInfo in pairs(currentNpcsToMark[zone]) do
    for guid, _ in pairs(packInfo) do
      if guid==id then
        return packName, currentNpcsToMark[zone][packName]
      end
    end
  end
end

local function PlayerCanMark()
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name==UnitName("player") then
      return rank>0
    end
  end
  return UnitIsPartyLeader("player") or false
end

function AutoMark_MarkGroup()
  local _, mouseoverGuid = UnitExists("mouseover")
  local _, targetGuid = UnitExists("target")
  targetGuid = mouseoverGuid and mouseoverGuid or targetGuid
  if targetGuid and not UnitIsDead(targetGuid) and PlayerCanMark() then
    local _, packMobs = guidToPack(targetGuid, GetRealZoneText())
    for mob, mark in pairs(packMobs or {}) do
      -- might be out of range, e.g. a patrol
      if UnitExists(mob) then
        SetRaidTarget(mob, mark)
      end
    end
  end
end

local function OnMouseover()
  if IsShiftKeyDown() and (IsControlKeyDown() or IsAltKeyDown()) then
    AutoMark_MarkGroup()
  end
end

-- when certain bosses reset so do their adds, but they come back in the same order with new id's
local temporary_mobs = {
  ["Deathknight Understudy"] = {
      minCount = 4,
      pack = "military_razuvious",
      raid = "Naxxramas",
      queue = {},
  },
  ["Crypt Guard"] = {
      minCount = 2,
      pack = "spider_anubrekhan",
      raid = "Naxxramas",
      queue = {},
  },
    ["The Prophet Skeram"] = {
        minCount = 3,
        pack = "skeram",
        raid = "Ahn'Qiraj",
        live_mark = true, -- do the mobs change in combat
        queue = {},
    },
}

-- talk to ferro about burnout

-- so we'll order them and assigned them ordered source marks
local elapsed = 0
function UpdateRespawns()
  elapsed = elapsed + arg1
  if elapsed > 0.25 then -- no sense checking tables every single frame
    elapsed = 0
    for mob, config in pairs(temporary_mobs) do
      if tsize(config.queue) >= config.minCount then
        currentNpcsToMark[config.raid][config.pack] =
          -- the purpose of the default pack despite being regenerated is for consitent marks
          sortAndReplaceKeys(defaultNpcsToMark[config.raid][config.pack], config.queue)
        config.queue = {}
        autoMarkerFrame:SetScript("OnUpdate", nil)
        if config.live_mark then
          for guid,mark in pairs(currentNpcsToMark[config.raid][config.pack]) do
            if UnitExists(guid) then
              SetRaidTarget(guid, mark)
            end
          end
        end
      end
    end
  end
end

-- Event handler
autoMarkerFrame:SetScript("OnEvent", function()
  if event=="ADDON_LOADED" and arg1=="AutoMarker" then
    -- init settings
    if not settings then
      settings = defaultSettings
    else -- update/clean settings
      local s = {}
      for k,v in defaultSettings do
        s[k] = settings[k] and settings[k] or v
      end
      settings = s
    end

    -- init vars
    if not customNpcsToMark then customNpcsToMark = {} end

    -- load defaults
    for raid_name,packs in pairs(defaultNpcsToMark) do
      if not currentNpcsToMark[raid_name] then currentNpcsToMark[raid_name] = {} end
      for pack_name,pack in pairs(packs) do
        if not currentNpcsToMark[raid_name][pack_name] then
          currentNpcsToMark[raid_name][pack_name] = defaultNpcsToMark[raid_name][pack_name]
        end
      end
    end
    -- over-write with customs
    for raid_name,packs in pairs(customNpcsToMark) do
      if not currentNpcsToMark[raid_name] then currentNpcsToMark[raid_name] = {} end
      for pack_name,pack in pairs(packs) do
        currentNpcsToMark[raid_name][pack_name] = customNpcsToMark[raid_name][pack_name]
      end
    end
    auto_print(c("AutoMarker loaded!",color.yellow).." Type "..c("/am",color.green).." to see commands.")
  elseif event=="UPDATE_MOUSEOVER_UNIT" then
    OnMouseover()
    if settings["debug"] then
      local _,guid = UnitExists("mouseover")
      auto_print(guid .. " " .. UnitName(guid))
    end
  elseif event=="UNIT_MODEL_CHANGED" then
    -- Certain mobs are script spawned so their IDs need to be fetched
    local name = UnitName(arg1)
    if temporary_mobs[name] then
      table.insert(temporary_mobs[name].queue, arg1)
      autoMarkerFrame:SetScript("OnUpdate", UpdateRespawns)
    end
  elseif event=="PLAYER_REGEN_DISABLED" then
    -- combat started, reset model queues in case of incomplete loads
    for _,config in pairs(temporary_mobs) do
      config.queue = {}
    end
  end
end)

local currentPackName = nil
local function handleCommands(msg, editbox)
  local args = {}
  for word in string.gfind(msg, '%S+') do
    if word ~= "" then
      table.insert(args, word)
    end
  end

  local command, packName = args[1], args[2]
  local force_add = command == "forceadd"
  local zoneName = GetRealZoneText()
  local function getGuid()
    local _, guid = UnitExists("target")
    return guid
  end

  -- skeram, 2nd war pat, extra mark in big bug pat room

  if command == "set" or command == "s" then
    if not packName then
      auto_print("You must provide a pack name as well when using set.")
      return
    end
    currentPackName = packName
    auto_print("Packname set to: " .. currentPackName)
  elseif command == "get" or command == "g" then
    auto_print("Curent packname set to: " .. (currentPackName or "none"))
    local guid = getGuid()
    if guid then
      local packName,pack = guidToPack(guid, zoneName)
      if packName then
        local mark = pack[guid]+1
        auto_print(format("Mob %s (%s) is %s in pack: %s",guid,UnitName(guid),raidMarks[mark],packName))
      else
        auto_print(format("Mob %s (%s) is not in any pack.",guid,UnitName(guid)))
      end
    end
  elseif command == "clear" or command == "c" then
    if customNpcsToMark[zoneName] then
      customNpcsToMark[zoneName][currentPackName] = nil
    end
    auto_print("Mobs in " .. currentPackName .. " have been cleared.")
  elseif command == "remove" or command == "r" then
    local guid = getGuid()
    if not guid then
      auto_print("Must target a mob to remove it from its pack.")
      return
    end
    local packName = guidToPack(guid, zoneName)
    if not packName then
      auto_print("Mob not in any pack.")
      return
    end
    auto_print("Removing mob " .. UnitName(guid) .. " from pack: " .. packName)
    customNpcsToMark[zoneName][packName][guid] = nil
  elseif command == "add" or command == "a" or force_add then
    if not currentPackName then
      auto_print("Must set packname before adding to pack.")
      return
    end
    local guid = getGuid()
    if not guid then
      auto_print("Must target a mob to add to current pack.")
      return
    end
    local packName = guidToPack(guid, zoneName)
    if packName and not force_add then
      auto_print("Mob already added to pack " .. packName .. ". use /am forceadd")
      return
    end
    local unitName, raidmark = UnitName(guid), GetRaidTargetIndex(guid) or 0
    auto_print("Adding " .. unitName .. "(" .. guid .. ") to pack: " .. currentPackName .. " with mark: " .. raidMarks[raidmark + 1] .. " in zone: " .. zoneName)
    customNpcsToMark[zoneName] = customNpcsToMark[zoneName] or {}
    customNpcsToMark[zoneName][currentPackName] = customNpcsToMark[zoneName][currentPackName] or {}
    customNpcsToMark[zoneName][currentPackName][guid] = raidmark
  elseif command == "debug" then
    settings["debug"] = not settings["debug"]
    auto_print("Debug mode set to: " .. (settings["debug"] and "on" or "off"))
  else
    auto_print("Commands:")
    auto_print("/am "..c("s",color.green).."et <packname>")
    auto_print("/am "..c("g",color.green).."et")
    auto_print("/am "..c("c",color.green).."lear")
    auto_print("/am "..c("a",color.green).."dd")
    auto_print("/am "..c("r",color.green).."emove")
    auto_print("/am debug")
    auto_print("/am clearcache")
  end
end

SLASH_AUTOMARKER1 = "/automarker";
SLASH_AUTOMARKER2 = "/am";
SlashCmdList["AUTOMARKER"] = handleCommands
