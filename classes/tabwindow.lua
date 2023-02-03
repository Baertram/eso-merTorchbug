local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

local classes = tbug.classes

local TabWindow = classes.TabWindow
local TextButton = classes.TextButton

local startsWith = tbug.startsWith
local endsWith = tbug.endsWith

local tos = tostring
local ton = tonumber
local tins = table.insert
local trem = table.remove
local tcon = table.concat
local strformat = string.format
local strmatch = string.match
local osdate = os.date

local panelData = tbug.panelNames

local filterModes = tbug.filterModes

local noFilterSelectedText = "No filter selected"
local filterSelectedText = "<<1[One filter selected/$d filters selected]>>"

local titlePatterns =       tbug.titlePatterns
local titleMocTemplate =    titlePatterns.mouseOverTemplate

local typeColors = tbug.cache.typeColors

local getControlName = tbug.getControlName
local tbug_glookup = tbug.glookup

local throttledCall = tbug.throttledCall
local FilterFactory = tbug.FilterFactory

------------------------------------------------------------------------------------------------------------------------
local function resetTabControlData(tabControl)
    tabControl.subject = nil
    tabControl.subjectName = nil
    tabControl.parentSubject = nil
    tabControl.parentSubjectName = nil
    tabControl.controlName = nil

    tabControl.isMOC = nil
    tabControl.MOCnumber = nil

    tabControl.titleText = nil
    tabControl.tooltipText = nil

    tabControl.timeStampAdded = nil
    tabControl.timeStampAddedStr = nil

    tabControl.childName = nil

    tabControl.breadCrumbs = nil
    tabControl.breadCrumbsStr = nil
end


local function onMouseEnterShowTooltip(ctrl, text, delay, alignment)
    if not ctrl or not text or (text and text == "") then return end
    alignment = alignment or TOP
    delay = delay or 0
    ctrl.hideTooltip = false
    ZO_Tooltips_HideTextTooltip()
    local function showToolTipNow()
        if ctrl.hideTooltip == true then
            ctrl.hideTooltip = false
            ZO_Tooltips_HideTextTooltip()
            return
        end
        ZO_Tooltips_ShowTextTooltip(ctrl, alignment, text)
    end
    if not delay or (delay and delay == 0) then
        showToolTipNow()
    else
        zo_callLater(function() showToolTipNow() end, delay)
    end
end


local function onMouseExitHideTooltip(ctrl)
    ctrl.hideTooltip = true
    ZO_Tooltips_HideTextTooltip()
end


local function buildTabTitleOrTooltip(tabControl, keyText, isGeneratingTitle)
     isGeneratingTitle = isGeneratingTitle or false
    if tbug.doDebug then
        tbug._tabControl = tabControl
        d("[tb]getTabsSubjectNameAndBuildTabTitle: " ..tos(keyText) .. ", isGeneratingTitle: " ..tos(isGeneratingTitle))
    end

    local keyTextNew = keyText
    if tabControl ~= nil and not tabControl.isGlobalInspector then
        local tabTitleClean = tabControl.titleClean
        local isMOC = tabControl.isMOC
        local gotParentSubject = (tabControl.parentSubject ~= nil and true) or false
        local subject = (gotParentSubject == true and tabControl.parentSubject) or tabControl.subject
        if subject ~= nil then
            local controlName = (tabControl.controlName ~= nil and tabControl.controlName) or getControlName(subject)
            tbug_glookup = tbug_glookup or tbug.glookup
            local lookupName = (((gotParentSubject == true and tabControl.parentSubjectName ~= nil and tabControl.parentSubjectName) or tbug_glookup(tabControl.parentSubject))
                    or ((gotParentSubject == false and tabControl.subjectName ~= nil and tabControl.subjectName) or tbug_glookup(subject))) or nil
            if lookupName ~= nil then
                if gotParentSubject == true and tabControl.parentSubjectName == nil then
                    tabControl.parentSubjectName = lookupName
                elseif tabControl.subjectName == nil then
                    tabControl.subjectName = lookupName
                end
            end

            if tbug.doDebug then d(">lookup: " ..tos(lookupName) .. ", parentSubject: ".. tos(tabControl.parentSubjectName) ..", subject: " ..tos(tabControl.subjectName)) end

            --The title is generated?
            if isGeneratingTitle == true then

                --"Mouse over control" tab? titleClean will just contain the "number" of the tab
                --which leads to e.g. 1.tableName or 2.tableName.__index in the inspector in the end
                --> We will exchange the titleClean variable with the lookupName or controlName here for MOC tabs' titles and tooltips
                if isMOC == true then
                    local titleCleanNumber = ton(tabTitleClean)
                    if type(titleCleanNumber) == "number" then
                        --1st the lookup name as it could contain the parentSubject's name
                        if lookupName ~= nil and lookupName ~= tabTitleClean then
                            tabControl.titleClean = lookupName
                        end
                        --2nd the control name
                        if lookupName == nil and controlName ~= nil and controlName ~= tabTitleClean then
                            tabControl.titleClean = controlName
                        end
                        --NO lookup or controlname? Use the normal titleClean
                        if lookupName == nil and controlName == nil then
                            tabControl.titleClean = tabTitleClean
                        end
                        tabTitleClean = tabControl.titleClean
                    end
                end


                --Are navigation breadCrumbs provided?
                --d("[tb]getTabsSubjectNameAndBuildTabTitle: " ..tos(keyText) .. ", controlName: " ..tos(controlName) .. ", lookupName: " ..tos(lookupName))
                local breadCrumbs = tabControl.breadCrumbs
                if breadCrumbs ~= nil and #breadCrumbs > 0 then
                    --The title string in the end
                    local breadCrumbsStr
                    --d(">#breadCrumbs: " ..tos(#breadCrumbs))
                    local lastBreadCrumbData
                    for breadCrumbsIndex, breadCrumbData in ipairs(breadCrumbs) do
                        local breadCrumbPartStr, isTableIndex, isChild
                        isTableIndex = false
                        isChild = false

                        if breadCrumbData ~= nil then
                            breadCrumbPartStr = ""

                            --From function ControlInspectorPanel:onRowClicked -> data.childName is passed on to the inspector -> then the panel -> and from there to the tabControl created
                            local childName = breadCrumbData.childName
                            isChild = (childName ~= nil and true) or false

                            --titleClean should contain the tab#s title without any trailing [] ("table" indicator)
                            if breadCrumbData.titleClean ~= nil then
                                if tbug.doDebug then tbug._lastBreadCrumbData = lastBreadCrumbData end

                                local clickedDataTitleClean = (isChild == true and childName) or breadCrumbData.titleClean
                                local clickedDataTitleCleanNumber = ton(breadCrumbData.titleClean)

                                --The breadCrumb entry before the current one is known?

                                --Using the referenced breadCrumbData._tabControl will fail if it get's closed! Values will be added to the breadcrumbs directly instead.
                                --local lastBreadCrumbDataTabControl = (lastBreadCrumbData ~= nil and lastBreadCrumbData._tabControl) or nil
                                if lastBreadCrumbData ~= nil then
                                    local subjectOfLastBreadCrumbTabControl = lastBreadCrumbData.subject
                                    local pKeyStrOfLastBreadCrumbTabControl = lastBreadCrumbData.pKeyStr

                                    --Was the breadcrumb subject before a table?
                                    -->And the current breadCrumb is just a number -> Then we assume it's a table "index"
                                    if ( not isChild and (
                                            ( (subjectOfLastBreadCrumbTabControl ~= nil and type(subjectOfLastBreadCrumbTabControl) == "table")
                                                    or (pKeyStrOfLastBreadCrumbTabControl ~= nil and endsWith(pKeyStrOfLastBreadCrumbTabControl, "[]")) )
                                                    and type(clickedDataTitleCleanNumber) == "number" )
                                    ) then
                                        breadCrumbPartStr = "[" .. clickedDataTitleClean .. "]"
                                        isTableIndex      = true
                                    else
                                        breadCrumbPartStr = clickedDataTitleClean
                                    end

                                else
                                    --1st breadcrumb still uses the "number" of the MOC control as titleClean variable
                                    -->Update it to the name of the control now too
                                    if isMOC == true then
                                        breadCrumbData.titleClean = tabTitleClean
                                        breadCrumbPartStr = (isChild == true and childName) or tabTitleClean
                                    else
                                        breadCrumbPartStr = clickedDataTitleClean
                                    end
                                end

                                --Backup data: Generate title by help of the other provided data
                            elseif breadCrumbData.pKeyStr ~= nil then
                                breadCrumbPartStr = breadCrumbData.pKeyStr
                            elseif breadCrumbData.controlName ~= nil then
                                breadCrumbPartStr = breadCrumbData.controlName
                            elseif breadCrumbData.subjectName ~= nil then
                                breadCrumbPartStr = breadCrumbData.subjectName
                            end
                        end

                        --We have build a partial string to add to the total title?
                        -->Add it now
                        if breadCrumbPartStr ~= nil then
                            if breadCrumbsStr == nil then
                                breadCrumbsStr = breadCrumbPartStr
                            else
                                --Part string is no table index
                                if not isTableIndex then
                                    --is the part string a child control of another control?
                                    if isChild == true then
                                        breadCrumbsStr = breadCrumbsStr .. " »Child: " .. breadCrumbPartStr
                                    else
                                        --Part string is not for a child control
                                        breadCrumbsStr = breadCrumbsStr .. "." .. breadCrumbPartStr
                                    end
                                else
                                    --Is the part string added for a table's index?
                                    breadCrumbsStr = breadCrumbsStr .. breadCrumbPartStr
                                end
                            end
                        end
                        --Save the last braedCrumbData for next loop
                        lastBreadCrumbData = breadCrumbData
                    end --end: for .. in (breadCrumbs) do


                    --A total title string based on the breadCrumbs was created?
                    if breadCrumbsStr ~= nil then

                        --Add the controlName or subjectName with a "-" at the end of the title, if the
                        --controlName / subjectName is provided AND they differ from the clickedDataTitleClean
                        if tabTitleClean ~= nil then
                            --Mouse over control at the current tab?
                            -->Add the [MOC_<number>] prefix
                            if isMOC == true then
                                breadCrumbsStr = strformat(titleMocTemplate, tos(tabControl.MOCnumber)) .. " " .. breadCrumbsStr
                            else
                                --No mouse over control at the tab
                                --1st the lookup name as it could contain the parentSubject's name
                                -->If the lookupName is e.g. ALCHEMY and the parentSubject also is ALCHEMY as we currently look at ZO_Alchemy "class"
                                -->via __index metatables -> Add the ALCHEMY parentSubjectName at the end too!
                                local startsWithLookupname = startsWith(breadCrumbsStr, lookupName)
                                if lookupName ~= nil and lookupName ~= tabTitleClean
                                        and (startsWithLookupname == false or startsWithLookupname == true and gotParentSubject == true) then
                                    breadCrumbsStr = breadCrumbsStr .. " - " .. lookupName
                                end
                                --2nd the control name
                                if controlName ~= nil and controlName ~= tabTitleClean and startsWith(breadCrumbsStr, controlName) == false
                                        and (lookupName ~= nil and controlName ~= lookupName) then

                                    --Get the type of the controlName, which could be "table: 00000260ACED39A8" e.g.
                                    local typeOfControl
                                    if startsWith(controlName, "table") then
                                        typeOfControl = "table"
                                    end
                                    if typeOfControl ~= nil and typeColors[typeOfControl] ~= nil then
                                        --local r, g, b, a = typeColors[typeOfControl]:UnpackRGBA()
                                        --typeColors[type(face)]:Colorize(face)
                                        local controlNameColorized = typeColors[typeOfControl]:Colorize(controlName)
                                        breadCrumbsStr = breadCrumbsStr .. " <" .. controlNameColorized .."|r>"
                                    else
                                        breadCrumbsStr = breadCrumbsStr .. " <" .. controlName ..">"
                                    end
                                end
                            end
                        end

                        if tbug.doDebug then d(">breadCrumbsStr: " ..tos(breadCrumbsStr)) end

                        --Update the breadCrumbsStr to the tabControl
                        tabControl.breadCrumbsStr = breadCrumbsStr

                        -- For the moment: Show the breadcrumbs text as the title
                        keyTextNew = breadCrumbsStr
                    end
                end --breadCrumbs are provided?

            else
                --The tooltip is generated?
                --Create the title/tooltiptext from the control or subject name
                if tabControl.breadCrumbsStr ~= nil and tabControl.breadCrumbsStr ~= "" then
                    keyTextNew = tabControl.breadCrumbsStr
                end
            end

        end
    end
    --d("<<keyTextNew: " ..tos(keyTextNew))
    return keyTextNew
end


local function getTabTooltipText(tabWindowObject, tabControl)
--d("[tb]getTabTooltipText")
--tbug._tabObject = tabWindowObject
--tbug._tabControl = tabControl

    if tabWindowObject == nil or tabControl == nil then return end
    local tabLabelText
    --Was the "Get Control Below Mouse" feature used and the tab's text is just the number of MOC tabs?
    tabLabelText = (tabControl.label ~= nil and tabControl.label:GetText()) or nil
--d(">tabLabelText: " ..tos(tabLabelText) .. ", isMOC: " .. tos(tabControl.isMOC))
    if tabControl.isMOC == true and tabLabelText ~= nil and tabLabelText ~= "" then
        tabLabelText = strformat(titleMocTemplate, tos(tabLabelText))
--d(">>tabLabelText MOC: " ..tos(tabLabelText))
    end

    local tooltipText = buildTabTitleOrTooltip(tabControl, tabLabelText, false)
    if tooltipText == nil or tooltipText == "" then
--d(">>>tooltipText is nil")
        tooltipText = (tabControl.tabName or tabControl.pKeyStr or tabControl.pkey or tabLabelText) or nil
    end
--d(">>tooltipText: " ..tos(tooltipText))
    if tooltipText ~= nil and tabLabelText ~= nil and tooltipText == tabLabelText then return end

    --Add the timeStamp info when the tab was added
    local timeStampAddedStr = tabControl.timeStampAddedStr
    if timeStampAddedStr ~= nil then
        timeStampAddedStr = "(" .. timeStampAddedStr .. ")"
        local timestampColorized = typeColors["comment"]:Colorize(timeStampAddedStr) --colorize white
        tooltipText = tooltipText .. " " .. timestampColorized
    end
    return tooltipText
end


local function resetTab(tabControl, selfTab)
    if tabControl.panel then
        tabControl.panel:release()
        tabControl.panel = nil
    end
end


local function getActiveTabPanel(selfVar)
    if not selfVar or not selfVar.activeTab then return end
    return selfVar.activeTab.panel
end

------------------------------------------------------------------------------------------------------------------------
-- Search history
local function getFilterMode(selfVar)
    --Get the active search mode
    return selfVar.filterModeButton:getId()
end

local function getActiveTabNameForSearchHistory(selfVar, isGlobalInspector)
    if isGlobalInspector == nil then isGlobalInspector = selfVar.control.isGlobalInspector end
    isGlobalInspector = isGlobalInspector or false
    --if not isGlobalInspector then return end

    --Get the globalInspectorObject and the active tab name
    local activeTabName
    local inspectorObject = selfVar
    if isGlobalInspector == true then
        inspectorObject = inspectorObject or tbug.getGlobalInspector()
        if not inspectorObject then return end
        local panels = inspectorObject.panels
        if not panels then return end
        local activeTab = inspectorObject.activeTab
        if not activeTab then return end
        activeTabName = activeTab.label:GetText()
    else
        --Other inspectors share the search history for all tabs and use the placeholder "_allTheSame_"
        activeTabName = "_allTheSame_"
    end
--d("getActiveTabName-isGlobalInspector: " ..tos(isGlobalInspector) .. ", activeTabName: " ..tos(activeTabName))
    return activeTabName, inspectorObject
end

local function getSearchHistoryData(inspectorObject, isGlobalInspector)
    if isGlobalInspector == nil then isGlobalInspector = inspectorObject.control.isGlobalInspector end
    isGlobalInspector = isGlobalInspector or false
    --if not isGlobalInspector then return end
    --Get the active search mode
    local activeTabName
    activeTabName, inspectorObject = getActiveTabNameForSearchHistory(inspectorObject, isGlobalInspector)
    local filterMode               = getFilterMode(inspectorObject)
--d("getSearchHistoryData-isGlobalInspector: " ..tos(isGlobalInspector) .. ", activeTabName: " ..tos(activeTabName) .. ", filterMode: " ..tos(filterMode))
    return inspectorObject, filterMode, activeTabName
end


local function updateSearchHistoryContextMenu(editControl, inspectorObject, isGlobalInspector, menuNeedsDivider)
    if isGlobalInspector == nil then isGlobalInspector = inspectorObject.control.isGlobalInspector end
    isGlobalInspector = isGlobalInspector or false
    menuNeedsDivider = menuNeedsDivider or false
    local filterMode, activeTabName
    --if not isGlobalInspector then return end
    --d("updateSearchHistoryContextMenu-isGlobalInspector: " ..tos(isGlobalInspector))
    inspectorObject, filterMode, activeTabName = getSearchHistoryData(inspectorObject, isGlobalInspector)
    if not activeTabName or not filterMode then return end
    local searchHistoryForPanelAndMode = tbug.loadSearchHistoryEntry(activeTabName, filterMode)
    --local isSHNil = (searchHistoryForPanelAndMode == nil) or false
    if searchHistoryForPanelAndMode ~= nil and #searchHistoryForPanelAndMode > 0 then
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
                    inspectorObject:updateFilter(editControl, filterMode, nil, 0)
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
        return true
    end
    return false
end

local function saveNewSearchHistoryContextMenuEntry(editControl, inspectorObject, isGlobalInspector)
    if not editControl then return end
    if isGlobalInspector == nil then isGlobalInspector = inspectorObject.control.isGlobalInspector end
    isGlobalInspector = isGlobalInspector or false
    local searchText = editControl:GetText()
    if not searchText or searchText == "" then return end
    local filterMode, activeTabName
    inspectorObject, filterMode, activeTabName = getSearchHistoryData(inspectorObject, isGlobalInspector)
    if not activeTabName or not filterMode then return end
    tbug.saveSearchHistoryEntry(activeTabName, filterMode, searchText)
end

------------------------------------------------------------------------------------------------------------------------




------------------------------------------------------------------------------------------------------------------------

local function hideEditAndSliderControls(selfVar, activeTabPanel)
    activeTabPanel = activeTabPanel or getActiveTabPanel(selfVar)
    if activeTabPanel then
--d(">found activeTabPanel")
--tbug._activeTabPanelResizeStartSelfVar = selfVar
--tbug._activeTabPanelResizeStart = activeTabPanel
        local editBox = activeTabPanel.editBox
        if editBox then
            editBox:LoseFocus()
        end
        local sliderCtrl = activeTabPanel.sliderControl
        if sliderCtrl then
--d(">found slider control")
            sliderCtrl.panel:valueSliderCancel(sliderCtrl)
        end
    end
end


local function getTabWindowPanelScrollBar(selfVar, activeTabPanel)
    activeTabPanel = activeTabPanel or getActiveTabPanel(selfVar)
    if activeTabPanel then
        local list = activeTabPanel.list
        local scrollBar = list ~= nil and list.scrollbar
        if scrollBar ~= nil then
--d(">found scrollbar")
            return scrollBar
        end
    end
    return
end




function TabWindow:__init__(control, id)
    self.control = assert(control)
    tbug.inspectorWindows = tbug.inspectorWindows or {}
    tbug.inspectorWindows[id] = self
    self.title = control:GetNamedChild("Title")
    self.title:SetMouseEnabled(false) -- Setting this to true wille disable the window (TLC) move!
   --[[
    --Without SetMouseEnabled -> No OnMouse* events!
    --TODO: 20230128: Set the title mouse enabled and add an OnMousDown and OnMouseUp handler which does allow moving the window (pass through behind windows OnMouseDown/Up events?)
    --TODO:           AND check if the title label's text is truncated, and show a tooltip with the whole title text of the active "tab" of the current inspector then
    self.title:SetHandler("OnMouseEnter", function(titleControl)
        if titleControl:WasTruncated() then
            onMouseEnterShowTooltip(titleControl, titleControl:GetText(), 500)
        end
    end)
    self.title:SetHandler("OnMouseExit", function(titleControl)
        onMouseExitHideTooltip(titleControl)
    end)
    ]]

    self.titleBg = control:GetNamedChild("TitleBg")
    self.titleIcon = control:GetNamedChild("TitleIcon")
    self.contents = control:GetNamedChild("Contents")
    self.activeBg = control:GetNamedChild("TabsContainerActiveBg")
    self.bg = control:GetNamedChild("Bg")
    self.contentsBg = control:GetNamedChild("ContentsBg")
    self.activeTab = nil
    self.activeColor = ZO_ColorDef:New(1, 1, 1, 1)
    self.inactiveColor = ZO_ColorDef:New(0.6, 0.6, 0.6, 1)

    local contentsCount = control:GetNamedChild("ContentsCount")
    contentsCount:SetText("")
    contentsCount:SetHidden(false)
    contentsCount:SetMouseEnabled(true)
    self.contentsCount = contentsCount

    self.tabs = {}
    self.tabScroll = control:GetNamedChild("Tabs")
    self:_initTabScroll(self.tabScroll)

    local tabContainer = control:GetNamedChild("TabsContainer")
    self.tabPool = ZO_ControlPool:New("tbugTabLabel", tabContainer, "Tab")
    self.tabPool:SetCustomFactoryBehavior(function(control) self:_initTab(control) end)
    self.tabPool:SetCustomResetBehavior(function(tabControl) resetTab(tabControl, self) end)

    --Global inspector tabWindow?
    if self.control.isGlobalInspector == nil then
        self.control.isGlobalInspector = false
    --else
--d(">GlobalInspector init - TabWindow")
    end

    --Filter and search
    self.filterColorGood = ZO_ColorDef:New(118/255, 188/255, 195/255)
    self.filterColorBad = ZO_ColorDef:New(255/255, 153/255, 136/255)

    self.filterButton = control:GetNamedChild("FilterButton")
    self.filterEdit = control:GetNamedChild("FilterEdit")
    self.filterEdit:SetColor(self.filterColorGood:UnpackRGBA())

    self.filterEdit.doNotRunOnChangeFunc = false
    self.filterEdit:SetHandler("OnTextChanged", function(editControl)
        if tbug.doDebug then d("[tbug]FilterEditBox:OnTextChanged-doNotRunOnChangeFunc: " ..tos(editControl.doNotRunOnChangeFunc)) end
        --local filterMode = self.filterModeButton:getText()
        if editControl.doNotRunOnChangeFunc == true then return end
        local mode = self.filterModeButton:getId()
        local delay = (editControl.reApplySearchTextInstantly == true and 0) or nil
        self:updateFilter(editControl, mode, nil, delay)
        editControl.reApplySearchTextInstantly = false
    end)

    self.filterEdit:SetHandler("OnMouseUp", function(editControl, mouseButton, upInside, shift, ctrl, alt, command)
        if mouseButton == MOUSE_BUTTON_INDEX_RIGHT and upInside then
            --Clear the context menu
            ClearMenu()
            local showMenuNow = false
            if editControl:GetText() ~= "" then
                AddCustomMenuItem("Clear search", function()
                    editControl.doNotRunOnChangeFunc = true
                    editControl:SetText("")
                    self:updateFilter(editControl, getFilterMode(self), nil, 0)
                end, MENU_ADD_OPTION_LABEL)
                showMenuNow = true
            end

            --Show context menu with the last saved searches (search history)
            if not updateSearchHistoryContextMenu(editControl, self, self.control.isGlobalInspector, showMenuNow) then
                if showMenuNow then
                    ShowMenu(editControl)
                end
            end
        end
    end)

    --The search mode buttons
    self.filterModeButton = TextButton(control, "FilterModeButton")
    self.filterMode = 1
    local mode = self.filterMode

    local function updateFilterModeButton(newMode, filterModeButton)
        --d(">updateFilterModeButton-newMode: " ..tos(newMode))
        filterModeButton = filterModeButton or self.filterModeButton
        self.filterMode = newMode
        filterModeButton:fitText(filterModes[newMode])
        filterModeButton:setId(newMode)
        local activeTab = self.activeTab
        if activeTab ~= nil then
            activeTab.filterModeButtonLastMode = newMode
        end
    end
    self.updateFilterModeButton = updateFilterModeButton
    updateFilterModeButton(mode, self.filterModeButton)

    self.filterModeButton.onClicked[MOUSE_BUTTON_INDEX_LEFT] = function()
        mode = self.filterMode
        mode = mode < #filterModes and mode + 1 or 1
        local filterModeStr = filterModes[mode]
        --self.filterModeButton:fitText(filterModeStr, 4)
        --self.filterModeButton:setId(mode)
        updateFilterModeButton(mode, self.filterModeButton)
        self:updateFilter(self.filterEdit, mode, filterModeStr, nil)
    end
    self.filterModeButton:enableMouseButton(MOUSE_BUTTON_INDEX_RIGHT)
    self.filterModeButton.onClicked[MOUSE_BUTTON_INDEX_RIGHT] = function()
        mode = self.filterMode
        mode = mode > 1 and mode - 1 or #filterModes
        local filterModeStr = filterModes[mode]
        --self.filterModeButton:fitText(filterModeStr, 4)
        --self.filterModeButton:setId(mode)
        updateFilterModeButton(mode, self.filterModeButton)
        self:updateFilter(self.filterEdit, mode, filterModeStr, nil)
    end

    --The filter combobox at the global inspector
    self.filterComboBox = control:GetNamedChild("FilterComboBox")
    self.filterComboBox:SetHidden(true)
    GetControl(self.filterComboBox, "BG"):SetHidden(true)
    --TBUG._globalInspectorFilterCombobox = self.filterComboBox
    self.filterComboBox.tooltipText = "Select control types"
    --FilterMode of the comboBox depends on the selected "panel" (tab), e.g. "controls" will provide
    -->control types CT_*. Changed at panel/Tab selection
    self.filterComboBox.filterMode = 1
    -- Initialize the filtertypes multiselect combobox.
    -->Fill with control types at the "Control" tab e.g.
    local dropdown = ZO_ComboBox_ObjectFromContainer(self.filterComboBox)
    self.filterComboBoxDropdown = dropdown
    --TBUG._globalInspectorFilterComboboxDropdown = self.filterComboBoxDropdown
    local function onFilterComboBoxChanged()
        self:OnFilterComboBoxChanged()
    end
    dropdown:SetHideDropdownCallback(onFilterComboBoxChanged)
    self:SetSelectedFilterText()
    dropdown:SetSortsItems(true)
    -->Contents of the filter combobox are set at function GlobalInspector:selectTab()
    -->The filterTypes to use per panel are defined here in this file at the top at tbug.filterComboboxFilterTypesPerPanel -> Coming from glookup.lua doRefresh()


    tbug.confControlColor(control, "Bg", "tabWindowBackground")
    tbug.confControlColor(control, "ContentsBg", "tabWindowPanelBackground")
    tbug.confControlColor(self.activeBg, "tabWindowPanelBackground")
    tbug.confControlVertexColors(control, "TitleBg", "tabWindowTitleBackground")


    local function setDrawLevel(ctrlToChangeDrawLevelOn, layer, allInspectorWindows)
        --d("[TBUG]setDrawLevel")
        layer = layer or DL_CONTROLS
        allInspectorWindows = allInspectorWindows or false
        local tiers = {
            [DL_BACKGROUND] =   DT_LOW,
            [DL_CONTROLS] =     DT_MEDIUM,
            [DL_OVERLAY] =      DT_HIGH,
        }
        local tier = tiers[layer] or DT_MEDIUM

        --Reset all inspector windows to normal layer and level?
        if allInspectorWindows == true then
            for _, inspectorWindow in ipairs(tbug.inspectorWindows) do
                if inspectorWindow.control ~= ctrlToChangeDrawLevelOn then
--d(">changing drawLevel of inspectorWindow: " .. tos(inspectorWindow.control:GetName()))
                    setDrawLevel(inspectorWindow.control, DL_CONTROLS, false)
                end
            end
            if tbug.firstInspector then
--d(">changing drawLevel of firstInspector: " .. tos(tbug.firstInspector.control:GetName()))
                if tbug.firstInspector.control ~= ctrlToChangeDrawLevelOn then
                    setDrawLevel(tbug.firstInspector.control, DL_CONTROLS, false)
                end
            end
        end

        if not ctrlToChangeDrawLevelOn then return end
        if ctrlToChangeDrawLevelOn.SetDrawTier then
--d(">setDrawTier: " .. tos(tier) .. " on ctrl: " ..tos(ctrlToChangeDrawLevelOn:GetName()))
            ctrlToChangeDrawLevelOn:SetDrawTier(tier)
        end
        if ctrlToChangeDrawLevelOn.SetDrawLayer then
--d(">SetDrawLayer: " ..tos(layer) .. " on ctrl: " ..tos(ctrlToChangeDrawLevelOn:GetName()))
            ctrlToChangeDrawLevelOn:SetDrawLayer(layer)
        end
    end

    local closeButton = TextButton(control, "CloseButton")
    closeButton.onClicked[MOUSE_BUTTON_INDEX_LEFT] = function()
        self:release()
        onMouseExitHideTooltip(closeButton.control)
    end
    closeButton:fitText("x", 12)
    closeButton:setMouseOverBackgroundColor(0.4, 0, 0, 0.4)
    closeButton:insertOnMouseEnterHandler(function(ctrl) onMouseEnterShowTooltip(ctrl.control, "Close", 500) end)
    closeButton:insertOnMouseExitHandler(function(ctrl) onMouseExitHideTooltip(ctrl.control) end)
    self.closeButton = closeButton

    local refreshButton = TextButton(control, "RefreshButton")

    local toggleSizeButton = TextButton(control, "ToggleSizeButton")
    toggleSizeButton.toggleState = false
    toggleSizeButton.onClicked[MOUSE_BUTTON_INDEX_LEFT] = function(buttonCtrl)
        if buttonCtrl then
            buttonCtrl.toggleState = not buttonCtrl.toggleState
            if not buttonCtrl.toggleState then
                toggleSizeButton:fitText("^", 12)
                toggleSizeButton:setMouseOverBackgroundColor(0.4, 0.4, 0, 0.4)
            else
                toggleSizeButton:fitText("v", 12)
                toggleSizeButton:setMouseOverBackgroundColor(0.4, 0.4, 0, 0.4)
            end
            refreshButton:setEnabled(not buttonCtrl.toggleState)
            refreshButton:setMouseEnabled(not buttonCtrl.toggleState)

            local sv
            local globalInspector = tbug.getGlobalInspector()
            local isGlobalInspectorWindow = (self == globalInspector) or false
            if not isGlobalInspectorWindow then
                sv = tbug.savedTable("objectInspector" .. id)
            else
                sv = tbug.savedTable("globalInspector1")
            end
            local width, height
            local widthDefault  = 400
            local heightDefault = 600
            if isGlobalInspectorWindow then
                widthDefault    = 800
                heightDefault   = 600
            end
            if not buttonCtrl.toggleState == true then
                if sv and sv.winWidth and sv.winHeight then
                    width, height = sv.winWidth, sv.winHeight
                else
                    width, height = widthDefault, heightDefault
                end
            else
                if sv and sv.winWidth then
                    width, height = sv.winWidth, tbug.minInspectorWindowHeight
                else
                    width, height = widthDefault, tbug.minInspectorWindowHeight
                end
            end
            if width and height then
                --d("TBUG >width: " ..tos(width) .. ", height: " ..tos(height))
                self.bg:ClearAnchors()
                self.bg:SetDimensions(width, height)
                self.control:ClearAnchors()
                self.control:SetDimensions(width, height)
                --Call the resize handler as if it was manually resized
                local panel = getActiveTabPanel(self)
                if panel and panel.onResizeUpdate then
                    panel:onResizeUpdate(height)
                end
                self.contents:SetHidden(buttonCtrl.toggleState)
                self.contentsBg:SetHidden(buttonCtrl.toggleState)
                self.tabScroll:SetHidden(buttonCtrl.toggleState)
                self.bg:SetHidden(buttonCtrl.toggleState)
                self.activeBg:SetHidden(buttonCtrl.toggleState)
                self.contents:SetMouseEnabled(not buttonCtrl.toggleState)
                self.contentsBg:SetMouseEnabled(not buttonCtrl.toggleState)
                self.tabScroll:SetMouseEnabled(not buttonCtrl.toggleState)
                self.activeBg:SetMouseEnabled(not buttonCtrl.toggleState)
                if self.contentsCount then self.contentsCount:SetHidden(buttonCtrl.toggleState) end

                if self.filterButton then
                    local filterBar = self.filterButton:GetParent()
                    if filterBar then
                        filterBar:SetHidden(buttonCtrl.toggleState)
                        filterBar:SetMouseEnabled(not buttonCtrl.toggleState)
                    end
                end

                --control:SetAnchor(AnchorPosition myPoint, object anchorTargetControl, AnchorPosition anchorControlsPoint, number offsetX, number offsetY)
                self.control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, self.control:GetLeft(), self.control:GetTop())
                self.control:SetDimensions(width, height)
                self.bg:SetAnchor(TOPLEFT, self.control, nil, 4, 6)
                self.bg:SetAnchor(BOTTOMRIGHT, self.control, nil, -4, -6)
                self.bg:SetDrawTier(DT_LOW)
                self.bg:SetDrawLayer(DL_BACKGROUND)
                self.bg:SetDrawLevel(0)
                self.control:SetDrawTier(DT_LOW)
                self.control:SetDrawLayer(DL_CONTROLS)
                self.control:SetDrawLevel(1)
                self.contentsBg:SetDrawTier(DT_LOW)
                self.contentsBg:SetDrawLayer(DL_BACKGROUND)
                self.contentsBg:SetDrawLevel(0)
                self.contents:SetDrawTier(DT_LOW)
                self.contents:SetDrawLayer(DL_BACKGROUND)
                self.contents:SetDrawLevel(1)
            end
        end
        onMouseExitHideTooltip(toggleSizeButton.control)
    end

    toggleSizeButton:fitText("^", 12)
    toggleSizeButton:setMouseOverBackgroundColor(0.4, 0.4, 0, 0.4)
    toggleSizeButton:insertOnMouseEnterHandler(function(ctrl) onMouseEnterShowTooltip(ctrl.control, "Collapse / Expand", 500) end)
    toggleSizeButton:insertOnMouseExitHandler(function(ctrl) onMouseExitHideTooltip(ctrl.control) end)
    self.toggleSizeButton = toggleSizeButton

    refreshButton.onClicked[MOUSE_BUTTON_INDEX_LEFT] = function()
        --tbug._selfRefreshButtonClicked = self
        if toggleSizeButton.toggleState == false then
            --d("[tbug]Refresh button pressed")
            local activeTabPanel = getActiveTabPanel(self)
            if activeTabPanel then
                hideEditAndSliderControls(self, activeTabPanel)
                --d(">found activeTab.panel")
                activeTabPanel:refreshData()
            end
        end
        onMouseExitHideTooltip(refreshButton.control)
    end
    refreshButton:fitText("o", 12)
    refreshButton:setMouseOverBackgroundColor(0, 0.4, 0, 0.4)
    refreshButton:insertOnMouseEnterHandler(function(ctrl) onMouseEnterShowTooltip(ctrl.control, "Refresh", 500) end)
    refreshButton:insertOnMouseExitHandler(function(ctrl) onMouseExitHideTooltip(ctrl.control) end)
    self.refreshButton = refreshButton

    --Events tracking
    if self.control.isGlobalInspector == true then
        local eventsButton = TextButton(control, "EventsButton")
        eventsButton.toggleState = false
        eventsButton.tooltipText = "Enable EVENT tracking"
        eventsButton.onMouseUp = function(buttonCtrl, mouseButton, upInside, ctrl, alt, shift, command)
            if upInside then
                if LibCustomMenu and mouseButton == MOUSE_BUTTON_INDEX_RIGHT then
                    tbug.ShowEventsContextMenu(buttonCtrl, nil, nil, true)

                elseif mouseButton == MOUSE_BUTTON_INDEX_LEFT then
                    local tbEvents = tbug.Events
                    if not tbEvents then return end
                    if tbEvents.IsEventTracking == true then
                        tbug.StopEventTracking()
                    else
                        tbug.StartEventTracking()
                    end

                    buttonCtrl.toggleState = not buttonCtrl.toggleState
                    onMouseExitHideTooltip(eventsButton.control)

                    if not buttonCtrl.toggleState then
                        eventsButton:fitText("e", 12)
                        eventsButton:setMouseOverBackgroundColor(0, 0.8, 0, 1)
                        eventsButton.tooltipText = "Enable EVENT tracking"
                    else
                        eventsButton:fitText("E", 12)
                        eventsButton:setMouseOverBackgroundColor(0.8, 0.0, 0, 0.4)
                        eventsButton.tooltipText = "Disable EVENT tracking"
                    end
                end
            end
        end
        eventsButton:fitText("e", 12)
        eventsButton:setMouseOverBackgroundColor(0, 0.8, 0, 1)
        eventsButton.tooltipText = "Enable EVENT tracking"
        eventsButton:insertOnMouseEnterHandler(function(ctrl) onMouseEnterShowTooltip(ctrl.control, ctrl.tooltipText, 500) end)
        eventsButton:insertOnMouseExitHandler(function(ctrl) onMouseExitHideTooltip(ctrl.control) end)
        self.eventsButton = eventsButton
    end


    local function updateSizeOnTabWindowAndCallResizeHandler(newWidth, newHeight)
        local left = control:GetLeft()
        local top = control:GetTop()
        control:ClearAnchors()
        control:SetAnchor(TOPLEFT, nil, TOPLEFT, left, top)
        control:SetDimensions(newWidth, newHeight)

        local OnResizeStopHandler = control:GetHandler("OnResizeStop")
        if OnResizeStopHandler and type(OnResizeStopHandler) == "function" then
            OnResizeStopHandler(control)
        end
    end


    self.titleIcon:SetMouseEnabled(true)
    --Does not work if OnMouseUp handler is also set
    self.titleIcon:SetHandler("OnMouseDoubleClick", function(selfCtrl, button, upInside, ctrl, alt, shift, command)
        if button == MOUSE_BUTTON_INDEX_LEFT then
            local owner = selfCtrl:GetOwningWindow()
--d("[TB]TitleIcon - OnMouseDoubleClick - owner: " ..tos(owner:GetName()))
            local ownerDrawLevel = owner ~= nil and owner:GetDrawLevel()
--d(">ownerDrawLevel: " ..tos(ownerDrawLevel))
            if ownerDrawLevel == DL_OVERLAY then
                setDrawLevel(owner, DL_CONTROLS, true)
            else
                setDrawLevel(owner, DL_OVERLAY, true)
            end
        end
    end)

    --Context menu at headline torchbug icon
    if LibCustomMenu then
        local function showTabWindowContextMenu(selfCtrl)
            local globalInspector = tbug.getGlobalInspector()
            local isGlobalInspectorWindow = (self == globalInspector) or false

            local owner = selfCtrl:GetOwningWindow()
            local dLayer = owner:GetDrawLayer()

            --Draw layer
            local function resetDrawLayer()
                setDrawLevel(owner, dLayer)
            end
            --setDrawLevel(owner, DL_CONTROLS)
            ClearMenu()
            local drawLayerSubMenu = {}
            local drawLayerSubMenuEntry = {
                label = "On top",
                callback = function() setDrawLevel(owner, DL_OVERLAY, true) end,
            }
            if dLayer ~= DL_OVERLAY then
                tins(drawLayerSubMenu, drawLayerSubMenuEntry)
            end
            drawLayerSubMenuEntry = {
                label = "Normal",
                callback = function() setDrawLevel(owner, DL_CONTROLS, true) end,
            }
            if dLayer ~= DL_CONTROLS then
                tins(drawLayerSubMenu, drawLayerSubMenuEntry)
            end
            drawLayerSubMenuEntry = {
                label = "Background",
                callback = function() setDrawLevel(owner, DL_BACKGROUND, true) end,
            }
            if dLayer ~= DL_BACKGROUND then
                tins(drawLayerSubMenu, drawLayerSubMenuEntry)
            end
            AddCustomSubMenuItem("DrawLayer", drawLayerSubMenu)

            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("Reset size to default", function() updateSizeOnTabWindowAndCallResizeHandler(tbug.defaultInspectorWindowWidth, tbug.defaultInspectorWindowHeight) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("Collapse/Expand", function() toggleSizeButton.onClicked[MOUSE_BUTTON_INDEX_LEFT](toggleSizeButton) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            if toggleSizeButton.toggleState == false then
                AddCustomMenuItem("Refresh", function() refreshButton.onClicked[MOUSE_BUTTON_INDEX_LEFT]() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            end
            --Not at the global inspector of TBUG itsself, else you'd remove all the libraries, scripts, globals etc. tabs
            if not isGlobalInspectorWindow and toggleSizeButton.toggleState == false and (self.tabs and #self.tabs > 0) then
                AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("Remove all tabs", function() self:removeAllTabs() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                --Only at the global inspector
            elseif isGlobalInspectorWindow and toggleSizeButton.toggleState == false and (self.tabs and #self.tabs < tbug.panelCount ) then
                AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                AddCustomMenuItem("+ Restore all standard tabs +", function() tbug.slashCommand("-all-") end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            end
            AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            AddCustomMenuItem("Hide", function() owner:SetHidden(true) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            if isGlobalInspectorWindow then
                if GetDisplayName() == "@Baertram" then
                    AddCustomMenuItem("-", function() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                    AddCustomMenuItem("~ DEBUG MODE ~", function() tbug.doDebug = not tbug.doDebug d("[TBUG]Debugging: " ..tos(tbug.doDebug)) end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
                end
            end
            AddCustomMenuItem("|cFF0000X Close|r", function() self:release() end, MENU_ADD_OPTION_LABEL, nil, nil, nil, nil, nil)
            --Fix to show the context menu entries above the window, and make them selectable
            if dLayer == DL_OVERLAY then
                setDrawLevel(owner, DL_CONTROLS)
            end
            ShowMenu(owner)
        end

        --Context menu at the title icon (top left)
        self.titleIcon:SetHandler("OnMouseUp", function(selfCtrl, button, upInside, ctrl, alt, shift, command)
            if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
                showTabWindowContextMenu(selfCtrl, button, upInside)
            end
        end)

        --Context menu at the collapse/refresh/close buttons (top right)
        toggleSizeButton.onMouseUp = function(selfCtrl, button, upInside, ctrl, alt, shift, command)
            if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
                showTabWindowContextMenu(selfCtrl, button, upInside)
            end
        end
        refreshButton.onMouseUp = function(selfCtrl, button, upInside, ctrl, alt, shift, command)
            if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
                showTabWindowContextMenu(selfCtrl, button, upInside)
            end
        end
        closeButton.onMouseUp = function(selfCtrl, button, upInside, ctrl, alt, shift, command)
            if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
                showTabWindowContextMenu(selfCtrl, button, upInside)
            end
        end

        --Context menu at the count label (bottom right)
        contentsCount:SetHandler("OnMouseUp", function(selfCtrl, button, upInside, ctrl, alt, shift, command)
            if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
                showTabWindowContextMenu(selfCtrl, button, upInside)
            end
        end)
    end

    --Right click on tabsScroll or vertical scoll bar: Set window to top draw layer!
    local controlsToAddRigtClickSetTopDrawLayer = {
        self.tabScroll,
    }
    for _, controlToProcess in ipairs(controlsToAddRigtClickSetTopDrawLayer) do
        if controlToProcess ~= nil and controlToProcess.SetHandler then
            controlToProcess:SetHandler("OnMouseUp", function(selfCtrl, button, upInside, ctrl, alt, shift, command)
                if button == MOUSE_BUTTON_INDEX_RIGHT and upInside then
                    local owner = selfCtrl:GetOwningWindow()
                    --d(">right mouse clicked: " ..tos(selfCtrl:GetName()) .. ", owner: " ..tos(owner:GetName()))
                    setDrawLevel(owner, DL_OVERLAY, true)
                    --tbug._clickedTabWindowTabScrollAtBottomSelf = self
                end
            end, "TBUG", nil, nil)
        end

    end
end


function TabWindow:_initTab(tabControl)
    tabControl:SetHandler("OnMouseEnter",
        function(control)
            if control ~= self.activeTab then
                control.label:SetColor(self.activeColor:UnpackRGBA())
            end
            if not self.control.isGlobalInspector then
                if tabControl.tooltipText == nil then
                    tabControl.tooltipText = getTabTooltipText(self, tabControl)
                end
                onMouseEnterShowTooltip(control, tabControl.tooltipText, 0, BOTTOM)
            end
        end)
    tabControl:SetHandler("OnMouseExit",
        function(control)
            ZO_Tooltips_HideTextTooltip()
            if control ~= self.activeTab then
                control.label:SetColor(self.inactiveColor:UnpackRGBA())
            end
        end)
    tabControl:SetHandler("OnMouseUp",
        function(control, mouseButton, upInside)
            if upInside then
                if mouseButton == MOUSE_BUTTON_INDEX_LEFT then
                    ZO_Tooltips_HideTextTooltip()
                    self:selectTab(control)
                elseif mouseButton == MOUSE_BUTTON_INDEX_RIGHT then
                    ZO_Tooltips_HideTextTooltip()
                    self:removeTab(control)
                end
            end
        end)
end

local function tabScroll_OnMouseWheel(self, delta)
--d("[TB]tabScroll_OnMouseWheel-delta: " ..tos(delta))
    local tabWindow = self.tabWindow
    local selectedIndex = tabWindow:getTabIndex(tabWindow.activeTab)
    if selectedIndex then
        local targetTab = tabWindow.tabs[selectedIndex - zo_sign(delta)]
        if targetTab then
            ZO_Tooltips_HideTextTooltip()
            tabWindow:selectTab(targetTab)
        end
    end
end


local function tabScroll_OnScrollExtentsChanged(self, horizontal, vertical)
--d("[TB]tabScroll_OnScrollExtentsChanged-horizontal: " ..tos(horizontal) .. ", vertical: " ..tos(vertical))
    local extent = horizontal
    local offset = self:GetScrollOffsets()
    self:SetFadeGradient(1, 1, 0, zo_clamp(offset, 0, 15))
    self:SetFadeGradient(2, -1, 0, zo_clamp(extent - offset, 0, 15))
    -- this is necessary to properly scroll to the active tab if it was
    -- inserted and immediately selected, before anchors were processed
    -- and scroll extents changed accordingly

    local xStart, xEnd = 0, self:GetWidth()
    self.animation:SetHorizontalStartAndEnd(xStart, xEnd)

    if self.tabWindow.activeTab then
        self.tabWindow:scrollToTab(self.tabWindow.activeTab)
    end
end


local function tabScroll_OnScrollOffsetChanged(self, horizontal, vertical)
--d("[TB]tabScroll_OnScrollOffsetChanged-horizontal: " ..tos(horizontal) .. ", vertical: " ..tos(vertical))
    local extent = self:GetScrollExtents()
    local offset = horizontal
    self:SetFadeGradient(1, 1, 0, zo_clamp(offset, 0, 15))
    self:SetFadeGradient(2, -1, 0, zo_clamp(extent - offset, 0, 15))
end


function TabWindow:_initTabScroll(tabScroll)
--d("[TB]_initTabScroll")
    local animation, timeline = CreateSimpleAnimation(ANIMATION_SCROLL, tabScroll)
    animation:SetDuration(400)
    animation:SetEasingFunction(ZO_BezierInEase)
    local xStart, xEnd = 0, tabScroll:GetWidth()
    animation:SetHorizontalStartAndEnd(xStart, xEnd)

    tabScroll.animation = animation
    tabScroll.timeline = timeline
    tabScroll.tabWindow = self

    tabScroll:SetHandler("OnMouseWheel", tabScroll_OnMouseWheel)
    tabScroll:SetHandler("OnScrollExtentsChanged", tabScroll_OnScrollExtentsChanged)
    tabScroll:SetHandler("OnScrollOffsetChanged", tabScroll_OnScrollOffsetChanged)
end

function TabWindow:getActiveTab()
    return self.activeTab
end

function TabWindow:configure(sv)
    local control = self.control

    local function isCollapsed()
        local toggleSizeButton = self.toggleSizeButton
        local isCurrentlyCollapsed = toggleSizeButton and toggleSizeButton.toggleState or false
--d(">isCurrentlyCollapsed: " ..tos(isCurrentlyCollapsed))
        return isCurrentlyCollapsed
    end

    local function reanchorAndResize(wasMoved, isCollapsedWindow)
        wasMoved = wasMoved or false
        isCollapsedWindow = isCollapsedWindow or false
--d("reanchorAndResize - wasMoved: " .. tos(wasMoved) .. ", isCollapsed: " ..tos(isCollapsed))
        if isCollapsedWindow == true then
            --Not moved but resized in height?
            if not wasMoved then
                local height = control:GetHeight()
                if height > tbug.minInspectorWindowHeight then
                    height = tbug.minInspectorWindowHeight
                    control:SetHeight(height)
                end
            end
        end
        if sv.winLeft and sv.winTop then
            control:ClearAnchors()
            control:SetAnchor(TOPLEFT, nil, TOPLEFT, sv.winLeft, sv.winTop)
        end
        if isCollapsedWindow == true then
            return
        end

        local width = control:GetWidth()
        local height = control:GetHeight()
--d(">sv.winWidth/width: " ..tos(sv.winWidth).."/"..tos(width) .. ", sv.winHeight/height: " ..tos(sv.winHeight).."/"..tos(height))

        if sv.winWidth ~= nil and sv.winHeight ~= nil and (width~=sv.winWidth or height~=sv.winHeight) then
--d(">>width and height")
            width, height = sv.winWidth, sv.winHeight
            if width < tbug.minInspectorWindowWidth then width = tbug.minInspectorWindowWidth end
            if height < tbug.minInspectorWindowHeight then height = tbug.minInspectorWindowHeight end
            control:SetDimensions(width, height)
        elseif not sv.winWidth or not sv.winHeight then
            sv.winWidth = sv.winWidth or tbug.minInspectorWindowWidth
            sv.winHeight = sv.winHeight or tbug.minInspectorWindowHeight
            control:SetDimensions(sv.winWidth, sv.winHeight)
        end
    end

    local function savePos(ctrl, wasMoved)
        ZO_Tooltips_HideTextTooltip()
        wasMoved = wasMoved or false
        --Check if the position really changed
        local newLeft = math.floor(control:GetLeft())
        local newTop = math.floor(control:GetTop())
        if wasMoved == true and (newLeft == sv.winLeft and newTop == sv.winTop) then
            wasMoved = false
        end

        local isCurrentlyCollapsed = isCollapsed()
--d("SavePos, wasMoved: " ..tos(wasMoved) .. ", isCollapsed: " ..tos(isCurrentlyCollapsed))

        control:SetHandler("OnUpdate", nil)

        --Always save the current x and y coordinates and the width of the window, even if collapsed
        sv.winLeft = newLeft
        sv.winTop = newTop
        local width = control:GetWidth()
        if width < tbug.minInspectorWindowWidth then width = tbug.minInspectorWindowWidth end
        sv.winWidth = math.ceil(width)

        local height = control:GetHeight()
        if height <= 0 or height < tbug.minInspectorWindowHeight then height = tbug.minInspectorWindowHeight end

--d(">width: " ..tos(width) .. ", height: " ..tos(height))

        if isCurrentlyCollapsed == true then
            reanchorAndResize(wasMoved, isCurrentlyCollapsed)
            return
        end
--d(">got here, as not collapsed!")

        --Only update the height if not collapsed!
        sv.winHeight = math.ceil(height)

        --d(">savePos - width: " ..tos(sv.winWidth) .. ", height: " .. tos(sv.winHeight) .. ", left: " ..tos(sv.winLeft ) .. ", top: " .. tos(sv.winTop))

        reanchorAndResize()
        if not wasMoved then
            --Refresh the panel to commit the scrollist etc.
            self.refreshButton.onClicked[MOUSE_BUTTON_INDEX_LEFT]()
        end
    end

    local function resizeStart()
--d("[TBUG]TabWindow.resizeStart")
--tbug._selfResizeStart = self

        ZO_Tooltips_HideTextTooltip()
        --local toggleSizeButton = self.toggleSizeButton
        local isCurrentlyCollapsed = isCollapsed()
--d("resizeStart, isCollapsed: " ..tos(isCurrentlyCollapsed))
        if isCurrentlyCollapsed == true then return end

--d(">got here, as not collapsed! Starting OnUpdate")

        local activeTabPanel = getActiveTabPanel(self)
        if activeTabPanel then
--d(">found activeTabPanel")
            hideEditAndSliderControls(self, activeTabPanel)

            if activeTabPanel.onResizeUpdate then
                control:SetHandler("OnUpdate", function()
                    activeTabPanel:onResizeUpdate()
                end)
            end
        end
    end

    reanchorAndResize()
    control:SetHandler("OnMoveStop", function() savePos(control, true) end)
    control:SetHandler("OnResizeStart", resizeStart)
    control:SetHandler("OnResizeStop", savePos)
end


function TabWindow:getTabControl(keyOrTabControl)
    if type(keyOrTabControl) == "number" then
        return self.tabs[keyOrTabControl]
    else
        return keyOrTabControl
    end
end

function TabWindow:getTabIndex(keyOrTabControl)
    if type(keyOrTabControl) == "number" then
        return keyOrTabControl
    end
    for index, tab in ipairs(self.tabs) do
        if tab == keyOrTabControl then
            return index
        end
    end
end

function TabWindow:getTabIndexByName(tabName)
    for index, tab in ipairs(self.tabs) do
        if tab.tabName and tab.tabName == tabName then
            return index
        end
    end
end


function TabWindow:insertTab(name, panel, index, inspectorTitle, useInspectorTitle, isGlobalInspectorTab, isMOC, newAddedData)
--d("[TB]insertTab-name: " ..tos(name) .. ", panel: " ..tos(panel).. ", index: " ..tos(index).. ", inspectorTitle: " ..tos(inspectorTitle).. ", useInspectorTitel: " ..tos(useInspectorTitle) .. ", isGlobalInspectorTab: " ..tos(isGlobalInspectorTab))
--tbug._panelInsertedATabTo = panel
--tbug._insertTabSELF = self
    isMOC = isMOC or false
    ZO_Tooltips_HideTextTooltip()
    useInspectorTitle = useInspectorTitle or false
    isGlobalInspectorTab = isGlobalInspectorTab or false
    if index > 0 then
        assert(index <= #self.tabs + 1)
    else
        assert(-index <= #self.tabs)
        index = #self.tabs + 1 + index
    end

    --Get new tab control from pool
    local tabControl, tabKey = self.tabPool:AcquireObject()
    resetTabControlData(tabControl)

    --Mouse over control - tab info
    tabControl.isMOC = isMOC
    if isMOC == true then
        --Increase the number of MOC tabs in total
        local numMOCTabs = tbug.numMOCTabs + 1
        tabControl.MOCnumber = numMOCTabs
        tbug.numMOCTabs = tbug.numMOCTabs + 1
    end
    --Add the "opened new tab" timestamp data for the tab tooltips
    if newAddedData ~= nil then
        local timeStamp = newAddedData.timeStamp
        if timeStamp ~= nil then
            tabControl.timeStampAdded =     timeStamp
            tabControl.timeStampAddedStr =  osdate("%c", timeStamp)
        end
    end

    tabControl.pkey = tabKey
    tabControl.tabName = inspectorTitle or name
    tabControl.panel = panel
    local tabKeyStr
    if isGlobalInspectorTab == true then
        panelData = panelData or tbug.panelNames --These are only the GlobalInspector panel names like "AddOns", "Scripts" etc.
        tabKeyStr = panelData[tabKey].key or tabControl.tabName
    else
        tabKeyStr = tabControl.tabName
    end
    tabControl.pKeyStr = tabKeyStr

    tabControl.label:SetColor(self.inactiveColor:UnpackRGBA())
    tabControl.label:SetText(useInspectorTitle == true and inspectorTitle or name)

    panel.control:SetHidden(true)
    panel.control:SetParent(self.contents)
    panel.control:ClearAnchors()
    panel.control:SetAnchorFill()

    tins(self.tabs, index, tabControl)

    local prevControl = self.tabs[index - 1]
    if prevControl then
        tabControl:SetAnchor(BOTTOMLEFT, prevControl, BOTTOMRIGHT)
    else
        tabControl:SetAnchor(BOTTOMLEFT)
    end

    local nextControl = self.tabs[index + 1]
    if nextControl then
        nextControl:ClearAnchors()
        nextControl:SetAnchor(BOTTOMLEFT, tabControl, BOTTOMRIGHT)
    end

    return tabControl
end


function TabWindow:release()
--d("[TB]TabWindow:release")
  self.activeTab = nil
end


function TabWindow:removeAllTabs()
    ZO_Tooltips_HideTextTooltip()

    self.activeTab = nil
    self.activeBg:SetHidden(true)
    self.activeBg:ClearAnchors()
    self.tabPool:ReleaseAllObjects()
    tbug.truncate(self.tabs, 0)

    local contentsCount = self.contentsCount
    if contentsCount ~= nil then
        contentsCount:SetText("")
    end
end


function TabWindow:removeTab(key)
    if tbug.doDebug then d("[TabWindow:removeTab]key: " ..tos(key)) end
    hideEditAndSliderControls(self, nil)
    local index = self:getTabIndex(key)
    local tabControl = self.tabs[index]
    if not tabControl then
        return
    end

    --Clear any active search data at the tab
    -->This will reset the search filter editbox at the total inspector and not only for the active tab
    --self:updateFilterEdit("", nil, 0)
    -->How can we reset it only at the active tab?
    local activeTab = self.activeTab
    local editControl = self.filterEdit
    activeTab.filterModeButtonLastMode = 1 --str
    activeTab.filterEditLastText = nil
    self.updateFilterModeButton(activeTab.filterModeButtonLastMode, self.filterModeButton)
    editControl.reApplySearchTextInstantly = true
    editControl.doNotRunOnChangeFunc = true --prevent running the OnTextChanged handler of the filter editbox -> Because it would call the activeTabPanel:refreshFilter() 1 frame delayed (see below)
    editControl:SetText("") -- >Should call updateFilter function which should call activeTabPanel:refreshFilter()
    -->But: after reopen of the same tab the searchEdit box is empty, and the filter is still applied...
    -->As this will be called delayed by 0 ms the next tab was selected already and is the active tab now, making the
    -->stored filterData for the "before closed tab" not update properly!
    -->So we need to update it manually here before the next tab is selected:
    local activeTabPanel = getActiveTabPanel(self)
    activeTabPanel:setFilterFunc(false, true)
    -->Will call activeTabPanel:refreshFilter() with a forced refresh!


    local nextControl = self.tabs[index + 1]
    if nextControl then
        nextControl:ClearAnchors()
        if index > 1 then
            local prevControl = self.tabs[index - 1]
            nextControl:SetAnchor(BOTTOMLEFT, prevControl, BOTTOMRIGHT)
        else
            nextControl:SetAnchor(BOTTOMLEFT)
        end
    end
    if activeTab == tabControl then
        if nextControl then
            self:selectTab(nextControl)
        else
            self:selectTab(index - 1)
        end
    end

    trem(self.tabs, index)

    if tabControl.isMOC == true then
        --Decrease the number of MOC tabs in total
        tbug.numMOCTabs = tbug.numMOCTabs - 1
        if tbug.numMOCTabs < 0 then tbug.numMOCTabs = 0 end
    end
    resetTabControlData(tabControl)

    self.tabPool:ReleaseObject(tabControl.pkey)

--tbug._selfControl = self.control
    if not self.tabs or #self.tabs == 0 then
--d(">reset all tabs: Title text = ''")
        self.title:SetText("")
        --No tabs left in this inspector? Hide it then
        --self.control:SetHidden(true)
        self:release()
    end
end


function TabWindow:reset()
    self.control:SetHidden(true)
    self:removeAllTabs()
end


function TabWindow:scrollToTab(key)
    --d("[TB]scrollToTab-key: " ..tos(key))
    --After the update to API 101031 the horizontal scroll list was always centering the tab upon scrolling.
    --Even if the window was wide enough to show all tabs properly -> In the past the selected tab was just highlighted
    --and no scrolling was done then.
    --So this function here should only scroll if the tab to select is not visible at the horizontal scrollbar
    --Attention: key is the tabControl! Not a number
    local tabControl = self:getTabControl(key)
    --local tabCenter = tabControl:GetCenter()
    local tabLeft = tabControl:GetLeft()
    local tabWidth = tabControl:GetWidth()
    local scrollControl = self.tabScroll
--Debugging
--tbug._scrollControl = scrollControl
--tbug._tabControlToScrollTo = tabControl
    --local scrollCenter = scrollControl:GetCenter()
    local scrollWidth = scrollControl:GetWidth()
    local scrollLeft = scrollControl:GetLeft()
    local scrollRight = scrollLeft + scrollWidth
    --The center of the tab is >= the width of the scroll container -> So it is not/partially visible.
    --Scroll the scrollbar to the left for the width of the tab + 10 pixels if it's not fully visible at the right edge,
    --or scroll to the left if it's not fully visible at the left edge
    --d(">scrollRight: " ..tos(scrollRight) .. ", tabLeft: " ..tos(tabLeft) .. ", tabWidth: " ..tos(tabWidth))
    --d(">scrollLeft: " ..tos(scrollLeft) .. ", tabLeft: " ..tos(tabLeft) .. ", tabWidth: " ..tos(tabWidth))
    if (tabLeft + tabWidth) >= scrollRight then
        scrollControl.timeline:Stop()
        scrollControl.animation:SetHorizontalRelative(-1 * (scrollRight - (tabLeft + tabWidth)))
        scrollControl.timeline:PlayFromStart()
    elseif tabLeft < scrollLeft then
        scrollControl.timeline:Stop()
        scrollControl.animation:SetHorizontalRelative(-1 * (scrollLeft - tabLeft))
        scrollControl.timeline:PlayFromStart()
    end
    ----old code!
    ----scrollControl.timeline:Stop()
    ----scrollControl.animation:SetHorizontalRelative(tabCenter - scrollCenter)
    ----scrollControl.timeline:PlayFromStart()
end


function TabWindow:selectTab(key, isMOC)
    --TBUG._selectedTab = self
    isMOC = isMOC or false
    local tabIndex = self:getTabIndex(key)
    if tbug.doDebug then d("[TabWindow:selectTab]tabIndex: " ..tos(tabIndex) .. ", key: " ..tos(key) ..", isMOC: " ..tos(isMOC)) end
    ZO_Tooltips_HideTextTooltip()
    hideEditAndSliderControls(self, nil)
    local tabControl = self:getTabControl(key)
    if self.activeTab == tabControl then
        if tbug.doDebug then d("< ABORT: active tab = current tab") end
        return
    end
    local activeTab = self.activeTab
    if activeTab then
        activeTab.label:SetColor(self.inactiveColor:UnpackRGBA())
        activeTab.panel.control:SetHidden(true)
    end
    if tabControl then
        --d("> found tabControl")

        if tabControl.isMOC == nil then
            tabControl.isMOC = isMOC
        end

        tabControl.label:SetColor(self.activeColor:UnpackRGBA())
        tabControl.panel:refreshData()
        tabControl.panel.control:SetHidden(false)
        self.activeBg:ClearAnchors()
        self.activeBg:SetAnchor(TOPLEFT, tabControl)
        self.activeBg:SetAnchor(BOTTOMRIGHT, tabControl)
        self.activeBg:SetHidden(false)
        self:scrollToTab(tabControl)

        local firstInspector = tabControl.panel.inspector
        if firstInspector ~= nil then
            --d("> found firstInspector")
            local title = firstInspector.title
            if title ~= nil and title.SetText then
                local keyValue = tabIndex --(type(key) ~= "number" and self:getTabIndex(key)) or key
                local keyText = firstInspector.tabs[keyValue].tabName
                --Set the title of the selected/active tab
                local titleText = tabControl.titleText
                if titleText == nil or titleText == "" then
                    titleText = buildTabTitleOrTooltip(tabControl, keyText, true)
                    tabControl.titleText = titleText
                end
                title:SetText(titleText)
            end
        end
    else
        self.activeBg:ClearAnchors()
        self.activeBg:SetHidden(true)
    end

    --Hide the filter dropdown and show it only for allowed tabIndices at the global inspector
    self:connectFilterComboboxToPanel(tabIndex)

    --d(">setting activeTab")
    self.activeTab = tabControl

    --Automatically re-filter the last used filter text, and mode at the current active tab
    -->Do not update the search history by doing this!
    activeTab = self.activeTab
    if activeTab ~= nil then
        if activeTab.filterModeButtonLastMode == nil then
            activeTab.filterModeButtonLastMode = 1 --str
        end
        self.updateFilterModeButton(activeTab.filterModeButtonLastMode, self.filterModeButton)
        if activeTab.filterEditLastText == nil then
            activeTab.filterEditLastText = ""
        end

        self.filterEdit.doNotRunOnChangeFunc = false
        self.filterEdit.doNotSaveToSearchHistory = true
        self.filterEdit.reApplySearchTextInstantly = true
        self.filterEdit:SetText(activeTab.filterEditLastText)
    end
    if tbug.doDebug then d(">ActiveTab: " ..tos(activeTab.tabName) .. ", lastMode: " ..tos(activeTab.filterModeButtonLastMode) ..", filterEditLastText: " ..tos(activeTab.filterEditLastText)) end
end

function TabWindow:connectFilterComboboxToPanel(tabIndex)
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

    --d("[TBUG]TabWindow:connectFilterComboboxToPanel-tabIndex:" ..tostring(tabIndex))
    local isGlobalInspector = self.control.isGlobalInspector
    if isGlobalInspector == true then
        local globalInspector = tbug.getGlobalInspector(true)
        if globalInspector ~= nil then
            -->See globalinspector.lua, GlobalInspector:connectFilterComboboxToPanel(tabIndex)
            globalInspector:connectFilterComboboxToPanel(tabIndex)
        end
    end
end


function TabWindow:setTabTitle(key, title)
    local tabControl = self:getTabControl(key)
    tabControl.label:SetText(title)
end


------------------------------------------------------------------------------------------------------------------------
--- Filter function

function TabWindow:updateFilter(filterEdit, mode, filterModeStr, searchTextDelay)
    searchTextDelay = searchTextDelay or 500

    if tbug.doDebug then d("[tbug]TabWindow:updateFilter-mode: " ..tos(mode) .. ", filterModeStr: " ..tos(filterModeStr) .. ", searchTextDelay: " ..tos(searchTextDelay)) end

    local function addToSearchHistory(p_self, p_filterEdit)
        saveNewSearchHistoryContextMenuEntry(p_filterEdit, p_self, p_self.control.isGlobalInspector)
    end

    local function filterEditBoxContentsNow(p_self, p_filterEdit, p_mode, p_filterModeStr)
        if tbug.doDebug then d("[tbug]filterEditBoxContentsNow") end

        --Filter by MultiSelect ComboBox dropdown selected entries
        local filterMode = self.filterComboBox.filterMode
        if filterMode and filterMode > 0 then
            local panel = p_self.tabs[filterMode].panel
            if panel then
                --TBUG._filterComboboxMode = filterMode
                --d(">filterEditBoxContentsNow dropDownFilterMode: " .. tostring(filterMode))
                local dropdownFilterFunc
                local selectedDropdownFilters = self:GetSelectedFilters()
                if ZO_IsTableEmpty(selectedDropdownFilters) then
                    --Nothing filtered? Re-enable all entries again
                    dropdownFilterFunc = false
                else
                    --Apply a filter function for the dropdown box
                    FilterFactory.searchedData["ctrl"] = {}
                    dropdownFilterFunc = FilterFactory["ctrl"](selectedDropdownFilters)
                end
                --Set the filter function of the dropdown box
                panel:setDropDownFilterFunc(dropdownFilterFunc)
            end
        end


        --Filter by editBox contents (text)
        local filterEditText = p_filterEdit:GetText()
        local activeTab = p_self:getActiveTab()
        if activeTab ~= nil then
            --d(">set activeTab " .. tos(activeTab.tabName) .. " filterEditLastText to: " ..tos(filterEditText))
            activeTab.filterEditLastText = filterEditText
            activeTab.filterModeButtonLastMode = self.filterMode
        end

        if tbug.doDebug then d(">text: " ..tos(filterEditText)) end

        p_filterEdit.doNotRunOnChangeFunc = false
        local expr = strmatch(filterEditText, "(%S+.-)%s*$")
        local filterFunc
        p_filterModeStr = p_filterModeStr or filterModes[p_mode]
        --d(strformat("[filterEditBoxContentsNow]expr: %s, mode: %s, modeStr: %s", tos(expr), tos(p_mode), tos(p_filterModeStr)))
        if expr then
            FilterFactory.searchedData[p_filterModeStr] = {}
            filterFunc = FilterFactory[p_filterModeStr](expr)
        else
            filterFunc = false
        end

        --todo: For debugging
        --[[
        TBUG._filterData = {
            self = p_self,
            panels = p_self.panels,
            filterEdit = p_filterEdit,
            mode = p_mode,
            modeStr = p_filterModeStr,
            filterFunc = filterFunc,
        }
        ]]
        local gotPanels = (p_self.panels ~= nil and true) or false --at global inspector e.g.
        local gotActiveTabPanel = (activeTab ~= nil and activeTab.panel ~= nil and true) or false --at other inspectors
        local filterFuncValid = (filterFunc ~= nil and true) or false

        if tbug.doDebug then d(">gotPanels: " ..tos(gotPanels) ..", gotActiveTabPanel: " ..tos(gotActiveTabPanel) .. ", filterFuncValid: " ..tos(filterFuncValid)) end

        if gotPanels then
            --At the global inspector e.g.
            if filterFuncValid then
                --Set the filterFunction to all panels -> BasicInspectorPanel:setFilterFunc
                --> Will call refreshFilter->filterScrollList->sortScrollList and commitScrollList this way
                --> filterScrollList will use function at filterFunc to filter the ZO_SortFilterScrollList then!
                for _, panel in next, p_self.panels do
                    panel:setFilterFunc(filterFunc, false)
                end
                p_filterEdit:SetColor(p_self.filterColorGood:UnpackRGBA())
            else
                p_filterEdit:SetColor(p_self.filterColorBad:UnpackRGBA())
            end
        elseif gotActiveTabPanel == true then
            --No normal panels: But subjectToPanel lookup exists
            if filterFuncValid then
                local panelToFilter = getActiveTabPanel(p_self)
                if panelToFilter ~= nil and panelToFilter.setFilterFunc ~= nil then
                    panelToFilter:setFilterFunc(filterFunc, nil)
                    p_filterEdit:SetColor(p_self.filterColorGood:UnpackRGBA())
                    gotPanels = true
                else
                    p_filterEdit:SetColor(p_self.filterColorBad:UnpackRGBA())
                end
            else
                p_filterEdit:SetColor(p_self.filterColorBad:UnpackRGBA())
            end

        end
        return filterFuncValid and gotPanels
    end

    throttledCall("merTorchbugSearchEditChanged", searchTextDelay,
            filterEditBoxContentsNow, self, filterEdit, mode, filterModeStr
    )

    if not filterEdit.doNotSaveToSearchHistory then
        throttledCall("merTorchbugSearchEditAddToSearchHistory", 2000,
                addToSearchHistory, self, filterEdit
        )
    else
        filterEdit.doNotSaveToSearchHistory = false
    end
end

--Update the current inspector's active tab's panel filterEdit with the search text, or the searchText table,
--set the search modem and optionally search now
function TabWindow:updateFilterEdit(searchText, searchMode, searchDelay)
    searchMode = searchMode or getFilterMode(self)
    --d("[TB]updateFilterEdit -searchText: " ..tos(searchText) .. ", searchMode: " ..tos(searchMode))
    if searchText == nil then return end

    local activePanel = getActiveTabPanel(self)
    if activePanel == nil then return end
    --d(">found active panel!")

    local editControl = self.filterEdit
    if editControl == nil then return end
    --d(">found active panel's filter editControl!")

    local searchTextType = type(searchText)
    searchText = (searchTextType == "table" and tcon(searchText, " ")) or tos(searchText)
    if searchText == nil then return end
--d(">searchText: " .. tos(searchText))
    editControl:SetText(searchText)
    self:updateFilter(editControl, searchMode, nil, searchDelay)
end

------------------------------------------------------------------------------------------------------------------------
--- Filter multi select combobox
---
function TabWindow:SetSelectedFilterText()
    local comboBox = self.filterComboBox.m_comboBox
    local dropdown = self.filterComboBoxDropdown
    dropdown:SetNoSelectionText(noFilterSelectedText)

    local selectedEntries = comboBox:GetNumSelectedEntries()
--d("[TBUG]TabWindow:SetSelectedFilterText - selectedEntries: " ..tostring(selectedEntries))
    if selectedEntries == 1 then
        local selectedFilterText = tostring(comboBox.m_selectedItemData[1].name)
        dropdown:SetMultiSelectionTextFormatter(selectedFilterText)
    else
        dropdown:SetMultiSelectionTextFormatter(filterSelectedText)
    end
end

function TabWindow:GetSelectedFilters()
--d("[TBUG]TabWindow:GetSelectedFilters")
    local filtersDropdown = self.filterComboBoxDropdown
    local selectedFilterTypes = {}
    for _, item in ipairs(filtersDropdown:GetItems()) do
        if filtersDropdown:IsItemSelected(item) then
            selectedFilterTypes[item.filterType] = true
        end
    end
    return selectedFilterTypes
end

function TabWindow:OnFilterComboBoxChanged()
--d("[TBUG]TabWindow:OnFilterComboBoxChanged")
    self:SetSelectedFilterText()

    local mode = self.filterMode
    self:updateFilter(self.filterEdit, mode, filterModes[mode], nil)
end
