local ADDON_NAME = "CraftersAddressBook"
local DB_SCHEMA_VERSION = 1
local ROW_HEIGHT = 28
local VISIBLE_ROWS = 12
local MAX_VISIBLE_PROFESSIONS = 2
local MINIMAP_BUTTON_RADIUS = 80
local MINIMAP_BUTTON_DRAG_THRESHOLD = 16
local WHO_QUERY_DELAY = 4
local WHO_QUERY_TIMEOUT = 8

local CAB = CreateFrame("Frame", ADDON_NAME .. "EventFrame")
_G.CraftersAddressBook = CAB

CAB.seenTradeLinks = {}
CAB.pendingScan = nil
CAB.whoQueue = nil
CAB.whoActive = nil
CAB.nextWhoQueryAt = 0
CAB.originalSetItemRef = nil

local function Now()
	if time then
		return time()
	end

	return 0
end

local function Trim(value)
	if not value then
		return nil
	end

	value = string.gsub(value, "^%s+", "")
	value = string.gsub(value, "%s+$", "")
	return value
end

local function GetAtan2(y, x)
	if math.atan2 then
		return math.atan2(y, x)
	end

	if x > 0 then
		return math.atan(y / x)
	elseif x < 0 and y >= 0 then
		return math.atan(y / x) + math.pi
	elseif x < 0 and y < 0 then
		return math.atan(y / x) - math.pi
	elseif x == 0 and y > 0 then
		return math.pi / 2
	elseif x == 0 and y < 0 then
		return -math.pi / 2
	end

	return 0
end

local function TableHasValues(value)
	if type(value) ~= "table" then
		return false
	end

	for _ in pairs(value) do
		return true
	end

	return false
end

function CAB:Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CraftersAddressBook|r: " .. tostring(message))
end

function CAB:GetVersion()
	local version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")
	return version or "0.0.0"
end

function CAB:GetPlayerName(value)
	value = Trim(value)
	if not value or value == "" or value == UNKNOWN then
		return nil
	end

	local name = string.match(value, "^([^%-]+)")
	name = Trim(name or value)
	if not name or name == "" then
		return nil
	end

	return name
end

function CAB:GetPlayerKey(value)
	local name = self:GetPlayerName(value)
	if not name then
		return nil
	end

	return string.lower(name)
end

function CAB:ExtractTradeLink(value, text)
	local raw
	local source = text or value

	if type(value) == "string" and string.sub(value, 1, 6) == "trade:" then
		raw = value
	end

	if not raw and type(source) == "string" then
		raw = string.match(source, "|H(trade:[^|]+)|h")
	end

	if not raw then
		return nil
	end

	local professionName
	if type(source) == "string" then
		professionName = string.match(source, "|h%[(.-)%]|h")
	end

	if not professionName and type(text) == "string" then
		professionName = string.match(text, "|h%[(.-)%]|h")
	end

	professionName = professionName or "Profesion"

	local fullLink = source
	if type(fullLink) ~= "string" or not string.find(fullLink, "|Htrade:", 1, true) then
		fullLink = "|cffffd000|H" .. raw .. "|h[" .. professionName .. "]|h|r"
	end

	return raw, fullLink, professionName
end

function CAB:GetProfessionKey(rawLink, professionName)
	if professionName and professionName ~= "" and professionName ~= "Profesion" then
		return string.lower(professionName)
	end

	local spellID = rawLink and string.match(rawLink, "^trade:(%d+)")
	return spellID or string.lower(professionName or rawLink or "unknown")
end

function CAB:RememberSeenTradeLink(link, sender)
	local playerName = self:GetPlayerName(sender)
	if not playerName then
		return
	end

	local raw, fullLink, professionName = self:ExtractTradeLink(link)
	if not raw then
		return
	end

	self.seenTradeLinks[raw] = {
		playerName = playerName,
		playerKey = self:GetPlayerKey(playerName),
		link = fullLink,
		rawLink = raw,
		professionName = professionName,
		professionKey = self:GetProfessionKey(raw, professionName),
		seenAt = Now(),
	}
end

function CAB:CaptureMessageLinks(message, sender)
	if type(message) ~= "string" then
		return
	end

	for link in string.gmatch(message, "|c%x%x%x%x%x%x%x%x|Htrade:[^|]+|h%[[^]]+%]|h|r") do
		self:RememberSeenTradeLink(link, sender)
	end

	for raw, professionName in string.gmatch(message, "|H(trade:[^|]+)|h%[([^]]+)%]|h") do
		self:RememberSeenTradeLink("|cffffd000|H" .. raw .. "|h[" .. professionName .. "]|h|r", sender)
	end
end

function CAB:EnsureDB()
	if type(CraftersAddressBookDB) ~= "table" then
		CraftersAddressBookDB = {}
	end

	local db = CraftersAddressBookDB
	if type(db.contacts) ~= "table" then
		db.contacts = {}
	end

	if type(db.minimap) ~= "table" then
		db.minimap = {}
	end

	db.minimap.angle = tonumber(db.minimap.angle) or 225
	if db.minimap.show == nil then
		db.minimap.show = true
	end

	for key, contact in pairs(db.contacts) do
		if type(contact) ~= "table" or not TableHasValues(contact.professions) then
			db.contacts[key] = nil
		end
	end

	db.schemaVersion = tonumber(db.schemaVersion) or DB_SCHEMA_VERSION
	if db.schemaVersion < DB_SCHEMA_VERSION then
		db.schemaVersion = DB_SCHEMA_VERSION
	end

	db.addonVersion = self:GetVersion()
	return db
end

function CAB:GetDB()
	return self.db or self:EnsureDB()
end

function CAB:GetContact(playerKey, playerName, create)
	if not playerKey then
		return nil
	end

	local db = self:GetDB()
	local contact = db.contacts[playerKey]
	if not contact and create then
		contact = {
			name = playerName or playerKey,
			professions = {},
			online = false,
			createdAt = Now(),
			updatedAt = Now(),
		}
		db.contacts[playerKey] = contact
	end

	if contact and playerName and playerName ~= "" then
		contact.name = playerName
	end

	return contact
end

function CAB:BuildContext(rawLink, fullLink, professionName, playerName)
	local playerKey = self:GetPlayerKey(playerName)
	if not playerKey then
		return nil
	end

	return {
		playerName = self:GetPlayerName(playerName),
		playerKey = playerKey,
		rawLink = rawLink,
		link = fullLink,
		professionName = professionName,
		professionKey = self:GetProfessionKey(rawLink, professionName),
	}
end

function CAB:FindClickContext(rawLink, fullLink, professionName)
	local seen = rawLink and self.seenTradeLinks[rawLink]
	if seen then
		return self:BuildContext(rawLink, fullLink or seen.link, professionName or seen.professionName, seen.playerName)
	end

	return nil
end

function CAB:ProfessionExists(context)
	local contact = self:GetContact(context.playerKey)
	return contact and contact.professions and contact.professions[context.professionKey]
end

function CAB:SaveProfession(context, cache)
	local contact = self:GetContact(context.playerKey, context.playerName, true)
	if type(contact.professions) ~= "table" then
		contact.professions = {}
	end

	local profession = contact.professions[context.professionKey] or {}
	profession.professionName = context.professionName or profession.professionName
	profession.rawLink = context.rawLink or profession.rawLink
	profession.link = context.link or profession.link
	profession.updatedAt = Now()
	profession.addedAt = profession.addedAt or Now()
	contact.professions[context.professionKey] = profession

	if cache then
		profession.skillName = cache.skillName
		profession.rank = cache.rank
		profession.maxRank = cache.maxRank
		profession.recipes = cache.recipes
		profession.recipeCount = cache.recipeCount
		profession.cachedAt = Now()
	end

	contact.updatedAt = Now()
	self:GetDB().addonVersion = self:GetVersion()

	self:RefreshWindow()
	return profession
end

function CAB:DeleteProfession(playerKey, professionKey)
	local contact = self:GetContact(playerKey)
	if not contact or not contact.professions then
		return
	end

	contact.professions[professionKey] = nil
	contact.updatedAt = Now()

	local hasProfessions = false
	for _ in pairs(contact.professions) do
		hasProfessions = true
		break
	end

	if not hasProfessions then
		self:GetDB().contacts[playerKey] = nil
	end

	self:RefreshWindow()
end

function CAB:DeleteContact(playerKey)
	if not playerKey then
		return
	end

	self:GetDB().contacts[playerKey] = nil
	self:RefreshWindow()
end

function CAB:ExpandAllTradeSkillHeaders()
	if not GetNumTradeSkills or not GetTradeSkillInfo or not ExpandTradeSkillSubClass then
		return
	end

	for _ = 1, 3 do
		local expandedAny = false
		for index = GetNumTradeSkills(), 1, -1 do
			local _, skillType, _, isExpanded = GetTradeSkillInfo(index)
			if skillType == "header" and not isExpanded then
				ExpandTradeSkillSubClass(index)
				expandedAny = true
			end
		end

		if not expandedAny then
			return
		end
	end
end

function CAB:ReadTradeSkillCache()
	if not IsTradeSkillLinked or not IsTradeSkillLinked() then
		return nil
	end

	if not GetNumTradeSkills or not GetTradeSkillInfo then
		return nil
	end

	self:ExpandAllTradeSkillHeaders()

	local skillName, rank, maxRank
	if GetTradeSkillLine then
		skillName, rank, maxRank = GetTradeSkillLine()
	end

	local recipes = {}
	for index = 1, GetNumTradeSkills() do
		local name, skillType, numAvailable = GetTradeSkillInfo(index)
		if name and skillType ~= "header" then
			local recipe = {
				name = name,
				difficulty = skillType,
				numAvailable = numAvailable,
				itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(index) or nil,
				recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(index) or nil,
				reagents = {},
			}

			local reagentCount = GetTradeSkillNumReagents and GetTradeSkillNumReagents(index) or 0
			for reagentIndex = 1, reagentCount do
				local reagentName, texture, count, playerCount
				if GetTradeSkillReagentInfo then
					reagentName, texture, count, playerCount = GetTradeSkillReagentInfo(index, reagentIndex)
				end
				recipe.reagents[reagentIndex] = {
					name = reagentName,
					texture = texture,
					count = count,
					playerCount = playerCount,
					link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(index, reagentIndex) or nil,
				}
			end

			table.insert(recipes, recipe)
		end
	end

	return {
		skillName = skillName,
		rank = rank,
		maxRank = maxRank,
		recipes = recipes,
		recipeCount = table.getn(recipes),
	}
end

function CAB:TryScanPendingProfession()
	if not self.pendingScan then
		return false
	end

	local cache = self:ReadTradeSkillCache()
	if not cache then
		return false
	end

	self:SaveProfession(self.pendingScan, cache)
	self:Print("Cache actualizado para " .. self.pendingScan.playerName .. " - " .. (cache.skillName or self.pendingScan.professionName) .. ".")
	self.pendingScan = nil
	return true
end

function CAB:AcceptProfession(context)
	self.pendingScan = context
	self:SaveProfession(context)
	self:Print("Profesion guardada para " .. context.playerName .. ": " .. (context.professionName or "Profesion") .. ".")

	if not self:TryScanPendingProfession() then
		self:Print("Link guardado para " .. context.playerName .. ". El cache se actualizara cuando termine de abrir la profesion.")
	end
end

function CAB:PromptAddOrRefresh(context)
	if not context then
		self:Print("No pude identificar el personaje que compartio ese link. Solo puedo agregar links capturados desde chat o desde la ventana del addon.")
		return
	end

	local existing = self:ProfessionExists(context)
	if existing then
		StaticPopup_Show("CAB_REFRESH_PROFESSION", context.playerName, context.professionName, context)
	else
		StaticPopup_Show("CAB_ADD_PROFESSION", context.playerName, context.professionName, context)
	end
end

function CAB:OpenStoredProfession(playerKey, professionKey)
	local contact = self:GetContact(playerKey)
	local profession = contact and contact.professions and contact.professions[professionKey]
	if not profession then
		return
	end

	local rawLink = profession.rawLink
	if not rawLink then
		rawLink = self:ExtractTradeLink(profession.link)
	end

	if self.originalSetItemRef and rawLink then
		self.originalSetItemRef(rawLink, profession.link, "LeftButton")
	end
end

function CAB:HandleSetItemRef(link, text)
	local rawLink, fullLink, professionName = self:ExtractTradeLink(link, text)
	if rawLink then
		self:PromptAddOrRefresh(self:FindClickContext(rawLink, fullLink, professionName))
	end
end

function CAB:InstallSetItemRefHook()
	if self.originalSetItemRef or not SetItemRef then
		return
	end

	self.originalSetItemRef = SetItemRef

	if hooksecurefunc then
		hooksecurefunc("SetItemRef", function(link, text)
			CAB:HandleSetItemRef(link, text)
		end)
	else
		SetItemRef = function(link, text, button, chatFrame)
			local result = CAB.originalSetItemRef(link, text, button, chatFrame)
			CAB:HandleSetItemRef(link, text)

			return result
		end
	end
end

function CAB:GetSortedContacts()
	local contacts = {}
	local db = self:GetDB()

	for key, contact in pairs(db.contacts) do
		table.insert(contacts, {
			key = key,
			contact = contact,
		})
	end

	table.sort(contacts, function(left, right)
		return string.lower(left.contact.name or left.key) < string.lower(right.contact.name or right.key)
	end)

	return contacts
end

function CAB:GetSortedProfessions(contact)
	local professions = {}
	if not contact or type(contact.professions) ~= "table" then
		return professions
	end

	for key, profession in pairs(contact.professions) do
		table.insert(professions, {
			key = key,
			profession = profession,
		})
	end

	table.sort(professions, function(left, right)
		return string.lower(left.profession.professionName or left.key) < string.lower(right.profession.professionName or right.key)
	end)

	return professions
end

function CAB:CreateProfessionControls(row, slot)
	row.professionControls = row.professionControls or {}
	if row.professionControls[slot] then
		return row.professionControls[slot]
	end

	local control = CreateFrame("Frame", nil, row)
	control:SetWidth(210)
	control:SetHeight(ROW_HEIGHT)

	control.linkButton = CreateFrame("Button", nil, control)
	control.linkButton:SetPoint("LEFT", control, "LEFT", 0, 0)
	control.linkButton:SetWidth(178)
	control.linkButton:SetHeight(20)
	control.linkButton.text = control.linkButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	control.linkButton.text:SetPoint("LEFT", control.linkButton, "LEFT", 0, 0)
	control.linkButton.text:SetWidth(174)
	control.linkButton.text:SetHeight(20)
	control.linkButton.text:SetJustifyH("LEFT")
	if control.linkButton.text.SetWordWrap then
		control.linkButton.text:SetWordWrap(false)
	end
	if control.linkButton.text.SetNonSpaceWrap then
		control.linkButton.text:SetNonSpaceWrap(false)
	end

	control.deleteButton = CreateFrame("Button", nil, control)
	control.deleteButton:SetPoint("LEFT", control.linkButton, "RIGHT", 2, 0)
	control.deleteButton:SetWidth(24)
	control.deleteButton:SetHeight(20)
	control.deleteButton.text = control.deleteButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	control.deleteButton.text:SetAllPoints(control.deleteButton)
	control.deleteButton.text:SetText("[x]")
	control.deleteButton.text:SetTextColor(1, 0.25, 0.25)

	row.professionControls[slot] = control
	return control
end

function CAB:CreateWindow()
	if self.window then
		return
	end

	local frame = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
	frame:SetWidth(720)
	frame:SetHeight(430)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(100)
	if frame.SetToplevel then
		frame:SetToplevel(true)
	end
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(true)
	end
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:Hide()

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -18)
	frame.title:SetText("CraftersAddressBook")

	frame.version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.version:SetPoint("LEFT", frame.title, "RIGHT", 8, -1)
	frame.version:SetText("v" .. self:GetVersion())

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

	frame.refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.refreshButton:SetWidth(150)
	frame.refreshButton:SetHeight(24)
	frame.refreshButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -42)
	frame.refreshButton:SetText("Refrescar estados")
	frame.refreshButton:SetScript("OnClick", function()
		CAB:StartStatusRefresh()
	end)

	frame.headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.headerName:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -75)
	frame.headerName:SetText("Nombre")

	frame.headerProfessions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.headerProfessions:SetPoint("TOPLEFT", frame, "TOPLEFT", 175, -75)
	frame.headerProfessions:SetText("Profesiones")

	frame.headerStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.headerStatus:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -55, -75)
	frame.headerStatus:SetText("Estado")

	frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.emptyText:SetPoint("CENTER", frame, "CENTER", 0, -10)
	frame.emptyText:SetText("Sin contactos guardados")

	frame.scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "ScrollFrame", frame, "FauxScrollFrameTemplate")
	frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -95)
	frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 36)
	frame.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
			CAB:RefreshWindow()
		end)
	end)

	frame.rows = {}
	for index = 1, VISIBLE_ROWS do
		local row = CreateFrame("Frame", nil, frame)
		row:SetWidth(660)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", frame.scrollFrame, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

		row.background = row:CreateTexture(nil, "BACKGROUND")
		row.background:SetAllPoints(row)
		if index % 2 == 0 then
			row.background:SetTexture(1, 1, 1, 0.04)
		else
			row.background:SetTexture(1, 1, 1, 0.02)
		end

		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.name:SetWidth(108)
		row.name:SetJustifyH("LEFT")

		row.deleteContactButton = CreateFrame("Button", nil, row)
		row.deleteContactButton:SetPoint("LEFT", row, "LEFT", 118, 0)
		row.deleteContactButton:SetWidth(24)
		row.deleteContactButton:SetHeight(20)
		row.deleteContactButton.text = row.deleteContactButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.deleteContactButton.text:SetAllPoints(row.deleteContactButton)
		row.deleteContactButton.text:SetText("[x]")
		row.deleteContactButton.text:SetTextColor(1, 0.25, 0.25)
		row.deleteContactButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("Borrar contacto")
			GameTooltip:Show()
		end)
		row.deleteContactButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		row.more = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.more:SetPoint("LEFT", row, "LEFT", 600, 0)
		row.more:SetWidth(35)
		row.more:SetJustifyH("LEFT")

		row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		row.status:SetWidth(24)
		row.status:SetHeight(16)
		row.status:SetPoint("RIGHT", row, "RIGHT", -14, 0)
		row.status:SetJustifyH("CENTER")
		row.status:SetText("●")

		frame.rows[index] = row
	end

	self.window = frame
end

function CAB:RefreshWindow()
	if not self.window then
		return
	end

	local frame = self.window
	local contacts = self:GetSortedContacts()
	local total = table.getn(contacts)
	local offset = FauxScrollFrame_GetOffset(frame.scrollFrame)

	FauxScrollFrame_Update(frame.scrollFrame, total, VISIBLE_ROWS, ROW_HEIGHT)
	if total == 0 then
		frame.emptyText:Show()
	else
		frame.emptyText:Hide()
	end

	for rowIndex = 1, VISIBLE_ROWS do
		local row = frame.rows[rowIndex]
		local entry = contacts[rowIndex + offset]

		if entry then
			local contact = entry.contact
			row:Show()
			row.name:SetText(contact.name or entry.key)
			row.deleteContactButton:SetScript("OnClick", function()
				StaticPopup_Show("CAB_DELETE_CONTACT", contact.name or entry.key, nil, {
					playerKey = entry.key,
				})
			end)

			local professions = self:GetSortedProfessions(contact)
			for slot = 1, MAX_VISIBLE_PROFESSIONS do
				local control = self:CreateProfessionControls(row, slot)
				local professionEntry = professions[slot]
				control:SetPoint("LEFT", row, "LEFT", 150 + ((slot - 1) * 220), 0)

				if professionEntry then
					local profession = professionEntry.profession
					control:Show()
					control.linkButton.text:SetText(profession.link or profession.professionName or "Profesion")
					control.linkButton:SetScript("OnClick", function()
						CAB:OpenStoredProfession(entry.key, professionEntry.key)
					end)
					control.linkButton:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:AddLine(profession.professionName or "Profesion")
						if profession.recipeCount then
							GameTooltip:AddLine(profession.recipeCount .. " recetas cacheadas", 0.8, 0.8, 0.8)
						end
						GameTooltip:Show()
					end)
					control.linkButton:SetScript("OnLeave", function()
						GameTooltip:Hide()
					end)
					control.deleteButton:SetScript("OnClick", function()
						StaticPopup_Show("CAB_DELETE_PROFESSION", contact.name or entry.key, profession.professionName or "Profesion", {
							playerKey = entry.key,
							professionKey = professionEntry.key,
						})
					end)
				else
					control:Hide()
				end
			end

			local hiddenCount = table.getn(professions) - MAX_VISIBLE_PROFESSIONS
			if hiddenCount > 0 then
				row.more:SetText("+" .. hiddenCount)
				row.more:Show()
			else
				row.more:Hide()
			end

			if contact.online then
				row.status:SetTextColor(0.1, 1, 0.1)
			else
				row.status:SetTextColor(1, 0.1, 0.1)
			end
		else
			row:Hide()
		end
	end
end

function CAB:ToggleWindow()
	if self.window and self.window:IsShown() then
		self.window:Hide()
	else
		self:ShowWindow()
	end
end

function CAB:ShowWindow(skipShow)
	if not self.window then
		local ok, errorMessage = pcall(function()
			self:CreateWindow()
		end)
		if not ok then
			self:Print("No pude crear la ventana: " .. tostring(errorMessage))
			return false
		end
	end

	if not self.window then
		self:Print("No pude crear la ventana.")
		return false
	end

	if skipShow then
		return true
	end

	self.window:SetFrameStrata("DIALOG")
	self.window:SetFrameLevel(100)
	self.window:Show()
	if self.window.Raise then
		self.window:Raise()
	end
	self:RefreshWindow()
	return true
end

function CAB:HideWindow()
	if self.window then
		self.window:Hide()
	end
end

function CAB:PositionMinimapButton()
	if not self.minimapButton or not Minimap then
		return
	end

	local db = self:GetDB()
	local angle = db.minimap and db.minimap.angle or 225
	local radians = math.rad(angle)
	local x = math.cos(radians) * MINIMAP_BUTTON_RADIUS
	local y = math.sin(radians) * MINIMAP_BUTTON_RADIUS

	self.minimapButton:ClearAllPoints()
	self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function CAB:RefreshMinimapButton()
	if not self.minimapButton then
		self:CreateMinimapButton()
	end

	if not self.minimapButton then
		return
	end

	self:PositionMinimapButton()

	if self:GetDB().minimap.show then
		self.minimapButton:Show()
	else
		self.minimapButton:Hide()
	end
end

function CAB:UpdateMinimapButtonDrag(button)
	if not button.isMouseDown or not Minimap or not GetCursorPosition then
		return
	end

	local rawX, rawY = GetCursorPosition()
	if not rawX or not rawY then
		return
	end

	local moveX = rawX - (button.downX or rawX)
	local moveY = rawY - (button.downY or rawY)
	if not button.isDragging and (moveX * moveX + moveY * moveY) < MINIMAP_BUTTON_DRAG_THRESHOLD then
		return
	end

	button.isDragging = true

	local mapX, mapY = Minimap:GetCenter()
	if not mapX or not mapY then
		return
	end

	local scale = Minimap:GetEffectiveScale() or 1
	if scale == 0 then
		scale = 1
	end

	local cursorX = rawX / scale
	local cursorY = rawY / scale
	local angle = math.deg(GetAtan2(cursorY - mapY, cursorX - mapX))
	if angle < 0 then
		angle = angle + 360
	end

	self:GetDB().minimap.angle = angle
	self:PositionMinimapButton()
end

function CAB:CreateMinimapButton()
	if self.minimapButton or not Minimap then
		return
	end

	local button = CreateFrame("Button", ADDON_NAME .. "MinimapButton", Minimap)
	button:SetWidth(31)
	button:SetHeight(31)
	button:SetFrameStrata("MEDIUM")
	button:EnableMouse(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetWidth(20)
	background:SetHeight(20)
	background:SetPoint("CENTER", button, "CENTER", 0, 0)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnMouseDown", function(self, mouseButton)
		if mouseButton ~= "LeftButton" or not GetCursorPosition then
			return
		end

		self.isMouseDown = true
		self.isDragging = false
		self.downX, self.downY = GetCursorPosition()
		self:SetScript("OnUpdate", function(dragButton)
			CAB:UpdateMinimapButtonDrag(dragButton)
		end)
	end)

	button:SetScript("OnMouseUp", function(self, mouseButton)
		if mouseButton == "LeftButton" then
			if self.isMouseDown and not self.isDragging and GetCursorPosition then
				local upX, upY = GetCursorPosition()
				local moveX = upX and self.downX and (upX - self.downX) or 0
				local moveY = upY and self.downY and (upY - self.downY) or 0
				if (moveX * moveX + moveY * moveY) >= MINIMAP_BUTTON_DRAG_THRESHOLD then
					CAB:UpdateMinimapButtonDrag(self)
				end
			end

			local wasDragging = self.isDragging
			self.isMouseDown = false
			self.isDragging = false
			self:SetScript("OnUpdate", nil)

			if not wasDragging then
				CAB:ShowWindow()
			end
		elseif mouseButton == "RightButton" then
			CAB:StartStatusRefresh()
		end
	end)

	button:SetScript("OnHide", function(self)
		self.isMouseDown = false
		self.isDragging = false
		self:SetScript("OnUpdate", nil)
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("CraftersAddressBook")
		GameTooltip:AddLine("Click izquierdo: abrir agenda", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Click derecho: refrescar estados", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Arrastrar: mover", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	self.minimapButton = button
	self:RefreshMinimapButton()
end

function CAB:SetMinimapButtonShown(show)
	self:GetDB().minimap.show = show and true or false
	self:RefreshMinimapButton()

	if show then
		self:Print("Boton de minimapa visible.")
	else
		self:Print("Boton de minimapa oculto. Usa /cab minimap show para mostrarlo.")
	end
end

function CAB:StartStatusRefresh()
	if not SendWho or not GetNumWhoResults or not GetWhoInfo then
		self:Print("La API /who no esta disponible en este cliente.")
		return
	end

	local contacts = self:GetSortedContacts()
	if table.getn(contacts) == 0 then
		self:Print("No hay contactos para refrescar.")
		return
	end

	self.whoQueue = {}
	for _, entry in ipairs(contacts) do
		entry.contact.online = false
		entry.contact.lastStatusCheck = Now()
		table.insert(self.whoQueue, {
			key = entry.key,
			name = self:GetPlayerName(entry.contact.name or entry.key),
		})
	end

	self.whoActive = nil
	self.nextWhoQueryAt = 0
	self:RefreshWindow()
	self:Print("Refrescando estados online/offline manualmente...")
end

function CAB:SendNextWhoQuery()
	if not self.whoQueue or self.whoActive then
		return
	end

	local nextQuery = table.remove(self.whoQueue, 1)
	if not nextQuery then
		self.whoQueue = nil
		self:RefreshWindow()
		self:Print("Refresco de estados finalizado.")
		return
	end

	if not nextQuery.name or nextQuery.name == "" then
		self.nextWhoQueryAt = GetTime() + WHO_QUERY_DELAY
		return
	end

	self.whoActive = nextQuery
	self.whoActive.startedAt = GetTime()

	if SetWhoToUI then
		SetWhoToUI(0)
	end

	if SendWho then
		SendWho("n-" .. nextQuery.name)
	end
end

function CAB:HandleWhoListUpdate()
	if not self.whoActive or not GetNumWhoResults or not GetWhoInfo then
		return
	end

	local active = self.whoActive
	local online = false

	for index = 1, GetNumWhoResults() do
		local name = GetWhoInfo(index)
		if self:GetPlayerKey(name) == active.key then
			online = true
			break
		end
	end

	local contact = self:GetContact(active.key)
	if contact then
		contact.online = online
		contact.lastStatusCheck = Now()
	end

	self.whoActive = nil
	self.nextWhoQueryAt = GetTime() + WHO_QUERY_DELAY
	self:RefreshWindow()
end

function CAB:OnUpdate()
	if self.whoActive and GetTime() - self.whoActive.startedAt > WHO_QUERY_TIMEOUT then
		local contact = self:GetContact(self.whoActive.key)
		if contact then
			contact.online = false
			contact.lastStatusCheck = Now()
		end
		self.whoActive = nil
		self.nextWhoQueryAt = GetTime() + WHO_QUERY_DELAY
		self:RefreshWindow()
	end

	if self.whoQueue and not self.whoActive and GetTime() >= self.nextWhoQueryAt then
		self:SendNextWhoQuery()
	end
end

function CAB:RegisterChatEvents()
	local events = {
		"CHAT_MSG_SAY",
		"CHAT_MSG_YELL",
		"CHAT_MSG_WHISPER",
		"CHAT_MSG_CHANNEL",
		"CHAT_MSG_GUILD",
		"CHAT_MSG_OFFICER",
		"CHAT_MSG_PARTY",
		"CHAT_MSG_PARTY_LEADER",
		"CHAT_MSG_RAID",
		"CHAT_MSG_RAID_LEADER",
		"CHAT_MSG_BATTLEGROUND",
		"CHAT_MSG_BATTLEGROUND_LEADER",
	}

	for _, eventName in ipairs(events) do
		self:RegisterEvent(eventName)
	end
end

function CAB:CreateOptionsPanel()
	if self.optionsPanel or not InterfaceOptions_AddCategory then
		return
	end

	local panel = CreateFrame("Frame", ADDON_NAME .. "OptionsPanel")
	panel.name = "CraftersAddressBook"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
	title:SetText("CraftersAddressBook")

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	subtitle:SetWidth(560)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Opciones del addon. Este panel queda preparado para futuras configuraciones.")

	local minimapCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	minimapCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20)
	minimapCheck.label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	minimapCheck.label:SetPoint("LEFT", minimapCheck, "RIGHT", 4, 1)
	minimapCheck.label:SetText("Mostrar boton del minimapa")
	minimapCheck:SetScript("OnClick", function(self)
		CAB:SetMinimapButtonShown(self:GetChecked() and true or false)
	end)

	local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	openButton:SetWidth(120)
	openButton:SetHeight(24)
	openButton:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 0, -18)
	openButton:SetText("Abrir agenda")
	openButton:SetScript("OnClick", function()
		if InterfaceOptionsFrame then
			InterfaceOptionsFrame:Hide()
		end
		CAB:ShowWindow()
	end)

	local refreshButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	refreshButton:SetWidth(130)
	refreshButton:SetHeight(24)
	refreshButton:SetPoint("LEFT", openButton, "RIGHT", 8, 0)
	refreshButton:SetText("Refrescar estados")
	refreshButton:SetScript("OnClick", function()
		CAB:StartStatusRefresh()
	end)

	panel.refresh = function()
		minimapCheck:SetChecked(CAB:GetDB().minimap.show and 1 or nil)
	end

	InterfaceOptions_AddCategory(panel)
	self.optionsPanel = panel
end

function CAB:OpenOptionsPanel()
	self:CreateOptionsPanel()
	if InterfaceOptionsFrame_OpenToCategory and self.optionsPanel then
		InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
	end
end

function CAB:RegisterSlashCommands()
	SLASH_CRAFTERSADDRESSBOOK1 = "/cab"
	SLASH_CRAFTERSADDRESSBOOK2 = "/craftersaddressbook"
	SlashCmdList.CRAFTERSADDRESSBOOK = function(message)
		message = string.lower(Trim(message or "") or "")
		if message == "version" then
			CAB:Print("Version " .. CAB:GetVersion() .. " / DB schema " .. DB_SCHEMA_VERSION .. ".")
		elseif message == "refresh" then
			CAB:StartStatusRefresh()
		elseif message == "show" or message == "open" or message == "list" or message == "lista" then
			CAB:ShowWindow()
		elseif message == "close" or message == "hide" then
			CAB:HideWindow()
		elseif message == "toggle" then
			CAB:ToggleWindow()
		elseif message == "options" or message == "config" then
			CAB:OpenOptionsPanel()
		elseif message == "debug" then
			CAB:Print("window=" .. tostring(CAB.window ~= nil) .. ", shown=" .. tostring(CAB.window and CAB.window:IsShown()) .. ", version=" .. CAB:GetVersion())
		elseif message == "minimap" then
			CAB:SetMinimapButtonShown(not CAB:GetDB().minimap.show)
		elseif message == "minimap show" then
			CAB:SetMinimapButtonShown(true)
		elseif message == "minimap hide" then
			CAB:SetMinimapButtonShown(false)
		elseif message == "help" or message == "ayuda" then
			CAB:Print("/cab muestra la lista. /cab refresh refresca estados. /cab minimap alterna el boton. /cab options abre opciones.")
		else
			CAB:ShowWindow()
		end
	end
end

function CAB:Initialize()
	self.db = self:EnsureDB()
	self:RegisterChatEvents()
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_UPDATE")
	self:RegisterEvent("WHO_LIST_UPDATE")
	self:InstallSetItemRefHook()
	self:RegisterSlashCommands()
	self:CreateMinimapButton()
	self:CreateOptionsPanel()
	self:SetScript("OnUpdate", function()
		CAB:OnUpdate()
	end)
	self:Print("cargado. Usa /cab para abrir la agenda.")
end

StaticPopupDialogs.CAB_ADD_PROFESSION = {
	text = "Agregar %s - %s a CraftersAddressBook?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		CAB:AcceptProfession(data)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs.CAB_REFRESH_PROFESSION = {
	text = "Actualizar el cache local de %s - %s?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		CAB:AcceptProfession(data)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs.CAB_DELETE_PROFESSION = {
	text = "Borrar %s - %s de CraftersAddressBook?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		CAB:DeleteProfession(data.playerKey, data.professionKey)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs.CAB_DELETE_CONTACT = {
	text = "Borrar el contacto %s y todas sus profesiones?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data)
		CAB:DeleteContact(data.playerKey)
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

CAB:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local addonName = ...
		if addonName == ADDON_NAME then
			self:UnregisterEvent("ADDON_LOADED")
			self:Initialize()
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
		self:TryScanPendingProfession()
	elseif event == "WHO_LIST_UPDATE" then
		self:HandleWhoListUpdate()
	elseif string.sub(event, 1, 9) == "CHAT_MSG_" then
		local message, sender = ...
		self:CaptureMessageLinks(message, sender)
	end
end)

CAB:RegisterEvent("ADDON_LOADED")
