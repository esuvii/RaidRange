-- author: esuvii

-- setup slash command handlers
SLASH_RAIDRANGE1 = "/rr" -- slash command
SLASH_RAIDRANGE2 = "/raidrange" -- slash command


-- frame for event handler/global functions
local RaidRangeFrame = CreateFrame("Frame", "RaidRangeFrame")
RaidRangeFrame:RegisterEvent("ADDON_LOADED")
RaidRangeFrame:RegisterEvent("PLAYER_LOGOUT")
RaidRangeFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
RaidRangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
RaidRangeFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
RaidRangeFrame:RegisterEvent("UNIT_FLAGS")
RaidRangeFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
local addonLoaded = false -- flag for if saved state is ready
local scannerActive = false -- start inactive
local playersDictionary = {} -- dictionary of player names -> true/false in range
local namesDictionary = {} -- dictionary of unit IDs -> player names
local classDictionary = {} -- dictionary of names -> classes
local numGroupMembers = 0 -- number of group members
local isRaid = false -- in a raid?
local isParty = false -- in a party?
local playerName = UnitName("player") -- player name
local counter = 0 -- frames since last scan
local changed = true -- did the players in range change
local validActionSlot = true

-- defaults
local defaultSlot = nil
local defaultRange = 10
local defaultRate = 60
local defaultInverse = false
local selectedSlot = defaultSlot
local selectedRange = defaultRange 
local selectedRate = defaultRate
local selectedInverse = defaultInverse


-- range data
local rangeData = {}
rangeData[5] = {
	["name"] = "Unbestowed Friendship Bracelet",
	["id"] = 22259,
	["texture"] = 133345
}
rangeData[10] = {
	["name"] = "Toasting Goblet",
	["id"] = 21267,
	["texture"] = 132789
}
rangeData[15] = {
	["name"] = "Crystal Infused Bandage",
	["id"] = 23684,
	["texture"] = 133686
}
rangeData[20] = {
	["name"] = "Juju Guile",
	["id"] = 12458,
	["texture"] = 134315
}
local knownRanges = {}
for k,v in pairs(rangeData) do
	table.insert(knownRanges,k)
end

-- class colors
local classColor = {
	["DEATHKNIGHT"] = "C41E3A",
	["DEMONHUNTER"] = "A330C9",
	["DRUID"] = "FF7C0A",
	["EVOKER"] = "33937F",
	["HUNTER"] = "AAD372",
	["MAGE"] = "3FC7EB",
	["MONK"] = "00FF98",
	["PALADIN"] = "F48CBA",
	["PRIEST"] = "FFFFFF",
	["ROGUE"] = "FFF468",
	["SHAMAN"] = "0070DD",
	["WARLOCK"] = "8788EE",
	["WARRIOR"] = "C69B6D"
}


-- action slot chooser macro info
local macroName = "_RaidRange"
local macroTexture = "Inv_misc_punchcards_blue"
local macroID = 134390
local macroBody = "/run RaidRangeFrame:ChooseActionSlot()"

local function GenerateMacro()
	local index = GetMacroIndexByName(macroName)
	if index and index ~= 0 then
		local body = GetMacroBody(index)
		if body and body == macroBody then
			-- macro is correct do nothing
		else
			-- fix macro body
			EditMacro(index, macroName, macroTexture, macroBody)
		end
	else
		-- create macro
		CreateMacro(macroName, macroTexture, macroBody, 1) -- 1 = per character macro
	end
end

local function SetActionSlot(slot, range)
	local valid = false
	for k,v in pairs(knownRanges) do
		if v == tonumber(range) then
			valid = true
			break
		end
	end
	if valid then
		if slot >=1 and slot <=120 then
			if not InCombatLockdown() then
				ClearCursor()
				PickupItem(rangeData[range].id)
				PlaceAction(slot)
				ClearCursor()
			else
				print("Cannot set RaidRange action slot in combat.")
			end
		else
			print("An invalid action bar slot is set. Please use \"/rr clear\" and use the macro to choose a new action slot.")
		end
	else
		print("RaidRange requires a valid range value input.")
	end
end


function RaidRangeFrame:ChooseActionSlot()
	local valid = false
	for i=1,120 do -- loop over all action slots
		local text = GetActionText(i)
		if text and text == macroName then
			valid = true
			SetActionSlot(i, selectedRange)
			selectedSlot = i -- store the new actionbar slot
			RaidRangeCharacter.slot = selectedSlot
			break
		end
	end
	if valid == false then
		print("RaidRange expects _RaidRange macro to be on a valid action bar slot.")
	end
end

local function validateActionSlot(slot)
	if slot and slot == selectedSlot then
		local slotID = select(2, GetActionInfo(slot)) or nil
		local validID = false
		if slotID then
			for k,v in pairs(knownRanges) do
				-- is it one of our valid range abilities?
				if slotID == rangeData[v].id then
					if tonumber(v) ~= tonumber(selectedRange) then
						-- it is the wrong range ability!
						print("WARNING: Selected range does not match the action button! Try \"/rr 10\" to reset this to 10 yards.")
						validActionSlot = false
					else
						validActionSlot = true
					end
					validID = true
					break
				end
			end
		end
		if not validID then
			-- button doesn't match any known range ability
			print("WARNING: RaidRange action button invalid! To stop using this slot please use \"/rr clear\"")
			validActionSlot = false
		end
	end
end


-- RANGE UI
-- font string is parent
-- anchor background to font string
-- anchor range "5 yds" to background
-- on click of background for movable, but it moves the font string
local RaidRangeUI = CreateFrame("Frame", "RaidRangeUI", UIParent)
RaidRangeUI:SetWidth(1)
RaidRangeUI:SetHeight(1)
RaidRangeUI:SetPoint("CENTER")

RaidRangeUI.text = RaidRangeUI:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
RaidRangeUI.text:SetPoint("CENTER")
RaidRangeUI.text:SetTextScale(0.8)
local defaultText = "          "
RaidRangeUI.text:SetText(defaultText) -- player list
RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)

RaidRangeUI.bg = CreateFrame("Frame", nil, RaidRangeUI)
RaidRangeUI.bg:SetPoint("TOPLEFT", RaidRangeUI.text, "TOPLEFT",-2,2)
RaidRangeUI.bg:SetPoint("BOTTOMRIGHT", RaidRangeUI.text, "BOTTOMRIGHT",2,-2)
RaidRangeUI.bg.texture = RaidRangeUI.bg:CreateTexture()
RaidRangeUI.bg.texture:SetAllPoints()
RaidRangeUI.bg.texture:SetColorTexture(0,0,0,0.5)
RaidRangeUI.bg:SetFrameLevel(1)

RaidRangeUI.note = RaidRangeUI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
RaidRangeUI.note:SetPoint("TOP", RaidRangeUI.text, "BOTTOMRIGHT", 2,-2)
RaidRangeUI.note:SetTextScale(0.8)
if selectedInverse then
	RaidRangeUI.note:SetText("\124cffC41E3ANOT\124r " ..selectedRange .. " yds")
else
	RaidRangeUI.note:SetText(selectedRange .. " yds")
end

RaidRangeUI:SetMovable(true)
RaidRangeUI:EnableMouse(true)
RaidRangeUI:RegisterForDrag("LeftButton")
RaidRangeUI:SetClampedToScreen(true)
RaidRangeUI:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
RaidRangeUI:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
RaidRangeUI:SetScript("OnHide", function(self)
    RaidRangeUI.text:SetText(defaultText)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
    self:StopMovingOrSizing()
end)

-- we toggle alpha/interactivity instead of show/hide
-- since show/hide doesn't like combat lockdown
function RaidRangeUI:Invisible()
    RaidRangeUI.text:SetText(defaultText)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
	RaidRangeUI:SetAlpha(0)
	RaidRangeUI.text:SetAlpha(0)
	RaidRangeUI.bg:SetAlpha(0)
	RaidRangeUI.note:SetAlpha(0)
	RaidRangeUI:EnableMouse(false)
end
RaidRangeUI:Invisible() -- invisible on init

function RaidRangeUI:Visible()
    RaidRangeUI.text:SetText(defaultText)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
	if selectedInverse then
		RaidRangeUI.note:SetText("\124cffC41E3ANOT\124r " ..selectedRange .. " yds")
	else
		RaidRangeUI.note:SetText(selectedRange .. " yds")
	end
	RaidRangeUI:SetAlpha(1)
	RaidRangeUI.text:SetAlpha(1)
	RaidRangeUI.bg:SetAlpha(1)
	RaidRangeUI.note:SetAlpha(1)
	RaidRangeUI:EnableMouse(true)
end

-- wrap text in class color
local function ColoredName(name)
	local text = ""
	local class = classDictionary[name] or nil
	if class and classColor[class] then
		text = "\124cff" .. classColor[class] .. name .. "\124r"
	else
		text = name
	end
	return text
end

-- for refreshing just the range UI's player list
function RaidRangeUI:RefreshList()
	local text = ""
	local num = 0
	local excess = 0
	for k,v in pairs(playersDictionary) do
		if v == not selectedInverse then
			num = num + 1
			if num > 5 then
				excess = excess + 1
			else
				text = text .. ColoredName(k) .. "\n"
			end
		end
	end
	if excess > 0 then
		text = text .. "+" .. excess .. " more"
	elseif num > 0 then
		text = text:sub(1,-2)
	else
		text = defaultText
	end
	
	RaidRangeUI.text:SetText(text)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
end

-- for refreshing the entire range UI
function RaidRangeUI:Refresh()
	RaidRangeUI:RefreshList()
	if selectedInverse then
		RaidRangeUI.note:SetText("\124cffC41E3ANOT\124r " ..selectedRange .. " yds")
	else
		RaidRangeUI.note:SetText(selectedRange .. " yds")
	end
end

-- if we UnitName before a player fully loaded
-- then it could give UNKNOWNOBJECT instead of name
local _UNKNOWNOBJECT = UNKNOWNOBJECT
local function retryUnknown(name, unitID)
	if name == _UNKNOWNOBJECT then
		-- wait and try to get the player info again
		C_Timer.After(1, function()
			if isRaid or isParty then
				local newName = UnitName(unitID) or nil
				local changeFlag = false
				if newName then
					if namesDictionary[unitID] == nil then
						namesDictionary[unitID] = newName
						changeFlag = true
					end
					if playersDictionary[newName] == nil then
						playersDictionary[newName] = false
						changeFlag = true
					end
					if classDictionary[newName] == nil then
						local class = select(2,UnitClass(unitID)) or nil
						if class then
							classDictionary[newName] = class
						changeFlag = true
						end
					end
				end
				if changeFlag then
					RaidRangeUI:RefreshList()
				end
			end
		end)
		return nil
	else
		return name
	end
end


-- ON EVENT STUFF
RaidRangeFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local args = ...
		if args and args == "RaidRange" then
			-- create the action bar setup macro
			C_Timer.After(1, function() GenerateMacro() end)
			-- saved variables RaidRangeSettings loaded
			if not RaidRangeSettings then
				RaidRangeSettings = {}
				RaidRangeSettings.rate = defaultRate
			end
			if not RaidRangeCharacter then
				RaidRangeCharacter= {}
				RaidRangeCharacter.slot = defaultSlot
				RaidRangeCharacter.range = defaultRange
				RaidRangeCharacter.inverse = defaultInverse
			end
			selectedSlot = RaidRangeCharacter.slot or defaultSlot
			selectedRange = RaidRangeCharacter.range or defaultRange 
			selectedInverse = RaidRangeCharacter.inverse or defaultInverse
			selectedRate = RaidRangeSettings.rate or defaultRate 
			addonLoaded = true

			C_Timer.After(1, function() validateActionSlot(selectedSlot) end)
		end

	elseif event == "PLAYER_LOGOUT" then
		if not RaidRangeSettings then
			RaidRangeSettings = {}
		end
		if not RaidRangeCharacter then
			RaidRangeCharacter = {}
		end
		RaidRangeCharacter.slot = selectedSlot or defaultSlot
		RaidRangeCharacter.range = selectedRange or defaultRange
		RaidRangeCharacter.inverse = selectedInverse or defaultInverse
		RaidRangeSettings.rate = selectedRate or defaultRate
		-- saved variables stored

	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		-- Fired whenever a group or raid is formed or disbanded, players are leaving or joining the group or raid.
		-- rebuild our dictionary of unit IDs to player names

		numGroupMembers = GetNumGroupMembers()
		isRaid = IsInRaid()
		if isRaid then
			isParty = false
		else
			isParty = IsInGroup()
		end
		if (not isRaid) and (not isParty) then
			playersDictionary = {}
		end

		local dictionary = {}
		local classes = {}
		local name = nil
		local class = nil
		local unitID = nil
		for i=1,4 do
			unitID = "party"..i
			name = UnitName(unitID) or nil
			name = retryUnknown(name, unitID)
			if name then
				dictionary[unitID] = name
				class = select(2,UnitClass(unitID)) or nil
				if class then
					classes[name] = class
				end
			end
		end
		for i=1,40 do
			unitID = "raid"..i
			name = UnitName(unitID) or nil
			name = retryUnknown(name, unitID)
			if name then
				dictionary[unitID] = name
				class = select(2,UnitClass(unitID)) or nil
				if class then
					classes[name] = class
				end
			end
		end

		namesDictionary = dictionary
		classDictionary = classes
		-- need to remove players who are no longer in the group
		for k,v in pairs(playersDictionary) do
			if not classDictionary[k] then
				playersDictionary[k] = false
			end
		end
		RaidRangeUI:Refresh()
	
	elseif event == "PARTY_MEMBER_DISABLE" then
		-- someone in party/raid logged out
		-- we need to set their value to nil (no false negatives)
		local args = {...} or {}
		local changeFlag = false
		for k,v in pairs(args) do
			local name = namesDictionary[v] or nil
			if name then
				if not (playersDictionary[name] == nil) then
					playersDictionary[name] = nil
					changeFlag = true
				end
			end
		end
		if changeFlag then
			RaidRangeUI:RefreshList()
		end

	elseif event == "UNIT_FLAGS" then
		-- detect if someone died
		local args = ... or nil
		local changeFlag = false
		local name = namesDictionary[args] or nil
		if name and not (playersDictionary[name] == nil) then
			if UnitIsDead(args) then
				playersDictionary[name] = nil
				changeFlag = true
			end
		end
		if changeFlag then
			RaidRangeUI:RefreshList()
		end
	
	elseif event=="ACTIONBAR_SLOT_CHANGED" then
		-- check if we broke the action button
		local args = ... or nil
		validateActionSlot(args)
	end

end)


-- the actual range check protocol
local _IsActionInRange = IsActionInRange
local function rangeScan(slot, unitID, name, check, changeFlag)
	check = nil
	check = _IsActionInRange(slot, unitID)
	name = namesDictionary[unitID] or UnitName(unitID) or nil
	if not (name == nil) and not (check == nil) and name ~= playerName then
		if playersDictionary[name] and playersDictionary[name] == check then
	    	-- do nothing, the player's range didnt change
	    else
	    	-- player move in/out of range since last check
	    	playersDictionary[name] = check
	    	changeFlag = true
	    end
	end
	return changeFlag
end


-- TIMING ANALYSIS
--[[
local prevTime = nil
local totalTime = 0
local nPrint = 100
local nTot = 0
local n=0
local runningAvg = 0
local function timingStart()
	prevTime = debugprofilestop()
end
local function timingEnd()
	local newTime = debugprofilestop()
	local diff = (newTime - prevTime)
	totalTime = totalTime+diff
	n = n + 1
	if n >= nPrint then
		runningAvg = ((runningAvg*nTot)+totalTime)/(nTot+n)
		nTot = nTot + n
		print(nTot.." scans: "..runningAvg.."ms avg")
		n = 0
		totalTime = 0
	end
end
]]--

-- ON UPDATE SCRIPT
local function updateScript()
	counter = counter + 1
	if counter >= selectedRate then
		--timingStart()
		counter = 0

		local name = nil
		local check = nil
		if isRaid then
			for i=1,numGroupMembers do
				changed = rangeScan(selectedSlot, "raid"..i, name, check, changed)
			end
		elseif isParty then
			for i=1,(numGroupMembers-1) do
				changed = rangeScan(selectedSlot, "party"..i, name, check, changed)
			end
		end

		if changed then
			changed = false
			RaidRangeUI:RefreshList()
		end
		--timingEnd()
	end
end
RaidRangeFrame:SetScript("OnUpdate", nil)


-- SLIDER FRAME FOR SETTING RATE
local RaidRangeRate = CreateFrame("frame", "RaidRangeRateFrame", UIParent, "UIPanelDialogTemplate")
RaidRangeRate.name = "RaidRangeRateFrame"
_G[RaidRangeRate.name.."Close"]:ClearAllPoints()
_G[RaidRangeRate.name.."Close"]:SetPoint("TOPRIGHT",_G[RaidRangeRate.name.."TopRight"],"TOPRIGHT",2,1)
RaidRangeRate:SetSize(430,100)
RaidRangeRate:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
RaidRangeRate:Hide()
RaidRangeRate:SetMovable(true)
RaidRangeRate:EnableMouse(true)
RaidRangeRate:RegisterForDrag("LeftButton")
RaidRangeRate:SetClampedToScreen(true)
RaidRangeRate:SetScript("OnDragStart", function(self)
      self:StartMoving()
end)
RaidRangeRate:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
end)

RaidRangeRate.title = RaidRangeRate:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
RaidRangeRate.title:SetPoint("LEFT", _G[RaidRangeRate.name.."TitleBG"], "LEFT", 5, 0)
RaidRangeRate.title:SetText("RaidRange: Adjust Update Rate")

RaidRangeRate.body = RaidRangeRate:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
RaidRangeRate.body:SetPoint("TOPLEFT", RaidRangeRate, "TOPLEFT", 12, -30)
RaidRangeRate.body:SetPoint("TOPRIGHT", RaidRangeRate, "TOPRIGHT", -12, -30)
RaidRangeRate.body:SetText("How many frames to wait between updates? \124cff3fca43Lower is faster\124r but \124cffC41E3Aworse performance\124r (\124cff3FC7EBdefault "..defaultRate.."\124r). Saved upon window close.")

RaidRangeRate.slider = CreateFrame("Slider", RaidRangeRate.name.."ScaleSlider", RaidRangeRate, "OptionsSliderTemplate")
RaidRangeRate.slider:SetMinMaxValues(1,200)
RaidRangeRate.slider:SetValueStep(1)
RaidRangeRate.slider:SetWidth(400)
_G[RaidRangeRate.name.."ScaleSliderLow"]:SetText("1")
_G[RaidRangeRate.name.."ScaleSliderHigh"]:SetText("200")
RaidRangeRate.slider:SetPoint("BOTTOM", RaidRangeRate, "BOTTOM", 0, 24)

RaidRangeRate.current = RaidRangeRate:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
RaidRangeRate.current:SetPoint("TOP", _G[RaidRangeRate.name.."ScaleSlider"], "BOTTOM")
RaidRangeRate.current:SetText(selectedRate)

local function RateColor(value)
   local text = ""
   if value <= 20 then
      text = "\124cffC41E3A"..value.."\124r"
   elseif value <=50 then
      text = "\124cffFFF468"..value.."\124r"
   elseif value == defaultRate then
      text = "\124cff3FC7EB"..value.."\124r"
   else
      text = "\124cff3fca43"..value.."\124r"
   end
   return text
end

RaidRangeRate:SetScript("OnShow", function(self)
      RaidRangeRate.slider:SetValue(selectedRate)
      RaidRangeRate.current:SetText(RateColor(selectedRate))
end)
RaidRangeRate.slider:SetScript("OnValueChanged", function(self)
      local value = math.floor(self:GetValue()+0.5)
      RaidRangeRate.current:SetText(RateColor(value))
end)
RaidRangeRate:SetScript("OnHide", function(self)
      local value = math.floor(RaidRangeRate.slider:GetValue()+0.5)
      if value and selectedRate~=value then
         selectedRate = value
         RaidRangeSettings.rate = selectedRate
      end
end)



local function activateScanner()
	scannerActive = true
	RaidRangeFrame:SetScript("OnUpdate", updateScript)
	RaidRangeUI:Visible()
end

local function deactivateScanner()
	RaidRangeUI:Invisible()
	RaidRangeFrame:SetScript("OnUpdate", nil)
	scannerActive = false
	counter = 0
	changed = true
end


local function ClearActionSlot()
	deactivateScanner()
	selectedSlot = nil
	RaidRangeCharacter.slot = selectedSlot
end


-- SLASH COMMAND FUNCTIONS
local function SlashCommandHandler(msg) 
	if addonLoaded then
		-- "/rr" or "/raidrange" (no flags)
		-- toggle the UI visibility and hook script
		if msg == "" or msg == nil then
			if selectedSlot then
				if scannerActive then
					deactivateScanner()
				else
					activateScanner()
				end
			else
				print("Please set an action bar slot. Open your character specific macros, place the \"_RaidRange\" macro onto your bars, and then click it.")
			end

			-- "/rr N" show and set range value to N (if possible)
		elseif tonumber(msg) then
			if selectedSlot then
				if not InCombatLockdown() then
					local valid = false
					for k,v in pairs(knownRanges) do
						if v == tonumber(msg) then
							valid = true
							break
						end
					end
					if valid then
						if tonumber(msg) ~= selectedRange or (not validActionSlot) then
							selectedRange = tonumber(msg)
							RaidRangeCharacter.range = selectedRange
							SetActionSlot(selectedSlot, selectedRange)
						end
						RaidRangeUI:Refresh()
						if not scannerActive then
							activateScanner()
						end
					else
						local text = "Supported range values are:"
						for k,v in pairs(knownRanges) do
							text = text .. " " .. v
						end
						print(text)
					end
				else
					print("Cannot adjust range value in combat.")
				end

			else
				print("Please set an action bar slot. Open your character specific macros, place the \"_RaidRange\" macro onto your bars, and then click it.")
			end

			-- "/rr clear" unset the action slot
		elseif msg == "clear" then
			ClearActionSlot()
			print("RaidRange action bar slot reset, to reactivate use the \"_RaidRange\" macro.")

			--"/rr macro" generates a new setup macro
		elseif msg == "macro" then
			GenerateMacro()

			-- "/rr update" or "/rr rate" show the rate slider
		elseif msg == "update" or msg == "rate" then
			deactivateScanner()
			_G["RaidRangeRateFrame"]:Show()

			-- "/rr inverse" or "/rr invert" toggles tracking players outside/inside the range
		elseif msg == "inverse" or msg =="invert" or msg == "not" or msg == "inv" then
			selectedInverse = not selectedInverse
			RaidRangeCharacter.inverse = selectedInverse
			RaidRangeUI:Refresh()
			if not scannerActive then
				activateScanner()
			end


			-- "/rr help" show available commands and current settings
		elseif msg == "help" or msg == "h" or msg == "usage" or msg == "-help" or msg == "-h" or msg == "-usage" or msg == "--help" then
			local text = "RaidRange:\n"
			if selectedSlot then
				text = text.."  Action Bar Slot: "..selectedSlot.."\n"
			else
				text = text.."  Action Bar Slot: NOT SET - Open your character specific macros, place the \"_RaidRange\" macro onto your bars, and then click it.\n"
			end
			if selectedInverse then
				text = text.."  \124cffC41E3AInverse\124r Range: "..selectedRange.."   ||"
			else
				text = text.."  Range: "..selectedRange.."   ||"
			end
			text = text.."  Updating every "..selectedRate.." frames\n"
			print(text)
			text = "Commands:\n"
			text = text.."/rr    toggle range tracker\n"
			text = text.."/rr N   track players within N yds ("
			for k,v in pairs(knownRanges) do
				text = text..v.." "
			end
			text = text:sub(1,-2)
			text = text..")\n"
			text = text.."/rr inverse   toggles tracking players outside/inside the selected range.\n"
			text = text.."/rr rate   set how often to scan for players; lower is faster but at a greater performance cost.\n"
			text = text.."/rr clear   unsets the currently chosen action bar slot.\n"
			text = text.."/rr macro   generates a new setup macro.\n"
			print(text)

		else
			print("Invalid command, for usage info see: \"/rr help\"")
		end

	else
		print("Please allow a moment for RaidRange to load.")
	end
end
SlashCmdList["RAIDRANGE"] = SlashCommandHandler