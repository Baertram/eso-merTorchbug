local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")
local cm = CALLBACK_MANAGER

local types = tbug.types
local stringType = types.string
local numberType = types.number
local functionType = types.func
local tableType = types.table
local userDataType = types.userdata
local structType = types.struct

local panelNames = tbug.panelNames

local firstToUpper = tbug.firstToUpper

------------------------------------------------------------------------------------------------------------------------
local defaults =
{
    _doDebug = false, --enables tbug.doDebug

    interfaceColors =
    {
        tabWindowBackground                  = "hsla(60, 10, 20, 0.5)",
        tabWindowPanelBackground             = "rgba(0, 0, 0, 0.6)",
        tabWindowTitleBackground_TOPLEFT     = "rgba(0, 0, 0, 0.3)",
        tabWindowTitleBackground_TOPRIGHT    = "rgba(0, 0, 0, 0.2)",
        tabWindowTitleBackground_BOTTOMLEFT  = "rgba(0, 0, 0, 0.6)",
        tabWindowTitleBackground_BOTTOMRIGHT = "rgba(0, 0, 0, 0.5)",
    },
    typeColors =
    {
        ["nil"]      = "hsl(120, 50, 70)",
        ["boolean"]  = "hsl(120, 50, 70)",
        ["event"]    = "hsl(60, 90, 70)",
        [numberType]   = "hsl(120, 50, 70)",
        [stringType]   = "hsl(30, 90, 70)",
        [functionType] = "hsl(270, 90, 80)",
        [tableType]    = "hsl(210, 90, 75)", --light blue
        [userDataType] = "hsl(0, 0, 75)",
        ["obsolete"] = "hsl(0, 100, 50)", --red
        ["comment"]  = "hsl(0, 0, 100)", --white
        ["object"]  = "hsl(248, 53, 58)", --lila
        ["sceneName"]= "hsla(319, 100, 50)", --pink
        ["__isClass"] = "hsl(0, 0, 100)", --white
        ["__isObject"] = "hsl(0, 0, 100)", --white
        [structType]    = "hsl(210, 90, 50)", --light blue, bit darker than a table
    },
    scriptHistory = {},
    scriptHistoryComments = {},
    scriptKeybinds = {},

    searchHistory = {},

    savedInspectors = {},
    savedInspectorsComments = {},

    enableMouseRightAndLeftAndSHIFTInspector = true,
    enableMouseRightAndLeftAndSHIFTInspectorDuringCombat = false,

	customTemplate = {
		font = 'ZoFontGameSmall',
		height = 24
	},

    enableEventTrackerAtStartup = false,
    --enableEventTrackerAtNextLogin = nil,          -- only added here for reference so you see it exists and is used!
    --enableEventTrackerAtStartupOnlyOnce = nil,    -- only added here for reference so you see it exists and is used!
    savedEvents = {},
}
tbug.svDefaults = defaults

local function copyDefaults(dst, src)
    for k, v in zo_insecureNext , src do
        local dk = dst[k]
        local tv = type(v)
        if tv == tableType then
            if type(dk) == tableType then
                copyDefaults(dk, v)
            else
                dst[k] = copyDefaults({}, v)
            end
        elseif type(dk) ~= tv then
            dst[k] = v
        end
    end
    return dst
end


------------------------------------------------------------------------------------------------------------------------
tbug.savedVars = tbug.savedVars or {}

function tbug.savedTable(...)
    return tbug.subtable(tbug.savedVars, ...)
end

function tbug.initSavedVars()
    local allowedSlashCommandsForPanels = {
        ["-all-"] = true,
    }
    local allowedSlashCommandsForPanelsLookup = {
        ["-all-"] = 1,
    }
    for idx, panelData in ipairs(panelNames) do
        local isLookup = (panelData.lookup ~= nil and true) or false
        if panelData.slashCommand ~= nil then
            for _, slashCommandForPanel in ipairs(panelData.slashCommand) do
                allowedSlashCommandsForPanels[slashCommandForPanel] = true
                if not isLookup then
                    allowedSlashCommandsForPanelsLookup[firstToUpper(slashCommandForPanel)] = idx
                end
            end
        end
        if isLookup == true then
            allowedSlashCommandsForPanelsLookup[panelData.lookup] = idx
        end

        --Search history in SV
        defaults.searchHistory[panelData.name] = {}
        defaults.searchHistory["_allTheSame_"] = {}
        for filterMode, _ in ipairs(tbug.filterModes) do
            defaults.searchHistory[panelData.name][filterMode] = {}
            defaults.searchHistory["_allTheSame_"][filterMode] = {}
        end
    end
    tbug.allowedSlashCommandsForPanels = allowedSlashCommandsForPanels
    tbug.allowedSlashCommandsForPanelsLookup = allowedSlashCommandsForPanelsLookup

    if merTorchbugSavedVars ~= nil then
        tbug.savedVars = merTorchbugSavedVars
    else
        merTorchbugSavedVars = tbug.savedVars
    end

    copyDefaults(tbug.savedVars, defaults)
    tbug.initColorTable("interfaceColors",  "tbugChanged:interfaceColor")
    tbug.initColorTable("typeColors",       "tbugChanged:typeColor")

    cm:RegisterCallback("tbugChanged:interfaceColor", function(key, color)
        tbug.interfaceColorChanges:FireCallbacks(key, color)
    end)
end

------------------------------------------------------------------------------------------------------------------------
function tbug.saveSearchHistoryEntry(panelKey, searchMode, value)
    if not panelKey or not searchMode then return end
    tbug.savedVars.searchHistory = tbug.savedVars.searchHistory or {}
    tbug.savedVars.searchHistory[panelKey] = tbug.savedVars.searchHistory[panelKey] or {}
    tbug.savedVars.searchHistory[panelKey][searchMode] = tbug.savedVars.searchHistory[panelKey][searchMode] or {}
    --Check if the value is already in the history
    for _,v in ipairs(tbug.savedVars.searchHistory[panelKey][searchMode]) do
        if v == value then return end
    end
    table.insert(tbug.savedVars.searchHistory[panelKey][searchMode], 1, value)
    if #tbug.savedVars.searchHistory[panelKey][searchMode] > 20 then
        table.remove(tbug.savedVars.searchHistory[panelKey][searchMode], 20)
    end
end

function tbug.loadSearchHistoryEntry(panelKey, searchMode)
    if not panelKey or not searchMode then return end
    if tbug.savedVars.searchHistory and tbug.savedVars.searchHistory[panelKey] then
        return tbug.savedVars.searchHistory[panelKey][searchMode]
    end
    return nil
end

function tbug.clearSearchHistory(panelKey, searchMode, idx)
    if not panelKey or not searchMode then return end
    if tbug.savedVars.searchHistory and tbug.savedVars.searchHistory[panelKey] and
        tbug.savedVars.searchHistory[panelKey][searchMode] then
        if idx == nil then
            tbug.savedVars.searchHistory[panelKey][searchMode] = {}
        elseif tbug.savedVars.searchHistory[panelKey][searchMode][idx] ~= nil then
            table.remove(tbug.savedVars.searchHistory[panelKey][searchMode], idx)
        end
    end
    return nil
end


------------------------------------------------------------------------------------------------------------------------
--The inspector tabs are: tbug.inspectorWindows[inspectorId].tabs[number].panel.subject (=is the control that got inspected)
-->Problems: How to define which tabs to keep, and how long?
--> Only firstInspector tabs can be saved as we need to re-open the tabs via tbug.inspect to properly show the "current" contents
--> and they will open at the first inspector then
--> How to clean last saved/set the time to keep the tabs etc.
--[[
function tbug.saveOpenedTabsHistoryEntry(inspectorId, panelKey, panelData)
    tbug.savedVars.openedTabHistory = tbug.savedVars.openedTabHistory or {}
    tbug.savedVars.openedTabHistory[inspectorId] = tbug.savedVars.openedTabHistory[inspectorId] or {}
    tbug.savedVars.openedTabHistory[inspectorId][panelKey] = panelData
end

function tbug.loadOpenedTabsHistoryEntry(inspectorId, panelKey)
    if not inspectorId or not panelKey then return end
    if tbug.savedVars.openedTabHistory and tbug.savedVars.openedTabHistory[inspectorId] and tbug.savedVars.openedTabHistory[panelKey] then
        return tbug.savedVars.openedTabHistory[panelKey]
    end
    return nil
end

function tbug.clearOpenedTabsHistory(inspectorId, panelKey)
    if not inspectorId or not panelKey then return end
    if tbug.savedVars.openedTabHistory and tbug.savedVars.openedTabHistory[inspectorId] then
        if panelKey == nil then
            tbug.savedVars.openedTabHistory[inspectorId] = {}
        elseif tbug.savedVars.openedTabHistory[inspectorId][panelKey] ~= nil then
            tbug.savedVars.openedTabHistory[inspectorId][panelKey] = nil
        end
    end
    return nil
end
]]