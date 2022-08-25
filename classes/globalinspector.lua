local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

local strfind = string.find
local strformat = string.format
local strlower = string.lower
local strmatch = string.match
local tos = tostring

local throttledCall = tbug.throttledCall

local classes = tbug.classes
local BasicInspector = classes.BasicInspector
local GlobalInspector = classes.GlobalInspector .. BasicInspector
local TextButton = classes.TextButton

local checkForSpecialDataEntryAsKey = tbug.checkForSpecialDataEntryAsKey
local isAControlOfTypes = tbug.isAControlOfTypes
local filterModes = tbug.filterModes

local noFilterSelectedText = "No filter selected"
local filterSelectedText = "<<1[One filter selected/$d filters selected]>>"

--------------------------------
-- Search history
--[[
local function getFilterMode(selfVar)
    --Get the active search mode
    return selfVar.filterModeButton:getId()
end

local function getActiveTabName(selfVar)
    --Get the globalInspectorObject and the active tab name
    local globalInspectorObject = selfVar or tbug.getGlobalInspector()
    if not globalInspectorObject then return end
    local panels = globalInspectorObject.panels
    if not panels then return end
    local activeTab = globalInspectorObject.activeTab
    if not activeTab then return end
    local activeTabName = activeTab.label:GetText()
    return activeTabName, globalInspectorObject
end

local function getSearchHistoryData(globalInspectorObject)
    --Get the active search mode
    local activeTabName
    activeTabName, globalInspectorObject = getActiveTabName(globalInspectorObject)
    local filterMode = getFilterMode(globalInspectorObject)
    return globalInspectorObject, filterMode, activeTabName
end


local function updateSearchHistoryContextMenu(editControl, globalInspectorObject, isGlobalInspector)
    local filterMode, activeTabName
    if not isGlobalInspector then return end

    globalInspectorObject, filterMode, activeTabName = getSearchHistoryData(globalInspectorObject)
    if not activeTabName or not filterMode then return end
    local searchHistoryForPanelAndMode = tbug.loadSearchHistoryEntry(activeTabName, filterMode)
    --local isSHNil = (searchHistoryForPanelAndMode == nil) or false
    if searchHistoryForPanelAndMode ~= nil and #searchHistoryForPanelAndMode > 0 then
        --Clear the context menu
        ClearMenu()
        --Search history
        local filterModeStr = filterModes[filterMode]
        if MENU_ADD_OPTION_HEADER ~= nil then
            AddCustomMenuItem(strformat("- Search history \'%s\' -", tos(filterModeStr)), function() end, MENU_ADD_OPTION_HEADER)
        else
            AddCustomMenuItem("-", function() end)
        end
        for _, searchTerm in ipairs(searchHistoryForPanelAndMode) do
            if searchTerm ~= nil and searchTerm ~= "" then
                AddCustomMenuItem(searchTerm, function()
                    editControl.doNotRunOnChangeFunc = true
                    editControl:SetText(searchTerm)
                    globalInspectorObject:updateFilter(editControl, filterMode)
                end)
            end
        end
        --Actions
        AddCustomMenuItem("-", function() end)
        if MENU_ADD_OPTION_HEADER ~= nil then
            AddCustomMenuItem(strformat("Actions", tos(filterModeStr)), function() end, MENU_ADD_OPTION_HEADER)
        end
        --Delete entry
        local subMenuEntriesForDeletion = {}
        for searchEntryIdx, searchTerm in ipairs(searchHistoryForPanelAndMode) do
            local entryForDeletion =
            {
                label = strformat("Delete \'%s\'", tos(searchTerm)),
                callback = function()
                    tbug.clearSearchHistory(activeTabName, filterMode, searchEntryIdx)
                end,
            }
            table.insert(subMenuEntriesForDeletion, entryForDeletion)
        end
        AddCustomSubMenuItem("Delete entry", subMenuEntriesForDeletion)
        --Clear whole search history
        AddCustomMenuItem("Clear whole history", function() tbug.clearSearchHistory(activeTabName, filterMode) end)
        --Show the context menu
        ShowMenu(editControl)
    end
end

local function saveNewSearchHistoryContextMenuEntry(editControl, globalInspectorObject)
    if not editControl then return end
    local searchText = editControl:GetText()
    if not searchText or searchText == "" then return end
    local filterMode, activeTabName
    globalInspectorObject, filterMode, activeTabName = getSearchHistoryData(globalInspectorObject)
    if not activeTabName or not filterMode then return end
    tbug.saveSearchHistoryEntry(activeTabName, filterMode, searchText)
end
]]

--------------------------------

function tbug.getGlobalInspector(doNotCreate)
    doNotCreate = doNotCreate or false
    local inspector = tbug.globalInspector
    if not inspector and doNotCreate == false then
        inspector = GlobalInspector(1, tbugGlobalInspector)
        tbug.globalInspector = inspector
    end
    return inspector
end

--------------------------------
-- class GlobalInspectorPanel --
local TableInspectorPanel = classes.TableInspectorPanel
local GlobalInspectorPanel = classes.GlobalInspectorPanel .. TableInspectorPanel

GlobalInspectorPanel.CONTROL_PREFIX = "$(parent)PanelG"
GlobalInspectorPanel.TEMPLATE_NAME = "tbugTableInspectorPanel"

local RT = tbug.RT


function GlobalInspectorPanel:buildMasterList()
    self:buildMasterListSpecial()
end


---------------------------
-- class GlobalInspector --

function GlobalInspector:__init__(id, control)
    control.isGlobalInspector = true
    BasicInspector.__init__(self, id, control)

    self.conf = tbug.savedTable("globalInspector" .. id)
    self:configure(self.conf)

    self.title:SetText("GLOBALS")

    self.panels = {}
    self:connectPanels(nil, false, false, nil)
    self:selectTab(1)
end


function GlobalInspector:connectFilterComboboxToPanel(tabIndex)
--d("[TBUG]GlobalInspector:connectFilterComboboxToPanel-tabIndex:" ..tostring(tabIndex))
    --Prepare the combobox filters at the panel
    local comboBox = self.filterComboBox
    local dropdown = self.filterComboBoxDropdown
    --Clear the combobox/dropdown
    --dropdown:HideDropdownInternal()
    dropdown:ClearAllSelections()
    dropdown:ClearItems()
    self:SetSelectedFilterText()
    comboBox:SetHidden(true)
    comboBox.filterMode = nil

    if not tabIndex then return end
    local tabIndexType = type(tabIndex)
    if tabIndexType == "number" then
        --All okay
    elseif tabIndexType == "string" then
        --Get number
        for k,v in ipairs(tbug.panelNames) do
            if v.key == tabIndex or v.name == tabIndex then
                tabIndex = k
                break
            end
        end
    else
        --Error
        return
    end
    comboBox.filterMode = tabIndex

    local panelData = tbug.panelNames[tabIndex]
    if not panelData then return end

    if panelData.comboBoxFilters == true then
        --Get the filter data to add to the combobox - TOOD: Different filtrs by panel!
        local filterDataToAdd = tbug.filterComboboxFilterTypesPerPanel[tabIndex]
--TBUG._filterDataToAdd = filterDataToAdd
        --Add the filter data to the combobox's dropdown
        for controlType, controlTypeName in pairs(filterDataToAdd) do
            if type(controlType) == "number" and controlType > -1 then
                local entry = dropdown:CreateItemEntry(controlTypeName)
                entry.filterType = controlType
                dropdown:AddItem(entry)
            end
        end
        comboBox:SetHidden(false)
    end
end


------------------------ Other functions of the class
function GlobalInspector:makePanel(title)
--d("[TB]makePanel-title: " ..tos(title))
    local panel = self:acquirePanel(GlobalInspectorPanel)
    --local tabControl = self:insertTab(title, panel, 0)
    self:insertTab(title, panel, 0, nil, nil, true)
    return panel
end

function GlobalInspector:connectPanels(panelName, rebuildMasterList, releaseAllTabs, tabIndex)
    rebuildMasterList = rebuildMasterList or false
    releaseAllTabs = releaseAllTabs or false
    if not self.panels then return end
    local panelNames = tbug.panelNames
    if releaseAllTabs == true then
        self:removeAllTabs()
    end
    for idx,v in ipairs(panelNames) do
        if releaseAllTabs == true then
            self.panels[v.key]:release()
        end
        --Use the fixed tabIndex instead of the name? For e.g. tabs where the text on the tab does not match the key (sv <-> SV, or Sv entered as slash command /tbug sv to re-create the tab)
        if tabIndex ~= nil and idx == tabIndex then
            --d(">connectPanels-panelName: " ..tos(panelName) .. ", tabIndex: " ..tos(tabIndex))
            --d(">>make panel for v.key: " ..tos(v.key) .. ", v.name: " ..tos(v.name))
            self.panels[v.key] = self:makePanel(v.name)
            if rebuildMasterList == true then
                self:refresh()
            end
        --Use the tab's name / or at creation of all tabs -> we will get here
        else
            if panelName and panelName ~= "" then
                if v.name == panelName then
                    self.panels[v.key] = self:makePanel(v.name)
                    if rebuildMasterList == true then
                        self:refresh()
                    end
                    return
                end
            else
                --Create all the tabs
                self.panels[v.key] = self:makePanel(v.name)
            end
        end
    end

    if rebuildMasterList == true then
        self:refresh()
    end
end

function GlobalInspector:refresh()
    local panels       = self.panels
    local panelClasses = panels.classes:clearMasterList(_G)
    local controls     = panels.controls:clearMasterList(_G)
    local fonts = panels.fonts:clearMasterList(_G)
    local functions = panels.functions:clearMasterList(_G)
    local objects = panels.objects:clearMasterList(_G)
    local constants = panels.constants:clearMasterList(_G)

    local function push(masterList, dataType, key, value)
        local data = {key = key, value = value}
        local n = #masterList + 1
        masterList[n] = ZO_ScrollList_CreateDataEntry(dataType, data)
    end

    for k, v in zo_insecureNext, _G do
        local tv = type(v)
        if tv == "userdata" then
            if v.IsControlHidden then
                push(controls, RT.GENERIC, k, v)
            elseif v.GetFontInfo then
                push(fonts, RT.FONT_OBJECT, k, v)
            else
                push(objects, RT.GENERIC, k, v)
            end
        elseif tv == "table" then
            if rawget(v, "__index") then
                push(panelClasses, RT.GENERIC, k, v)
            else
                push(objects, RT.GENERIC, k, v)
            end
        elseif tv == "function" then
            push(functions, RT.GENERIC, k, v)
        elseif tv ~= "string" or type(k) ~= "string" then
            push(constants, RT.GENERIC, k, v)
        elseif IsPrivateFunction(k) then
            push(functions, RT.GENERIC, k, "function: private")
        elseif IsProtectedFunction(k) then
            push(functions, RT.GENERIC, k, "function: protected")
        else
            push(constants, RT.GENERIC, k, v)
        end
    end

    --Also check TableInspectorPanel:buildMasterListSpecial() for the special types of masterLists!
    panels.dialogs:bindMasterList(_G.ESO_Dialogs, RT.GENERIC)
    panels.strings:bindMasterList(_G.EsoStrings, RT.LOCAL_STRING)
    panels.sounds:bindMasterList(_G.SOUNDS, RT.SOUND_STRING)

    tbug.refreshScenes()
    panels.scenes:bindMasterList(tbug.ScenesOutput, RT.SCENES_TABLE) --_G.SCENE_MANAGER.scenes
    panels.fragments:bindMasterList(tbug.FragmentsOutput, RT.FRAGMENTS_TABLE)

    panels.libs:bindMasterList(tbug.LibrariesOutput, RT.LIB_TABLE)
    panels.addons:bindMasterList(tbug.AddOnsOutput, RT.ADDONS_TABLE)

    tbug.refreshScripts()
    panels.scriptHistory:bindMasterList(tbug.ScriptsData, RT.SCRIPTHISTORY_TABLE)
    tbug.RefreshTrackedEventsList()
    panels.events:bindMasterList(tbug.Events.eventsTable, RT.EVENTS_TABLE)

    panels.sv:bindMasterList(tbug.SavedVariablesOutput, RT.SAVEDVARIABLES_TABLE)


    for _, panel in next, panels do
        panel:refreshData()
    end
end


function GlobalInspector:release()
    -- do not release anything
    self.control:SetHidden(true)
end