local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")
local tos = tostring
local type = type
--local zo_ls = zo_loadstring

local tins = table.insert
local trem = table.remove

local RT                 = tbug.RT
local RT_savedInspectors = RT.SAVEDINSPECTORS_TABLE

local tbug_slashCommand = tbug.slashCommand
local tbug_addSavedInspectors = tbug.addSavedInspectors

local typeColors = tbug.cache.typeColors

local tbug_truncate = tbug.truncate
local tbug_specialKeyToColorType = tbug.specialKeyToColorType

local tbug_inspect = tbug.inspect
local tbug_checkIfInspectorPanelIsShown = tbug.checkIfInspectorPanelIsShown

--------------------------------

local function loadSavedInspectorsByClick(selfVar, row, data)
tbug._rowClickedSavedInspectors = row
tbug._dataClickedSavedInspectors = data
    local value = data.value
    local dataEntry = data.dataEntry
    if value ~= nil and type(value) == "table" and dataEntry ~= nil and dataEntry.typeId == RT_savedInspectors then
        --Load the clicked inspector windows
        local savedWindowsData = {}
        for windowIdx, savedInspectorWindowData in ipairs(value) do
            for idx, savedTabData in ipairs(savedInspectorWindowData) do
                local window = savedTabData.window
                window = window or 1
                savedWindowsData[window] = savedWindowsData[window] or {}
                tins(savedWindowsData[window], savedTabData.name)
            end
        end
        if ZO_IsTableEmpty(savedWindowsData) then return end

--tbug._savedWindowsData = savedWindowsData
        local windowsOpened = 0
        for windowNr, objectData in ipairs(savedWindowsData) do
            windowsOpened = windowsOpened + 1
            for idx, objectName in ipairs(objectData) do
                if objectName ~= nil and objectName ~= "" and objectName ~= "_G" then
--d(">window: " .. tos(windowNr) .. ", objectName: " ..tos(objectName))
                    if windowsOpened == 1 then
                        tbug.slashCommand(objectName)
                    else
                        --object, tabTitle, winTitle, recycleActive, objectParent, currentResultIndex, allResults, data, searchData, isMOC, wasClickedAtGlobalInspector
                        if _G[objectName] ~= nil then
                            local inspector = tbug_inspect(_G[objectName], nil, objectName, false, nil, nil, nil, data, nil, false, nil)
                            if inspector then
                                inspector.control:BringWindowToTop()
                            end
                        else
                            tbug.slashCommand(objectName)
                        end
                    end
                end
            end
        end
    end
end

--Get opened inspectors and their subjects
function tbug.getCurrentInspectorsAndSubjects()
    local subjectNamesTable
    local globalInspector = tbug.getGlobalInspector(true)

    local firstInspector = tbug.firstInspector
    if firstInspector ~= nil then
--d(">firstInspector")
        local subjectsTable = firstInspector:GetAllTabSubjects()
        if not ZO_IsTableEmpty(subjectsTable) then
            subjectNamesTable = { [1] = {} }
            for idx, object in ipairs(subjectsTable) do
                local name
                if tbug.isControl(object) then
                    name = tbug.getControlName(object)
                else
                    name = tbug.getRelevantNameForCall(object)
                end
--d(">idx: " ..tos(idx) .. ", name: " ..tos(name))
                if name ~= nil and name ~= "" then
                    tins(subjectNamesTable[1],  {
                        window  =   1,
                        name    =   name,
                    })
                end
            end
        end
    end

    local inspectorWindows = tbug.inspectorWindows
    if #inspectorWindows > 0 then
        for windowIdx, windowData in ipairs(inspectorWindows) do
--d(">inspectorWindows " ..tos(windowIdx))
            if (globalInspector == nil or (windowData ~= globalInspector))
             and (firstInspector == nil or (windowData ~= firstInspector)) then
                local subjectsTable = windowData:GetAllTabSubjects()
                if not ZO_IsTableEmpty(subjectsTable) then
                    local windowName = windowData.control:GetName()
--d(">windowName: " ..tos(windowName))
                    local windowNr = windowName:match('%d+') or windowIdx
                    windowNr = tonumber(windowNr)

                    if subjectNamesTable == nil then
                        subjectNamesTable = { [1] = {} }
                        windowNr = 1
                    else
                        subjectNamesTable[windowNr] = {}
                    end

                    for idx, object in ipairs(subjectsTable) do
                        local name
                        if tbug.isControl(object) then
                            name = tbug.getControlName(object)
                        else
                            name = tbug.getRelevantNameForCall(object)
                        end
--d(">>windowNr: " .. tos(windowNr) ..", idx: " ..tos(idx) .. ", name: " ..tos(name))
                        if name ~= nil and name ~= "" then
                            tins(subjectNamesTable[windowNr],  {
                                window  =   tonumber(windowNr),
                                name    =   name,
                            })
                        end
                    end
                end
            end
        end
    end
    return subjectNamesTable
end
local getCurrentInspectorsAndSubjects = tbug.getCurrentInspectorsAndSubjects

--Save the currently opened inspectors -> their subjects to the SV
function tbug.saveCurrentInspectorsAndSubjects()
    local currentlyOpenedInspectorSubjects = getCurrentInspectorsAndSubjects()
    if ZO_IsTableEmpty(currentlyOpenedInspectorSubjects) then return end

    local savedInspectors = tbug.savedVars.savedInspectors
    local numSavedInspectors = #savedInspectors or 0
    numSavedInspectors = numSavedInspectors + 1
    tbug.savedVars.savedInspectors[numSavedInspectors] = currentlyOpenedInspectorSubjects
end


--Get a saved inspectors comment
function tbug.getSavedInspectorsComment(savedInspectorsRowId)
    if savedInspectorsRowId == nil then return end
    if tbug.savedVars and tbug.savedVars.savedInspectorsComments then
        return tbug.savedVars.savedInspectorsComments[savedInspectorsRowId]
    end
    return
end
local getSavedInspectorsComment = tbug.getSavedInspectorsComment

--Add/Change a saved inspectors text or comment
function tbug.changeSavedInspectors(savedInspectorsRowId, editBox, savedInspectorsOrCommentText, doNotRefresh)
    doNotRefresh = doNotRefresh or false
    if savedInspectorsRowId == nil or savedInspectorsOrCommentText == nil then return end
    if not editBox or not editBox.updatedColumnIndex then return end
    if not tbug.savedVars then return end

    local updatedColumnIndex = editBox.updatedColumnIndex
    if savedInspectorsOrCommentText == "" then savedInspectorsOrCommentText = nil end

    --Update the entry
    if updatedColumnIndex == 1 then
        if savedInspectorsOrCommentText == nil and tbug.savedVars.savedInspectors and tbug.savedVars.savedInspectors[savedInspectorsRowId] then
            trem(tbug.savedVars.savedInspectors, savedInspectorsRowId)
        end

    --Update the comment
    elseif updatedColumnIndex == 2 then
        if tbug.savedVars.savedInspectorsComments then
            if savedInspectorsOrCommentText == "" then savedInspectorsOrCommentText = nil end
            if not savedInspectorsOrCommentText then
                --Only remove the comment
                trem(tbug.savedVars.savedInspectorsComments, savedInspectorsRowId)
            else
                tbug.savedVars.savedInspectorsComments[savedInspectorsRowId] = savedInspectorsOrCommentText
            end
        end
    end
    --is the saved inspectors panel currently shown? Then update it
    if not doNotRefresh then
        if tbug_checkIfInspectorPanelIsShown("globalInspector", "savedInsp") then
            tbug.refreshInspectorPanel("globalInspector", "savedInsp")
            --Todo: Again the problem with non-updated table columns that's why the refresh is done twice for the non-direct SavedVariables update
            --column
            if updatedColumnIndex == 1 then
                tbug.refreshInspectorPanel("globalInspector", "savedInsp")
            end
        end
    end
end
local changeSavedInspectors = tbug.changeSavedInspectors

-------------------------------
-- class SavedInspectorsPanel --

local classes = tbug.classes
local TableInspectorPanel = classes.TableInspectorPanel
local SavedInspectorsPanel = classes.SavedInspectorsPanel .. TableInspectorPanel

SavedInspectorsPanel.CONTROL_PREFIX = "$(parent)PanelSavedInspectors"
SavedInspectorsPanel.TEMPLATE_NAME = "tbugSavedInspectorsPanel"

--Update the table tbug.panelClassNames with the SavedInspectorsPanel class
tbug.panelClassNames["savedInspectors"] = SavedInspectorsPanel


function SavedInspectorsPanel:__init__(control, ...)
    TableInspectorPanel.__init__(self, control, ...)
--d("[tbug]SavedInspectorsPanel:Init")
end


function SavedInspectorsPanel:bindMasterList(editTable, specialMasterListID)
--d("[tbug]SavedInspectorsPanel:bindMasterList")
    self.subject = editTable
    self.specialMasterListID = specialMasterListID
end


function SavedInspectorsPanel:buildMasterList()
--d("[tbug]SavedInspectorsPanel:buildMasterList")
    self:buildMasterListSpecial()
end


function SavedInspectorsPanel:buildMasterListSpecial()
    local editTable = self.subject
    local specialMasterListID = self.specialMasterListID
--d(string.format("[tbug]SavedInspectorsPanel:buildMasterListSpecial - specialMasterListID: %s", tos(specialMasterListID)))

    if rawequal(editTable, nil) then
        return true
    elseif (specialMasterListID and specialMasterListID == RT.SAVEDINSPECTORS_TABLE) or rawequal(editTable, tbug.SavedInspectorsData) then
        tbug.refreshSavedInspectors()
        self:bindMasterList(tbug.SavedInspectorsData, RT.SAVEDINSPECTORS_TABLE)
        self:populateMasterList(editTable, RT.SAVEDINSPECTORS_TABLE)
    else
        return false
    end
    return true
end


function SavedInspectorsPanel:canEditValue(data)
    local dataEntry = data.dataEntry
    if not dataEntry then return false end
    local typeId = dataEntry.typeId
    return typeId == RT.SAVEDINSPECTORS_TABLE
end


function SavedInspectorsPanel:clearMasterList(editTable)
    local masterList = self.masterList
    tbug_truncate(masterList, 0)
    self.subject = editTable
    return masterList
end


function SavedInspectorsPanel:initScrollList(control)
    TableInspectorPanel.initScrollList(self, control)

--d("SavedInspectorsPanel:initScrollList")

    --Check for special key colors!
    local function checkSpecialKeyColor(keyValue)
        if keyValue == "event" or not tbug_specialKeyToColorType then return end
        local newType = tbug_specialKeyToColorType[keyValue]
        return newType
    end

    local function setupValue(cell, typ, val, isKey)
        isKey = isKey or false
        cell:SetColor(typeColors[typ]:UnpackRGBA())
        cell:SetText(tos(val))
    end

    local function setupCommon(row, data, list, font)
        local k = data.key
        local tk = data.meta and "event" or type(k)
        local tkOrig = tk
        tk = checkSpecialKeyColor(k) or tkOrig

        self:setupRow(row, data)
        if row.cKeyLeft then
            setupValue(row.cKeyLeft, tk, k, true)
            if font and font ~= "" then
                row.cKeyLeft:SetFont(font)
            end
        end
        if row.cKeyRight then
            setupValue(row.cKeyRight, tk, "", true)
        end

        return k, tkOrig
    end

    local function setupSavedInspectors(row, data, list)
--d(">setupSavedInspectors")
        local k, tk = setupCommon(row, data, list)
        local v = data.value
        local tv = type(v)

--d(">>tv: " ..tos(tv) .. "; k: " ..tos(k) .. "; key: " ..tos(data.key))

        row.cVal:SetText("")
        if tv == "string" then
            setupValue(row.cVal, tv, v)
        else
            if tv == "table" then
                local tooltipOutput = {}
                local tooltipText = ""
                local tooltipLine = ""
                --Loop all saved windows of the inspectors for the entry and build 1 table per window
                for windowIdx, windowData in ipairs(v) do
                    for nr, subjectData in ipairs(windowData) do
                        local windowNr = subjectData.window
                        tooltipOutput[windowNr] = tooltipOutput[windowNr] or {}
                        tins(tooltipOutput[windowNr], { nr=nr, name=subjectData.name })
                    end
                end
tbug._debugTooltipOutput = tooltipOutput
                if not ZO_IsTableEmpty(tooltipOutput) then
                    --Build a tooltip for the row to show all subjects of the saved tabs of that inspector window
                    for windowNr, windowData in ipairs(tooltipOutput) do
                        if tooltipText ~= "" then
                            tooltipText = tooltipText .. "\n"
                            tooltipLine = tooltipLine .. "/"
                        end
                        tooltipText = tooltipText .. "Inspector #" .. tos(windowNr) .. ": "
                        tooltipLine = tooltipLine .. "Inspector #" .. tos(windowNr) .. ": "
                        for _, subjectData in ipairs(windowData) do
                            local nr = subjectData.nr
                            local subjectEntryStr = "[" ..tos(nr) .."]" .. tos(subjectData.name)
                            tooltipText = tooltipText .. subjectEntryStr
                            tooltipLine = tooltipLine .. subjectEntryStr
                            if nr < #windowData then
                                tooltipText = tooltipText .. "\n"
                                tooltipLine = tooltipLine .. ";"
                            end
                        end
                    end
                end
                if tooltipText ~= "" then
                    row.tooltip = tooltipText
                    data.tooltip = tooltipText
                    row.tooltipLine = tooltipLine
                    data.tooltipLine = tooltipLine
                end
                setupValue(row.cVal, "string", tooltipLine)
            end
        end
        if row.cVal2 then
            row.cVal2:SetText("")
            v = nil
            v = getSavedInspectorsComment(data.key)
            if v ~= nil and v ~= "" then
                setupValue(row.cVal2, "comment", v)
            end
        end
    end

    local function hideCallback(row, data)
        if self.editData == data then
            self.editBox:ClearAnchors()
            self.editBox:SetAnchor(BOTTOMRIGHT, nil, TOPRIGHT, 0, -20)
        end
    end

    self:addDataType(RT.SAVEDINSPECTORS_TABLE,    "tbugTableInspectorRowSavedInspectors",   40, setupSavedInspectors, hideCallback)
end


--Clicking on a tables index (e.g.) 6 should not open a new tab called 6 but tableName[6] instead
function SavedInspectorsPanel:BuildWindowTitleForTableKey(data)
    local winTitle
    if data.key and type(tonumber(data.key)) == "number" then
        winTitle = self.inspector.activeTab.label:GetText()
        if winTitle and winTitle ~= "" then
            winTitle = tbug.cleanKey(winTitle)
            winTitle = winTitle .. "[" .. tos(data.key) .. "]"
--d(">tabTitle: " ..tos(tabTitle))
        end
    end
    return winTitle
end


function SavedInspectorsPanel:onRowClicked(row, data, mouseButton, ctrl, alt, shift)
--d("[tbug]SavedInspectorsPanel:onRowClicked")
    if mouseButton == MOUSE_BUTTON_INDEX_RIGHT then
        TableInspectorPanel.onRowClicked(self, row, data, mouseButton, ctrl, alt, shift)
    else
        if mouseButton == MOUSE_BUTTON_INDEX_LEFT then
            if MouseIsOver(row.cKeyLeft) then
                loadSavedInspectorsByClick(self, row, data)
            elseif MouseIsOver(row.cVal) then
                loadSavedInspectorsByClick(self, row, data)
            end
        end
    end
end

function SavedInspectorsPanel:onRowDoubleClicked(row, data, mouseButton, ctrl, alt, shift)
--df("tbug:SavedInspectorsPanel:onRowDoubleClicked")
    --[[
    ClearMenu()
    if mouseButton == MOUSE_BUTTON_INDEX_LEFT then
        local sliderCtrl = self.sliderControl

        local value = data.value
        local typeValue = type(value)
        if MouseIsOver(row.cVal) then
            if sliderCtrl ~= nil then
                sliderCtrl.panel:valueSliderCancel(sliderCtrl)
            end
            if self:canEditValue(data) then
                if typeValue == "string" then
                    if value ~= "" and data.dataEntry.typeId == RT.SAVEDINSPECTORS_TABLE then

                    end
                end
            end
        end
    end
    ]]
end

function SavedInspectorsPanel:populateMasterList(editTable, dataType)
    local masterList, n = self.masterList, 0
    for k, v in next, editTable do
        n = n + 1
        local data = {key = k, value = v}
        masterList[n] = ZO_ScrollList_CreateDataEntry(dataType, data)
    end
    return tbug_truncate(masterList, n)
end

--[[
function SavedInspectorsPanel:valueEditStart(editBox, row, data)
    d("SavedInspectorsPanel:valueEditStart")
    ObjectInspectorPanel.valueEditStart(self, editBox, row, data)
end
]]

function SavedInspectorsPanel:valueEditConfirmed(editBox, evalResult)
    local editData = self.editData
    --d(">editBox.updatedColumnIndex: " .. tos(editBox.updatedColumnIndex))
    local function confirmEditBoxValueChange(p_setIndex, p_editTable, p_key, p_evalResult)
        local l_ok, l_setResult = pcall(p_setIndex, p_editTable, p_key, p_evalResult)
        return l_ok, l_setResult
    end

    if editData then
        local editTable = editData.meta or self.subject
        local updateSpecial = false
        if editBox.updatedColumn ~= nil and editBox.updatedColumnIndex ~= nil then
            updateSpecial = true
        end
        if updateSpecial == false then
            local ok, setResult = confirmEditBoxValueChange(tbug.setindex, editTable, editData.key, evalResult)
            if not ok then return setResult end
            self.editData = nil
            editData.value = setResult
        else
            local typeId = editData.dataEntry.typeId
            --Update comment
            if typeId and typeId == RT.SAVEDINSPECTORS_TABLE then
                changeSavedInspectors(editData.dataEntry.data.key, editBox, evalResult) --Use the row's dataEntry.data table for the key or it will be the wrong one after scrolling!
                editBox.updatedColumn:SetHidden(false)
                if evalResult == "" then
                    editBox.updatedColumn:SetText("")
                end
            --TypeId not given or generic
            elseif (not typeId or typeId == RT.GENERIC) then
                local ok, setResult = confirmEditBoxValueChange(tbug.setindex, editTable, editData.key, evalResult)
                if not ok then return setResult end
                self.editData = nil
                editData.value = setResult
            end
        end
        -- refresh only the edited row
        ZO_ScrollList_RefreshVisible(self.list, editData)
    end
    editBox:LoseFocus()
    editBox.updatedColumn = nil
    editBox.updatedColumnIndex = nil
end