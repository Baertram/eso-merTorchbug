local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

--local tsort = table.sort

local classes = tbug.classes
local BasicInspector = classes.BasicInspector
local GlobalInspector = classes.GlobalInspector .. BasicInspector

local types = tbug.types
local stringType = types.string
local numberType = types.number
local functionType = types.func
local tableType = types.table
local userDataType = types.userdata
local structType = types.struct

local panelClassName2panelClass = tbug.panelClassNames
local panelNames = tbug.panelNames
local getTBUGGlobalInspectorPanelIdByName = tbug.getTBUGGlobalInspectorPanelIdByName

local tbug_glookup = tbug.glookup

local checkIfItemLinkFunc = tbug.checkIfItemLinkFunc
local sortItemLinkFunctions = tbug.sortItemLinkFunctions

--local customKeysForInspectorRows = tbug.customKeysForInspectorRows

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

--Update the table tbug.panelClassNames with the GlobalInspectorPanel class
tbug.panelClassNames["globalInspector"] = GlobalInspectorPanel


local RT = tbug.RT


function GlobalInspectorPanel:buildMasterList(libAsyncTask)
--d("[TBug]GlobalInspector:buildMasterList")
    self:buildMasterListSpecial()
end



------------------------ Generic functions for panel
function tbug.makePanel(selfClassVar, panelClass, title, panelData)
    if selfClassVar == nil then return end
    local panelClassName
    if panelData ~= nil then
        panelClassName = panelData.panelClassName
        if panelClassName ~= nil and panelClassName ~= "" then
            panelClass = panelClassName2panelClass[panelClassName]
            if panelClass == nil then
                panelClass = GlobalInspectorPanel --fallback: GlobalInspectorPanel
            end
        end
    end
--d("[TB]makePanel-title: " ..tostring(title) .. ", panelClass: " ..tostring(panelClass) .. ", panelClassName: " ..tostring(panelClassName))
    if panelClass == nil then return end

    local panel = selfClassVar:acquirePanel(panelClass)
    --local tabControl = self:insertTab(title, panel, 0)
    selfClassVar:insertTab(title, panel, 0, nil, nil, true, false)
    return panel
end
local tbug_makePanel = tbug.makePanel



---------------------------
-- class GlobalInspector --

function GlobalInspector:__init__(id, control)
    control.isGlobalInspector = true
    BasicInspector.__init__(self, id, control)

    self.conf = tbug.savedTable("globalInspector" .. id)
    self:configure(self.conf)

    self.title:SetText("GLOBALS")

    self.panels = {}

    self.loadingSpinner = control:GetNamedChild("LoadingSpinner")
    self:UpdateLoadingState(not self.g_refreshRunning)

    self:connectPanels(nil, false, false, nil)
    self:selectTab(1)
end

function GlobalInspector:UpdateLoadingState(doHide)
    if self.loadingSpinner == nil then return end
--d("[tbug]GlobalInspector:UpdateLoadingState - doHide: " ..tostring(doHide))
    if doHide then
        self.loadingSpinner:Hide()
    else
        self.loadingSpinner:Show()
    end
    self.loading = not doHide
end


function GlobalInspector:connectFilterComboboxToPanel(tabIndex)
--d("[TBUG]GlobalInspector:connectFilterComboboxToPanel-tabIndex: " ..tostring(tabIndex))
    --Prepare the combobox filters at the panel
    local comboBoxCtrl = self.filterComboBox
    local comboBox = ZO_ComboBox_ObjectFromContainer(comboBoxCtrl)
    --local dropdown = self.filterComboBoxDropdown
    --Clear the combobox/dropdown
    --dropdown:HideDropdownInternal()
    comboBox:ClearAllSelections()
    comboBox:ClearItems()
    self:SetSelectedFilterText()
    comboBoxCtrl:SetHidden(true)
    comboBox.filterMode = nil

    if not tabIndex then return end
    local tabIndexType = type(tabIndex)
    if tabIndexType == numberType then
        --All okay
    elseif tabIndexType == stringType then
        --Get pael's tabIndex number
        tabIndex = getTBUGGlobalInspectorPanelIdByName(tabIndex)
    else
        --Error
        return
    end
    comboBox.filterMode = tabIndex

    local panelData = panelNames[tabIndex]
    if not panelData then return end

    if panelData.comboBoxFilters == true then
        --Get the filter data to add to the combobox - TOOD: Different filters, by panel!
        local filterDataToAdd = tbug.filterComboboxFilterTypesPerPanel[tabIndex]
--TBUG._filterDataToAdd = filterDataToAdd
        if not ZO_IsTableEmpty(filterDataToAdd) then
            --Add the filter data to the combobox's dropdown
            for controlType, controlTypeName in pairs(filterDataToAdd) do
                if type(controlType) == numberType and controlType > -1 then
                    local entry = comboBox:CreateItemEntry(controlTypeName)
                    entry.filterType = controlType
                    comboBox:AddItem(entry)
                end
            end
        end
        --Update the (last) selected entries (if any filtered before)
        local panelOfComboboxFilter = self.panels[panelData.key] --Get the panel of the tab with tabIndex
        local dropdownFiltersSelected = panelOfComboboxFilter.dropdownFiltersSelected
        local ignoreCallback = true
        if not ZO_IsTableEmpty(dropdownFiltersSelected) then
            for selectedFilterType, wasSelected in pairs(dropdownFiltersSelected) do
                if wasSelected then
--d(">selected comboboxFilter filterType before: " ..tostring(selectedFilterType))
                    comboBox:SetSelectedItemByEval(function(item) return item.filterType == selectedFilterType end, ignoreCallback)
                end
            end
        end
        comboBoxCtrl:SetHidden(false)
    end
end


------------------------ Other functions of the class
function GlobalInspector:makePanel(title, panelData)
    return tbug_makePanel(self, GlobalInspectorPanel, title, panelData)
    --[[
    local panelClass = GlobalInspectorPanel
    local panelClassName
    if panelData ~= nil then
        panelClassName = panelData.panelClassName
        if panelClassName ~= nil and panelClassName ~= "" then
            panelClass = panelClassName2panelClass[panelClassName]
            if panelClass == nil then
                panelClass = GlobalInspectorPanel --fallback: GlobalInspectorPanel
            end
        end
    end
--d("[TB]makePanel-title: " ..tostring(title) .. ", panelClass: " ..tostring(panelClass) .. ", panelClassName: " ..tostring(panelClassName))

    local panel = self:acquirePanel(panelClass)
    --local tabControl = self:insertTab(title, panel, 0)
    self:insertTab(title, panel, 0, nil, nil, true, false)
    return panel
    ]]
end

function GlobalInspector:connectPanels(panelName, rebuildMasterList, releaseAllTabs, tabIndex)
--d("[TBug]GlobalInspector:connectPanels - panelName: " .. tostring(panelName) ..", rebuildMasterList: " .. tostring(rebuildMasterList))
    rebuildMasterList = rebuildMasterList or false
    releaseAllTabs = releaseAllTabs or false
    if not self.panels then return end
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
            self.panels[v.key] = self:makePanel(v.name, v)
            --[[
            --Do not refresh ALL panels in the loop each time!
            if rebuildMasterList == true then
                self:refresh()
            end
            ]]
        --Use the tab's name / or at creation of all tabs -> we will get here
        else
            if panelName and panelName ~= "" then
                if v.name == panelName then
                    self.panels[v.key] = self:makePanel(v.name, v)
                    --[[
                    --Do not refresh ALL panels here. They should be refreshed either way as their tab gets selected?!
                    if rebuildMasterList == true then
                        self:refresh()
                    end
                    ]]
                    return
                end
            else
                --Create all the tabs
                self.panels[v.key] = self:makePanel(v.name, v)
            end
        end
    end

    if rebuildMasterList == true then
--d(">[TBug]GlobalInspector:connectPanels -> Calling refresh of all tabs!")
        self:refresh()
    end
end

local function pushToMasterlist(masterList, dataType, key, value)
    local data = {key = key, value = value}
    local n = #masterList + 1
    masterList[n] = ZO_ScrollList_CreateDataEntry(dataType, data)
end

function GlobalInspector:refresh()
--d("[TBug]GlobalInspector:refresh")

    local panels       = self.panels
    local panelClasses = panels.classes:clearMasterList(_G) --Set's the subject to _G
    local controls     = panels.controls:clearMasterList(_G)  --Set's the subject to _G
    local fonts = panels.fonts:clearMasterList(_G)  --Set's the subject to _G
    local functions = panels.functions:clearMasterList(_G)  --Set's the subject to _G
    local objects = panels.objects:clearMasterList(_G)  --Set's the subject to _G
    local constants = panels.constants:clearMasterList(_G)  --Set's the subject to _G

    local itemLinkFunctionsUpdated = false

    local svTabs = tbug.SavedVariablesTabs
    if ZO_IsTableEmpty(svTabs) then
        tbug.refreshSavedVariablesTable()
        svTabs = tbug.SavedVariablesTabs
    end

    local lookupTabClass = tbug.LookupTabs["class"]
    local lookupTabObject = tbug.LookupTabs["object"]
    --Do not reset the tables here as entries once added should stay until reloadUI!
    --local lookupTabLibrary = tbug.LookupTabs["library"]
    --lookupTabClass = {}
    --lookupTabObject = {}
    --lookupTabLibrary = {}

    --Refresh ALL tab's data!
    for k, v in zo_insecureNext, _G do
        local tv = type(v)
        if tv == userDataType or tv == structType then
            if v.IsControlHidden then
                pushToMasterlist(controls, RT.GENERIC, k, v)
            elseif v.GetFontInfo then
                pushToMasterlist(fonts, RT.FONT_OBJECT, k, v)
            else
                pushToMasterlist(objects, RT.GENERIC, k, v)
            end
        elseif tv == tableType then
            if rawget(v, "__index") then
                --v[isClassKey] = true
                local classTabName = tbug_glookup(v)
                if type(classTabName) == stringType then
                    lookupTabClass[classTabName] = true
                end

                pushToMasterlist(panelClasses, RT.GENERIC, k, v)
            else
                --Do not add __isObject = true to a SavedVariables table
                --todo 20250102 Detect SavedVariables more reliably, like MasterMerchant etc. or do not add __isObject anymore to each table.
                if svTabs and svTabs[v] == nil and v ~= _G and v ~= EsoStrings then
                    --v[isObjectKey] = true
                    --would make detection of objects slower then as it needs to always check each table, as the contextMenu opens, if it is an object
                    local objectTabName = tbug_glookup(v)
                    if type(objectTabName) == stringType then
                        lookupTabObject[objectTabName] = true
                    end
                --else
--d(">found SV table - k: " .. tostring(k) .. ", v: " .. tostring(v))
                end

                pushToMasterlist(objects, RT.GENERIC, k, v)
            end
        elseif tv == functionType then
            pushToMasterlist(functions, RT.GENERIC, k, v)
            --Check if functionName is starting with IsItemLink or GetItemLink or CheckItemLink or *Itemlink*
            --and add them to the itemLinkFunctions table for later context menu usage
            -->Will add it to tbug.functionsItemLink
            local l_updated = checkIfItemLinkFunc(k, v) --> Should have been filled in glookup.lua already while parsing the _G table. Only adding missing ones here
            if l_updated == true then itemLinkFunctionsUpdated = true end
        elseif tv ~= stringType or type(k) ~= stringType then
            pushToMasterlist(constants, RT.GENERIC, k, v)
        elseif IsPrivateFunction(k) then
            pushToMasterlist(functions, RT.GENERIC, k, "function: |cFF0000private|r")
        elseif IsProtectedFunction(k) then
            pushToMasterlist(functions, RT.GENERIC, k, "function: |c0000D2protected|r")
        else
            pushToMasterlist(constants, RT.GENERIC, k, v)
        end
    end

    if itemLinkFunctionsUpdated == true then
        sortItemLinkFunctions()
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

    tbug.refreshSavedInspectors()
    panels.savedInsp:bindMasterList(tbug.SavedInspectorsData, RT.SAVEDINSPECTORS_TABLE)

    for _, panel in next, panels do
        panel:refreshData()
    end
end


function GlobalInspector:release()
    -- do not release anything
    if not self.control or not self.control.SetHidden then return end
    self.control:SetHidden(true)
end