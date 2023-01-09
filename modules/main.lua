local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")
local myNAME = TBUG.name

local EM = EVENT_MANAGER

local sessionStartTime = tbug.sessionStartTime
local ADDON_MANAGER

local addOns = {}
local scenes = {}
local fragments = {}
tbug.IsEventTracking = false

local tbug_inspectorScrollLists = tbug.inspectorScrollLists

local titlePatterns =       tbug.titlePatterns
local titleTemplate =       titlePatterns.normalTemplate
local titleMocTemplate =    titlePatterns.mouseOverTemplate
local specialInspectTabTitles = tbug.specialInspectTabTitles

local specialLibraryGlobalVarNames = tbug.specialLibraryGlobalVarNames

local serversShort = tbug.serversShort

local tos = tostring
local ton = tonumber
local strformat = string.format
local strfind = string.find
local strgmatch = string.gmatch
local strlower = string.lower
local strsub = string.sub
local strlen = string.len
local zo_ls = zo_loadstring
local tins = table.insert
local trem = table.remove
local tcon = table.concat
local firstToUpper = tbug.firstToUpper
local startsWith = tbug.startsWith
local endsWith = tbug.endsWith

local classes = tbug.classes
local filterModes = tbug.filterModes
local panelNames = tbug.panelNames

local tbug_glookup = tbug.glookup
local tbug_getKeyOfObject = tbug.getKeyOfObject
local tbug_inspect


local function strsplit(inputstr, sep)
   sep = sep or "%s" --whitespace
   local t={}
   for str in strgmatch(inputstr, "([^"..sep.."]+)") do
      tins(t, str)
   end
   return t
end
tbug.strSplit = strsplit

local function evalString(source, funcOnly)
    funcOnly = funcOnly or false
    -- first, try to compile it with "return " prefixed,
    -- this way we can evaluate things like "_G.tab[5]"
    local func, err = zo_ls("return " .. source)
--d("[tbug]evalString-source: " ..tos(source) .. ", funcOnly: " .. tos(funcOnly) .. ", func: " .. tos(func) .. ", err: " .. tos(err))
--[[
tbug._evalString = {
    source = source,
    funcOnly = funcOnly,
    func = func,
    err = err,
}
]]
    if not func then
        -- failed, try original source
        func, err = zo_ls(source, "<< " .. source .. " >>")
--d(">Failed, original source func: " .. tos(func) .. ", err: " .. tos(err))
        if not func then
            return func, err
        end
    end
    if funcOnly then
--d("<returning func, err")
        -- return the function
        return func, err
    else
--d("<returning pcall(func, tbug.env)")
        -- run compiled chunk in custom  (_G)
        return pcall(setfenv(func, tbug.env))
    end
end

local function compareBySubTablesKeyName(a,b)
    if a.name and b.name then return a.name < b.name
    elseif a.__name and b.__name then return a.__name < b.__name end
end

--[[
local function compareBySubTablesLoadOrderIndex(a,b)
    if a._loadOrderIndex and b._loadOrderIndex then return a._loadOrderIndex < b._loadOrderIndex end
end
]]

--Check if a key or value is already inside a table
--checkKeyOrValue - true: Check the key, false: Check the value
local function checkIfAlreadyInTable(table, key, value, checkKeyOrValue)
    if not table or checkKeyOrValue == nil then return false end
    if checkKeyOrValue == true then
        if not key then return false end
        if table[key] == nil then return true end
    else
        if not value then return false end
        for k, v in pairs(table) do
            if key ~= nil then
                if k == key then
                    if v == value then return true end
                end
            else
                if v == value then return true end
            end
        end
    end
    return false
end

local function showDoesNotExistError(object, winTitle, tabTitle)
--d("[TBUG]showDoesNotExistError - object: " ..tostring(object) .. ", winTitle: " ..tostring(winTitle) ..", tabTitle: " .. tostring(tabTitle))
    local errText = "[TBUG]No inspector for \'%s\' (%q)"
    local title = (winTitle ~= nil and tos(winTitle)) or tos(tabTitle)
    df(errText, title, tos(object))
end

local function showFunctionReturnValue(object, tabTitle, winTitle, objectParent)
--d("[tbug]showFunctionReturnValue")
    local wasRunWithoutErrors, resultsOfFunc = pcall(setfenv(object, tbug.env))
    local title = (winTitle ~= nil and tos(winTitle)) or tos(tabTitle) or ""
    title = (objectParent ~= nil and objectParent ~= "" and objectParent and ".") or "" .. title
--d(">wasRunWithoutErrors: " ..tos(wasRunWithoutErrors) .. ", resultsOfFunc: " ..tos(resultsOfFunc) .. ", title: " ..tos(title))

    if wasRunWithoutErrors == true then
        d((resultsOfFunc == nil and "[TBUG]No results for function \'" .. tos(title) .. "\'") or "[TBUG]Results of function \'" .. tos(title) .. "\':")
    else
        d("[TBUG]<<<ERROR>>>Function \'" .. tos(title) .. "\' ended with errors:")
    end
    if resultsOfFunc == nil then return end
--tbug._resultsOfFunc = resultsOfFunc
    if type(resultsOfFunc) == "table" then
        for k, v in ipairs(resultsOfFunc) do
            d("["..tos(k).."] "..v)
        end
    else
        d("[1] "..tos(resultsOfFunc))
    end
end

--Parse the arguments string
local function parseSlashCommandArgumentsAndReturnTable(args, doLower)
    doLower = doLower or false
    local argsAsTable = {}
    if not args then return argsAsTable end
    args = zo_strtrim(args)
    --local searchResult = {} --old: searchResult = { string.match(args, "^(%S*)%s*(.-)$") }
    for param in strgmatch(args, "([^%s]+)%s*") do
        if param ~= nil and param ~= "" then
            argsAsTable[#argsAsTable+1] = (not doLower and param) or strlower(param)
        end
    end
    return argsAsTable
end
tbug.parseSlashCommandArgumentsAndReturnTable = parseSlashCommandArgumentsAndReturnTable

local function getSearchDataAndUpdateInspectorSearchEdit(searchData, inspector)
d("[TB]getSearchDataAndUpdateInspectorSearchEdit")
    if searchData ~= nil and inspector ~= nil and inspector.updateFilterEdit ~= nil then
        local searchText = searchData.searchText
d(">searchStr: " .. tos(searchText))
        if searchText ~= nil then
            inspector:updateFilterEdit(searchText, searchData.mode, searchData.delay)
        end
    end
end
tbug.getSearchDataAndUpdateInspectorSearchEdit = getSearchDataAndUpdateInspectorSearchEdit

local function buildSearchData(searchValues, delay)
    delay = delay or 10
    local searchText = ""
    local searchMode = 1 --String search

    if searchValues ~= nil then
        local searchOptions = parseSlashCommandArgumentsAndReturnTable(searchValues, false)
        if searchOptions == nil or searchOptions ~= nil and #searchOptions == 0 then return end
        --Check if the 1st param was a number -> and if it's a valid searchMode number: Use it.
        --Else: Use it as normal search string part
        searchMode = ton(searchOptions[1])
        --{ [1]="str", [2]="pat", [3]="val", [4]="con" }
        if searchMode ~= nil and type(searchMode) == "number" and filterModes[searchMode] ~= nil then
            searchText = tcon(searchOptions, " ", 2, #searchOptions)
        else
            searchText = tcon(searchOptions, " ", 1, #searchOptions)
        end
    end

    return {
        searchText =    searchText,
        mode =          searchMode,
        delay =         delay
    }
end
tbug.buildSearchData = buildSearchData

local function inspectResults(specialInspectionString, searchData, source, status, ...) --... contains the compiled result of pcall (evalString)
    local doDebug = tbug.doDebug --TODO: disable again if not needed!
    if doDebug then
        TBUG._status = status
        TBUG._evalData = {...}
    end

    local recycle = not IsShiftKeyDown()
    local isMOCFromGlobalEventMouseUp = (specialInspectionString and specialInspectionString == "MOC_EVENT_GLOBAL_MOUSE_UP") or false
    --Prevent SHIFT key handling at EVENT_GLOBAL_MOUSE_UP, as the shift key always needs to be pressed there!
    if isMOCFromGlobalEventMouseUp == true then recycle = true end
    local isMOC = (specialInspectionString ~= nil and (isMOCFromGlobalEventMouseUp == true or specialInspectionString == "MOC")) or false
    if doDebug then d("tb: inspectResults - specialInspectionString: " ..tos(specialInspectionString) .. ", source: " ..tos(source) .. ", status: " ..tos(status) .. ", recycle: " ..tos(recycle) .. ", isMOC: " ..tos(isMOC) .. ", searchData: " ..tos(searchData)) end
    if not status then
        local err = tos(...)
        err = err:gsub("(stack traceback)", "|cff3333%1", 1)
        err = err:gsub("%S+/(%S+%.lua:)", "|cff3333> |c999999%1")
        df("[TBUG]<<<ERROR>>>\n%s", err)
        return
    end
    local firstInspectorShow = false
    local firstInspector = tbug.firstInspector
    local globalInspector = nil
    local nres = select("#", ...)
    if doDebug then d(">nres: " ..tos(nres)) end
    local numTabs = 0
    local errorOccured = false
    if firstInspector and firstInspector.tabs then
        numTabs = #firstInspector.tabs
        if doDebug then d(">>firstInspector found with numTabs: " ..tos(numTabs)) end
    end
    --Increase the number of tabs by 1 to show the correct number at the tab title and do some checks
    --The actual number of tabs increases in #firstInspector.tabs after (further down below) a new tab was created
    --via local newTab = firstInspector:openTabFor(...)
    numTabs = numTabs + 1
    local calledRes = 0
    for ires = 1, nres do
        local res = select(ires, ...)
        calledRes = calledRes +1
        if rawequal(res, _G) then
            if not globalInspector then
                if doDebug then d(">>globalInspector shows _G var") end
                globalInspector = tbug.getGlobalInspector()
                globalInspector:refresh()
                globalInspector.control:SetHidden(false)
                globalInspector.control:BringWindowToTop()
                getSearchDataAndUpdateInspectorSearchEdit(searchData, globalInspector)
            end
        else
            if doDebug then d(">>no _G var") end
            local tabTitle = ""
            if isMOC == true then
                tabTitle = titleMocTemplate
            end
            if not isMOC and specialInspectionString and specialInspectionString ~= "" then
                tabTitle = specialInspectionString
            else
                tabTitle = strformat("%d", ton(numTabs) or ires)
            end
            tabTitle = strformat(titleTemplate, tos(tabTitle))
            if firstInspector then
                if type(source) ~= "string" then
                    source = tbug.getControlName(res)
                else
                    if not isMOC and not specialInspectionString and type(ton(tabTitle)) == "number" then
                        local objectKey = tbug_getKeyOfObject(source)
                        if objectKey and objectKey ~= "" then
                            tabTitle = objectKey
                        end
                    end
                end
                --Open existing tab in firstInspector

                --Use existing inspector?
                if recycle == true then
                    local newTab = firstInspector:openTabFor(res, tabTitle, source)

                    if doDebug then
                        tbug._res = res
                        tbug._newTab = newTab
                    end

                    if newTab ~= nil then
                        if doDebug then d(">>newTab at first inspector!") end
                        --local newTabLabelText = newTab.label:GetText()
                        --local newTabLabelTextNew = ((isMOC == true and newTabLabelText .. " " .. source) or (specialInspectionString ~= nil and newTabLabelText)) or source
                        --df(">newTabLabelTextNew: %s, tabTitle: %s, source: %s", tos(newTabLabelTextNew), tos(tabTitle), tos(source))
                        --firstInspector.title:SetText(newTabLabelTextNew)
                        firstInspectorShow = true
                    else
                        if doDebug then d(">>tbug_inspect - res: " ..tos(res) .. ", source: " ..tos(source)) end
                        tbug_inspect = tbug_inspect or tbug.inspect
                        tbug_inspect(res, tabTitle, source, recycle, nil, ires, {...}, nil, searchOptions)
                        --showDoesNotExistError(res, source, nil)
                        errorOccured = true
                    end
                else
                    if doDebug then d(">>create new inspector!") end
                    --Or open new one (SHIFT key was pressed)
                    tbug_inspect = tbug_inspect or tbug.inspect
                    tbug_inspect(res, tabTitle, source, recycle, nil, ires, {...}, nil, searchOptions)
                end
            else
                if doDebug then d(">Creating firstInspector") end
                --Create new firstInspector
                if not isMOC and not specialInspectionString and source and source ~= "" and type(source) == "string" and type(ton(tabTitle)) == "number" then
                    local objectKey = tbug_getKeyOfObject(source)
                    if objectKey and objectKey ~= "" then
                        tabTitle = objectKey
                    end
                end
                if doDebug then d(">res: " ..tos(res) .. ", tabTitle: " ..tos(tabTitle) .. ", source: " ..tos(source)) end
                tbug_inspect = tbug_inspect or tbug.inspect
                firstInspector = tbug_inspect(res, tabTitle, source, recycle, nil, ires, {...}, nil, searchOptions)
                firstInspectorShow = true
            end
        end
    end
    if calledRes == 0 then
        errorOccured = true
    end
    if doDebug then d(">calledRes: " ..tostring(calledRes) .. ", errorOccured: " ..tos(errorOccured)) end
    if firstInspector ~= nil then
        if doDebug then d(">firstInspector found, numTabs: " ..tos(numTabs) .. ", #firstInspector.tabs: " ..tos(#firstInspector.tabs)) end
        if not errorOccured then
            if not firstInspectorShow and numTabs > 0 and #firstInspector.tabs > 0 then firstInspectorShow = true end
            if firstInspectorShow == true then
                firstInspector.control:SetHidden(false)
                firstInspector.control:BringWindowToTop()
            end
        end
        tbug.firstInspector = firstInspector
    end
end

function tbug.prepareItemLink(control, asPlainText)
    asPlainText = asPlainText or false
    local itemLink = ""
    local bagId = (control.dataEntry and control.dataEntry.data and (control.dataEntry.data.bagId or control.dataEntry.data.bag)) or
            (control.dataEntry and (control.dataEntry.bagId or control.dataEntry.bag))
            or control.bagId or control.bag
    local slotIndex = (control.dataEntry and control.dataEntry.data and (control.dataEntry.data.slotIndex or control.dataEntry.data.index or control.dataEntry.data.slot)) or
            (control.dataEntry and (control.dataEntry.slotIndex or control.dataEntry.index or control.dataEntry.slot))
            or control.slotIndex or control.index or control.slot
    if bagId == nil or slotIndex == nil then
        local parentControl = control:GetParent()
        if parentControl ~= nil then
            bagId = (parentControl.dataEntry and parentControl.dataEntry.data and (parentControl.dataEntry.data.bagId or parentControl.dataEntry.data.bag)) or
                    (parentControl.dataEntry and (parentControl.dataEntry.bagId or parentControl.dataEntry.bag))
                    or parentControl.bagId or parentControl.bag
            slotIndex = (parentControl.dataEntry and parentControl.dataEntry.data and (parentControl.dataEntry.data.slotIndex or parentControl.dataEntry.data.index or parentControl.dataEntry.data.slot)) or
                    (parentControl.dataEntry and (parentControl.dataEntry.slotIndex or parentControl.dataEntry.index or parentControl.dataEntry.slot))
                    or parentControl.slotIndex or parentControl.index or parentControl.slot
        end
    end

    if bagId and slotIndex and type(bagId) == "number" and type(slotIndex) == "number" then
        itemLink = GetItemLink(bagId, slotIndex, LINK_STYLE_BRACKETS)
    end
    if itemLink and itemLink ~= "" and asPlainText == true then
        --Controls within ESO will show itemLinks "comiled" as clickable item's link. If we only want the ||h* plain text
        --we need to remove the leading | so that it's not recognized as an itemlink anymore
        local ilPlaintext = itemLink:gsub("^%|", "", 1)
        itemLink = "| " .. ilPlaintext
    end
    return itemLink
end

function tbug.inspect(object, tabTitle, winTitle, recycleActive, objectParent, currentResultIndex, allResults, data, searchData)
    local inspector = nil

    local doDebug = tbug.doDebug --TODO: change again

    local resType = type(object)
    if doDebug then d("[tbug.inspect]object: " ..tos(object) .. ", objType: "..tos(resType) ..", tabTitle: " ..tos(tabTitle) .. ", winTitle: " ..tos(winTitle) .. ", recycleActive: " .. tos(recycleActive) ..", objectParent: " ..tos(objectParent)) end
    if rawequal(object, _G) then
        if doDebug then d(">rawequal _G") end
        inspector = tbug.getGlobalInspector()
        inspector.control:SetHidden(false)
        inspector:refresh()
        getSearchDataAndUpdateInspectorSearchEdit(searchData, inspector)
    elseif resType == "table" then
        if doDebug then d(">table") end
        local title = tbug_glookup(object) or winTitle or tos(object)
        if not endsWith(title, "[]") then title = title .. "[]" end
        inspector = classes.ObjectInspector:acquire(object, tabTitle, recycleActive, title)
        inspector.control:SetHidden(false)
        inspector:refresh()
        getSearchDataAndUpdateInspectorSearchEdit(searchData, inspector)
    elseif tbug.isControl(object) then
        if doDebug then d(">isControl") end
        local title = ""
        if type(winTitle) == "string" then
            title = winTitle
        else
            title = tbug.getControlName(object)
        end
        inspector = classes.ObjectInspector:acquire(object, tabTitle, recycleActive, title, data)
        inspector.control:SetHidden(false)
        inspector:refresh()
        getSearchDataAndUpdateInspectorSearchEdit(searchData, inspector)
    elseif resType == "function" then
        if doDebug then d(">function") end
        showFunctionReturnValue(object, tabTitle, winTitle, objectParent)
    else
        if doDebug then d(">all others...") end
        --Check if the source of the call was ending on () -> it was a function call then
        --Output the function data then
        local wasAFunction = false
        if winTitle and winTitle ~= "" then
            local winTitleLast2Chars = strsub(winTitle, -2)
            local winTitleLastChar = strsub(winTitle, -1)
            if winTitleLast2Chars == "()" or winTitleLastChar == ")" then
                wasAFunction = true
            end
        end
        if not wasAFunction then
            if doDebug then d(">>showDoesNotExistError") end
            showDoesNotExistError(object, winTitle, tabTitle)
        else
            --Object contains the current return value of the function.
            --currentResult is the index of that result, in table allResults.
            --Output the function return value text, according to the "call to tbug.inspect"
            if currentResultIndex and allResults then
                if currentResultIndex == 1 then
                    d("[TBUG]Results of function \'" .. tos((winTitle ~= nil and winTitle ~= "" and winTitle) or tabTitle) .. "\':")
                end
                d("[" ..tos(currentResultIndex) .."]" .. tos(object))
            end
        end
    end
    return inspector
end
tbug_inspect = tbug.inspect

--Get a panel of an inspector
function tbug.getInspectorPanel(inspectorName, panelName)
    if tbug[inspectorName] then
        local inspector = tbug[inspectorName]
        local panels = inspector.panels
        if panels and panels[panelName] then
            return panels[panelName]
        end
    end
    return nil
end
local tbug_getInspectorPanel = tbug.getInspectorPanel

--Refresh the panel of a TableInspector
function tbug.refreshInspectorPanel(inspectorName, panelName, delay)
    delay = delay or 0
--d("[tbug.refreshInspectorPanel]inspectorName: " ..tos(inspectorName) .. ", panelName: " ..tos(panelName) .. ", delay: " ..tos(delay))
    local function refreshPanelNow()
        local panel = tbug_getInspectorPanel(inspectorName, panelName)
        if panel and panel.refreshData then
            --d(">refreshing now...")
            panel:refreshData()
            if panel.refreshVisible then panel:refreshVisible() end
        end
    end
    --Delayed call?
    if delay > 0 then
        zo_callLater(function() refreshPanelNow() end, delay)
    else
        refreshPanelNow()
    end
end
local tbug_refreshInspectorPanel = tbug.refreshInspectorPanel

--Check if the TBUG TableInspector with the scripts tab is currently shown and needs a refresh then
function tbug.checkIfInspectorPanelIsShown(inspectorName, panelName)
    if tbug[inspectorName] then
        local panel = tbug_getInspectorPanel(inspectorName, panelName)
        local panelCtrl = panel.control
        if panelCtrl and panelCtrl.IsHidden then
            return not panelCtrl:IsHidden()
        end
    end
    return false
end
local tbug_checkIfInspectorPanelIsShown = tbug.checkIfInspectorPanelIsShown

--Select the tab at the global inspector
function tbug.inspectorSelectTabByName(inspectorName, tabName, tabIndex, doCreateIfMissing, searchData)
    doCreateIfMissing = doCreateIfMissing or false
d("[TB]inspectorSelectTabByName - inspectorName: " ..tos(inspectorName) .. ", tabName: " ..tos(tabName) .. ", tabIndex: " ..tos(tabIndex) .. ", doCreateIfMissing: " ..tos(doCreateIfMissing) ..", searchData: ".. tos(searchData))
    if tbug[inspectorName] then
        local inspector = tbug[inspectorName]
        local isGlobalInspector = (inspectorName == "globalInspector") or false
        if inspector.getTabIndexByName and inspector.selectTab then
            --Special treatment: Restore all the global inspector tabs
            if isGlobalInspector == true and tabName == "-all-" and doCreateIfMissing == true then
                inspector:connectPanels(nil, true, true, nil)
                tabIndex = 1
            else
                tabIndex = tabIndex or inspector:getTabIndexByName(tabName)
--d(">tabIndex: " ..tos(tabIndex))
                --The tabIndex could be taken "hardcoded" from the table tbug.panelNames. So check if the current inspector's tab's really got a tab with the name of that index!
                if doCreateIfMissing == true then
                    local connectPanelNow = false
                    if isGlobalInspector == true then
--d(">>connecting tab new again: " ..tos(tabName))
                        if (not tabIndex or (tabIndex ~= nil and not inspector:getTabIndexByName(panelNames[tabIndex].name))) then
                            connectPanelNow = true
                        end
                    else
                        if tabIndex == nil then
                            connectPanelNow = true
                        end
                    end
                    if connectPanelNow == true then
                        inspector:connectPanels(tabName, true, false, tabIndex) --use the tabIndex to assure the differences between e.g. sv and Sv (see tbug.panelNames) are met!
                        tabIndex = inspector:getTabIndexByName(tabName)
                    end
                end
            end
            if tabIndex then
                inspector:selectTab(tabIndex)
                getSearchDataAndUpdateInspectorSearchEdit(searchData, inspector)
            end
        end
    end
end
local tbug_inspectorSelectTabByName = tbug.inspectorSelectTabByName

------------------------------------------------------------------------------------------------------------------------

function tbug.slashCommandMOC(comingFromEventGlobalMouseUp, searchData)
    comingFromEventGlobalMouseUp = comingFromEventGlobalMouseUp or false
--d("tbug.slashCommandMOC - comingFromEventGlobalMouseUp: " ..tos(comingFromEventGlobalMouseUp))
    local env = tbug.env
    local wm = env.wm
    if not wm then return end
    local mouseOverControl = wm:GetMouseOverControl()
    --local mocName = (mouseOverControl ~= nil and ((mouseOverControl.GetName and mouseOverControl:GetName()) or mouseOverControl.name)) or "n/a"
--d(">mouseOverControl: " .. tos(mocName))
    if mouseOverControl == nil then return end

    inspectResults((comingFromEventGlobalMouseUp == true and "MOC_EVENT_GLOBAL_MOUSE_UP") or "MOC", searchData, mouseOverControl, true, mouseOverControl)
end
local tbug_slashCommandMOC = tbug.slashCommandMOC

function tbug.slashCommand(args, searchValues)
    local supportedGlobalInspectorArgs = tbug.allowedSlashCommandsForPanels
    local supportedGlobalInspectorArgsLookup = tbug.allowedSlashCommandsForPanelsLookup

    local searchData = buildSearchData(searchValues, 10) --10 milliseconds delay before search starts

    if args ~= "" then
        if tbug.doDebug then d("[tbug]slashCommand - " ..tos(args) .. ", searchValues: " ..tos(searchValues)) end
        local argsOptions = parseSlashCommandArgumentsAndReturnTable(args, true)

        --local moreThanOneArg = (argsOptions and #argsOptions > 1) or false
        local argOne = argsOptions[1]

        if argOne == "mouse" or argOne == "m" then
            tbug_slashCommandMOC(false, searchValues)
        elseif argOne == "free" then
            SetGameCameraUIMode(true)
        else
            local isSupportedGlobalInspectorArg = supportedGlobalInspectorArgs[argOne] or false
            --Check if only a number was passed in and then select the tab index of that number
            if not isSupportedGlobalInspectorArg then
                local firstArgNum = ton(argOne)
                if firstArgNum ~= nil and type(firstArgNum) == "number" and panelNames[firstArgNum] ~= nil then
                    argOne = panelNames[firstArgNum].slashCommand[1] -- use the 1st slashCommand of that panel as arguent 1 now
                    isSupportedGlobalInspectorArg = true
                end
            end
            if isSupportedGlobalInspectorArg then
                local supportedGlobalInspectorArg = firstToUpper(argOne)

                --Were searchValues added from a slash command, but they are provided via the 1st param "args"?
                if #argsOptions > 1 and searchValues == nil then
                    searchValues = tcon(argsOptions, " ", 2, #argsOptions)
                    searchData = buildSearchData(searchValues, 10) --10 milliseconds delay before search starts
                end

                --Call/show the global inspector
                if tbugGlobalInspector and tbugGlobalInspector:IsHidden() then
                    inspectResults(nil, nil, "_G", true, _G) -- Only call/create the global inspector, do no search. Will be done below at the "inspectorSelectTabByName" or "inspect results"
                end
                --Select the tab named in the slashcommand parameter
                local tabIndexToShow = supportedGlobalInspectorArgsLookup[supportedGlobalInspectorArg]
                if tbug.doDebug then d(">>tabIndexToShow: " ..tos(tabIndexToShow)) end
                if tabIndexToShow ~= nil then
                    if tbug.doDebug then d(">tbug_inspectorSelectTabByName") end
                    tbug_inspectorSelectTabByName("globalInspector", supportedGlobalInspectorArg, tabIndexToShow, true, searchData)
                else
                    if tbug.doDebug then d(">inspectResults1") end
                    inspectResults(nil, searchData, args, evalString(args)) --evalString uses pcall and returns boolean, table(nilable)
                end
            else
                local specialInspectTabTitle
                --e.g. listtlc -> Calls function ListTLC()
                for startStr, replaceData in pairs(specialInspectTabTitles) do
                    if startsWith(argOne, startStr) then
                        specialInspectTabTitle = replaceData.tabTitle

                        if replaceData.functionToCall ~= nil and replaceData.functionToCall ~= "" then
                            --Only 1 argument and argOne does not end on ) (closed function parameters)
                            if #argsOptions == 1 and not tbug.endsWith(argOne, ")") then
                                --replace the arguments with replaceData.functionToCall
                                args = replaceData.functionToCall
                            end
                        end
                        break
                    end
                end
                if tbug.doDebug then d(">>>>>specialInspectTabTitle: " ..tos(specialInspectTabTitle) .. ", args: " ..tos(args)) end
                --d(">inspectResults2")
                inspectResults(specialInspectTabTitle, searchData, args, evalString(args)) --evalString uses pcall and returns boolean, table(nilable) (->where the table will be the ... at inspectResults)
            end
        end
    elseif tbugGlobalInspector then
        if tbugGlobalInspector:IsHidden() then
            if tbug.doDebug then d(">show GlobalInspector") end
            inspectResults(nil, searchData, "_G", true, _G)
        else
            if tbug.doDebug then d(">hide GlobalInspector") end
            tbugGlobalInspector:SetHidden(true)
        end
    end
end
local tbug_slashCommand = tbug.slashCommand

function tbug.slashCommandSavedVariables(args)
    tbug_slashCommand("sv", args)
end
local tbug_slashCommandSavedVariables = tbug.slashCommandSavedVariables

function tbug.slashCommandEvents(args)
    tbug_slashCommand("events", args)
end
local tbug_slashCommandEvents = tbug.slashCommandEvents

function tbug.slashCommandScripts(args)
    tbug_slashCommand("scripts", args)
end
local tbug_slashCommandScripts = tbug.slashCommandScripts

function tbug.slashCommandAddOns(args)
    tbug_slashCommand("addons", args)
end
local tbug_slashCommandAddOns = tbug.slashCommandAddOns

function tbug.slashCommandStrings(args)
    tbug_slashCommand("strings", args)
end
local tbug_slashCommandStrings = tbug.slashCommandStrings

function tbug.slashCommandTBUG(args)
    tbug_slashCommand("TBUG", args)
end
local tbug_slashCommandTBUG = tbug.slashCommandTBUG

function tbug.slashCommandITEMLINKINFO(args)
    if not args or args=="" then return end
    args = zo_strtrim(args)
    if args ~= "" then
        local il = args
        d(">>>~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~>>>")
        d("[TBUG]Itemlink Info: " .. il .. ", id: " ..tos(GetItemLinkItemId(il)))
        local itemType, specItemType = GetItemLinkItemType(il)
        d(string.format("-itemType: %s, specializedItemtype: %s", tos(itemType), tos(specItemType)))
        d(string.format("-armorType: %s, weaponType: %s, equipType: %s", tos(GetItemLinkArmorType(il)), tos(GetItemLinkWeaponType(il)), tos(GetItemLinkEquipType(il))))
        d("<<<~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~<<<")
    end
end
local tbug_slashCommandITEMLINKINFO = tbug.slashCommandITEMLINKINFO

function tbug.slashCommandITEMLINK()
    local il = tbug.prepareItemLink(moc(), false)
    if not il or il=="" then return end
    --d(il)
    --StartChatInput("/tbiinfo "..il, CHAT_CHANNEL_SAY, nil)
    tbug.slashCommandITEMLINKINFO(il)
end
local tbug_slashCommandITEMLINK = tbug.slashCommandITEMLINK

function tbug.slashCommandSCENEMANAGER()
    tbug_slashCommand("SCENE_MANAGER")
end
local tbug_slashCommandSCENEMANAGER = tbug.slashCommandSCENEMANAGER


function tbug.slashCommandDumpToChat(slashArguments)
    --Dump the slashArguments' values to the chat
    local funcOfSlashArgs, errorText = zo_ls( ("d(\"[TBUG]Dump of \'%s\'\")"):format(slashArguments) )
    if funcOfSlashArgs ~= nil then
        funcOfSlashArgs()
        funcOfSlashArgs = nil
    elseif errorText ~= nil then
        d("[TBUG]|cffff0000Error:|r "..errorText)
    end
end
local tbug_slashCommandDumpToChat = tbug.slashCommandDumpToChat

--Delayed call: /tbd <delayInSeconds> <command1> <command2> ...
function tbug.slashCommandDelayed(args)
    local argsOptions = parseSlashCommandArgumentsAndReturnTable(args, false)
    local moreThanOneArg = (argsOptions and #argsOptions > 1) or false
    if moreThanOneArg then
        --Multiple arguments given after the slash command
        local secondsToDelay = ton(argsOptions[1])
        if not secondsToDelay or type(secondsToDelay) ~= "number" then return end
        --Get the other arguments
        local argsLeftStr = ""
        for i=2, #argsOptions, 1 do
            if i>2 then
                argsLeftStr = argsLeftStr .. " " .. argsOptions[i]
            else
                argsLeftStr = argsLeftStr .. argsOptions[i]
            end
        end
        d(strformat("[TBUG]Delayed call to: \'%s\' (delay=%ss)", argsLeftStr, tos(secondsToDelay)))
        if argsLeftStr ~= "" then
            zo_callLater(function()
                tbug_slashCommand(argsLeftStr)
            end, secondsToDelay * 1000)
        end
    end
end
local tbug_slashCommandDelayed = tbug.slashCommandDelayed

--Call the "Mouse cursor over control" slash command, but delayed (1st param of args)
function tbug.slashCommandMOCDelayed(args)
    local argsOptions = parseSlashCommandArgumentsAndReturnTable(args, false)
    local secondsToDelay = (argsOptions ~= nil and ton(argsOptions[1])) or nil
    if not secondsToDelay or type(secondsToDelay) ~= "number" then return end
    local searchValues
    if argsOptions ~= nil then
        local numArgOptions = #argsOptions
        if numArgOptions >= 2 then
            searchValues = tcon(argsOptions, " ", 2, numArgOptions)
        end
    end
    d(strformat("[TBUG]Delayed call to mouse cursor inspect (delay=%ss)", tos(secondsToDelay), tos(searchValues)))
    zo_callLater(function()
                tbug_slashCommandMOC(nil, searchValues)
            end, secondsToDelay * 1000)
end
local tbug_slashCommandMOCDelayed = tbug.slashCommandMOCDelayed

local function controlOutlineFunc(args, withChildren, doRemove)
    if not ControlOutline then return end
    withChildren = withChildren or false
    doRemove = doRemove or false
    local outlineTheControlNowFunc = (doRemove and ControlOutline_ReleaseOutlines) or
            (not doRemove and (withChildren and ControlOutline_OutlineParentChildControls) or ControlOutline_ToggleOutline)
    if outlineTheControlNowFunc == nil then return end
    if args == nil or args == "" then
        local mouseUnderControl = moc()
        if mouseUnderControl ~= nil and mouseUnderControl.GetName then
            args = mouseUnderControl:GetName()
        end
    end
    if args == nil or args == "" then return end

    local argsOptions = parseSlashCommandArgumentsAndReturnTable(args, false)
    local moreThanOneArg = (argsOptions and #argsOptions >= 1) or false
    if moreThanOneArg then
        for _, control in ipairs(argsOptions) do
            if _G[control] ~= nil then
                outlineTheControlNowFunc(_G[control])
            end
        end
    end
end
function tbug.slashCommandControlOutline(args)
    controlOutlineFunc(args, false, false)
end
local tbug_slashCommandControlOutline = tbug.slashCommandControlOutline

function tbug.slashCommandControlOutlineWithChildren(args)
    controlOutlineFunc(args, true, false)
end
local tbug_slashCommandControlOutlineWithChildren = tbug.slashCommandControlOutlineWithChildren

function tbug.slashCommandControlOutlineRemove(args)
    controlOutlineFunc(args, true, true)
end
local tbug_slashCommandControlOutlineRemove = tbug.slashCommandControlOutlineRemove

function tbug.slashCommandControlOutlineRemoveAll(args)
    if not ControlOutline then return end
    ControlOutline_ReleaseAllOutlines()
end
local tbug_slashCommandControlOutlineRemoveAll = tbug.slashCommandControlOutlineRemoveAll

function tbug.dumpConstants()
    --Dump the constants to the SV table merTorchbugSavedVars_Dumps
    merTorchbugSavedVars_Dumps = merTorchbugSavedVars_Dumps or {}
    local worldName = serversShort[GetWorldName()]
    merTorchbugSavedVars_Dumps[worldName] = merTorchbugSavedVars_Dumps[worldName] or {}
    local APIVersion = GetAPIVersion()
    merTorchbugSavedVars_Dumps[worldName][APIVersion] = merTorchbugSavedVars_Dumps[worldName][APIVersion] or {}
    merTorchbugSavedVars_Dumps[worldName][APIVersion]["Constants"] = {}
    merTorchbugSavedVars_Dumps[worldName][APIVersion]["SI_String_Constants"] = {}
    --Save the "Constants" tab of the global inspector to the DUMP SVs
    local globalInspector = tbug.getGlobalInspector()
    if not globalInspector then return end
    local constants = globalInspector.panels.constants
    if not constants then return end
    local masterList = constants.masterList
    if not masterList then return end
    local cntConstants, cntSIConstants = 0, 0
    --No entries in the constants list yet? Create it by forcing the /tbug slash command to show the global inspector,
    --and updating all variables
    if #masterList == 0 then
        tbug_slashCommand("Constants")
    end
    for idx, dataTable in ipairs(masterList) do
        --Do not save the SI_ string constants to the same table
        local data = dataTable.data
        local key = data.key
        if key ~= nil then
            local value = data.value
            if value ~= nil then
                local tvIsNumber = (type(value) == "number") or false
                if tvIsNumber == true and string.match(key, '^SI_(.*)') ~= nil then
                    merTorchbugSavedVars_Dumps[worldName][APIVersion]["SI_String_Constants"][key] = value
                    cntSIConstants = cntSIConstants + 1
                else
                    merTorchbugSavedVars_Dumps[worldName][APIVersion]["Constants"][key] = value
                    cntConstants = cntConstants + 1
                end
            end
        end
    end
    d(string.format("[merTorchbug]Dumped %s constants, and %s SI_ string constants to the SavedVariables!\nPlease reload the UI to save the data to the disk!", tos(cntConstants), tos(cntSIConstants)))
end
local tbug_dumpConstants = tbug.dumpConstants

local function deleteDumpConstantsFromSV(worldName, APIVersion, deleteAll)
    deleteAll = deleteAll or false
    local wasError = false
    local APIVersionNumber = ton(APIVersion)
    --Delete the SV table of dumped data of the current server and apiversion
    if merTorchbugSavedVars_Dumps ~= nil then
        if deleteAll == true then
            merTorchbugSavedVars_Dumps = {}
            d("[merTorchbug]All dumped constants were deleted!\nPlease reload the UI to save the data to the disk!")
        else
            if merTorchbugSavedVars_Dumps[worldName] == nil then
                local worldNameLower = string.lower(worldName)
                if merTorchbugSavedVars_Dumps[worldNameLower] ~= nil then
                    worldName = worldNameLower
                else
                    local worldNameUpper = string.upper(worldName)
                    if merTorchbugSavedVars_Dumps[worldNameUpper] ~= nil then
                        worldName = worldNameUpper
                    end
                end
            end
            if merTorchbugSavedVars_Dumps[worldName] ~= nil then
                if merTorchbugSavedVars_Dumps[worldName][APIVersionNumber] ~= nil then
                    merTorchbugSavedVars_Dumps[worldName][APIVersionNumber] = nil
                    d(string.format("[merTorchbug]Dumped constants (server: %s, API: %s) were deleted!\nPlease reload the UI to save the data to the disk!", tos(worldName), tos(APIVersion)))
                else
                    wasError = true
                end
            else
                wasError = true
            end
        end
    else
        wasError = true
    end
    if wasError == true then
        d(string.format("[merTorchbug]Dumped constants (server: %s, API: %s) could not be found!", tos(worldName), tos(APIVersion)))
    end
end

function tbug.dumpConstantsDelete(args)
    local worldName = serversShort[GetWorldName()]
    local APIVersion = GetAPIVersion()
    if args ~= nil and  args ~= "" then
        local argsOptions = parseSlashCommandArgumentsAndReturnTable(args, false)
        --local moreThanOneArg = (argsOptions and #argsOptions > 1) or false
        local argOne = argsOptions[1]
        if argOne == "all" then
            deleteDumpConstantsFromSV(worldName, APIVersion, false)
        else
            --1st param is the worldName, 2nd is the APIversion
            local argTwo = argsOptions[2]
            if argTwo ~= nil then
                deleteDumpConstantsFromSV(argOne, argTwo, false)
            end
        end
    else
        deleteDumpConstantsFromSV(worldName, APIVersion, false)
    end
end
local tbug_dumpConstantsDelete = tbug.dumpConstantsDelete


function tbug.slashCommandLanguage(args)
    local argsOptions = parseSlashCommandArgumentsAndReturnTable(args, true)
    local isOnlyOneArg = (argsOptions and #argsOptions == 1) or false
    if isOnlyOneArg == true then
        local langStr = argsOptions[1]
        if strlen(langStr) == 2 then
            SetCVar("language.2", langStr)
        end
    end
end
local tbug_slashCommandLanguage = tbug.slashCommandLanguage


--Add a script to the script history
function tbug.addScriptHistory(scriptToAdd)
    if scriptToAdd == nil or scriptToAdd == "" then return end
    --Check if script is not already in
    if tbug.savedVars and tbug.savedVars.scriptHistory then
        local scriptHistory = tbug.savedVars.scriptHistory
        --Check value of scriptHistory table
        local alreadyInScriptHistory = checkIfAlreadyInTable(scriptHistory, nil, scriptToAdd, false)
        if alreadyInScriptHistory == true then return end
        tins(tbug.savedVars.scriptHistory, scriptToAdd)
        --is the scripts panel currently shown? Then update it
        if tbug_checkIfInspectorPanelIsShown("globalInspector", "scriptHistory") then
            tbug.refreshInspectorPanel("globalInspector", "scriptHistory")
            --TODO: Why does a single data refresh not work directly where a manual click on the update button does work?! Even a delayed update does not work properly...
            tbug_refreshInspectorPanel("globalInspector", "scriptHistory")
        end
    end
end
local tbug_addScriptHistory = tbug.addScriptHistory

--Chat text's entry return key was pressed
local function tbugChatTextEntry_Execute(control)
    --Update the script history if the text entry is not empty
    local chatTextEntry = CHAT_SYSTEM.textEntry
    if not chatTextEntry then return end
    local chatTextEntryText = chatTextEntry.editControl:GetText()
    if not chatTextEntryText or chatTextEntryText == "" then return end
    --Check if the chat text begins with "/script "
    local startingChatText = strlower(strsub(chatTextEntryText, 1, 8))
    if not startingChatText or startingChatText == "" then return end
    if startingChatText == "/script " then
        --Add the script to the script history (if not already in)
        tbug_addScriptHistory(strsub(chatTextEntryText, 9))
    else
        --Check if the chat text begins with "/tbug "
        startingChatText = strlower(strsub(chatTextEntryText, 1, 6))
        if startingChatText == "/tbug " then
            --Add the script to the script history (if not already in)
            tbug_addScriptHistory(strsub(chatTextEntryText, 7))
        else
            --Check if the chat text begins with "/tb "
            startingChatText = strlower(strsub(chatTextEntryText, 1, 4))
            if startingChatText == "/tb " then
                --Add the script to the script history (if not already in)
                tbug_addScriptHistory(strsub(chatTextEntryText, 5))
            end
        end
    end
end

--Add a script comment to the script history
function tbug.changeScriptHistory(scriptRowId, editBox, scriptOrCommentText, doNotRefresh)
    doNotRefresh = doNotRefresh or false
    if scriptRowId == nil or scriptOrCommentText == nil then return end
    if not editBox or not editBox.updatedColumnIndex then return end
    if not tbug.savedVars then return end

    local updatedColumnIndex = editBox.updatedColumnIndex
    if scriptOrCommentText == "" then scriptOrCommentText = nil end

    --Update the script
    if updatedColumnIndex == 1 then
        if tbug.savedVars.scriptHistory then
            if not scriptOrCommentText then
                --Remove the script? Then remove the script comment as well!
                trem(tbug.savedVars.scriptHistory, scriptRowId)
                trem(tbug.savedVars.scriptHistoryComments, scriptRowId)
            else
                tbug.savedVars.scriptHistory[scriptRowId] = scriptOrCommentText
            end
        end

    --Update the script comment
    elseif updatedColumnIndex == 2 then
        if tbug.savedVars.scriptHistoryComments then
            if scriptOrCommentText == "" then scriptOrCommentText = nil end
            if not scriptOrCommentText then
                --Only remove the script comment
                trem(tbug.savedVars.scriptHistoryComments, scriptRowId)
            else
                tbug.savedVars.scriptHistoryComments[scriptRowId] = scriptOrCommentText
            end
        end
    end
    --is the scripts panel currently shown? Then update it
    if not doNotRefresh then
        if tbug_checkIfInspectorPanelIsShown("globalInspector", "scriptHistory") then
            tbug.refreshInspectorPanel("globalInspector", "scriptHistory")
            --Todo: Again the problem with non-updated table columns that's why the refresh is done twice for the non-direct SavedVariables update
            --column
            if updatedColumnIndex == 1 then
                tbug.refreshInspectorPanel("globalInspector", "scriptHistory")
            end
        end
    end
end

--Get a script comment from the script history
function tbug.getScriptHistoryComment(scriptRowId)
    if scriptRowId == nil then return end
    --Check if script is not already in
    if tbug.savedVars and tbug.savedVars.scriptHistoryComments then
        return tbug.savedVars.scriptHistoryComments[scriptRowId]
    end
    return
end

function tbug.UpdateAddOns()
    if addOns == nil or #addOns <= 0 then return end
    --Read each addon from the EVENT_ADD_ON_LOADED event: Read the addonData
    --and add infos from the AddOnManager
    for loadOrderIndex, addonData in ipairs(addOns) do
        local name = addonData.__name
        tbug.AddOnsOutput[loadOrderIndex] = {}
        local addonDataForOutput = {
            _directory = addonData.dir,
            _loadOrderIndex = loadOrderIndex,
            name = name,
            version = addonData.version,
            author = addonData.author,
            title = addonData.title,
            description = addonData.description,
            isOutOfDate = addonData.isOutOfDate,
            loadDateTime = addonData._loadDateTime,
            loadFrameTime = addonData._loadFrameTime,
            loadGameTime = addonData._loadGameTime,
            loadedAtGameTimeMS = addonData.loadedAtGameTimeMS,
            loadedAtFrameTimeMS = addonData.loadedAtFrameTimeMS,
        }
        if addonData.isLibrary then
            addonDataForOutput.isLibrary = addonData.isLibrary
            addonDataForOutput.LibraryGlobalVar = tbug.LibrariesOutput[name]
        end
        tbug.AddOnsOutput[loadOrderIndex] = addonDataForOutput
    end
end
local tbug_UpdateAddOns = tbug.UpdateAddOns

function tbug.UpdateAddOnsAndLibraries()
    tbug.AddOnsOutput = {}
    tbug.LibrariesData = {}
    --Non LibStub libraries here
    --Example
    --[[
        tbug.LibrariesData["LibSets"] = {
            name = "LibSets",
            version = "15",
            globalVarName = "LibSets",
            globalVar = { global table LibSets },
        }
    ]]


    local addonsLoaded = {}
    --Build local table of loaded addons
    for loadIndex, addonData in ipairs(addOns) do
        addonsLoaded[addonData.__name] = true
    end
    tbug.addOnsLoaded = addonsLoaded

    --Get the addon manager and scan it for IsLibrary tagged libs
    ADDON_MANAGER = GetAddOnManager()
    if ADDON_MANAGER then
        local libs = {}
        local numAddOns = ADDON_MANAGER:GetNumAddOns()
        for i = 1, numAddOns do
            local name, title, author, description, enabled, state, isOutOfDate, isLibrary = ADDON_MANAGER:GetAddOnInfo(i)
            local addonVersion = ADDON_MANAGER:GetAddOnVersion(i)
            local addonDirectory = ADDON_MANAGER:GetAddOnRootDirectoryPath(i)
            if enabled == true and state == ADDON_STATE_ENABLED then
                if isLibrary == true then
                    local libData = {
                        name = name,
                        version = addonVersion,
                        dir = addonDirectory,
                    }
                    tins(libs, libData)
                end
                --Is the currently looped addon loaded (no matter if library or real AddOn)?
                local addonIsLoaded = addonsLoaded[name] == true or false
                if addonIsLoaded == true then
                    --Add the addonManager data of the addon to the table addOns
                    local addonIndexInTbugAddOns
                    for idx, addonData in ipairs(addOns) do
                        if addonData.__name == name then
                            addonIndexInTbugAddOns = idx
                            break
                        end
                    end
                    if addonIndexInTbugAddOns ~= nil then
                        local addonDataOfTbugAddOns = addOns[addonIndexInTbugAddOns]
                        addonDataOfTbugAddOns.author = author
                        addonDataOfTbugAddOns.title = title
                        addonDataOfTbugAddOns.description = description
                        addonDataOfTbugAddOns.isOutOfDate = isOutOfDate
                        addonDataOfTbugAddOns.version = addonVersion
                        addonDataOfTbugAddOns.dir = addonDirectory
                        addonDataOfTbugAddOns.isLibrary = isLibrary
                    end
                end
            end
        end
        --Update library data for output in tbug "Libs" globalInspector tab
        if libs and #libs > 0 then
            table.sort(libs, compareBySubTablesKeyName)
            --Check if a global variable exists with the same name as the librarie's name
            for _, addonData in ipairs(libs) do
                local addonName = addonData.name
                --Does the name contain a - (like in LibAddonMenu-2.0)?
                --Then split the string there and convert the 2.0 to an integer number
                local checkNameTable = {}
                if specialLibraryGlobalVarNames[addonName] ~= nil then
                    tins(checkNameTable, specialLibraryGlobalVarNames[addonName])
                else
                    tins(checkNameTable, addonName)
                    local firstCharUpperCaseName = firstToUpper(addonName)
                    if addonName ~= firstCharUpperCaseName then
                        tins(checkNameTable, firstCharUpperCaseName)
                    end
                    local nameStr, versionNumber = zo_strsplit("-", addonName)
                    if versionNumber and versionNumber ~= "" then
                        versionNumber = ton(versionNumber)
                        local nameStrWithVersion = nameStr .. tos(versionNumber)
                        tins(checkNameTable, nameStrWithVersion)
                        local firstCharUpperCaseNameWithVersion = firstToUpper(nameStrWithVersion)
                        if nameStrWithVersion ~= firstCharUpperCaseNameWithVersion then
                            tins(checkNameTable, firstCharUpperCaseNameWithVersion)
                        end
                        if nameStr ~= addonName then
                            tins(checkNameTable, nameStr)
                        end
                    end
                end
                local libWasAdded = false
                for _, nameToCheckInGlobal in ipairs(checkNameTable) do
                    if _G[nameToCheckInGlobal] ~= nil then
                        --d(">>>global was found!")
                        tbug.LibrariesData[addonName] = {
                            name = addonName,
                            version = addonData.version,
                            dir = addonData.dir,
                            globalVarName = nameToCheckInGlobal,
                            globalVar = _G[nameToCheckInGlobal],
                        }
                        _G[nameToCheckInGlobal]._directory = addonData.dir
                        libWasAdded = true
                        break -- exit the loop
                    end
                end
                if libWasAdded == false then
                    tbug.LibrariesData[addonName] = {
                        name = addonName,
                        version = addonData.version,
                        dir = addonData.dir,
                        globalVarName = addonData.dir,
                        globalVar = addonData.dir,
                    }
                    libWasAdded = true
                end
            end
        end
    end
end
local tbug_UpdateAddOnsAndLibraries = tbug.UpdateAddOnsAndLibraries


function tbug.refreshScenes()
--d("[tbug]refreshScenes")
    tbug.ScenesOutput = {}
    tbug.FragmentsOutput = {}
    scenes = {}
    fragments = {}
    local globalScenes = _G.SCENE_MANAGER.scenes
    if globalScenes ~= nil then
        for k,v in pairs(globalScenes) do
            --Add the scenes for the output at the "Scenes" tbug globalInspector tab
            scenes[k] = v
            tbug.ScenesOutput[k] = v

            --Add the fragments for the output at the "Fragm." tbug globalInspector tab
            if v.fragments ~= nil then
                local fragmentsOfScene = v.fragments
                for kf, vf in ipairs(fragmentsOfScene) do
                    local fragmentName = tbug_glookup(vf)
                    if fragmentName ~= nil and fragmentName ~= "" then
                        fragments[fragmentName] = fragments[fragmentName] or vf
                        fragments[fragmentName].__usedInScenes = fragments[fragmentName].__usedInScenes or {}
                        fragments[fragmentName].__usedInScenes[k] = v
                    end
                end
            end
        end
    end
    --Sort the fragments by their _G[fragmentName]
    if ZO_IsTableEmpty(fragments) then return end
    local orderFragmentsTab = {}
    for fragmentName, fragmentData in pairs(fragments) do
        table.insert(orderFragmentsTab, fragmentName)
    end
    table.sort(orderFragmentsTab)
    for _, fragmentName in ipairs(orderFragmentsTab) do
        tbug.FragmentsOutput[fragmentName] = fragments[fragmentName]
    end
end


function tbug.refreshAddOnsAndLibraries()
--d(">refreshLibraries")
    --Update and refresh the libraries list
    tbug_UpdateAddOnsAndLibraries()

    tbug.LibrariesOutput = {}
    if LibStub then
        local lsLibs = LibStub.libs
        if lsLibs then
            for k,v in pairs(lsLibs) do
                tbug.LibrariesOutput[k]=v
            end
        end
    end
    if tbug.LibrariesData then
        for k,v in pairs(tbug.LibrariesData) do
            tbug.LibrariesOutput[k]=v.globalVar
        end
    end

    --Update the addonData now for the table output on tbug globalInspector tab "AddOns"
    tbug_UpdateAddOns()
end
local tbug_refreshAddOnsAndLibraries = tbug.refreshAddOnsAndLibraries

function tbug.refreshScripts()
--d(">refreshScripts")
    --Refresh the scripts history list
    tbug.ScriptsData = {}
    local svScriptsHist = tbug.savedVars.scriptHistory
    if svScriptsHist then
        tbug.ScriptsData = ZO_ShallowTableCopy(svScriptsHist)
    end
end

function tbug.refreshSavedVariablesTable()
    --Code taken from addon zgoo. All rights and thanks to the authors!
    tbug.SavedVariablesOutput = {}
    local svFound = tbug.SavedVariablesOutput
    local svSuffix = tbug.svSuffix
    local specialAddonSVTableNames = tbug.svSpecialTableNames
    local servers = tbug.servers
    local patternVersion = "^version$"
    local patternNumber = "number"


    local function hasMember(tab, keyPattern, valueType, maxDepth)
        if type(tab) == "table" and maxDepth > 0 then
            for k, v in zo_insecureNext, tab do
                if type(v) == valueType and type(k) == "string" and strfind(k, keyPattern) then
                    return true
                elseif hasMember(v, keyPattern, valueType, maxDepth - 1) then
                    return true
                end
            end
        end
        return false
    end

    --First check the addons found for possible "similar" global SV tables
    if tbug.addOnsLoaded ~= nil then
        for addonName, _ in pairs(tbug.addOnsLoaded) do
            local addonsSVTabFound = false

            for _, suffix in ipairs(svSuffix) do
                if addonsSVTabFound == false then
                    local addSVTable = 0
                    local possibeSVName = tos(addonName  .. suffix)
                    local possibeSVNameLower
                    local possibeSVNameUpper
                    local possibleSVTable = _G[possibeSVName]
                    if possibleSVTable ~= nil and type(possibleSVTable) == "table" then
                        addSVTable = 1
                    else
                        possibeSVNameLower = tos(addonName  .. suffix:lower())
                        possibleSVTable = _G[possibeSVNameLower]
                        if possibleSVTable ~= nil and type(possibleSVTable) == "table" then
                            addSVTable = 2
                        else
                            possibeSVNameUpper = tos(addonName  .. suffix:upper())
                            possibleSVTable = _G[possibeSVNameUpper]
                            if possibleSVTable ~= nil and type(possibleSVTable) == "table" then
                                addSVTable = 3
                            else

                            end
                        end
                    end
                    if addSVTable > 0 and possibleSVTable ~= nil then
                        addonsSVTabFound = true
                        if addSVTable == 1 and possibeSVName ~= nil then
                            svFound[possibeSVName] = rawget(_G, possibeSVName)
                        elseif addSVTable == 2 and possibeSVNameLower ~= nil then
                            svFound[possibeSVNameLower] = rawget(_G, possibeSVNameLower)
                        elseif addSVTable == 3 and possibeSVNameUpper ~= nil then
                            svFound[possibeSVNameUpper] = rawget(_G, possibeSVNameUpper)
                        end
                    end
                else
                    break
                end
            end
        end
    end

    --Then check all other global tables for the "Default"/"EU/NA Megaserver/PTS" subtable with a value "version = <number>"
    for k, v in zo_insecureNext, _G do
        if svFound[k] == nil and type(v) == "table" then
            --"Default" entry
            if hasMember(rawget(v, "Default"), patternVersion, patternNumber, 4) then
                svFound[k] = v
            else
                --EU/NA Megaserveror PTS
                for _, serverName in ipairs(servers) do
                    if hasMember(rawget(v, serverName), patternVersion, patternNumber, 4) then
                        svFound[k] = v
                    end
                end
            end
        end
    end

    --Special tables not found before (not using ZO_SavedVariables wrapper e.g.)
    for _, k in ipairs(specialAddonSVTableNames) do
        svFound[k] = rawget(_G, k)
    end

    return svFound
end
local tbug_refreshSavedVariablesTable = tbug.refreshSavedVariablesTable


local function onPlayerActivated(event, init)
    --Update libs and AddOns
    tbug_refreshAddOnsAndLibraries()
    --Find and update global SavedVariable tables
    tbug_refreshSavedVariablesTable()
end

--The possible slash commands in the chat editbox
local function slashCommands()
    --Uses params: any variable/function. Show the result of the variable/function in the chat.
    --             any table/control/userdata. Open the torchbug inspector and show the variable contents
    --             "free": Frees the mouse and let's you move it around (same like the vanilla game keybind)
    --w/o param: Open the torchbug UI and load + cache all global variables, constants etc.
    SLASH_COMMANDS["/tbug"]     = tbug_slashCommand
    if SLASH_COMMANDS["/tb"] == nil then
        SLASH_COMMANDS["/tb"]   = tbug_slashCommand
    end

    --Call the slash command delayed
    SLASH_COMMANDS["/tbugd"]     = tbug_slashCommandDelayed
    SLASH_COMMANDS["/tbugdelay"] = tbug_slashCommandDelayed
    if SLASH_COMMANDS["/tbd"] == nil then
        SLASH_COMMANDS["/tbd"]   = tbug_slashCommandDelayed
    end

    --Show the info about the control below the mouse
    if SLASH_COMMANDS["/tbm"] == nil then
        SLASH_COMMANDS["/tbm"]   = function(...) tbug_slashCommandMOC(false, ...) end
    end
    SLASH_COMMANDS["/tbugm"]    = function(...) tbug_slashCommandMOC(false, ...) end

    --Show the info about the control below the mouse delayed by <seconds>
    if SLASH_COMMANDS["/tbdm"] == nil then
        SLASH_COMMANDS["/tbdm"]   = tbug_slashCommandMOCDelayed
    end
    SLASH_COMMANDS["/tbugdm"]    = tbug_slashCommandMOCDelayed
    SLASH_COMMANDS["/tbugdelaymouse"] = tbug_slashCommandMOCDelayed

    --Show the scripts tab at the torchbug UI
    if SLASH_COMMANDS["/tbs"]  == nil then
        SLASH_COMMANDS["/tbs"]  = tbug_slashCommandScripts
    end
    SLASH_COMMANDS["/tbugs"]    = tbug_slashCommandScripts

    --Show the events tab at the torchbug UI
    if SLASH_COMMANDS["/tbe"]  == nil then
        SLASH_COMMANDS["/tbe"]  = tbug_slashCommandEvents
    end
    SLASH_COMMANDS["/tbevents"] = tbug_slashCommandEvents
    SLASH_COMMANDS["/tbuge"]    = tbug_slashCommandEvents

    --Show the SavedVariables tab at the torchbug UI
    if SLASH_COMMANDS["/tbsv"]  == nil then
        SLASH_COMMANDS["/tbsv"]  = tbug_slashCommandSavedVariables
    end
    SLASH_COMMANDS["/tbugsv"]    = tbug_slashCommandSavedVariables

    --Show the AddOns tab at the torchbug UI
    if SLASH_COMMANDS["/tba"] == nil then
        SLASH_COMMANDS["/tba"]   = tbug_slashCommandAddOns
    end
    SLASH_COMMANDS["/tbugaddons"]    = tbug_slashCommandAddOns
    SLASH_COMMANDS["/tbuga"]    = tbug_slashCommandAddOns

    --Create an itemlink for the item below the mouse and get some info about it in the chat
    if SLASH_COMMANDS["/tbi"] == nil then
        SLASH_COMMANDS["/tbi"]   = tbug_slashCommandITEMLINK
    end
    SLASH_COMMANDS["/tbugi"]    = tbug_slashCommandITEMLINK
    SLASH_COMMANDS["/tbugitemlink"]    = tbug_slashCommandITEMLINK

    --Uses params: itemlink. Get some info about the itemlink in the chat
    if SLASH_COMMANDS["/tbiinfo"] == nil then
        SLASH_COMMANDS["/tbiinfo"]   = tbug_slashCommandITEMLINKINFO
    end
    SLASH_COMMANDS["/tbugiinfo"]    = tbug_slashCommandITEMLINKINFO
    SLASH_COMMANDS["/tbugitemlinkinfo"]    = tbug_slashCommandITEMLINKINFO

    --Show the Scenes tab at the torchbug UI
    if SLASH_COMMANDS["/tbsc"] == nil then
        SLASH_COMMANDS["/tbsc"]   = tbug_slashCommandSCENEMANAGER
    end
    SLASH_COMMANDS["/tbugsc"] = tbug_slashCommandSCENEMANAGER

    --Show the Strings tab at the torchbug UI
    if SLASH_COMMANDS["/tbst"] == nil then
        SLASH_COMMANDS["/tbst"]   = tbug_slashCommandStrings
    end
    SLASH_COMMANDS["/tbugst"] = tbug_slashCommandStrings

    --Dump the parameter's values to the chat. About the same as /tbug <variable>
    SLASH_COMMANDS["/tbdump"] = tbug_slashCommandDumpToChat
    SLASH_COMMANDS["/tbugdump"] = tbug_slashCommandDumpToChat

    --Dump ALL the constants to the SavedVariables table merTorchbugSavedVars_Dumps[worldName][APIversion]
    --About the same as the DumpVars addon does
    -->Make sure to disable other addons if you only want to dump vanilla game constants!
    SLASH_COMMANDS["/tbugdumpconstants"] = tbug_dumpConstants
    SLASH_COMMANDS["/tbugdumpconstantsdelete"] = tbug_dumpConstantsDelete

    --Language change
    SLASH_COMMANDS["/tbuglang"] = tbug_slashCommandLanguage
    SLASH_COMMANDS["/tblang"] = tbug_slashCommandLanguage

    --ControlOutlines - Add/Remove an outline at a control
    SLASH_COMMANDS["/tbugo"] = tbug_slashCommandControlOutline
    if SLASH_COMMANDS["/tbo"] == nil then
        SLASH_COMMANDS["/tbo"] = tbug_slashCommandControlOutline
    end

    --ControlOutlines - Add/Remove an outline at a control + it's children
    SLASH_COMMANDS["/tbugoc"] = tbug_slashCommandControlOutlineWithChildren
    if SLASH_COMMANDS["/tboc"] == nil then
        SLASH_COMMANDS["/tboc"] = tbug_slashCommandControlOutlineWithChildren
    end

    --ControlOutlines - Remove an outline at a control + it's children
    SLASH_COMMANDS["/tbugor"] = tbug_slashCommandControlOutlineRemove
    if SLASH_COMMANDS["/tbor"] == nil then
        SLASH_COMMANDS["/tbor"] = tbug_slashCommandControlOutlineRemove
    end

    --ControlOutlines - Remove ALL outline at ALL control + it's children
    SLASH_COMMANDS["/tbugo-"] = tbug_slashCommandControlOutlineRemoveAll
    if SLASH_COMMANDS["/tbo-"] == nil then
        SLASH_COMMANDS["/tbo-"] = tbug_slashCommandControlOutlineRemoveAll
    end

    --Add the TopLevelControl list slash command
    if SLASH_COMMANDS["/tbtlc"] == nil then
        SLASH_COMMANDS["/tbtlc"] = function()
            tbug_slashCommand(specialInspectTabTitles["listtlc"].functionToCall)
        end
    end

    --Add an easier reloadUI slash command
    if SLASH_COMMANDS["/rl"] == nil then
        SLASH_COMMANDS["/rl"] = function() ReloadUI("ingame") end
    end

    --Compatibilty with ZGOO (if not activated)
    if SLASH_COMMANDS["/zgoo"] == nil then
        SLASH_COMMANDS["/zgoo"] = tbug_slashCommand
    end

    --Inspect the global TBUG variable
    if GetDisplayName() == "@Baertram" then
        SLASH_COMMANDS["/tbugt"]    = tbug_slashCommandTBUG
        if SLASH_COMMANDS["/tbt"] == nil then
            SLASH_COMMANDS["/tbt"]   = tbug_slashCommandTBUG
        end


        SLASH_COMMANDS["/tbdebug"] = function()
            tbug.doDebug = not tbug.doDebug
        end
    end
end

local function loadKeybindings()
    -- Register Keybindings
    ZO_CreateStringId("SI_BINDING_NAME_TBUG_TOGGLE",    "Toggle UI (/tbug)")
    ZO_CreateStringId("SI_BINDING_NAME_TBUG_MOUSE",     "Control below mouse (/tbugm)")
    ZO_CreateStringId("SI_BINDING_NAME_TBUG_RELOADUI",  "Reload the UI")
end

local function onAddOnLoaded(event, addOnName)
    --Add all loaded AddOns and libraries to the global "TBUG.AddOns" table of merTorchbug
    local loadTimeMs = GetGameTimeMilliseconds()
    local loadTimeFrameMs = GetFrameTimeMilliseconds()
    local loadTimeMsSinceMerTorchbugStart = sessionStartTime + loadTimeMs
    local loadTimeFrameMsSinceSessionStart = sessionStartTime + loadTimeFrameMs
    local currentlyLoadedAddOnTab = {
        __name              = addOnName,
        _loadDateTime       = tbug.formatTime(loadTimeMsSinceMerTorchbugStart),
        _loadFrameTime      = loadTimeFrameMsSinceSessionStart,
        _loadGameTime       = loadTimeMsSinceMerTorchbugStart,
        loadedAtGameTimeMS  = loadTimeMs,
        loadedAtFrameTimeMS = loadTimeFrameMs,
    }
    tins(addOns, currentlyLoadedAddOnTab)

    if addOnName ~= myNAME then return end

    tbug.initSavedVars()

    local env =
    {
        gg = _G,
        am = ANIMATION_MANAGER,
        cm = CALLBACK_MANAGER,
        em = EM,
        sm = SCENE_MANAGER,
        wm = WINDOW_MANAGER,
        tbug = tbug,
        conf = tbug.savedVars,
    }

    env.env = setmetatable(env, {__index = _G})
    tbug.env = env

    --Load the slash commands
    slashCommands()

    --Load keybindings
    loadKeybindings()

    --PreHook the chat#s return key pressed function in order to check for run /script commands
    --and add them to the script history
    ZO_PreHook("ZO_ChatTextEntry_Execute", tbugChatTextEntry_Execute)

    --Add a global OnMouseDown handler so we can track mouse button left + right + shift key for the "inspection start"
    local mouseUpBefore = {}
    local function onGlobalMouseUp(eventId, button, ctrl, alt, shift, command)
        --d(string.format("[merTorchbug]onGlobalMouseUp-button %s, ctrl %s, alt %s, shift %s, command %s", tos(button), tos(ctrl), tos(alt), tos(shift), tos(command)))
        if not shift == true then return end
        --If we are currenty in combat do not execute this!
        if IsUnitInCombat("player") then return end
        local goOn = false
        if button == MOUSE_BUTTON_INDEX_LEFT_AND_RIGHT then
            goOn = true
            mouseUpBefore = {}
        else
            --The companion scenes do not send any MOUSE_BUTTON_INDEX_LEFT_AND_RIGHT :-( We need to try to detect it by other means
            --Get the active scene
            local activeSceneIsCompanion = (env.sm.currentScene == COMPANION_CHARACTER_KEYBOARD_SCENE) or false
            if activeSceneIsCompanion == true then
                local controlbelowMouse = moc()
                if controlbelowMouse ~= nil then
                    local currentTimestamp = GetTimeStamp()
                    mouseUpBefore[controlbelowMouse] = mouseUpBefore[controlbelowMouse] or  {}
                    if mouseUpBefore[controlbelowMouse][MOUSE_BUTTON_INDEX_LEFT] ~= nil then
                        if currentTimestamp - mouseUpBefore[controlbelowMouse][MOUSE_BUTTON_INDEX_LEFT] <= 1000 then
                            if button == MOUSE_BUTTON_INDEX_RIGHT then
                                goOn = true
                            end
                        end
                    elseif mouseUpBefore[controlbelowMouse][MOUSE_BUTTON_INDEX_RIGHT] ~= nil then
                        if currentTimestamp - mouseUpBefore[controlbelowMouse][MOUSE_BUTTON_INDEX_RIGHT] <= 1000 then
                            if button == MOUSE_BUTTON_INDEX_LEFT then
                                goOn = true
                            end
                        end
                    end
                    if goOn == false then
                        mouseUpBefore[controlbelowMouse][button] = currentTimestamp
                    end
                end
            end
        end
        if not goOn then return end
        mouseUpBefore = {}
        tbug_slashCommandMOC(true, nil)
    end

    --DebugLogViewer
    --Enable right click on main UI to bring the window to the front
    if DebugLogViewer then
        if DebugLogViewerMainWindow then
            DebugLogViewerMainWindow:SetHandler("OnMouseUp", function(selfCtrl, mouseButton, upInside)
                if upInside and mouseButton == MOUSE_BUTTON_INDEX_RIGHT then
                    DebugLogViewerMainWindow:SetDrawTier(DT_HIGH)
                    DebugLogViewerMainWindow:SetDrawTier(DT_MEDIUM) --2nd call to fix context menus for that control
                end
            end)

        end
    end

    --Scroll lists hooks
    local function checkForInspectorPanelScrollBarScrolledAndHideControls(selfScrollList)
        local panelOfInspector = tbug_inspectorScrollLists[selfScrollList]
        if panelOfInspector ~= nil then
            --Hide the editBox and sliderControl at the inspector panel rows, if shown
            panelOfInspector:valueEditCancel(panelOfInspector.editBox)
            panelOfInspector:valueSliderCancel(panelOfInspector.sliderControl)
        end
    end
    --For the mouse wheel and up/down button press
    SecurePostHook("ZO_ScrollList_ScrollRelative", function(selfScrollList, delta, onScrollCompleteCallback, animateInstantly)
--tbug._selfScrollList = selfScrollList
        checkForInspectorPanelScrollBarScrolledAndHideControls(selfScrollList)
    end)
    --For the click on the scroll bar control
    SecurePostHook("ZO_Scroll_ScrollAbsoluteInstantly", function(selfScrollList, value)
--tbug._selfScrollList = selfScrollList
        checkForInspectorPanelScrollBarScrolledAndHideControls(selfScrollList)
    end)
    SecurePostHook("ZO_ScrollList_ScrollAbsolute", function(selfScrollList, value)
--tbug._selfScrollList = selfScrollList
        checkForInspectorPanelScrollBarScrolledAndHideControls(selfScrollList)
    end)

    EM:RegisterForEvent(myNAME.."_OnGlobalMouseUp", EVENT_GLOBAL_MOUSE_UP, onGlobalMouseUp)

    EM:RegisterForEvent(myNAME.."_AddOnActivated", EVENT_PLAYER_ACTIVATED, onPlayerActivated)
end


EM:RegisterForEvent(myNAME .."_AddOnLoaded", EVENT_ADD_ON_LOADED, onAddOnLoaded)



--[[
--SHIFT+linksklick auf function:
Beim Klicken auf function (row.DataEntry.data.value) kann per row.index die Zeile (oder row.key der Schlüssel) ermittelt werden.
Dann müsste man noch zur row herausfinden, in welchem inspector das geklickt wurde. Über den aktuell aktiven Zab in der tabScrollList:
self.panel.inspector ?
Und die aktuell inspizierte control über self.panel.subject

]]