TBUG = {}
local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

--Version and name of the AddOn
TBUG.version = "1.39"
TBUG.name = "merTorchbug"

--Track merTorchbug load time and session time
local startTimeTimeStamp = GetTimeStamp()
TBUG.startTimeTimeStamp = startTimeTimeStamp
local startTime = startTimeTimeStamp * 1000
TBUG.sessionStartTime = startTime - GetGameTimeMilliseconds()
TBUG.startTime = startTime

------------------------------------------------------------------------------------------------------------------------
-- TODOs, planned features and known bugs
---------------------------------------------------------------------------------------------------------------------------
-- Version 1.38 - Baertram
--
-- [Todo]
-- Add color box to color properties, open color picker on click.
-- Add "loaded addons and their order" to TBUG.AddOns table in EVENT_ADD_ON_LOADED
--
-- [Added / Fixed]
-- Control types showing the constant name instead of the number
-- Preview textures as small tooltip if mouse is moved above the textureFileName row
-- Fixed the search bar not showing if insector get's collapsed to the headline
-- Fixed the collapsed control resizing to the original size (still collapsed and invisible but mouse click enabled, overlaying other controls)
-- Show a small texture preview on mouseOver the textFileName column
-- Added the small e (disabled) and E (enabled) to the global inspector -> Track all events if enabled and show in the new "Events" tab of the global inspector
--
-- [Planned features]
--
-- [Known bugs]
-- #1) Opening the global inspector will open any "empty" (containing no tabs) inspector windows as well
---------------------------------------------------------------------------------------------------------------------------

local getmetatable = getmetatable
local next = next
local rawget = rawget
local rawset = rawset
local select = select
local setmetatable = setmetatable
local tostring = tostring
local type = type

--The megasevers and the testserver
tbug.servers = {
    "EU Megaserver",
    "NA Megaserver",
    "PTS",
}

--Global SavedVariable table suffix to test for existance
local svSuffix = {
    "SavedVariables",
    "SavedVars",
    "_Data",
    "_SavedVariables",
    "_SV",
    "_OPTS",
    "_OPTIONS",
    "_SETTINGS",
}
tbug.svSuffix = svSuffix

--Patterns for a string.match to find supported inventory rows (for their dataEntry.data subtables), or other controls
--like the e.g. character equipment button controls
local inventoryRowPatterns = {
    "^ZO_%a+Backpack%dRow%d%d*",                                          --Inventory backpack
    "^ZO_%a+InventoryList%dRow%d%d*",                                     --Inventory backpack
    "^ZO_CharacterEquipmentSlots.+$",                                     --Character
    "^ZO_CraftBagList%dRow%d%d*",                                         --CraftBag
    "^ZO_Smithing%aRefinementPanelInventoryBackpack%dRow%d%d*",           --Smithing refinement
    "^ZO_RetraitStation_%a+RetraitPanelInventoryBackpack%dRow%d%d*",      --Retrait
    "^ZO_QuickSlotList%dRow%d%d*",                                        --Quickslot
    "^ZO_RepairWindowList%dRow%d%d*",                                     --Repair at vendor
    "^ZO_ListDialog1List%dRow%d%d*",                                      --List dialog (Repair, Recharge, Enchant, Research)
}
--Special keys at the inspector list, which add special contextmenu entries
local specialEntriesAtInspectorLists = {
    ["bagId"]       = true,
    ["slotIndex"]   = true,
}
tbug.specialEntriesAtInspectorLists = specialEntriesAtInspectorLists

--Special colors for some entries in the object inspector (key)
local specialKeyToColorType = {
    ["LibStub"] = "obsolete",
}
tbug.specialKeyToColorType = specialKeyToColorType

--Keys of entries in tables which normally are used for a GetString() value
local getStringKeys = {
    ["text"]        = true,
    ["defaultText"] = true,
}
tbug.getStringKeys = getStringKeys

local function isGetStringKey(key)
    return getStringKeys[key] or false
end
tbug.isGetStringKey = isGetStringKey

--The panel names for the global inspector tabs
local panelNames = {
    { key="addons",         name="AddOns",          slashCommand="addons" },
    { key="classes",        name="Classes",         slashCommand="classes" },
    { key="objects",        name="Objects",         slashCommand="objects" },
    { key="controls",       name="Controls",        slashCommand="controls" },
    { key="fonts",          name="Fonts",           slashCommand="fonts" },
    { key="functions",      name="Functions",       slashCommand="functions" },
    { key="constants",      name="Constants",       slashCommand="constants" },
    { key="strings",        name="Strings",         slashCommand="strings" },
    { key="sounds",         name="Sounds",          slashCommand="sounds" },
    { key="dialogs",        name="Dialogs",         slashCommand="dialogs" },
    { key="scenes",         name="Scenes",          slashCommand="scenes" },
    { key="libs",           name="Libs",            slashCommand="libs" },
    { key="scriptHistory",  name="Scripts",         slashCommand="scripts" },
    { key="events",         name="Events",          slashCommand="events" },
    { key="sv",             name="SavedVariables",  slashCommand="sv" },
}
tbug.panelNames = panelNames
local allowedSlashCommandsForPanels = {
    ["-all-"] = true,
}
for _, panelData in ipairs(panelNames) do
    allowedSlashCommandsForPanels[panelData.slashCommand] = true
end
tbug.allowedSlashCommandsForPanels = allowedSlashCommandsForPanels

--The rowTypes ->  the ZO_SortFilterScrollList DataTypes
local rt = {}
rt.GENERIC = 1
rt.FONT_OBJECT = 2
rt.LOCAL_STRING = 3
rt.SOUND_STRING = 4
rt.LIB_TABLE = 5
rt.SCRIPTHISTORY_TABLE = 6
rt.ADDONS_TABLE = 7
rt.EVENTS_TABLE = 8
rt.SAVEDVARIABLES_TABLE = 9
tbug.RT = rt


------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
local function inherit(class, base)
    getmetatable(class).__index = base
    return class
end


local function new(class, ...)
    local instance = setmetatable({}, class)
    return instance, instance:__init__(...)
end


local function newClass(dict, name)
    local classMT = {__call = new, __concat = inherit}
    local class = {}
    rawset(class, "__index", class)
    rawset(dict, name, class)
    return setmetatable(class, classMT)
end


tbug.classes = setmetatable({}, {__index = newClass})


function tbug.autovivify(mt)
    local function setdefault(self, key)
        local sub = setmetatable({}, mt)
        rawset(self, key, sub)
        return sub
    end
    return {__index = setdefault}
end


tbug.cache = setmetatable({}, tbug.autovivify(nil))


function tbug.bind1(func, arg1)
    return function(...)
        return func(arg1, ...)
    end
end


function tbug.bind2(func, arg1, arg2)
    return function(...)
        return func(arg1, arg2, ...)
    end
end


function tbug.foreach(tab, func)
    for key, val in next, tab do
        func(key, val)
    end
end


function tbug.foreachValue(tab, func)
    for key, val in next, tab do
        func(val)
    end
end


function tbug.gettype(tab, key)
    local mt = getmetatable(tab)
    if mt then
        local gettype = mt._tbug_gettype
        if gettype then
            return gettype(tab, key)
        end
    end
    return type(rawget(tab, key))
end


function tbug.setindex(tab, key, val)
    local mt = getmetatable(tab)
    if mt then
        local setindex = mt._tbug_setindex
        if setindex then
            setindex(tab, key, val)
            return rawget(tab, key)
        end
    end
    rawset(tab, key, val)
    return val
end


function tbug.subtable(tab, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local sub = tab[key]
        if type(sub) ~= "table" then
            sub = {}
            tab[key] = sub
        end
        tab = sub
    end
    return tab
end


do
    local function tail(name, t1, ...)
        local t2 = GetGameTimeMilliseconds()
        df("%s took %.3fms", name, t2 - t1)
        return ...
    end

    function tbug.timed(name, func)
        return function(...)
            local t1 = GetGameTimeMilliseconds()
            return tail(name, t1, func(...))
        end
    end
end


function tbug.truncate(tab, len)
    for i = #tab, len + 1, -1 do
        tab[i] = nil
    end
    return tab
end


local typeOrder =
{
    ["nil"] = 0,
    ["boolean"] = 1,
    ["number"] = 2,
    ["string"] = 3,
    ["table"] = 4,
    ["userdata"] = 5,
    ["function"] = 6,
}

setmetatable(typeOrder,
{
    __index = function(t, k)
        df("tbug: typeOrder[%q] undefined", tostring(k))
        return -1
    end
})

local typeCompare =
{
    ["nil"] = function(a, b) return false end,
    ["boolean"] = function(a, b) return not a and b end,
    ["number"] = function(a, b) return a < b end,
    ["string"] = function(a, b)
        local _, na = a:find("^_*")
        local _, nb = b:find("^_*")
        if na ~= nb then
            return na > nb
        else
            return a < b
        end
    end,
    ["table"] = function(a, b) return tostring(a) < tostring(b) end,
    ["userdata"] = function(a, b) return tostring(a) < tostring(b) end,
    ["function"] = function(a, b) return tostring(a) < tostring(b) end,
}

function tbug.typeSafeLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return typeOrder[ta] < typeOrder[tb]
    else
        return typeCompare[ta](a, b)
    end
end

function tbug.firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

function tbug.startsWith(str, start)
    if str == nil or start == nil or start  == "" then return false end
    return str:sub(1, #start) == start
end
function tbug.endsWith(str, ending)
    if str == nil or ending == nil or ending  == "" then return false end
    return ending == "" or str:sub(-#ending) == ending
end

--Create list of TopLevelControls (boolean parameter onlyVisible: only add visible, or all TLCs)
function ListTLC(onlyVisible)
    onlyVisible = onlyVisible or false
    local res = {}
    if GuiRoot then
        for i = 1, GuiRoot:GetNumChildren() do
            local doAdd = false
            local c = GuiRoot:GetChild(i)
            if c then
                if onlyVisible then
                    if not c.IsHidden or (c.IsHidden and not c:IsHidden()) then
                        doAdd = true
                    end
                else
                    doAdd = true
                end
                if doAdd then
                    res[i] = c
                end
            end
        end
    end
    return res
end

--Get a property of a control in the TorchBugControlInspector list, at index indexInList, and the name should be propName
function tbug.getPropOfControlAtIndex(listWithProps, indexInList, propName, searchWholeList)
    if not listWithProps or not indexInList or not propName or propName == "" then return end
    searchWholeList = searchWholeList or false
    local listEntryAtIndex = listWithProps[indexInList]
    if listEntryAtIndex then
        local listEntryAtIndexData = listEntryAtIndex.data
        if listEntryAtIndexData then
            if (listEntryAtIndexData.prop and listEntryAtIndexData.prop.name and listEntryAtIndexData.prop.name == propName) or
             (listEntryAtIndexData.data and listEntryAtIndexData.data.key and listEntryAtIndexData.data.key == propName) then
                return listEntryAtIndexData.value
            else
                --The list is not control inspector and thus the e.g. bagId and slotIndex are not next to each other, so we
                --need to search the whole list for the propName
                if searchWholeList == true then
                    for _, propData in ipairs(listWithProps) do
                        if (propData.prop and propData.prop.name and propData.prop.name == propName) or
                            (propData.data and propData.data.key and propData.data.key == propName) then
                            return propData.data and propData.data.value
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function isSpecialEntryAtInspectorList(entry)
    local specialKeys = specialEntriesAtInspectorLists
    return specialKeys[entry] or false
end

--Check if the number at the currently clicked row at the controlInspectorList is a special number
--like a pair of bagid and slotIndex
function tbug.isSpecialEntryAtInspectorList(p_self, p_row, p_data)
    if not p_self or not p_row or not p_data then return end
    local props = p_data.prop
    if not props then

        --Check if it's not a control but another type having only a key
        if p_data.key then
            props = {}
            props.isSpecial = isSpecialEntryAtInspectorList(p_data.key)
        end
    end
    if not props then return end
    return props.isSpecial or false
end

local function returnTextAfterLastDot(str)
    local strAfterLastDot = str:match("[^%.]+$")
    return strAfterLastDot
end

--Try to get the key of the object (the string behind the last .)
function tbug.getKeyOfObject(objectStr)
    if objectStr and objectStr ~= "" then
        return returnTextAfterLastDot(objectStr)
    end
    return nil
end

--Clean the key of a key String (remove trailing () or [])
function tbug.cleanKey(keyStr)
    if keyStr == nil or keyStr == "" then return end
    if not tbug.endsWith(keyStr, "()") and not tbug.endsWith(keyStr, "[]") then return keyStr end
    local retStr = keyStr:sub(1, (keyStr:len()-2))
    return retStr
end

--Is the control an inventory list row? Check by it's name pattern
function tbug.isSupportedInventoryRowPattern(controlName)
    if not controlName then return false, nil end
    if not inventoryRowPatterns then return false, nil end
    for _, patternToCheck in ipairs(inventoryRowPatterns) do
        if controlName:find(patternToCheck) ~= nil then
            return true, patternToCheck
        end
    end
    return false, nil
end

function tbug.formatTime(timeStamp)
    return os.date("%F %T.%%03.0f %z", timeStamp / 1000):format(timeStamp % 1000)
end

--Get the zone and subZone string from the given map's tile texture (or the current's map's tile texture name)
function tbug.getZoneInfo(mapTileTextureName, patternToUse)
--[[
    Possible texture names are e.g.
    /art/maps/southernelsweyr/els_dragonguard_island05_base_8.dds
    /art/maps/murkmire/tsofeercavern01_1.dds
    /art/maps/housing/blackreachcrypts.base_0.dds
    /art/maps/housing/blackreachcrypts.base_1.dds
    Art/maps/skyrim/blackreach_base_0.dds
    Textures/maps/summerset/alinor_base.dds
]]
    mapTileTextureName = mapTileTextureName or GetMapTileTexture()
    if not mapTileTextureName or mapTileTextureName == "" then return end
    local mapTileTextureNameLower = mapTileTextureName:lower()
    mapTileTextureNameLower = mapTileTextureNameLower:gsub("ui_map_", "")
    --mapTileTextureNameLower = mapTileTextureNameLower:gsub(".base", "_base")
    --mapTileTextureNameLower = mapTileTextureNameLower:gsub("[_+%d]*%.dds$", "") -> Will remove the 01_1 at the end of tsofeercavern01_1
    mapTileTextureNameLower = mapTileTextureNameLower:gsub("%.dds$", "")
    mapTileTextureNameLower = mapTileTextureNameLower:gsub("_%d*$", "")
    local regexData = {}
    if not patternToUse or patternToUse == "" then patternToUse = "([%/]?.*%/maps%/)(%w+)%/(.*)" end
    regexData = {mapTileTextureNameLower:find(patternToUse)} --maps/([%w%-]+/[%w%-]+[%._][%w%-]+(_%d)?)
    local zoneName, subzoneName = regexData[4], regexData[5]
    local zoneId = GetZoneId(GetCurrentMapZoneIndex())
    local parentZoneId = GetParentZoneId(zoneId)
    d("========================================\n[TBUG.getZoneInfo]\nzone: " ..tostring(zoneName) .. ", subZone: " .. tostring(subzoneName) .. "\nmapTileTexture: " .. tostring(mapTileTextureNameLower).."\nzoneId: " ..tostring(zoneId).. ", parentZoneId: " ..tostring(parentZoneId))
    return zoneName, subzoneName, mapTileTextureNameLower, zoneId, parentZoneId
end