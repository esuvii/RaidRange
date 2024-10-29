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
RaidRangeFrame.loaded = false -- flag for if saved state is ready
RaidRangeFrame.active = false -- start inactive
RaidRangeFrame.hooked = false -- is secure script hooked?
RaidRangeFrame.players = {} -- dictionary of player names -> true/false in range
--RaidRangeFrame.counter = {} -- dictionary of unit IDs -> frames since last range check
RaidRangeFrame.names = {} -- dictionary of unit IDs -> player names
RaidRangeFrame.class = {} -- dictionary of names -> classes
local counter = 0 -- frames since last scan
local changed = true -- did the players in range change

-- defaults
local defaultSlot = nil
local defaultRange = 10
local defaultRate = 60
RaidRangeFrame.slot = defaultSlot
RaidRangeFrame.range = defaultRange 
RaidRangeFrame.rate = defaultRate 


-- range data
RaidRangeFrame.ranges = {5, 10, 15, 20}
RaidRangeFrame.data = {}
RaidRangeFrame.data[5] = {
	["name"] = "Unbestowed Friendship Bracelet",
	["id"] = 22259,
	["texture"] = 133345
}
RaidRangeFrame.data[10] = {
	["name"] = "Toasting Goblet",
	["id"] = 21267,
	["texture"] = 132789
}
RaidRangeFrame.data[15] = {
	["name"] = "Crystal Infused Bandage",
	["id"] = 23684,
	["texture"] = 133686
}
RaidRangeFrame.data[20] = {
	["name"] = "Juju Guile",
	["id"] = 12458,
	["texture"] = 134315
}

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
	for k,v in pairs(RaidRangeFrame.ranges) do
		if v == tonumber(range) then
			valid = true
			break
		end
	end
	if valid then
		if slot >=1 and slot <=120 then
			if not InCombatLockdown() then
				ClearCursor()
				PickupItem(RaidRangeFrame.data[range].id)
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
			SetActionSlot(i, RaidRangeFrame.range)
			RaidRangeFrame.slot = i -- store the new actionbar slot
			RaidRangeCharacter.slot = RaidRangeFrame.slot
			break
		end
	end
	if valid == false then
		print("RaidRange expects _RaidRange macro to be on a valid action bar slot.")
	end
end


local function ClearActionSlot()
	RaidRangeFrame.slot = nil
	RaidRangeCharacter.slot = RaidRangeFrame.slot
end


-- SLASH COMMAND FUNCTIONS
-- /rr /raidrange = toggle display and range tracking
-- /rr N = show and set range value to N
-- /rr clear = unbind the saved action slot
-- /rr update  /rr rate = show rate slider
-- /rr macro generates a new setup macro
-- /rr help = print this list of command and the current settings

local function SlashCommandHandler(msg) 
	if RaidRangeFrame.loaded and RaidRangeFrame.hooked then
		-- "/rr" or "/raidrange" (no flags)
		-- toggle the UI visibility and hook script
		if msg == "" or msg == nil then
			if RaidRangeFrame.slot then
				if RaidRangeFrame.active then
					RaidRangeFrame.active = false
					RaidRangeUI:Invisible()
					counter = 0
					changed = true
				else
					RaidRangeFrame.active = true
					RaidRangeUI:Visible()
				end
			else
				print("Please set an action bar slot. Open your character specific macros, place the \"_RaidRange\" macro onto your bars, and then click it.")
			end

			-- "/rr N" show and set range value to N (if possible)
		elseif tonumber(msg) then
			if RaidRangeFrame.slot then
				if not InCombatLockdown() then
					local valid = false
					for k,v in pairs(RaidRangeFrame.ranges) do
						if v == tonumber(msg) then
							valid = true
							break
						end
					end
					if valid then
						if tonumber(msg) ~= RaidRangeFrame.range then
							RaidRangeFrame.range = tonumber(msg)
							RaidRangeCharacter.range = RaidRangeFrame.range
							SetActionSlot(RaidRangeFrame.slot, RaidRangeFrame.range)
						end
						RaidRangeUI:Refresh()
						if not RaidRangeFrame.active then
							RaidRangeFrame.active = true
							RaidRangeUI.Visible()
						end
					else
						local text = "Supported range values are:"
						for k,v in pairs(RaidRangeFrame.ranges) do
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
			RaidRangeFrame.active = false
			RaidRangeUI:Invisible()
			_G["RaidRangeRateFrame"]:Show()

			-- "/rr help" show available commands and current settings
		elseif msg == "help" or msg == "h" or msg == "usage" or msg == "-help" or msg == "-h" or msg == "-usage" or msg == "--help" then
			local text = "RaidRange:\n"
			if RaidRangeFrame.slot then
				text = text.."  Action Bar Slot: "..RaidRangeFrame.slot.."\n"
			else
				text = text.."  Action Bar Slot: NOT SET - Open your character specific macros, place the \"_RaidRange\" macro onto your bars, and then click it.\n"
			end
			text = text.."  Range: "..RaidRangeFrame.range.."   ||"
			text = text.."  Updating every "..RaidRangeFrame.rate.." frames\n"
			text = text.."/rr    toggle range tracker\n"
			text = text.."/rr N   track players within N yds ("
			for k,v in pairs(RaidRangeFrame.ranges) do
				text = text..v.." "
			end
			text = text:sub(1,-2)
			text = text..")\n"
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
RaidRangeUI.defaultText = "          "
RaidRangeUI.text:SetText(RaidRangeUI.defaultText) -- player list
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
RaidRangeUI.note:SetText(RaidRangeFrame.range.." yds") -- distance

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
    RaidRangeUI.text:SetText(RaidRangeUI.defaultText)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
    self:StopMovingOrSizing()
end)

function RaidRangeUI:Invisible()
    RaidRangeUI.text:SetText(RaidRangeUI.defaultText)
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
    RaidRangeUI.text:SetText(RaidRangeUI.defaultText)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
	RaidRangeUI.note:SetText(RaidRangeFrame.range .. " yds")
	RaidRangeUI:SetAlpha(1)
	RaidRangeUI.text:SetAlpha(1)
	RaidRangeUI.bg:SetAlpha(1)
	RaidRangeUI.note:SetAlpha(1)
	RaidRangeUI:EnableMouse(true)
end

local function ColoredName(name)
	local text = ""
	local class = RaidRangeFrame.class[name] or nil
	if class and classColor[class] then
		text = "\124cff" .. classColor[class] .. name .. "\124r"
	else
		text = name
	end
	return text
end

function RaidRangeUI:Refresh()
	local text = ""
	local num = 0
	local excess = 0
	for k,v in pairs(RaidRangeFrame.players) do
		if v then
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
		text = RaidRangeUI.defaultText
	end
	
	RaidRangeUI.text:SetText(text)
	RaidRangeUI:SetWidth(RaidRangeUI.text:GetWidth()+4)
	RaidRangeUI:SetHeight(RaidRangeUI.text:GetHeight()+4)
	RaidRangeUI.note:SetText(RaidRangeFrame.range .. " yds")
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
			end
			RaidRangeFrame.slot = RaidRangeCharacter.slot or defaultSlot
			RaidRangeFrame.range = RaidRangeCharacter.range or defaultRange 
			RaidRangeFrame.rate = RaidRangeSettings.rate or defaultRate 
			RaidRangeFrame.loaded = true
		end

	elseif event == "PLAYER_LOGOUT" then
		if not RaidRangeSettings then
			RaidRangeSettings = {}
		end
		if not RaidRangeCharacter then
			RaidRangeCharacter = {}
		end
		RaidRangeCharacter.slot = RaidRangeFrame.slot or defaultSlot
		RaidRangeCharacter.range = RaidRangeFrame.range or defaultRange
		RaidRangeSettings.rate = RaidRangeFrame.rate or defaultRate
		-- saved variables stored

	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		-- Fired whenever a group or raid is formed or disbanded, players are leaving or joining the group or raid.
		-- rebuild our dictionary of unit IDs to player names
		local dictionary = {}
		local classes = {}
		local name = nil
		local class = nil
		for i=1,4 do
			name = UnitName("party"..i) or nil
			if name then
				dictionary["party"..i] = name
				class = select(2,UnitClass("party"..i)) or nil
				if class then
					classes[name] = class
				end
			end
		end
		for i=1,40 do
			name = UnitName("raid"..i) or nil
			if name then
				dictionary["raid"..i] = name
				class = select(2,UnitClass("raid"..i)) or nil
				if class then
					classes[name] = class
				end
			end
		end
		RaidRangeFrame.names = dictionary
		RaidRangeFrame.class = classes
		-- need to remove players who are no longer in the group
		for k,v in pairs(RaidRangeFrame.players) do
			if not RaidRangeFrame.class[k] then
				RaidRangeFrame.players[k] = false
			end
		end
		RaidRangeUI:Refresh()
	end
end)



-- ON UPDATE HOOK
if not RaidRangeFrame.hooked then
	local playerName = UnitName("player")
	RaidRangeFrame:HookScript("OnUpdate", function(self,elapsed)
		if RaidRangeFrame.active then
			counter = counter + 1
			if counter >= RaidRangeFrame.rate then
				counter = 0
				local name = nil
				local check = nil
				if IsInRaid() then
					for i=1,40 do
						check = nil
						check = IsActionInRange(RaidRangeFrame.slot, "raid"..i)
						name = RaidRangeFrame.names["raid"..i] or UnitName("raid"..i) or nil
						if not (name == nil) and not (check == nil) and name ~= playerName then
							if RaidRangeFrame.players[name] and RaidRangeFrame.players[name] == check then
						    	-- do nothing, the player's range didnt change
						    else
						    	-- player move in/out of range since last check
						    	RaidRangeFrame.players[name] = check
						    	changed = true
						    end
						end
					end
				elseif IsInGroup() then
					for i=1,4 do
						check = nil
						check = IsActionInRange(RaidRangeFrame.slot, "party"..i)
						name = RaidRangeFrame.names["party"..i] or UnitName("party"..i) or nil
						if not (name == nil) and not (check == nil) and name ~= playerName then
							if RaidRangeFrame.players[name] and RaidRangeFrame.players[name] == check then
						    	-- do nothing, the player's range didnt change
						    else
						    	-- player move in/out of range since last check
						    	RaidRangeFrame.players[name] = check
						    	changed = true
						    end
						end
					end
				end

				if changed then
					changed = false
					RaidRangeUI:Refresh()
				end
			end
		end
	end)
	RaidRangeFrame.hooked = true
end


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
RaidRangeRate.current:SetText(RaidRangeFrame.rate)

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
      RaidRangeRate.slider:SetValue(RaidRangeFrame.rate)
      RaidRangeRate.current:SetText(RateColor(RaidRangeFrame.rate))
end)
RaidRangeRate.slider:SetScript("OnValueChanged", function(self)
      local value = math.floor(self:GetValue()+0.5)
      RaidRangeRate.current:SetText(RateColor(value))
end)
RaidRangeRate:SetScript("OnHide", function(self)
      local value = math.floor(RaidRangeRate.slider:GetValue()+0.5)
      if value and RaidRangeFrame.rate~=value then
         RaidRangeFrame.rate = value
         RaidRangeSettings.rate = RaidRangeFrame.rate
      end
end)