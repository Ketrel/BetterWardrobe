--	///////////////////////////////////////////////////////////////////////////////////////////
--
--	Better Wardrobe and Collection;
--	Author: SLOKnightfall;

--	Wardrobe and Collection: Adds additional functionality and sets to the transmog and collection areas;

--	///////////////////////////////////////////////////////////////////////////////////////////

BW_TRANSMOG_SHAPESHIFT_MIN_ZOOM = -0.3;

local addonName, addon = ...;
---addon = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0");
addon = LibStub("AceAddon-3.0"):GetAddon(addonName);
--_G[addonName] = {};
addon.ViewDelay = 3;
local newTransmogInfo  = {["latestSource"] = NO_TRANSMOG_SOURCE_ID} --{[99999999] = {[58138] = 10}, };
addon.newTransmogInfo = newTransmogInfo
local playerInv_DB;
local Profile;
local playerNme;
local realmName;
local playerClass, classID, playerClassName;

local L = LibStub("AceLocale-3.0"):GetLocale(addonName);

local BASE_SET_BUTTON_HEIGHT = addon.Globals.BASE_SET_BUTTON_HEIGHT;
local VARIANT_SET_BUTTON_HEIGHT = addon.Globals.VARIANT_SET_BUTTON_HEIGHT;
local SET_PROGRESS_BAR_MAX_WIDTH = addon.Globals.SET_PROGRESS_BAR_MAX_WIDTH;
local IN_PROGRESS_FONT_COLOR =addon.Globals.IN_PROGRESS_FONT_COLOR;
local IN_PROGRESS_FONT_COLOR_CODE = addon.Globals.IN_PROGRESS_FONT_COLOR_CODE;
local COLLECTION_LIST_WIDTH = addon.Globals.COLLECTION_LIST_WIDTH;

addon.useAltSet = false;

--local Sets = {};
--addon.Sets = Sets;
local inventoryTypes = {

};

local EXCLUSION_CATEGORY_OFFHAND = 1;
local EXCLUSION_CATEGORY_MAINHAND = 2;
local Sets = addon.Sets;


local g_selectionBehavior = nil;

local function GetPage(entryIndex, pageSize)
	return floor((entryIndex-1) / pageSize) + 1;
end

local function GetAdjustedDisplayIndexFromKeyPress(contentFrame, index, numEntries, key)
	if ( key == WARDROBE_PREV_VISUAL_KEY ) then
		index = index - 1;
		if ( index < 1 ) then
			index = numEntries;
		end
	elseif ( key == WARDROBE_NEXT_VISUAL_KEY ) then
		index = index + 1;
		if ( index > numEntries ) then
			index = 1;
		end
	elseif ( key == WARDROBE_DOWN_VISUAL_KEY ) then
		local newIndex = index + contentFrame.NUM_COLS;
		if ( newIndex > numEntries ) then
			-- If you're at the last entry, wrap back around; otherwise go to the last entry.
			index = index == numEntries and 1 or numEntries;
		else
			index = newIndex;
		end
	elseif ( key == WARDROBE_UP_VISUAL_KEY ) then
		local newIndex = index - contentFrame.NUM_COLS;
		if ( newIndex < 1 ) then
			-- If you're at the first entry, wrap back around; otherwise go to the first entry.
			index = index == 1 and numEntries or 1;
		else
			index = newIndex;
		end
	end
	return index;
end

-- ************************************************************************************************************************************************************
-- **** MAIN **********************************************************************************************************************************************
-- ************************************************************************************************************************************************************

BetterWardrobeFrameMixin = CreateFromMixins(CallbackRegistryMixin);

BetterWardrobeFrameMixin:GenerateCallbackEvents(
{
	"OnCollectionTabChanged",
});

function BetterWardrobeFrameMixin:OnLoad()
	self:SetPortraitToAsset("Interface\\Icons\\INV_Arcane_Orb");
	self:SetTitle(TRANSMOGRIFY);
	CallbackRegistryMixin.OnLoad(self);
end

-- ************************************************************************************************************************************************************
-- **** TRANSMOG **********************************************************************************************************************************************
-- ************************************************************************************************************************************************************
BW_TransmogFrameMixin = { };

function BW_TransmogFrameMixin:OnLoad()
	local race, fileName = UnitRace("player");
	local atlas = "transmog-background-race-"..fileName;
	self.Inset.BG:SetAtlas(atlas);

	self:RegisterEvent("TRANSMOGRIFY_UPDATE");
	self:RegisterEvent("TRANSMOGRIFY_ITEM_UPDATE");
	self:RegisterEvent("TRANSMOGRIFY_SUCCESS");
	-- set up dependency links
	self.MainHandButton.dependentSlot = self.MainHandEnchantButton;
	self.MainHandEnchantButton.dependencySlot = self.MainHandButton;
	self.SecondaryHandButton.dependentSlot = self.SecondaryHandEnchantButton;
	self.SecondaryHandEnchantButton.dependencySlot = self.SecondaryHandButton;
	self.ShoulderButton.dependentSlot = self.SecondaryShoulderButton;
	self.SecondaryShoulderButton.dependencySlot = self.ShoulderButton;

	WardrobeTransmogFrame.ToggleSecondaryAppearanceCheckbox.Label:SetPoint("RIGHT", WardrobeCollectionFrame.ItemsCollectionFrame.PagingFrame.PageText, "LEFT", -40, 0);

end

function BW_TransmogFrameMixin:OnEvent(event, ...)
	if ( event == "TRANSMOGRIFY_UPDATE" or event == "TRANSMOGRIFY_ITEM_UPDATE" ) then
		local transmogLocation = ...;
		-- play sound?
		local slotButton = self:GetSlotButton(transmogLocation);
		if ( slotButton ) then
			local isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotTransmogrifyReason, hasUndo = C_Transmog.GetSlotInfo(transmogLocation);
			if ( hasUndo ) then
				PlaySound(SOUNDKIT.UI_TRANSMOGRIFY_UNDO);
			elseif ( not hasPending ) then
				if ( slotButton.hadUndo ) then
					PlaySound(SOUNDKIT.UI_TRANSMOGRIFY_REDO);
					slotButton.hadUndo = nil;
				end
			end
			-- specs button tutorial
			if ( hasPending and not hasUndo ) then
				if ( not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SPECS_BUTTON) ) then
					local helpTipInfo = {
						text = TRANSMOG_SPECS_BUTTON_TUTORIAL,
						buttonStyle = HelpTip.ButtonStyle.Close,
						cvarBitfield = "closedInfoFrames",
						bitfieldFlag = LE_FRAME_TUTORIAL_TRANSMOG_SPECS_BUTTON,
						targetPoint = HelpTip.Point.BottomEdgeCenter,
						onAcknowledgeCallback = function() BetterWardrobeCollectionFrame.ItemsCollectionFrame:CheckHelpTip(); end,
						acknowledgeOnHide = true,
					};
					HelpTip:Show(self, helpTipInfo, self.SpecButton);
				end
			end
		end
		if ( event == "TRANSMOGRIFY_UPDATE" ) then
			StaticPopup_Hide("TRANSMOG_APPLY_WARNING");
		elseif ( event == "TRANSMOGRIFY_ITEM_UPDATE" and self.redoApply ) then
			self:ApplyPending(0);
		end
		self:MarkDirty();
	elseif ( event == "PLAYER_EQUIPMENT_CHANGED" ) then
		local slotID = ...;
		self:OnEquipmentChanged(slotID);
	elseif ( event == "TRANSMOGRIFY_SUCCESS" ) then
		local transmogLocation = ...;
		local slotButton = self:GetSlotButton(transmogLocation);
		if ( slotButton ) then
			slotButton:OnTransmogrifySuccess();
		end
	elseif ( event == "UNIT_FORM_CHANGED" ) then
		local unit = ...;
				if ( unit == "player" ) then
			self:HandleFormChanged();
		end
	end
end

function BW_TransmogFrameMixin:HandleFormChanged()
	self.needsFormChangedHandling = true;
	if IsUnitModelReadyForUI("player") then
		local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo();
		if ( self.inAlternateForm ~= inAlternateForm ) then
			self.inAlternateForm = inAlternateForm;
			self:RefreshPlayerModel();
			self.needsFormChangedHandling = false;
		end	
	end
end

function BW_TransmogFrameMixin:OnShow()
	HideUIPanel(CollectionsJournal);
	BetterWardrobeCollectionFrame:SetContainer(WardrobeFrame);
	
	PlaySound(SOUNDKIT.UI_TRANSMOG_OPEN_WINDOW);
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
	local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo();
	if ( hasAlternateForm ) then
		self:RegisterUnitEvent("UNIT_FORM_CHANGED", "player");
		self.inAlternateForm = inAlternateForm;
	end
	self.ModelScene:TransitionToModelSceneID(290, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true);
	self:RefreshPlayerModel();

	WardrobeFrame:RegisterCallback(BetterWardrobeFrameMixin.Event.OnCollectionTabChanged, self.EvaluateSecondaryAppearanceCheckbox, self);
end

function BW_TransmogFrameMixin:OnHide()
	PlaySound(SOUNDKIT.UI_TRANSMOG_CLOSE_WINDOW);
	StaticPopup_Hide("TRANSMOG_APPLY_WARNING");
	self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED");
	self:UnregisterEvent("UNIT_FORM_CHANGED");

	C_PlayerInteractionManager.ClearInteraction(Enum.PlayerInteractionType.Transmogrifier);
	WardrobeFrame:UnregisterCallback(BetterWardrobeFrameMixin.Event.OnCollectionTabChanged, self);
end

function BW_TransmogFrameMixin:MarkDirty()
	self.dirty = true;
end

function BW_TransmogFrameMixin:OnUpdate()
	if self.dirty then
		self:Update();
		end

	if self.needsFormChangedHandling then
		self:HandleFormChanged();
	end
end

function BW_TransmogFrameMixin:OnEquipmentChanged(slotID)
	local resetHands = false;
	for i, slotButton in ipairs(self.SlotButtons) do
		if slotButton.transmogLocation:GetSlotID() == slotID then
			C_Transmog.ClearPending(slotButton.transmogLocation);
			if slotButton.transmogLocation:IsEitherHand() then
				resetHands = true;
			end
			self:MarkDirty();
		end
	end
	if resetHands then
		-- Have to do this because of possible weirdness with RANGED type combined with other weapon types
		local actor = self.ModelScene:GetPlayerActor();
		if actor then
			actor:UndressSlot(INVSLOT_MAINHAND);
			actor:UndressSlot(INVSLOT_OFFHAND);
		end
	end
	if C_Transmog.CanHaveSecondaryAppearanceForSlotID(slotID) then
		self:CheckSecondarySlotButtons();
	end
end

function BW_TransmogFrameMixin:GetRandomAppearanceID()
	if not self.selectedSlotButton or not C_Item.DoesItemExist(self.selectedSlotButton.itemLocation) then
		return Constants.Transmog.NoTransmogID;
	end

	-- we need to skip any appearances that match base or current
	local baseItemTransmogInfo = C_Item.GetBaseItemTransmogInfo(self.selectedSlotButton.itemLocation);
	local baseInfo = C_TransmogCollection.GetAppearanceInfoBySource(baseItemTransmogInfo.appearanceID);
	local baseVisual = baseInfo and baseInfo.appearanceID;
	local appliedItemTransmogInfo = C_Item.GetAppliedItemTransmogInfo(self.selectedSlotButton.itemLocation);
	local appliedInfo = C_TransmogCollection.GetAppearanceInfoBySource(appliedItemTransmogInfo.appearanceID);
	local appliedVisual = appliedInfo and appliedInfo.appearanceID or Constants.Transmog.NoTransmogID;

	-- the collection should always be matched with the slot
	local visualsList = BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetFilteredVisualsList();
	
	local function GetValidRandom(minIndex, maxIndex)
		local range = maxIndex - minIndex + 1;
		local startPoint = math.random(minIndex, maxIndex);
		for i = minIndex, maxIndex do
			local currentIndex = startPoint + i;
			if currentIndex > maxIndex then
				-- overflow cycles from the beginning
				currentIndex = currentIndex - range;
			end
			local visualInfo = visualsList[currentIndex];
			local visualID = visualInfo.visualID;
			if visualID ~= baseVisual and visualID ~= appliedVisual and not visualInfo.isHideVisual then
				return BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetAnAppearanceSourceFromVisual(visualID, true);
			end
		end
		return nil;
	end

	-- first try favorites
	local numFavorites = 0;
	for i, visualInfo in ipairs(visualsList) do
		-- favorites are all at the front
		if not visualInfo.isFavorite then
			numFavorites = i - 1;
			break;
		end
	end
	if numFavorites > 0 then
		local appearanceID = GetValidRandom(1, numFavorites);
		if appearanceID then
			return appearanceID;
		end
	end
	-- now try the rest
	if numFavorites < #visualsList then
		local appearanceID = GetValidRandom(numFavorites + 1, #visualsList);
		if appearanceID then
			return appearanceID;
		end
	end
	-- This is the case of only 1, maybe 2 collected appearances
	return Constants.Transmog.NoTransmogID;
end

function BW_TransmogFrameMixin:ToggleSecondaryForSelectedSlotButton()
	local transmogLocation = self.selectedSlotButton and self.selectedSlotButton.transmogLocation;
	-- if on the main slot, switch to secondary
	if transmogLocation.modification == Enum.TransmogModification.Main then
		transmogLocation = TransmogUtil.GetTransmogLocation(transmogLocation.slotID, transmogLocation.type, Enum.TransmogModification.Secondary);
	end	
	local isSecondaryTransmogrified = TransmogUtil.IsSecondaryTransmoggedForItemLocation(self.selectedSlotButton.itemLocation);
	local toggledOn = self.ToggleSecondaryAppearanceCheckbox:GetChecked();
	if toggledOn then
		-- if the item does not already have secondary then set a random pending, otherwise clear any pending
		if not isSecondaryTransmogrified then
			local pendingInfo;
			local randomAppearanceID = self:GetRandomAppearanceID();
			if randomAppearanceID == Constants.Transmog.NoTransmogID then
				pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.ToggleOn);
			else
				pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, randomAppearanceID);
			end
			C_Transmog.SetPending(transmogLocation, pendingInfo);
		else
			C_Transmog.ClearPending(transmogLocation);
		end
	else
		-- if the item already has secondary then it's a toggle off, otherwise clear any pending
		if isSecondaryTransmogrified then
			local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.ToggleOff);
			C_Transmog.SetPending(transmogLocation, pendingInfo);
		else
			C_Transmog.ClearPending(transmogLocation);
		end
	end
	self:CheckSecondarySlotButtons();
end

function BW_TransmogFrameMixin:CheckSecondarySlotButtons()
	local headButton = self.HeadButton;
	local mainShoulderButton = self.ShoulderButton;
	local secondaryShoulderButton = self.SecondaryShoulderButton;
	local secondaryShoulderTransmogged = TransmogUtil.IsSecondaryTransmoggedForItemLocation(secondaryShoulderButton.itemLocation);

	local pendingInfo = C_Transmog.GetPending(secondaryShoulderButton.transmogLocation);
	local showSecondaryShoulder = false;
	if not pendingInfo then
		showSecondaryShoulder = secondaryShoulderTransmogged;
	elseif pendingInfo.type == Enum.TransmogPendingType.ToggleOff then
		showSecondaryShoulder = false;
	else
		showSecondaryShoulder = true;
	end

	secondaryShoulderButton:SetShown(showSecondaryShoulder);
	self.ToggleSecondaryAppearanceCheckbox:SetChecked(showSecondaryShoulder);

	if showSecondaryShoulder then
		headButton:SetPoint("TOP", -121, -15);
		secondaryShoulderButton:SetPoint("TOP", mainShoulderButton, "BOTTOM", 0, -10);
	else
		headButton:SetPoint("TOP", -121, -41);
		secondaryShoulderButton:SetPoint("TOP", mainShoulderButton, "TOP");
	end

	if not showSecondaryShoulder and self.selectedSlotButton == secondaryShoulderButton then
		self:SelectSlotButton(mainShoulderButton);
	end
end

function BW_TransmogFrameMixin:HasActiveSecondaryAppearance()
	local checkbox = self.ToggleSecondaryAppearanceCheckbox;
	return checkbox:IsShown() and checkbox:GetChecked();
end

function BW_TransmogFrameMixin:SelectSlotButton(slotButton, fromOnClick)
	if self.selectedSlotButton then
		self.selectedSlotButton:SetSelected(false);
	end
	self.selectedSlotButton = slotButton;
	if slotButton then
		slotButton:SetSelected(true);
		if (fromOnClick and BetterWardrobeCollectionFrame.activeFrame ~= BetterWardrobeCollectionFrame.ItemsCollectionFrame) then
			BetterWardrobeCollectionFrame:ClickTab(BetterWardrobeCollectionFrame.ItemsTab);
		end
		if ( BetterWardrobeCollectionFrame.activeFrame == BetterWardrobeCollectionFrame.ItemsCollectionFrame ) then
			local _, _, selectedSourceID = TransmogUtil.GetInfoForEquippedSlot(slotButton.transmogLocation);
			local forceGo = slotButton.transmogLocation:IsIllusion();
			local forTransmog = true;
			local effectiveCategory;
			if slotButton.transmogLocation:IsEitherHand() then
				effectiveCategory = C_Transmog.GetSlotEffectiveCategory(slotButton.transmogLocation);
			end
			BetterWardrobeCollectionFrame.ItemsCollectionFrame:GoToSourceID(selectedSourceID, slotButton.transmogLocation, forceGo, forTransmog, effectiveCategory);
			BetterWardrobeCollectionFrame.ItemsCollectionFrame:SetTransmogrifierAppearancesShown(true);
		end
	else
		BetterWardrobeCollectionFrame.ItemsCollectionFrame:SetTransmogrifierAppearancesShown(false);
	end
	self:EvaluateSecondaryAppearanceCheckbox();
end

function BW_TransmogFrameMixin:EvaluateSecondaryAppearanceCheckbox()
	local showToggleCheckbox = false;
	if self.selectedSlotButton and BetterWardrobeCollectionFrame.activeFrame == BetterWardrobeCollectionFrame.ItemsCollectionFrame then
		showToggleCheckbox = C_Transmog.CanHaveSecondaryAppearanceForSlotID(self.selectedSlotButton.transmogLocation.slotID);
	end
	self.ToggleSecondaryAppearanceCheckbox:SetShown(showToggleCheckbox);
end

function BW_TransmogFrameMixin:GetSelectedTransmogLocation()
	if self.selectedSlotButton then
		return self.selectedSlotButton.transmogLocation;
	end
	return nil;
end

function BW_TransmogFrameMixin:RefreshPlayerModel()
	if self.ModelScene.previousActor then
		self.ModelScene.previousActor:ClearModel();
		self.ModelScene.previousActor = nil;
	end

	local actor = self.ModelScene:GetPlayerActor();
	if actor then
		local sheatheWeapons = false;
		local autoDress = true;
		local hideWeapons = false;
		local useNativeForm = true;
		local _, raceFilename = UnitRace("Player");
		if (raceFilename == "Dracthyr" or raceFilename == "Worgen") then
			useNativeForm = not self.inAlternateForm;
		end
		actor:SetModelByUnit("player", sheatheWeapons, autoDress, hideWeapons, useNativeForm)
		self.ModelScene.previousActor = actor
	end
	self:Update()
end


function BW_TransmogFrameMixin:Update()
	self.dirty = false;
	for i, slotButton in ipairs(self.SlotButtons) do
		slotButton:Update()
	end
	for i, slotButton in ipairs(self.SlotButtons) do
		slotButton:RefreshItemModel()
	end

	self:UpdateApplyButton()
	self.BW_OutfitDropDown:UpdateSaveButton()

	self:CheckSecondarySlotButtons()

	if not self.selectedSlotButton or not self.selectedSlotButton:IsEnabled() then
		-- select first valid slot or clear selection
		local validSlotButton;
		for i, slotButton in ipairs(self.SlotButtons) do
			if slotButton:IsEnabled() and slotButton.transmogLocation:IsAppearance() then
				validSlotButton = slotButton;
				break;
			end
		end
		self:SelectSlotButton(validSlotButton)
	else
		self:SelectSlotButton(self.selectedSlotButton)
	end
end

function BW_TransmogFrameMixin:SetPendingTransmog(transmogID, category)
	if self.selectedSlotButton then

		local transmogLocation = self.selectedSlotButton.transmogLocation;
		if transmogLocation:IsSecondary() then
			local currentPendingInfo = C_Transmog.GetPending(transmogLocation)
			if currentPendingInfo and currentPendingInfo.type == Enum.TransmogPendingType.Apply then
				self.selectedSlotButton.priorTransmogID = currentPendingInfo.transmogID;
			end
		end
		local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, transmogID, category)
		C_Transmog.SetPending(transmogLocation, pendingInfo)
	end
end

function BW_TransmogFrameMixin:UpdateApplyButton()
	local cost = C_Transmog.GetApplyCost()
	local canApply;
	if cost and cost > GetMoney() then
		SetMoneyFrameColor("WardrobeTransmogMoneyFrame", "red")
	else
		SetMoneyFrameColor("WardrobeTransmogMoneyFrame")
		if cost then
			canApply = true;
		end
	end
	if StaticPopup_FindVisible("TRANSMOG_APPLY_WARNING") then
		canApply = false;
	end
	MoneyFrame_Update("WardrobeTransmogMoneyFrame", cost or 0, true);	-- always show 0 copper
	self.ApplyButton:SetEnabled(canApply)
	self.ModelScene.ClearAllPendingButton:SetShown(canApply)
end

function BW_TransmogFrameMixin:GetSlotButton(transmogLocation)
	for i, slotButton in ipairs(self.SlotButtons) do
		if slotButton.transmogLocation:IsEqual(transmogLocation) then
			return slotButton;
		end
	end
end

function BW_TransmogFrameMixin:ApplyPending(lastAcceptedWarningIndex)
	if ( lastAcceptedWarningIndex == 0 or not self.applyWarningsTable ) then
		self.applyWarningsTable = C_Transmog.GetApplyWarnings()
	end
	self.redoApply = nil;
	if ( self.applyWarningsTable and lastAcceptedWarningIndex < #self.applyWarningsTable ) then
		lastAcceptedWarningIndex = lastAcceptedWarningIndex + 1;
		local data = {
			["link"] = self.applyWarningsTable[lastAcceptedWarningIndex].itemLink,
			["useLinkForItemInfo"] = true,
			["warningIndex"] = lastAcceptedWarningIndex;
		}
		StaticPopup_Show("TRANSMOG_APPLY_WARNING", self.applyWarningsTable[lastAcceptedWarningIndex].text, nil, data)
		self:UpdateApplyButton()
		-- return true to keep static popup open when chaining warnings
		return true;
	else
		local success = C_Transmog.ApplyAllPending(GetCVarBool("transmogCurrentSpecOnly"))
		if ( success ) then
			self:OnTransmogApplied()
			PlaySound(SOUNDKIT.UI_TRANSMOG_APPLY)
			self.applyWarningsTable = nil;
			-- outfit tutorial
			if ( not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_OUTFIT_DROPDOWN) ) then
				local outfits = C_TransmogCollection.GetOutfits()
				if ( #outfits == 0 ) then
					local helpTipInfo = {
						text = TRANSMOG_OUTFIT_DROPDOWN_TUTORIAL,
						buttonStyle = HelpTip.ButtonStyle.Close,
						cvarBitfield = "closedInfoFrames",
						bitfieldFlag = LE_FRAME_TUTORIAL_TRANSMOG_OUTFIT_DROPDOWN,
						targetPoint = HelpTip.Point.RightEdgeCenter,
						offsetX = -18,
						onAcknowledgeCallback = function() BetterWardrobeCollectionFrame.ItemsCollectionFrame:CheckHelpTip(); end,
						acknowledgeOnHide = true,
					}
					HelpTip:Show(self, helpTipInfo, self.OutfitDropDown)
				end
			end
		else
			-- it's retrieving item info
			self.redoApply = true;
		end
		return false;
	end
end

function BW_TransmogFrameMixin:OnTransmogApplied()
	local dropDown = self.OutfitDropDown;
	if dropDown.selectedOutfitID and dropDown:IsOutfitDressed() then
		dropDown:OnOutfitApplied(dropDown.selectedOutfitID)
	end
end

BetterWardrobeOutfitMixin = CreateFromMixins(WardrobeOutfitFrameMixin)

function BetterWardrobeOutfitMixin:OnOutfitApplied(outfitID)
		-----self:SaveLastOutfit(outfitID);

	--revisit 9.1.5;
	addon.OutfitDB.char.lastTransmogOutfitIDSpec = addon.OutfitDB.char.lastTransmogOutfitIDSpec or {}

	if addon.IsDefaultSet(outfitID) then
		local value = addon:GetBlizzID(outfitID) or ""
		if GetCVarBool("transmogCurrentSpecOnly") then
			local specIndex = GetSpecialization()
			SetCVar("lastTransmogOutfitIDSpec"..specIndex, value)
			addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] =  outfitID;
		else
			for specIndex = 1, GetNumSpecializations() do
				SetCVar("lastTransmogOutfitIDSpec"..specIndex, value)
				addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] = outfitID;
			end
		end
	else
		local value = outfitID or ""
		if GetCVarBool("transmogCurrentSpecOnly") then
			local specIndex = GetSpecialization()
			addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] = value;
		else
			for specIndex = 1, GetNumSpecializations() do
				addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] = value;
			end
		end
	end
end

----todo revisit;
function BetterWardrobeOutfitMixin:LoadOutfit(outfitID)
	if ( not outfitID ) then
		return;
	end
	addon.C_Transmog.LoadOutfit(outfitID)
end


function BetterWardrobeOutfitMixin:GetItemTransmogInfoList()
	if not WardrobeTransmogFrame then return nil end
	local playerActor = WardrobeTransmogFrame.ModelScene:GetPlayerActor()
	if playerActor then
		return playerActor:GetItemTransmogInfoList()
	end
	return nil;
end

function BetterWardrobeOutfitMixin:OnOutfitSaved(outfitID)
	if C_Transmog.GetApplyCost() then
		self:OnOutfitApplied(outfitID)
	end
end

function BetterWardrobeOutfitMixin:OnSelectOutfit(outfitID)
	addon.OutfitDB.char.lastTransmogOutfitIDSpec = addon.OutfitDB.char.lastTransmogOutfitIDSpec or {}

	if addon.IsDefaultSet(outfitID) then

		-- outfitID can be 0, so use empty string for none
		local value = addon:GetBlizzID(outfitID) or ""
		for specIndex = 1, GetNumSpecializations() do
			if GetCVar("lastTransmogOutfitIDSpec"..specIndex) == "" then
				SetCVar("lastTransmogOutfitIDSpec"..specIndex, value)
				addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] = outfitID;
			end
		end
	else
		local value = outfitID or ""
		for specIndex = 1, GetNumSpecializations() do
			if addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] == "" then
				addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] = value;
			end
		end
	end
end


--TODO U{PDATE}
function BetterWardrobeOutfitMixin:GetLastOutfitID()
	local specIndex = GetSpecialization()
	--if not specIndex then return end
	--if addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex] then 
		return addon.OutfitDB.char.lastTransmogOutfitIDSpec[specIndex]
	--else
		--return tonumber(GetCVar("lastTransmogOutfitIDSpec"..specIndex))
	--end
end



BetterTransmogSlotButtonMixin = { }

function BetterTransmogSlotButtonMixin:OnLoad()
	local slotID, textureName = GetInventorySlotInfo(self.slot)
	self.slotID = slotID;
	self.transmogLocation = TransmogUtil.GetTransmogLocation(slotID, self.transmogType, self.modification)
	if self.transmogLocation:IsAppearance() then
		self.Icon:SetTexture(textureName)
	else
		self.Icon:SetTexture(ENCHANT_EMPTY_SLOT_FILEDATAID)
	end
	self.itemLocation = ItemLocation:CreateFromEquipmentSlot(slotID)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

function BetterTransmogSlotButtonMixin:OnClick(mouseButton)
	local isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotTransmogrifyReason, hasUndo = C_Transmog.GetSlotInfo(self.transmogLocation)
	-- save for sound to play on TRANSMOGRIFY_UPDATE event
	self.hadUndo = hasUndo
	if mouseButton == "RightButton" then
		if hasPending or hasUndo then
			local newPendingInfo;
			-- for secondary this action might require setting a different pending instead of clearing current pending
			if self.transmogLocation:IsSecondary() then
				if not TransmogUtil.IsSecondaryTransmoggedForItemLocation(self.itemLocation) then
					local currentPendingInfo = C_Transmog.GetPending(self.transmogLocation)
					if currentPendingInfo.type == Enum.TransmogPendingType.ToggleOn then
						if self.priorTransmogID then
							newPendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, self.priorTransmogID)
						else
							newPendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.ToggleOn)
						end
					else
						self.priorTransmogID = currentPendingInfo.transmogID;
						newPendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.ToggleOn)
					end
				end
			end
			if newPendingInfo then
				C_Transmog.SetPending(self.transmogLocation, newPendingInfo)
			else
				C_Transmog.ClearPending(self.transmogLocation)
			end
			PlaySound(SOUNDKIT.UI_TRANSMOG_REVERTING_GEAR_SLOT)
			self:OnUserSelect()
		elseif isTransmogrified then
			PlaySound(SOUNDKIT.UI_TRANSMOG_REVERTING_GEAR_SLOT)
			local newPendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Revert)
			C_Transmog.SetPending(self.transmogLocation, newPendingInfo)
			self:OnUserSelect()
		end
	else
		PlaySound(SOUNDKIT.UI_TRANSMOG_GEAR_SLOT_CLICK)
		self:OnUserSelect()
	end
	if self.UndoButton then
		self.UndoButton:Hide()
	end
	self:OnEnter()
end

function BetterTransmogSlotButtonMixin:OnUserSelect()
	local fromOnClick = true;
	self:GetParent():SelectSlotButton(self, fromOnClick)
end

function BetterTransmogSlotButtonMixin:OnEnter()
	local isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotTransmogrifyReason, hasUndo = C_Transmog.GetSlotInfo(self.transmogLocation)

	if ( self.transmogLocation:IsIllusion() ) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
		GameTooltip:SetText(WEAPON_ENCHANTMENT)
		local baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo = C_Transmog.GetSlotVisualInfo(self.transmogLocation)
		if ( self.invalidWeapon ) then
			GameTooltip:AddLine(TRANSMOGRIFY_ILLUSION_INVALID_ITEM, TRANSMOGRIFY_FONT_COLOR.r, TRANSMOGRIFY_FONT_COLOR.g, TRANSMOGRIFY_FONT_COLOR.b, true)
		elseif ( hasPending or hasUndo or canTransmogrify ) then
			if ( baseSourceID > 0 ) then
				local name = C_TransmogCollection.GetIllusionStrings(baseSourceID)
				GameTooltip:AddLine(name, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
			end
			if ( hasUndo ) then
				GameTooltip:AddLine(TRANSMOGRIFY_TOOLTIP_REVERT, TRANSMOGRIFY_FONT_COLOR.r, TRANSMOGRIFY_FONT_COLOR.g, TRANSMOGRIFY_FONT_COLOR.b)
			elseif ( pendingSourceID > 0 ) then
				GameTooltip:AddLine(WILL_BE_TRANSMOGRIFIED_HEADER, TRANSMOGRIFY_FONT_COLOR.r, TRANSMOGRIFY_FONT_COLOR.g, TRANSMOGRIFY_FONT_COLOR.b)
				local name = C_TransmogCollection.GetIllusionStrings(pendingSourceID)
				GameTooltip:AddLine(name, TRANSMOGRIFY_FONT_COLOR.r, TRANSMOGRIFY_FONT_COLOR.g, TRANSMOGRIFY_FONT_COLOR.b)
			elseif ( appliedSourceID > 0 ) then
				GameTooltip:AddLine(TRANSMOGRIFIED_HEADER, TRANSMOGRIFY_FONT_COLOR.r, TRANSMOGRIFY_FONT_COLOR.g, TRANSMOGRIFY_FONT_COLOR.b)
				local name = C_TransmogCollection.GetIllusionStrings(appliedSourceID)
				GameTooltip:AddLine(name, TRANSMOGRIFY_FONT_COLOR.r, TRANSMOGRIFY_FONT_COLOR.g, TRANSMOGRIFY_FONT_COLOR.b)
			end
		else
			if not C_Item.DoesItemExist(self.itemLocation) then
				GameTooltip:AddLine(TRANSMOGRIFY_INVALID_NO_ITEM, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
			else
				GameTooltip:AddLine(TRANSMOGRIFY_ILLUSION_INVALID_ITEM, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
			end
		end
		GameTooltip:Show()
	else
		if ( self.UndoButton and canTransmogrify and isTransmogrified and not ( hasPending or hasUndo ) ) then
			self.UndoButton:Show()
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 14, 0)
		if not canTransmogrify and not hasUndo then
			GameTooltip:SetText(_G[self.slot])
			local tag = TRANSMOG_INVALID_CODES[cannotTransmogrifyReason]
			local errorMsg;
			if ( tag == "CANNOT_USE" ) then
				local errorCode, errorString = C_Transmog.GetSlotUseError(self.transmogLocation)
				errorMsg = errorString;
			else
				errorMsg = tag and _G["TRANSMOGRIFY_INVALID_"..tag]
			end
			if ( errorMsg ) then
				GameTooltip:AddLine(errorMsg, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
			end
			GameTooltip:Show()
		else
			GameTooltip:SetTransmogrifyItem(self.transmogLocation)
		end
	end
	WardrobeTransmogFrame.ModelScene.ControlFrame:Show()
	self.UpdateTooltip = GenerateClosure(self.OnEnter, self)
end

function BetterTransmogSlotButtonMixin:OnLeave()
	if ( self.UndoButton and not self.UndoButton:IsMouseOver() ) then
		self.UndoButton:Hide()
	end
	WardrobeTransmogFrame.ModelScene.ControlFrame:Hide()
	GameTooltip:Hide()
	self.UpdateTooltip = nil;
end

function BetterTransmogSlotButtonMixin:OnShow()
	self:Update()
end

function BetterTransmogSlotButtonMixin:OnHide()
	self.priorTransmogID = nil;
end

function BetterTransmogSlotButtonMixin:SetSelected(selected)
	self.SelectedTexture:SetShown(selected)
end

function BetterTransmogSlotButtonMixin:OnTransmogrifySuccess()
	self:Animate()
	self:GetParent():MarkDirty()
	self.priorTransmogID = nil;	
end

function BetterTransmogSlotButtonMixin:Animate()
	-- don't do anything if already animating
	if self.AnimFrame:IsShown() then
		return;
	end
	local isTransmogrified = C_Transmog.GetSlotInfo(self.transmogLocation)
	if isTransmogrified then
		self.AnimFrame.Transition:Show()
	else
		self.AnimFrame.Transition:Hide()
	end
	self.AnimFrame:Show()
	self.AnimFrame.Anim:Play()
end

function BetterTransmogSlotButtonMixin:OnAnimFinished()
	self.AnimFrame:Hide()
	self:Update()
end

function BetterTransmogSlotButtonMixin:Update()
	if not self:IsShown() then
		return;
	end

	local isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotTransmogrifyReason, hasUndo, isHideVisual, texture = C_Transmog.GetSlotInfo(self.transmogLocation)
	local baseTexture = GetInventoryItemTexture("player", self.transmogLocation.slotID)

	if C_Transmog.IsSlotBeingCollapsed(self.transmogLocation) then
		-- This will indicate a pending change for the item
		hasPending = true;
		isPendingCollected = true;
		canTransmogrify = true;
	end

	local hasChange = (hasPending and canTransmogrify) or hasUndo

	if self.transmogLocation:IsAppearance() then
		if canTransmogrify or hasChange then
			if hasUndo then
				self.Icon:SetTexture(baseTexture)
			else
				self.Icon:SetTexture(texture)
			end
			self.NoItemTexture:Hide()
		else
			local tag = TRANSMOG_INVALID_CODES[cannotTransmogrifyReason]

			local slotID, defaultTexture = GetInventorySlotInfo(self.slot)

			if tag == "SLOT_FOR_FORM" then
				if texture then
					self.Icon:SetTexture(texture)
				else
					self.Icon:SetTexture(defaultTexture)
				end
			elseif tag == "NO_ITEM" or tag == "SLOT_FOR_RACE" then
				self.Icon:SetTexture(defaultTexture);	
			else
				self.Icon:SetTexture(texture)
			end
			
			self.NoItemTexture:Show()
		end
	else
		-- check for weapons lacking visual attachments
		local sourceID = self.dependencySlot:GetEffectiveTransmogID()
		if sourceID ~= Constants.Transmog.NoTransmogID and not BetterWardrobeCollectionFrame.ItemsCollectionFrame:CanEnchantSource(sourceID) then
			-- clear anything in the enchant slot, otherwise cost and Apply button state will still reflect anything pending
			C_Transmog.ClearPending(self.transmogLocation)
			isTransmogrified = false;	-- handle legacy, this weapon could have had an illusion applied previously
			canTransmogrify = false;
			self.invalidWeapon = true;
		else
			self.invalidWeapon = false;
		end

		if ( hasPending or hasUndo or canTransmogrify ) then
			self.Icon:SetTexture(texture or ENCHANT_EMPTY_SLOT_FILEDATAID)
			self.NoItemTexture:Hide()
		else
			self.Icon:SetColorTexture(0, 0, 0)
			self.NoItemTexture:Show()
		end
	end
	self:SetEnabled(canTransmogrify or hasUndo)

	-- show transmogged border if the item is transmogrified and doesn't have a pending transmogrification or is animating
	local showStatusBorder = false;
	if hasPending then
		showStatusBorder = hasUndo or (isPendingCollected and canTransmogrify)
	else
		showStatusBorder = isTransmogrified and not hasChange and not self.AnimFrame:IsShown()
	end
	self.StatusBorder:SetShown(showStatusBorder)

	-- show ants frame is the item has a pending transmogrification and is not animating
	if ( hasChange and (hasUndo or isPendingCollected) and not self.AnimFrame:IsShown() ) then
		self.PendingFrame:Show()
		if ( hasUndo ) then
			self.PendingFrame.Undo:Show()
		else
			self.PendingFrame.Undo:Hide()
		end
	else
		self.PendingFrame:Hide()
	end

	if ( isHideVisual and not hasUndo ) then
		if ( self.HiddenVisualIcon ) then
			if ( canTransmogrify ) then
				self.HiddenVisualCover:Show()
				self.HiddenVisualIcon:Show()
			else
				self.HiddenVisualCover:Hide()
				self.HiddenVisualIcon:Hide()
			end
		end

		local baseTexture = GetInventoryItemTexture("player", self.transmogLocation.slotID)
		self.Icon:SetTexture(baseTexture)
	else
		if ( self.HiddenVisualIcon ) then
			self.HiddenVisualCover:Hide()
			self.HiddenVisualIcon:Hide()
		end
	end
end

function BetterTransmogSlotButtonMixin:GetEffectiveTransmogID()
	if not C_Item.DoesItemExist(self.itemLocation) then
		return Constants.Transmog.NoTransmogID;
	end

	local function GetTransmogIDFrom(fn)
		local itemTransmogInfo = fn(self.itemLocation)
		return TransmogUtil.GetRelevantTransmogID(itemTransmogInfo, self.transmogLocation)
	end

	local pendingInfo = C_Transmog.GetPending(self.transmogLocation)
	if pendingInfo then
		if pendingInfo.type == Enum.TransmogPendingType.Apply then
			return pendingInfo.transmogID;
		elseif pendingInfo.type == Enum.TransmogPendingType.Revert then
			return GetTransmogIDFrom(C_Item.GetBaseItemTransmogInfo)
		elseif pendingInfo.type == Enum.TransmogPendingType.ToggleOff then
			return Constants.Transmog.NoTransmogID;
		end
	end
	local appliedTransmogID = GetTransmogIDFrom(C_Item.GetAppliedItemTransmogInfo)
	-- if nothing is applied, get base
	if appliedTransmogID == Constants.Transmog.NoTransmogID then
		return GetTransmogIDFrom(C_Item.GetBaseItemTransmogInfo)
	else
		return appliedTransmogID;
	end
end

function BetterTransmogSlotButtonMixin:RefreshItemModel()
	local actor = WardrobeTransmogFrame.ModelScene:GetPlayerActor()
	if not actor then
		return;
	end
	-- this slot will be handled by the dependencySlot
	if self.dependencySlot then
		return;
	end

	local appearanceID = self:GetEffectiveTransmogID()
	local secondaryAppearanceID = Constants.Transmog.NoTransmogID;
	local illusionID = Constants.Transmog.NoTransmogID;
	if self.dependentSlot then
		if self.transmogLocation:IsEitherHand() then
			illusionID = self.dependentSlot:GetEffectiveTransmogID()
		else
			secondaryAppearanceID = self.dependentSlot:GetEffectiveTransmogID()
		end
	end

	if appearanceID ~= Constants.Transmog.NoTransmogID then
		local slotID = self.transmogLocation.slotID;
		local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(appearanceID, secondaryAppearanceID, illusionID)
		local currentItemTransmogInfo = actor:GetItemTransmogInfo(slotID)
		-- need the main category for mainhand
		local mainHandCategoryID;
		local isLegionArtifact = false;

		if self.transmogLocation:IsMainHand() then
			mainHandCategoryID = C_Transmog.GetSlotEffectiveCategory(self.transmogLocation)
			isLegionArtifact = TransmogUtil.IsCategoryLegionArtifact(mainHandCategoryID)
			itemTransmogInfo:ConfigureSecondaryForMainHand(isLegionArtifact)
		end
		-- update only if there is a change or it can recurse (offhand is processed first and mainhand might override offhand)
		if not itemTransmogInfo:IsEqual(currentItemTransmogInfo) or isLegionArtifact then
			-- don't specify a slot for ranged weapons
			if mainHandCategoryID and TransmogUtil.IsCategoryRangedWeapon(mainHandCategoryID) then
				slotID = nil;
			end
			actor:SetItemTransmogInfo(itemTransmogInfo, slotID)
		end
	end
end

BetterWardrobeTransmogClearAllPendingButtonMixin = {}

function BetterWardrobeTransmogClearAllPendingButtonMixin:OnClick()
	PlaySound(SOUNDKIT.UI_TRANSMOG_REVERTING_GEAR_SLOT)
	for index, button in ipairs(WardrobeTransmogFrame.SlotButtons) do
		C_Transmog.ClearPending(button.transmogLocation)
	end
end

function BetterWardrobeTransmogClearAllPendingButtonMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(TRANSMOGRIFY_CLEAR_ALL_PENDING)
end

function BetterWardrobeTransmogClearAllPendingButtonMixin:OnLeave()
	GameTooltip:Hide()
end

-- ************************************************************************************************************************************************************
-- **** COLLECTION ********************************************************************************************************************************************
-- ************************************************************************************************************************************************************

local MAIN_HAND_INV_TYPE = 21;
local OFF_HAND_INV_TYPE = 22;
local RANGED_INV_TYPE = 15;
local TAB_ITEMS = 1;
local TAB_SETS = 2;
local TAB_EXTRASETS = addon.Globals.TAB_EXTRASETS;
local TAB_SAVED_SETS = addon.Globals.TAB_SAVED_SETS;
local TABS_MAX_WIDTH = 85;

local WARDROBE_MODEL_SETUP = {
	["HEADSLOT"] 		= { useTransmogSkin = false, useTransmogChoices = false, obeyHideInTransmogFlag = false, slots = { CHESTSLOT = true,  HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = false } },
	["SHOULDERSLOT"]	= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["BACKSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["CHESTSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["TABARDSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["SHIRTSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["WRISTSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["HANDSSLOT"]		= { useTransmogSkin = false, useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = true,  HANDSSLOT = false, LEGSSLOT = true,  FEETSLOT = true,  HEADSLOT = true  } },
	["WAISTSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["LEGSSLOT"]		= { useTransmogSkin = true,  useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = false, HANDSSLOT = false, LEGSSLOT = false, FEETSLOT = false, HEADSLOT = true  } },
	["FEETSLOT"]		= { useTransmogSkin = false, useTransmogChoices = true,  obeyHideInTransmogFlag = true,  slots = { CHESTSLOT = true,  HANDSSLOT = true,  LEGSSLOT = true,  FEETSLOT = false, HEADSLOT = true  } },
}

local function GetUseTransmogSkin(slot)
	local modelSetupTable = WARDROBE_MODEL_SETUP[slot]
	if not modelSetupTable or modelSetupTable.useTransmogSkin then
		return true;
	end

	-- this exludes head slot
	if modelSetupTable.useTransmogChoices then
		local transmogLocation = TransmogUtil.GetTransmogLocation(slot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
		if transmogLocation then
			if not C_PlayerInfo.HasVisibleInvSlot(transmogLocation.slotID) then
				return true;
			end
		end
	end

	return false;
end

local WARDROBE_MODEL_SETUP_GEAR = {
	["CHESTSLOT"] = 78420,
	["LEGSSLOT"] = 78425,
	["FEETSLOT"] = 78427,
	["HANDSSLOT"] = 78426,
	["HEADSLOT"] = 78416,
}

local SET_MODEL_PAN_AND_ZOOM_LIMITS = {
	["Draenei2"] = { maxZoom = 2.2105259895325, panMaxLeft = -0.56983226537705, panMaxRight = 0.82581323385239, panMaxTop = -0.17342753708363, panMaxBottom = -2.6428601741791 },
	["Draenei3"] = { maxZoom = 3.0592098236084, panMaxLeft = -0.33429977297783, panMaxRight = 0.29183092713356, panMaxTop = -0.079871296882629, panMaxBottom = -2.4141833782196 },
	["Worgen2"] = { maxZoom = 1.9605259895325, panMaxLeft = -0.64045578241348, panMaxRight = 0.59410041570663, panMaxTop = -0.11050206422806, panMaxBottom = -2.2492413520813 },
	["Worgen3"] = { maxZoom = 2.9013152122498, panMaxLeft = -0.2526838183403, panMaxRight = 0.38198262453079, panMaxTop = -0.10407017171383, panMaxBottom = -2.4137926101685 },
	["Worgen3Alt"] = { maxZoom = 3.3618412017822, panMaxLeft = -0.19753229618072, panMaxRight = 0.26802557706833, panMaxTop = -0.073476828634739, panMaxBottom = -1.9255120754242 },
	["Worgen2Alt"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.33268970251083, panMaxRight = 0.36896070837975, panMaxTop = -0.14780110120773, panMaxBottom = -2.1662468910217 },
	["Scourge2"] = { maxZoom = 3.1710526943207, panMaxLeft = -0.3243542611599, panMaxRight = 0.5625838637352, panMaxTop = -0.054175414144993, panMaxBottom = -1.7261047363281 },
	["Scourge3"] = { maxZoom = 2.7105259895325, panMaxLeft = -0.35650563240051, panMaxRight = 0.41562974452972, panMaxTop = -0.07072202116251, panMaxBottom = -1.877711892128 },
	["Orc2"] = { maxZoom = 2.5526309013367, panMaxLeft = -0.64236557483673, panMaxRight = 0.77098786830902, panMaxTop = -0.075792260468006, panMaxBottom = -2.0818419456482 },
	["Orc3"] = { maxZoom = 3.2960524559021, panMaxLeft = -0.22763830423355, panMaxRight = 0.32022559642792, panMaxTop = -0.038521766662598, panMaxBottom = -2.0473554134369 },
	["Gnome3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.29900181293488, panMaxRight = 0.35779395699501, panMaxTop = -0.076380833983421, panMaxBottom = -0.99909907579422 },
	["Gnome2"] = { maxZoom = 2.8552639484406, panMaxLeft = -0.2777853012085, panMaxRight = 0.29651582241058, panMaxTop = -0.095201380550861, panMaxBottom = -1.0263166427612 },
	["Dwarf2"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.50352156162262, panMaxRight = 0.4159924685955, panMaxTop = -0.07211934030056, panMaxBottom = -1.4946432113648 },
	["Dwarf3"] = { maxZoom = 2.8947370052338, panMaxLeft = -0.37057432532311, panMaxRight = 0.43383255600929, panMaxTop = -0.084960877895355, panMaxBottom = -1.7173190116882 },
	["BloodElf3"] = { maxZoom = 3.1644730567932, panMaxLeft = -0.2654082775116, panMaxRight = 0.28886350989342, panMaxTop = -0.049619361758232, panMaxBottom = -1.9943760633469 },
	["BloodElf2"] = { maxZoom = 3.1710524559021, panMaxLeft = -0.25901651382446, panMaxRight = 0.45525884628296, panMaxTop = -0.085230752825737, panMaxBottom = -2.0548067092895 },
	["Troll2"] = { maxZoom = 2.2697355747223, panMaxLeft = -0.58214980363846, panMaxRight = 0.5104039311409, panMaxTop = -0.05494449660182, panMaxBottom = -2.3443803787231 },
	["Troll3"] = { maxZoom = 3.1249995231628, panMaxLeft = -0.35141581296921, panMaxRight = 0.50875341892242, panMaxTop = -0.063820324838161, panMaxBottom = -2.4224486351013 },
	["Tauren2"] = { maxZoom = 2.1118416786194, panMaxLeft = -0.82946360111237, panMaxRight = 0.83975899219513, panMaxTop = -0.061676319688559, panMaxBottom = -2.035267829895 },
	["Tauren3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.37433895468712, panMaxRight = 0.40420442819595, panMaxTop = -0.1868137717247, panMaxBottom = -2.2116675376892 },
	["NightElf3"] = { maxZoom = 2.9539475440979, panMaxLeft = -0.27334463596344, panMaxRight = 0.27148312330246, panMaxTop = -0.094710879027844, panMaxBottom = -2.3087983131409 },
	["NightElf2"] = { maxZoom = 2.9144732952118, panMaxLeft = -0.45042458176613, panMaxRight = 0.47114592790604, panMaxTop = -0.10513981431723, panMaxBottom = -2.4612309932709 },
	["Human3"] = { maxZoom = 3.3618412017822, panMaxLeft = -0.19753229618072, panMaxRight = 0.26802557706833, panMaxTop = -0.073476828634739, panMaxBottom = -1.9255120754242 },
	["Human2"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.33268970251083, panMaxRight = 0.36896070837975, panMaxTop = -0.14780110120773, panMaxBottom = -2.1662468910217 },
	["Pandaren3"] = { maxZoom = 2.5921046733856, panMaxLeft = -0.45187762379646, panMaxRight = 0.54132586717606, panMaxTop = -0.11439494043589, panMaxBottom = -2.2257535457611 },
	["Pandaren2"] = { maxZoom = 2.9342107772827, panMaxLeft = -0.36421552300453, panMaxRight = 0.50203305482864, panMaxTop = -0.11241528391838, panMaxBottom = -2.3707413673401 },
	["Goblin2"] = { maxZoom = 2.4605259895325, panMaxLeft = -0.31328883767128, panMaxRight = 0.39014467597008, panMaxTop = -0.089733943343162, panMaxBottom = -1.3402827978134 },
	["Goblin3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.26144406199455, panMaxRight = 0.30945864319801, panMaxTop = -0.07625275105238, panMaxBottom = -1.2928194999695 },
	["LightforgedDraenei2"] = { maxZoom = 2.2105259895325, panMaxLeft = -0.56983226537705, panMaxRight = 0.82581323385239, panMaxTop = -0.17342753708363, panMaxBottom = -2.6428601741791 },
	["LightforgedDraenei3"] = { maxZoom = 3.0592098236084, panMaxLeft = -0.33429977297783, panMaxRight = 0.29183092713356, panMaxTop = -0.079871296882629, panMaxBottom = -2.4141833782196 },
	["HighmountainTauren2"] = { maxZoom = 2.1118416786194, panMaxLeft = -0.82946360111237, panMaxRight = 0.83975899219513, panMaxTop = -0.061676319688559, panMaxBottom = -2.035267829895 },
	["HighmountainTauren3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.37433895468712, panMaxRight = 0.40420442819595, panMaxTop = -0.1868137717247, panMaxBottom = -2.2116675376892 },
	["Nightborne3"] = { maxZoom = 2.9539475440979, panMaxLeft = -0.27334463596344, panMaxRight = 0.27148312330246, panMaxTop = -0.094710879027844, panMaxBottom = -2.3087983131409 },
	["Nightborne2"] = { maxZoom = 2.9144732952118, panMaxLeft = -0.45042458176613, panMaxRight = 0.47114592790604, panMaxTop = -0.10513981431723, panMaxBottom = -2.4612309932709 },
	["VoidElf3"] = { maxZoom = 3.1644730567932, panMaxLeft = -0.2654082775116, panMaxRight = 0.28886350989342, panMaxTop = -0.049619361758232, panMaxBottom = -1.9943760633469 },
	["VoidElf2"] = { maxZoom = 3.1710524559021, panMaxLeft = -0.25901651382446, panMaxRight = 0.45525884628296, panMaxTop = -0.085230752825737, panMaxBottom = -2.0548067092895 },
	["MagharOrc2"] = { maxZoom = 2.5526309013367, panMaxLeft = -0.64236557483673, panMaxRight = 0.77098786830902, panMaxTop = -0.075792260468006, panMaxBottom = -2.0818419456482 },
	["MagharOrc3"] = { maxZoom = 3.2960524559021, panMaxLeft = -0.22763830423355, panMaxRight = 0.32022559642792, panMaxTop = -0.038521766662598, panMaxBottom = -2.0473554134369 },
	["DarkIronDwarf2"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.50352156162262, panMaxRight = 0.4159924685955, panMaxTop = -0.07211934030056, panMaxBottom = -1.4946432113648 },
	["DarkIronDwarf3"] = { maxZoom = 2.8947370052338, panMaxLeft = -0.37057432532311, panMaxRight = 0.43383255600929, panMaxTop = -0.084960877895355, panMaxBottom = -1.7173190116882 },
	["KulTiran2"] = { maxZoom =  1.71052598953247, panMaxLeft = -0.667941331863403, panMaxRight = 0.589463412761688, panMaxTop = -0.373320609331131, panMaxBottom = -2.7329957485199 },
	["KulTiran3"] = { maxZoom =  2.22368383407593, panMaxLeft = -0.43183308839798, panMaxRight = 0.445900857448578, panMaxTop = -0.303212702274323, panMaxBottom = -2.49550628662109 },
	["ZandalariTroll2"] = { maxZoom =  2.1710512638092, panMaxLeft = -0.487841755151749, panMaxRight = 0.561356604099274, panMaxTop = -0.385127544403076, panMaxBottom = -2.78562784194946 },
	["ZandalariTroll3"] = { maxZoom =  3.32894563674927, panMaxLeft = -0.376705944538116, panMaxRight = 0.488780438899994, panMaxTop = -0.20890490710735, panMaxBottom = -2.67064166069031 },
	["Mechagnome3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.29900181293488, panMaxRight = 0.35779395699501, panMaxTop = -0.076380833983421, panMaxBottom = -0.99909907579422 },
	["Mechagnome2"] = { maxZoom = 2.8552639484406, panMaxLeft = -0.2777853012085, panMaxRight = 0.29651582241058, panMaxTop = -0.095201380550861, panMaxBottom = -1.0263166427612 },
	["Vulpera2"] = { maxZoom = 2.4605259895325, panMaxLeft = -0.31328883767128, panMaxRight = 0.39014467597008, panMaxTop = -0.089733943343162, panMaxBottom = -1.3402827978134 },
	["Vulpera3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.26144406199455, panMaxRight = 0.30945864319801, panMaxTop = -0.07625275105238, panMaxBottom = -1.2928194999695 },
	["Dracthyr2"] = { maxZoom = 2.1118416786194, panMaxLeft = -0.72946360111237, panMaxRight = 0.83975899219513, panMaxTop = -0.061676319688559, panMaxBottom = -2.035267829895 },
	["Dracthyr3"] = { maxZoom = 2.9605259895325, panMaxLeft = -0.37433895468712, panMaxRight = 0.40420442819595, panMaxTop = -0.1868137717247, panMaxBottom = -2.2116675376892 },
	["Dracthyr3Alt"] = { maxZoom = 3.3618412017822, panMaxLeft = -0.19753229618072, panMaxRight = 0.26802557706833, panMaxTop = -0.073476828634739, panMaxBottom = -1.9255120754242 },
	["Dracthyr2Alt"] = { maxZoom = 3.1710524559021, panMaxLeft = -0.25901651382446, panMaxRight = 0.45525884628296, panMaxTop = -0.085230752825737, panMaxBottom = -2.0548067092895 },
}

BetterWardrobeCollectionFrameMixin = { }

function BetterWardrobeCollectionFrameMixin:ReloadTab()
		self.ItemsCollectionFrame:Hide()
		self.SetsCollectionFrame:Hide()
		self.SetsTransmogFrame:Hide()
end

function BetterWardrobeCollectionFrameMixin:CheckTab(tab)
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()
	if (atTransmogrifier and BetterWardrobeCollectionFrame.selectedTransmogTab == tab) or BetterWardrobeCollectionFrame.selectedCollectionTab == tab then
		return true;
	end
end

function BetterWardrobeCollectionFrameMixin:SetContainer(parent)
	self:SetParent(parent)
	self:ClearAllPoints()
	if parent == CollectionsJournal then
		self:SetPoint("TOPLEFT", CollectionsJournal)
		self:SetPoint("BOTTOMRIGHT", CollectionsJournal)
		self.ItemsCollectionFrame.ModelR1C1:SetPoint("TOP", -238, -85)
		self.ItemsCollectionFrame.SlotsFrame:Show()
		self.ItemsCollectionFrame.BGCornerTopLeft:Hide()
		self.ItemsCollectionFrame.BGCornerTopRight:Hide()
		self.ItemsCollectionFrame.WeaponDropDown:SetPoint("TOPRIGHT", -6, -22)
		self.ItemsCollectionFrame.NoValidItemsLabel:Hide()
		self.FilterButton:SetText(FILTER)
		self.ItemsTab:SetPoint("TOPLEFT", 58, -28)
		self:SetTab(self.selectedCollectionTab)
	elseif parent == WardrobeFrame then
		self:SetPoint("TOPRIGHT", 0, 0)
		self:SetSize(662, 606)
		self.ItemsCollectionFrame.ModelR1C1:SetPoint("TOP", -235, -71)
		self.ItemsCollectionFrame.SlotsFrame:Hide()
		self.ItemsCollectionFrame.BGCornerTopLeft:Show()
		self.ItemsCollectionFrame.BGCornerTopRight:Show()
		self.ItemsCollectionFrame.WeaponDropDown:SetPoint("TOPRIGHT", -32, -25)
		self.FilterButton:SetText(SOURCES)
		self.ItemsTab:SetPoint("TOPLEFT", 8, -28)
		self:SetTab(self.selectedTransmogTab)
	end
	self:Show()
end

function BetterWardrobeCollectionFrameMixin:ClickTab(tab)
	self:SetTab(tab:GetID())
	PanelTemplates_ResizeTabsToFit(BetterWardrobeCollectionFrame, TABS_MAX_WIDTH)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local tempSorting
function BetterWardrobeCollectionFrameMixin:SetTab(tabID)
	PanelTemplates_SetTab(self, tabID)
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()
	if atTransmogrifier then
		self.selectedTransmogTab = tabID;
		self.selectedCollectionTab = 1;
	else
		self.selectedCollectionTab = tabID;
		self.selectedTransmogTab = 1;
	end

	local ElvUI = IsAddOnLoaded("ElvUI")

if BW_DBSavedSetDropdown then
	
	BW_DBSavedSetDropdown:Hide()
end
	self.BW_SetsHideSlotButton:Hide()
	BetterWardrobeVisualToggle.VisualMode = false;
	self.TransmogOptionsButton:Hide()
	----self.ItemsCollectionFrame:Hide()
	self.SetsCollectionFrame:Hide()
	self.SetsTransmogFrame:Hide()

	BetterWardrobeSetsCollectionVariantSetsButton:SetShown(tabID == TAB_SETS)
	addon.ColorFilterFrame:Hide()
	if tabID == TAB_ITEMS then
		BetterWardrobeVisualToggle:Hide()
		addon.ColorFilterFrame:Show()

		BW_ColectionListFrame:SetShown(BetterWardrobeCollectionFrame:IsShown() and not atTransmogrifier)
		self.activeFrame = self.ItemsCollectionFrame;
		self.ItemsCollectionFrame:Show()
		self.SetsCollectionFrame:Hide()
		self.SetsTransmogFrame:Hide()
		self.SearchBox:ClearAllPoints()
		self.SearchBox:SetPoint("TOPRIGHT", -107, -35)
		self.SearchBox:SetWidth(115)
		self.SearchBox:Show()

		local enableSearchAndFilter = self.ItemsCollectionFrame.transmogLocation and self.ItemsCollectionFrame.transmogLocation:IsAppearance()
		self.SearchBox:SetEnabled(enableSearchAndFilter)
		self.FilterButton:Show()
		self.FilterButton:SetEnabled(enableSearchAndFilter)

		BW_SortDropDown:Show()
		BW_SortDropDown:ClearAllPoints()

		local _, isWeapon = C_TransmogCollection.GetCategoryInfo((BetterWardrobeCollectionFrame and BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetActiveCategory()) or 1)
		local yOffset = (atTransmogrifier and (isWeapon and 55 or 32)) or LegionWardrobeY;
		if atTransmogrifier  then
			self.TransmogOptionsButton:Show()

			if ElvUI then 
				BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown:SetPoint("TOPRIGHT", -42, -10)
				BW_SortDropDown:SetPoint("TOPLEFT", BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown, "BOTTOMLEFT", 0, 0)
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",self:GetParent(), "TOPRIGHT", -17,-45)
			else 
				BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown:SetPoint("TOPRIGHT", -30, -7)
				BW_SortDropDown:SetPoint("TOPLEFT", BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown, "BOTTOMLEFT", 0, 0)
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",self:GetParent(), "TOPRIGHT", -12,-50)
			end

		else
			BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown:SetPoint("TOPRIGHT", -32, -25)
			if ElvUI then 
				BW_SortDropDown:SetPoint("TOPLEFT", BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown, "BOTTOMLEFT", -55, yOffset)
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",self:GetParent(), "TOPRIGHT", -13,-55)
			else 
				BW_SortDropDown:SetPoint("TOPLEFT", BetterWardrobeCollectionFrame.ItemsCollectionFrame.WeaponDropDown, "BOTTOMLEFT", 0, yOffset)
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",self:GetParent(), "TOPRIGHT", -19,-65)
			end
		end

	elseif tabID == TAB_SETS or tabID == TAB_EXTRASETS or tabID == TAB_SAVED_SETS then
		BetterWardrobeVisualToggle:Show()
		BW_ColectionListFrame:Hide()

		self.ItemsCollectionFrame:Hide()
		self.SearchBox:ClearAllPoints()
		BW_SortDropDown:Show()
		self.SearchBox:Show()
		BW_SortDropDown:ClearAllPoints()
		if ( atTransmogrifier )  then
			self.TransmogOptionsButton:Show()
			self.activeFrame = self.SetsTransmogFrame;

			if tabID == TAB_SAVED_SETS then 
				self.SearchBox:SetPoint("TOPRIGHT", -57, -75)
			else
				self.SearchBox:SetPoint("TOPRIGHT", -97, -35)
			end

			----self.SearchBox:SetWidth(115)
			self.FilterButton:Hide()
			BW_SortDropDown:SetPoint("TOPRIGHT", BetterWardrobeCollectionFrame.ItemsCollectionFrame, "TOPRIGHT",-30, -10)


			if ElvUI then 
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",BetterWardrobeCollectionFrame.SetsCollectionFrame.DetailsFrame, "TOPRIGHT", 0 ,-5)

			else 
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
				BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",BetterWardrobeCollectionFrame.SetsCollectionFrame.DetailsFrame, "TOPRIGHT", -5 ,10)

			end
		else
			self.activeFrame = self.SetsCollectionFrame;
			self.SearchBox:SetPoint("TOPLEFT", 19, -69)
			self.SearchBox:SetWidth(145)
			self.FilterButton:Show()
			self.FilterButton:SetEnabled(true)
			BW_SortDropDown:SetPoint("TOPLEFT", BetterWardrobeVisualToggle, "TOPRIGHT", 5, 0)
			self.BW_SetsHideSlotButton:Show()
			BetterWardrobeCollectionFrame.AlteredFormSwapButton:ClearAllPoints()
			BetterWardrobeCollectionFrame.AlteredFormSwapButton:SetPoint("TOPRIGHT",BetterWardrobeCollectionFrame.SetsCollectionFrame.DetailsFrame, "TOPRIGHT", 2, -15)

		end
		self.SearchBox:SetEnabled(true)
		self.SetsCollectionFrame:SetShown(not atTransmogrifier)
		self.SetsTransmogFrame:SetShown(atTransmogrifier)
		local sortValue
		if tabID == TAB_SAVED_SETS then 
			BW_DBSavedSetDropdown:Show()
			--BW_SortDropDown:SetPoint("TOPLEFT", BetterWardrobeVisualToggle, "TOPRIGHT", 5, 0)
			BW_SortDropDown:ClearAllPoints()
			BW_SortDropDown:SetPoint("TOPRIGHT", self.SearchBox, "TOPRIGHT", 21, 5)
			BW_SortDropDown:Show()
			self.FilterButton:Hide()
			self.SearchBox:Hide()

			--BW_SortDropDown:Hide()
			local savedCount = #addon.GetSavedList()
			--WardrobeCollectionFrame_UpdateProgressBar(savedCount, savedCount)

			--tempSorting = BW_SortDropDown.selectedValue
			--addon.setdb.profile.sorting = BW_SortDropDown.selectedValue

			sortValue = addon.setdb.profile.sorting


		else
			--db.sortDropdown = BW_SortDropDown.selectedValue;
			sortValue = db.sortDropdown
		end

		BW_UIDropDownMenu_SetSelectedValue(BW_SortDropDown, sortValue)
		BW_UIDropDownMenu_SetText(BW_SortDropDown, COMPACT_UNIT_FRAME_PROFILE_SORTBY.." "..L[sortValue])
	end
	--xx-WardrobeResetFiltersButton_UpdateVisibility();

	WardrobeFrame:TriggerEvent(BetterWardrobeFrameMixin.Event.OnCollectionTabChanged)
end

function BetterWardrobeCollectionFrameMixin:GetActiveTab()
	if C_Transmog.IsAtTransmogNPC() then
		return self.selectedTransmogTab;
	else
		return self.selectedCollectionTab;
	end
end

function BetterWardrobeCollectionFrameMixin:OnLoad()
	PanelTemplates_SetNumTabs(self, 4)
	PanelTemplates_SetTab(self, TAB_ITEMS)
	--PanelTemplates_ResizeTabsToFit(self, 50)
	PanelTemplates_TabResize(BetterWardrobeCollectionFrameTab1, 30)
	self.selectedCollectionTab = TAB_ITEMS;
	self.selectedTransmogTab = TAB_ITEMS;

	CollectionsJournal:SetPortraitToAsset("Interface\\Icons\\inv_misc_enggizmos_19")
	--self.CloseButton:SetScript("OnClick", function() ToggleCollectionsJournal() end)
	--self.CloseButton:Hide()
	-- TODO: Remove this at the next deprecation reset
	self.searchBox = self.SearchBox;

	--self.Inset:Hide()
end

local addedLink
function BetterWardrobeCollectionFrameMixin:OnEvent(event, ...)
	if ( event == "TRANSMOG_COLLECTION_ITEM_UPDATE" ) then
		if ( self.tooltipContentFrame ) then
			self.tooltipContentFrame:RefreshAppearanceTooltip()
		end
		if ( self.ItemsCollectionFrame:IsShown() ) then
			self.ItemsCollectionFrame:ValidateChosenVisualSources()
		end
	elseif ( event == "UNIT_FORM_CHANGED" ) then
		self:HandleFormChanged()
	elseif ( event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" or event == "UPDATE_FACTION" or event == "SPELLS_CHANGED" ) then
		self:UpdateUsableAppearances()
	elseif ( event == "TRANSMOG_SEARCH_UPDATED" ) then
		local searchType, arg1 = ...
		if ( searchType == self:GetSearchType() ) then
			self.activeFrame:OnSearchUpdate(arg1)
		end
	elseif ( event == "SEARCH_DB_LOADED" ) then
		self:RestartSearchTracking()
	elseif ( event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" or event == "TRANSMOG_COLLECTION_CAMERA_UPDATE" ) then
		self:RefreshCameras()

	elseif (event == "TRANSMOG_COLLECTION_SOURCE_ADDED") then
		addon.ClearSourceDB()
		addon.SetsDataProvider:ClearSets()
		if not addon.Profile.ShowCollectionUpdates then return end
		local sourceID = ...
		if not sourceID then return end
		local categoryID, visualID, canEnchant, icon, isCollected, itemLink, transmogLink, _ = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
		if not itemLink then return end
		local itemID, _, _, itemEquipLoc = GetItemInfoInstant(itemLink)

		--print(ExtractHyperlinkString(transmogLink))
		local setIDs = C_TransmogSets.GetSetsContainingSourceID(sourceID)
		local setItem = addon.IsSetItem(itemLink)
		addedLink = itemLink

		if setIDs and not setItem and addon.Profile.ShowSetCollectionUpdates then 
			for i, setID in pairs(setIDs) do 
				local setInfo = C_TransmogSets.GetSetInfo(setID)
				print((YELLOW_FONT_COLOR_CODE..L["Added missing appearances of: \124cffff7fff\124H%s:%s\124h[%s]\124h\124r"]):format("BW_transmogset", setID, setInfo.name))
				return;
			end
		end

		local isInList = addon.CollectionList:IsInList(visualID, "item")
		if addon.Profile.ShowCollectionListCollectionUpdates and isInList then  
			print((YELLOW_FONT_COLOR_CODE..L["Added appearance in Collection List"]))
		end

		if setItem and addon.Profile.ShowExtraSetsCollectionUpdates then 
			--local item = tonumber(itemLink:match("item:(%d+)"))
		
			newTransmogInfo = newTransmogInfo or {}
			addon.newTransmogInfo = newTransmogInfo
			for setID, setInfo in pairs(setItem) do 
			--local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				--local setInfo = C_TransmogSets.GetSetInfo(setID)
				--local setInfo = addon.GetSetInfo(setID)
				if setInfo then 
					newTransmogInfo["latestSource"] = setID;
					newTransmogInfo[setID] = newTransmogInfo[setID] or {}
					local inventoryTypes = C_Item.GetItemInventoryTypeByID(itemID)
		
					newTransmogInfo[setID][itemID] = inventoryTypes
					

					print((YELLOW_FONT_COLOR_CODE..L["Added missing appearances of: \124cffff7fff\124H%s:%s\124h[%s]\124h\124r"]):format("BW_transmogset-extra", setID, setInfo.name))
				end
				return;
			end
		end
		----SetsDataProvider:ClearSets()
		addon:SendMessage("BW_TRANSMOG_COLLECTION_UPDATED")

	elseif (event == "TRANSMOG_COLLECTION_SOURCE_REMOVED") then
		addon.ClearSourceDB()
		local sourceID = ...
		local categoryID, visualID, canEnchant, icon, isCollected, itemLink, transmogLink, _ = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
		local setItem = addon.IsSetItem(itemLink)
		if setItem then 
			--local item = tonumber(itemLink:match("item:(%d+)"))
			local itemID, _, _, itemEquipLoc = GetItemInfoInstant(itemLink)
			newTransmogInfo = newTransmogInfo or {}
			addon.newTransmogInfo = newTransmogInfo

			for setID, setInfo in pairs(setItem) do 
				addon.ClearSetNewSourcesForSlot(setID, inventoryTypes[itemEquipLoc])
				SetsDataProvider:ResetBaseSetNewStatus(setID)
				if 	newTransmogInfo["latestSource"] == setID then 
					self:ClearLatestSource()
				end
			end
		end
		----SetsDataProvider:ClearSets()
		addon:SendMessage("BW_TRANSMOG_COLLECTION_UPDATED")
	end
end

function BetterWardrobeCollectionFrameMixin:HandleFormChanged()
	local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo();
	self.needsFormChangedHandling = false;
	if ( self.inAlternateForm ~= inAlternateForm or self.updateOnModelChanged ) then
		if ( self.activeFrame:OnUnitModelChangedEvent() ) then
			self.inAlternateForm = inAlternateForm;
			self.updateOnModelChanged = nil;
		else
			self.needsFormChangedHandling = true;
		end
	end
end


function BetterWardrobeCollectionFrameMixin:OnUpdate()
	if self.needsFormChangedHandling then
		self:HandleFormChanged();
	end
end

local setCollected,setUncollected,setPvE,setPvP;
local function clearFilters()
	setCollected = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_COLLECTED)
	setUncollected = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_UNCOLLECTED)
	setPvE = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVE)
	setPvP =	C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVP)

	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_UNCOLLECTED, true)
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_COLLECTED, true)
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVE, true)
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVP, true)
	RefreshLists()

	--BetterWardrobeCollectionFrame:SetTab(1)
	--BetterWardrobeCollectionFrame:SetTab(2)
end

local function resetFilters()
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_UNCOLLECTED, setUncollected)
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_COLLECTED, setCollected)
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVE, setPvE)
	C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVP, setPvP)
	RefreshLists()
end

function BetterWardrobeCollectionFrameMixin:OnShow()
	playerClassName,playerClass, classID = UnitClass("player")
	CollectionsJournal:SetPortraitToAsset("Interface\\Icons\\inv_chest_cloth_17")
	local level = CollectionsJournal:GetFrameLevel()
	--BetterWardrobeCollectionFrame.NineSlice:Hide()

	--BetterWardrobeCollectionFrame:SetFrameLevel(level+10)
	--CollectionsJournal.NineSlice:SetFrameLevel(level-1)

	self:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:RegisterUnitEvent("UNIT_FORM_CHANGED", "player")
	self:RegisterEvent("TRANSMOG_SEARCH_UPDATED")
	self:RegisterEvent("SEARCH_DB_LOADED")
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:RegisterEvent("SKILL_LINES_CHANGED")
	self:RegisterEvent("UPDATE_FACTION")
	self:RegisterEvent("SPELLS_CHANGED")
	self:RegisterEvent("UI_SCALE_CHANGED")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED")
	self:RegisterEvent("TRANSMOG_COLLECTION_CAMERA_UPDATE")

	local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
	self.inAlternateForm = inAlternateForm;

	local selectedtab;
	local isAtTransmogNPC = C_Transmog.IsAtTransmogNPC();
	self.InfoButton:SetShown(false);
	if isAtTransmogNPC then
		self:SetTab(self.selectedTransmogTab);
	else
		self:SetTab(self.selectedCollectionTab);
	end
	self:UpdateTabButtons()

	--if (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_MODEL_CLICK) and WardrobeCollectionFrame.fromSuggestedContent) then
		--skip showing info tutorial if we came from suggested content and haven't seen the tracking tutorial
	--elseif (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_WARDROBE_TRACKING_INTERFACE)) then
		--HelpTip:Show(WardrobeCollectionFrame.InfoButton, WardrobeCollectionFrame.InfoButton.helpTipInfo);
		--BW_TrackingInterfaceShortcutsFrame.NewAlert:ValidateIsShown();
	--end
	addon.selectedArmorType = addon.Globals.CLASS_INFO[playerClass][3]
	addon.refreshData = true;
end

function BetterWardrobeCollectionFrameMixin:OnHide()
	self:UnregisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:UnregisterEvent("UNIT_FORM_CHANGED")
	self:UnregisterEvent("TRANSMOG_SEARCH_UPDATED")
	self:UnregisterEvent("SEARCH_DB_LOADED")
	self:UnregisterEvent("PLAYER_LEVEL_UP")
	self:UnregisterEvent("SKILL_LINES_CHANGED")
	self:UnregisterEvent("UPDATE_FACTION")
	self:UnregisterEvent("SPELLS_CHANGED")
	self:UnregisterEvent("UI_SCALE_CHANGED")
	self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
	self:UnregisterEvent("TRANSMOG_COLLECTION_CAMERA_UPDATE")
	C_TransmogCollection.EndSearch()
	self.jumpToVisualID = nil;
	for i, frame in ipairs(self.ContentFrames) do
		frame:Hide()
	end
	addon.sortDB.sortDropdown = 1;
	BW_UIDropDownMenu_SetSelectedValue(BW_SortDropDown, addon.sortDB.sortDropdown)
	BW_UIDropDownMenu_SetText(BW_SortDropDown, COMPACT_UNIT_FRAME_PROFILE_SORTBY.." "..L[addon.sortDB.sortDropdown])
	addon.selectedArmorType = addon.Globals.CLASS_INFO[playerClass][3]
	addon.useAltSet = false;
end

function BetterWardrobeCollectionFrameMixin:OnKeyDown(key)
	if  InCombatLockdown() then return end
	if self.tooltipCycle and key == WARDROBE_CYCLE_KEY then
		self:SetPropagateKeyboardInput(false)
		if IsShiftKeyDown() then
			self.tooltipSourceIndex = self.tooltipSourceIndex - 1;
		else
			self.tooltipSourceIndex = self.tooltipSourceIndex + 1;
		end
		self.tooltipContentFrame:RefreshAppearanceTooltip()
	elseif key == WARDROBE_PREV_VISUAL_KEY or key == WARDROBE_NEXT_VISUAL_KEY or key == WARDROBE_UP_VISUAL_KEY or key == WARDROBE_DOWN_VISUAL_KEY then
		if self.activeFrame:CanHandleKey(key) then
			self:SetPropagateKeyboardInput(false)
			self.activeFrame:HandleKey(key)
		else
			self:SetPropagateKeyboardInput(true)
		end
	else
		self:SetPropagateKeyboardInput(true)
	end
end

function BetterWardrobeCollectionFrameMixin:OpenTransmogLink(link)
	local linkType, id = strsplit(":", link)


	C_Timer.After(0, function() 

	if ( linkType == "transmogappearance" ) then
		local sourceID = tonumber(id)
		self:SetTab(TAB_ITEMS)
		-- For links a base appearance is fine
		local categoryID = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
		local slot = CollectionWardrobeUtil.GetSlotFromCategoryID(categoryID)
		local transmogLocation = TransmogUtil.GetTransmogLocation(slot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
		self.ItemsCollectionFrame:GoToSourceID(sourceID, transmogLocation)

	elseif ( linkType == "BW_transmogset" or linkType == "transmogset") then
		local setID = tonumber(id)
		self:SetTab(TAB_SETS)
		self.SetsCollectionFrame:SelectSet(setID)
		self.SetsCollectionFrame:ScrollToSet(self.SetsCollectionFrame:GetSelectedSetID(), ScrollBoxConstants.AlignCenter)


	elseif ( linkType == "BW_transmogset-extra") then
		local setID = tonumber(id)
		addon:RegisterMessage("BW_TRANSMOG_EXTRASETSHOWN", function(self) 
			addon:UnregisterMessage("BW_TRANSMOG_EXTRASETSHOWN")
			BetterWardrobeCollectionFrame.SetsCollectionFrame:DisplaySet(setID)
			BetterWardrobeCollectionFrame.SetsCollectionFrame:ScrollToSet(setID)
		end)

		local setInfo = addon.GetSetInfo(setID)
		local armorType = setInfo.armorType;
		if armorType ~= addon.selectedArmorType then 
			self:SetTab(TAB_EXTRASETS)
			addon.selectedArmorType = armorType;

		else 
			self:SetTab(TAB_ITEMS)
			self:SetTab(TAB_EXTRASETS)
		end
		self.SetsCollectionFrame:SelectSet(setID)


			--BetterWardrobeCollectionFrame:SetTab(TAB_EXTRASETS);
			--BetterWardrobeCollectionFrame.SetsCollectionFrame:SelectSet(setID);
			--BetterWardrobeCollectionFrame.SetsCollectionFrame:DisplaySet(setID)
			--BetterWardrobeCollectionFrame.SetsCollectionFrame:ScrollToSet(setID)
		
		
	end

	end)
end

function BetterWardrobeCollectionFrameMixin:GoToItem(sourceID)
	self:SetTab(TAB_ITEMS)
	local categoryID = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
	local slot = CollectionWardrobeUtil.GetSlotFromCategoryID(categoryID)
	local transmogLocation = TransmogUtil.GetTransmogLocation(slot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
	self.ItemsCollectionFrame:GoToSourceID(sourceID, transmogLocation)
end


function BetterWardrobeCollectionFrameMixin:GoToSet(setID)
	self:SetTab(TAB_SETS)
	self.SetsCollectionFrame:SelectSet(setID)
end

function BetterWardrobeCollectionFrameMixin:UpdateTabButtons()
	--Force Better Wardrobe frames higher than the default one
	self:SetFrameLevel(WardrobeCollectionFrame:GetFrameLevel()+200);

	-- sets tab
	self.SetsTab.FlashFrame:SetShown(C_TransmogSets.GetLatestSource() ~= Constants.Transmog.NoTransmogID and not C_Transmog.IsAtTransmogNPC())
	self.ExtraSetsTab.FlashFrame:SetShown(newTransmogInfo["latestSource"] and (newTransmogInfo["latestSource"] ~= Constants.Transmog.NoTransmogID) and not C_Transmog.IsAtTransmogNPC())
end

local function IsAnySourceCollected(sources)
	for i, source in ipairs(sources) do
		if source.isCollected then
			return true;
		end
	end

	return false;
end

function BetterWardrobeCollectionFrameMixin:SetAppearanceTooltip(contentFrame, sources, primarySourceID, warningString)
	self.tooltipContentFrame = contentFrame;
	local selectedIndex = self.tooltipSourceIndex;
	local showUseError = true;
	local inLegionArtifactCategory = TransmogUtil.IsCategoryLegionArtifact(self.ItemsCollectionFrame:GetActiveCategory())
	local subheaderString = nil;
	local showTrackingInfo = not IsAnySourceCollected(sources) and not C_Transmog.IsAtTransmogNPC();
	if BetterWardrobeCollectionFrame.activeFrame == BetterWardrobeCollectionFrame.SetsCollectionFrame then
		showTrackingInfo = false;
	end
	self.tooltipSourceIndex, self.tooltipCycle = CollectionWardrobeUtil.SetAppearanceTooltip(GameTooltip, sources, primarySourceID, selectedIndex, showUseError, inLegionArtifactCategory, subheaderString, warningString, showTrackingInfo);

	local index = 1
	if selectedIndex then
		index = selectedIndex - 1
	end 

	local itemID = sources[index] and sources[index].itemID
	local visualID = sources[index] and sources[index].visualID
	local sourceID = sources[index] and sources[index].sourceID
	
	if addon.Profile.ShowItemIDTooltips and itemID then
		GameTooltip_AddNormalLine(GameTooltip, "ItemID: " .. itemID);
		GameTooltip:Show()
	end

	if addon.Profile.ShowVisualIDTooltips and visualID then
		GameTooltip_AddNormalLine(GameTooltip, "VisualID: " .. visualID);
		GameTooltip:Show()
	end

	if addon.Profile.ShowVisualIDTooltips and sourceID then
		GameTooltip_AddNormalLine(GameTooltip, "SourceID: " .. sourceID);
		GameTooltip:Show()
	end

	if addon.Profile.ShowILevelTooltips and itemID then 
	local ilevel = select(4, GetItemInfo(itemID))
		if ilevel then 
			GameTooltip_AddNormalLine(GameTooltip, "ILevel: " .. ilevel);
			GameTooltip:Show()
		end
	end
end

function BetterWardrobeCollectionFrameMixin:HideAppearanceTooltip()
	self.tooltipContentFrame = nil;
	self.tooltipCycle = nil;
	self.tooltipSourceIndex = nil;
	GameTooltip:Hide()
end

function BetterWardrobeCollectionFrameMixin:UpdateUsableAppearances()
	if not self.updateUsableAppearances then
		self.updateUsableAppearances = true;
		C_Timer.After(0, function() self.updateUsableAppearances = nil; C_TransmogCollection.UpdateUsableAppearances(); end)  --Causes Taint
	end
end

function BetterWardrobeCollectionFrameMixin:RefreshCameras()
	for i, frame in ipairs(self.ContentFrames) do
		frame:RefreshCameras()
	end
end

function BetterWardrobeCollectionFrameMixin:GetAppearanceNameTextAndColor(appearanceInfo)
	local inLegionArtifactCategory = TransmogUtil.IsCategoryLegionArtifact(self.ItemsCollectionFrame:GetActiveCategory())
	return CollectionWardrobeUtil.GetAppearanceNameTextAndColor(appearanceInfo, inLegionArtifactCategory)
end

function BetterWardrobeCollectionFrameMixin:GetAppearanceSourceTextAndColor(appearanceInfo)
	return CollectionWardrobeUtil.GetAppearanceSourceTextAndColor(appearanceInfo)
end

function BetterWardrobeCollectionFrameMixin:GetAppearanceItemHyperlink(appearanceInfo)
	local link = select(6, C_TransmogCollection.GetAppearanceSourceInfo(appearanceInfo.sourceID))
	if self.selectedTransmogTab == TAB_ITEMS and self.ItemsCollectionFrame:GetActiveCategory() == Enum.TransmogCollectionType.Paired then
		local artifactName, artifactLink = C_TransmogCollection.GetArtifactAppearanceStrings(appearanceInfo.sourceID)
		if artifactLink then
			link = artifactLink;
		end
	end
	return link;
end

function BetterWardrobeCollectionFrameMixin:UpdateProgressBar(value, max)
	self.progressBar:SetMinMaxValues(0, max)
	self.progressBar:SetValue(value)
	self.progressBar.text:SetFormattedText(HEIRLOOMS_PROGRESS_FORMAT, value, max)
end

function BetterWardrobeCollectionFrameMixin:SwitchSearchCategory()
	if self.ItemsCollectionFrame.transmogLocation:IsIllusion() then
		self:ClearSearch()
		self.SearchBox:Disable()
		self.FilterButton:Disable()
		return;
	end

	self.SearchBox:Enable()
	self.FilterButton:Enable()
	if self.SearchBox:GetText() ~= "" then
		local finished = C_TransmogCollection.SetSearch(self:GetSearchType(), self.SearchBox:GetText())
		if not finished then
			self:RestartSearchTracking()
		end
	end
end

function BetterWardrobeCollectionFrameMixin:RestartSearchTracking()
	if self.activeFrame.transmogLocation and self.activeFrame.transmogLocation:IsIllusion() then
		return;
	end

	self.SearchBox.ProgressFrame:Hide()
	self.SearchBox.updateDelay = 0;
	if not C_TransmogCollection.IsSearchInProgress(self:GetSearchType()) then
		self.activeFrame:OnSearchUpdate()
	else
		self.SearchBox:StartCheckingProgress()
	end
end

function BetterWardrobeCollectionFrameMixin:SetSearch(text)
	if text == "" then
		C_TransmogCollection.ClearSearch(self:GetSearchType())
	else
		C_TransmogCollection.SetSearch(self:GetSearchType(), text)
	end
	self:RestartSearchTracking()
end

function BetterWardrobeCollectionFrameMixin:ClearSearch(searchType)
	self.SearchBox:SetText("")
	self.SearchBox.ProgressFrame:Hide()
	C_TransmogCollection.ClearSearch(searchType or self:GetSearchType())
end

function BetterWardrobeCollectionFrameMixin:GetSearchType()
	return self.activeFrame and self.activeFrame.searchType or 1;
end

function BetterWardrobeCollectionFrameMixin:ShowItemTrackingHelptipOnShow()
	if (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_MODEL_CLICK)) then
		self.fromSuggestedContent = true;
	end
end
		
BetterWardrobeItemsCollectionSlotButtonMixin = { }

function BetterWardrobeItemsCollectionSlotButtonMixin:OnClick()
	PlaySound(SOUNDKIT.UI_TRANSMOG_GEAR_SLOT_CLICK)
	BetterWardrobeCollectionFrame.ItemsCollectionFrame:SetActiveSlot(self.transmogLocation)
end

function BetterWardrobeItemsCollectionSlotButtonMixin:OnEnter()
	if self.transmogLocation:IsIllusion() then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(WEAPON_ENCHANTMENT);	
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local slotName = _G[self.slot]
		-- for shoulders check if equipped item has the secondary appearance toggled on
		if self.transmogLocation:GetSlotName() == "SHOULDERSLOT" then
			local itemLocation = TransmogUtil.GetItemLocationFromTransmogLocation(self.transmogLocation)
			if TransmogUtil.IsSecondaryTransmoggedForItemLocation(itemLocation) then
				if self.transmogLocation:IsSecondary() then
					slotName = LEFTSHOULDERSLOT;
				else
					slotName = RIGHTSHOULDERSLOT;
				end
			end
		end
		GameTooltip:SetText(slotName)
	end
end

BetterWardrobeItemsCollectionMixin = { }

local spacingNoSmallButton = 2;
local spacingWithSmallButton = 12;
local defaultSectionSpacing = 24;
local shorterSectionSpacing = 19;

function BetterWardrobeItemsCollectionMixin:CreateSlotButtons()
	local slots = { "head", "shoulder", "back", "chest", "shirt", "tabard", "wrist", defaultSectionSpacing, "hands", "waist", "legs", "feet", defaultSectionSpacing, "mainhand", spacingWithSmallButton, "secondaryhand" }
	local parentFrame = self.SlotsFrame;
	local lastButton;
	local xOffset = spacingNoSmallButton;
	for i = 1, #slots do
		local value = tonumber(slots[i])
		if ( value ) then
			-- this is a spacer
			xOffset = value;
		else
			local slotString = slots[i]
			local button = CreateFrame("BUTTON", nil, parentFrame, "BetterWardrobeSlotButtonTemplate")
			button.NormalTexture:SetAtlas("transmog-nav-slot-"..slotString, true)
			if ( lastButton ) then
				button:SetPoint("LEFT", lastButton, "RIGHT", xOffset, 0)
			else
				button:SetPoint("TOPLEFT")
			end
			button.slot = string.upper(slotString).."SLOT"
			xOffset = spacingNoSmallButton;
			lastButton = button;
			-- small buttons
			if ( slotString == "mainhand" or slotString == "secondaryhand" or slotString == "shoulder" ) then
				local smallButton = CreateFrame("BUTTON", nil, parentFrame, "BetterWardrobeSmallSlotButtonTemplate")
				smallButton:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 16, -15)
				smallButton.slot = button.slot;
				if ( slotString == "shoulder" ) then
					smallButton.transmogLocation = TransmogUtil.GetTransmogLocation(smallButton.slot, Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary)

					smallButton.NormalTexture:SetAtlas("transmog-nav-slot-shoulder", false)
					smallButton:Hide()
				else
					smallButton.transmogLocation = TransmogUtil.GetTransmogLocation(smallButton.slot, Enum.TransmogType.Illusion, Enum.TransmogModification.Main)
				end
			end

			button.transmogLocation = TransmogUtil.GetTransmogLocation(button.slot, button.transmogType, button.modification)
		end
	end
end

function BetterWardrobeItemsCollectionMixin:OnEvent(event, ...)
	--print(event)
	--print(...)
	if ( event == "TRANSMOGRIFY_UPDATE" or event == "TRANSMOGRIFY_SUCCESS" or event == "PLAYER_EQUIPMENT_CHANGED" ) then
		local slotID = ...
		if ( slotID and self.transmogLocation:IsAppearance() ) then
			if ( slotID == self.transmogLocation:GetSlotID() ) then
				self:UpdateItems()
			end
		else
			-- generic update
			self:UpdateItems()
		end
		if event == "PLAYER_EQUIPMENT_CHANGED" then
			if C_Transmog.CanHaveSecondaryAppearanceForSlotID(slotID) then
				self:UpdateSlotButtons()
			end
		end
	elseif ( event == "TRANSMOG_COLLECTION_UPDATED") then
		self:CheckLatestAppearance(true)
		self:ValidateChosenVisualSources()
		if ( self:IsVisible() ) then
			self:RefreshVisualsList()
			self:UpdateItems()
		end
		BetterWardrobeCollectionFrame:UpdateTabButtons()
	end
end

function BetterWardrobeItemsCollectionMixin:CheckLatestAppearance(changeTab)
	local latestAppearanceID, latestAppearanceCategoryID = C_TransmogCollection.GetLatestAppearance()
	if ( self.latestAppearanceID ~= latestAppearanceID ) then
		self.latestAppearanceID = latestAppearanceID;
		self.jumpToLatestAppearanceID = latestAppearanceID;
		self.jumpToLatestCategoryID = latestAppearanceCategoryID;

		--Don't call.  Causes taint and it will get get called by the default wadrobe api
		--if ( changeTab and not CollectionsJournal:IsShown() ) then
			--CollectionsJournal_SetTab(CollectionsJournal, 5)
		--end
	end
end

function BetterWardrobeItemsCollectionMixin:OnLoad()
	self:CreateSlotButtons()
	self.BGCornerTopLeft:Hide()
	self.BGCornerTopRight:Hide()
	self.HiddenModel:SetKeepModelOnHide(true)

	self.chosenVisualSources = { }

	self.NUM_ROWS = 3;
	self.NUM_COLS = 6;
	self.PAGE_SIZE = self.NUM_ROWS * self.NUM_COLS;

	BW_UIDropDownMenu_Initialize(self.RightClickDropDown, nil, "MENU")
	self.RightClickDropDown.initialize = BetterWardrobeCollectionFrameRightClickDropDown_Init;
	addon.Init:InitFilterButtons()

	self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")

	self:CheckLatestAppearance()
end

--Leave the help tips to the default game
function BetterWardrobeItemsCollectionMixin:CheckHelpTip()
	--[[
	if (C_Transmog.IsAtTransmogNPC()) then
		if (GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SETS_VENDOR_TAB)) then
			return;
		end

		if (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SPECS_BUTTON)) then
			return;
		end

		if (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_OUTFIT_DROPDOWN)) then
			return;
		end

		if (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_WARDROBE_TRACKING_INTERFACE)) then
			return;
		end

		local sets = C_TransmogSets.GetAllSets()
		local hasCollected = false;
		if (sets) then
			for i = 1, #sets do
				if (sets[i].collected) then
					hasCollected = true;
					break;
				end
			end
		end
		if (not hasCollected) then
			return;
		end

		local helpTipInfo = {
			text = TRANSMOG_SETS_VENDOR_TUTORIAL,
			buttonStyle = HelpTip.ButtonStyle.Close,
			cvarBitfield = "closedInfoFrames",
			bitfieldFlag = LE_FRAME_TUTORIAL_TRANSMOG_SETS_VENDOR_TAB,
			targetPoint = HelpTip.Point.BottomEdgeCenter,
		}
		HelpTip:Show(BetterWardrobeCollectionFrame, helpTipInfo, BetterWardrobeCollectionFrame.SetsTab)
	else
		if (GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SETS_TAB)) then
			return;
		end

		if (not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_WARDROBE_TRACKING_INTERFACE)) then
			return;
		end

		local helpTipInfo = {
			text = TRANSMOG_SETS_TAB_TUTORIAL,
			buttonStyle = HelpTip.ButtonStyle.Close,
			cvarBitfield = "closedInfoFrames",
			bitfieldFlag = LE_FRAME_TUTORIAL_TRANSMOG_SETS_TAB,
			targetPoint = HelpTip.Point.BottomEdgeCenter,
		}
		HelpTip:Show(BetterWardrobeCollectionFrame, helpTipInfo, BetterWardrobeCollectionFrame.SetsTab)
	end
	--]]
end


function BetterWardrobeItemsCollectionMixin:OnShow()
	self:RegisterEvent("TRANSMOGRIFY_UPDATE")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("TRANSMOGRIFY_SUCCESS")
	local needsUpdate = false;	-- we don't need to update if we call :SetActiveSlot as that will do an update
	if ( self.jumpToLatestCategoryID and self.jumpToLatestCategoryID ~= self.activeCategory and not C_Transmog.IsAtTransmogNPC() ) then
		local slot = CollectionWardrobeUtil.GetSlotFromCategoryID(self.jumpToLatestCategoryID)
		-- The model got reset from OnShow, which restored all equipment.
		-- But ChangeModelsSlot tries to be smart and only change the difference from the previous slot to the current slot, so some equipment will remain left on.
		-- This is only set for new apperances, base transmogLocation is fine
		local transmogLocation = TransmogUtil.GetTransmogLocation(slot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
		local ignorePreviousSlot = true;
		self:SetActiveSlot(transmogLocation, self.jumpToLatestCategoryID, ignorePreviousSlot)
		self.jumpToLatestCategoryID = nil;
	elseif ( self.transmogLocation ) then
		-- redo the model for the active slot
		self:ChangeModelsSlot(self.transmogLocation)
		needsUpdate = true;
	else
		local transmogLocation = C_Transmog.IsAtTransmogNPC() and WardrobeTransmogFrame:GetSelectedTransmogLocation() or TransmogUtil.GetTransmogLocation("HEADSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
		self:SetActiveSlot(transmogLocation)
	end

	BetterWardrobeCollectionFrame.progressBar:SetShown(not TransmogUtil.IsCategoryLegionArtifact(self:GetActiveCategory()))

	if ( needsUpdate ) then
		BetterWardrobeCollectionFrame:UpdateUsableAppearances()
		self:RefreshVisualsList()
		self:UpdateItems()
		self:UpdateWeaponDropDown()
	end

	self:UpdateSlotButtons()

	-- tab tutorial
	--self:CheckHelpTip()
end

function BetterWardrobeItemsCollectionMixin:OnHide()
	self:UnregisterEvent("TRANSMOGRIFY_UPDATE")
	self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:UnregisterEvent("TRANSMOGRIFY_SUCCESS")

	StaticPopup_Hide("TRANSMOG_FAVORITE_WARNING")

	self:GetParent():ClearSearch(Enum.TransmogSearchType.Items)

	for i = 1, #self.Models do
		self.Models[i]:SetKeepModelOnHide(false)
	end

	self.visualsList = nil;
	self.filteredVisualsList = nil;
	self.activeCategory = nil;
	self.transmogLocation = nil;
end

function BetterWardrobeItemsCollectionMixin:DressUpVisual(visualInfo)
	if self.transmogLocation:IsAppearance() then
		local sourceID = self:GetAnAppearanceSourceFromVisual(visualInfo.visualID, nil)
		DressUpCollectionAppearance(sourceID, self.transmogLocation, self:GetActiveCategory())
	elseif self.transmogLocation:IsIllusion() then
		local slot = self:GetActiveSlot()
		DressUpVisual(self.illusionWeaponAppearanceID, slot, visualInfo.sourceID)
	end
end

function BetterWardrobeItemsCollectionMixin:OnMouseWheel(delta)
	self.PagingFrame:OnMouseWheel(delta)

end

function BetterWardrobeItemsCollectionMixin:CanHandleKey(key)
	if ( C_Transmog.IsAtTransmogNPC() and (key == WARDROBE_PREV_VISUAL_KEY or key == WARDROBE_NEXT_VISUAL_KEY or key == WARDROBE_UP_VISUAL_KEY or key == WARDROBE_DOWN_VISUAL_KEY) ) then
		return true;
	end
	return false;
end

function BetterWardrobeItemsCollectionMixin:HandleKey(key)
	local _, _, _, selectedVisualID = self:GetActiveSlotInfo()
	local visualIndex;
	local visualsList = self:GetFilteredVisualsList()
	for i = 1, #visualsList do
		if ( visualsList[i].visualID == selectedVisualID ) then
			visualIndex = i;
			break;
		end
	end
	if ( visualIndex ) then
		visualIndex = GetAdjustedDisplayIndexFromKeyPress(self, visualIndex, #visualsList, key)
		self:SelectVisual(visualsList[visualIndex].visualID)
		self.jumpToVisualID = visualsList[visualIndex].visualID;
		self:ResetPage()
	end
end

function BetterWardrobeItemsCollectionMixin:ChangeModelsSlot(newTransmogLocation, oldTransmogLocation)
	BetterWardrobeCollectionFrame.updateOnModelChanged = nil;
	local oldSlot = oldTransmogLocation and oldTransmogLocation:GetSlotName()
	local newSlot = newTransmogLocation:GetSlotName()

	local undressSlot, reloadModel;
	local newSlotIsArmor = newTransmogLocation:GetArmorCategoryID()
	if ( newSlotIsArmor ) then
		local oldSlotIsArmor = oldTransmogLocation and oldTransmogLocation:GetArmorCategoryID()
		if ( oldSlotIsArmor ) then
			if ( (GetUseTransmogSkin(oldSlot) ~= GetUseTransmogSkin(newSlot)) or
				 (WARDROBE_MODEL_SETUP[oldSlot].useTransmogChoices ~= WARDROBE_MODEL_SETUP[newSlot].useTransmogChoices) or
				 (WARDROBE_MODEL_SETUP[oldSlot].obeyHideInTransmogFlag ~= WARDROBE_MODEL_SETUP[newSlot].obeyHideInTransmogFlag) ) then
				reloadModel = true;
			else
				undressSlot = true;
			end
		else
			reloadModel = true;
		end
	end

	if ( reloadModel and not IsUnitModelReadyForUI("player") ) then
		BetterWardrobeCollectionFrame.updateOnModelChanged = true;
		for i = 1, #self.Models do
			self.Models[i]:ClearModel()
		end
		return;
	end

	for i = 1, #self.Models do
		local model = self.Models[i]
		if ( undressSlot ) then
			local changedOldSlot = false;
			-- dress/undress setup gear
			for slot, equip in pairs(WARDROBE_MODEL_SETUP[newSlot].slots) do
				if ( equip ~= WARDROBE_MODEL_SETUP[oldSlot].slots[slot] ) then
					if ( equip ) then
						model:TryOn(WARDROBE_MODEL_SETUP_GEAR[slot])
					else
						model:UndressSlot(GetInventorySlotInfo(slot))
					end
					if ( slot == oldSlot ) then
						changedOldSlot = true;
					end
				end
			end
			-- undress old slot
			if ( not changedOldSlot ) then
				local slotID = GetInventorySlotInfo(oldSlot)
				model:UndressSlot(slotID)
			end
		elseif ( reloadModel ) then
			model:Reload(newSlot)
		end
		model.visualInfo = nil;
		end
	self.illusionWeaponAppearanceID = nil;

	self:EvaluateSlotAllowed();
end

-- For dracthyr/mechagnome
function BetterWardrobeItemsCollectionMixin:EvaluateSlotAllowed()
	local isArmor = self.transmogLocation:GetArmorCategoryID();
		-- Any model will do, using the 1st
	local model = self.Models[1];
	self.slotAllowed = not isArmor or model:IsSlotAllowed(self.transmogLocation:GetSlotID());	
	if not model:IsGeoReady() then
		self:MarkGeoDirty();
	end
end

function BetterWardrobeItemsCollectionMixin:MarkGeoDirty()
	self.geoDirty = true;
end

function BetterWardrobeItemsCollectionMixin:RefreshCameras()
	if ( self:IsShown() ) then
		for i, model in ipairs(self.Models) do
			model:RefreshCamera()
			if ( model.cameraID ) then
				addon.Model_ApplyUICamera(model, model.cameraID)
			end
		end
	end
end

function BetterWardrobeItemsCollectionMixin:OnUnitModelChangedEvent()
	if ( IsUnitModelReadyForUI("player") ) then
		self:ChangeModelsSlot(self.transmogLocation)
		self:UpdateItems()
		return true;
	else
		return false;
	end
end

function BetterWardrobeItemsCollectionMixin:GetActiveSlot()
	return self.transmogLocation and self.transmogLocation:GetSlotName()
end

function BetterWardrobeItemsCollectionMixin:GetActiveCategory()
	return self.activeCategory;
end

function BetterWardrobeItemsCollectionMixin:IsValidWeaponCategoryForSlot(categoryID)
	local name, isWeapon, canEnchant, canMainHand, canOffHand = C_TransmogCollection.GetCategoryInfo(categoryID)
	if ( name and isWeapon ) then
		if ( (self.transmogLocation:IsMainHand() and canMainHand) or (self.transmogLocation:IsOffHand() and canOffHand) ) then
			if ( C_Transmog.IsAtTransmogNPC() ) then
				local equippedItemID = GetInventoryItemID("player", self.transmogLocation:GetSlotID())
				return C_TransmogCollection.IsCategoryValidForItem(categoryID, equippedItemID)
			else
				return true;
			end
		end
	end
	return false;
end

function BetterWardrobeItemsCollectionMixin:SetActiveSlot(transmogLocation, category, ignorePreviousSlot)
	local previousTransmogLocation;
	if not ignorePreviousSlot then
		previousTransmogLocation = self.transmogLocation;
	end
	local slotChanged = not previousTransmogLocation or not previousTransmogLocation:IsEqual(transmogLocation)

	self.transmogLocation = transmogLocation;

	-- figure out a category
	if ( not category ) then
		if ( self.transmogLocation:IsIllusion() ) then
			category = nil;
		elseif ( self.transmogLocation:IsAppearance() ) then
			local useLastWeaponCategory = self.transmogLocation:IsEitherHand() and
											self.lastWeaponCategory and
											self:IsValidWeaponCategoryForSlot(self.lastWeaponCategory)
			if ( useLastWeaponCategory ) then
				category = self.lastWeaponCategory;
			else
				local appliedSourceID, appliedVisualID, selectedSourceID, selectedVisualID = self:GetActiveSlotInfo()
				if ( selectedSourceID ~= Constants.Transmog.NoTransmogID ) then
					category = C_TransmogCollection.GetAppearanceSourceInfo(selectedSourceID)
					if category and not self:IsValidWeaponCategoryForSlot(category) then
						category = nil;
					end
				end
			end
			if ( not category ) then
				if ( self.transmogLocation:IsEitherHand() ) then
					-- find the first valid weapon category
					for categoryID = FIRST_TRANSMOG_COLLECTION_WEAPON_TYPE, LAST_TRANSMOG_COLLECTION_WEAPON_TYPE do
						if ( self:IsValidWeaponCategoryForSlot(categoryID) ) then
							category = categoryID;
							break;
						end
					end
				else
					category = self.transmogLocation:GetArmorCategoryID()
				end
			end
		end
	end

	if ( slotChanged ) then
		self:ChangeModelsSlot(transmogLocation, previousTransmogLocation)
	end
	-- set only if category is different or slot is different
	if (( category ~= self.activeCategory and self.activeCategory ~= Enum.TransmogCollectionType.Paired) or slotChanged ) then
		CloseDropDownMenus()
		self:SetActiveCategory(category)
	end
end

function BetterWardrobeItemsCollectionMixin:SetTransmogrifierAppearancesShown(hasAnyValidSlots)
	self.NoValidItemsLabel:SetShown(not hasAnyValidSlots)
	C_TransmogCollection.SetCollectedShown(hasAnyValidSlots)
end

function BetterWardrobeItemsCollectionMixin:UpdateWeaponDropDown()
	local dropdown = self.WeaponDropDown;
	local name, isWeapon;
	if ( self.transmogLocation:IsAppearance() ) then
		name, isWeapon = C_TransmogCollection.GetCategoryInfo(self.activeCategory)
	end
	if ( not isWeapon ) then
		if ( C_Transmog.IsAtTransmogNPC() ) then
			dropdown:Hide()
		else
			dropdown:Show()
			BW_UIDropDownMenu_DisableDropDown(dropdown)
			BW_UIDropDownMenu_SetText(dropdown, "")
		end
	else
		dropdown:Show()
		BW_UIDropDownMenu_SetSelectedValue(dropdown, self.activeCategory)
		BW_UIDropDownMenu_SetText(dropdown, name)
		local validCategories = BetterWardrobeCollectionFrameWeaponDropDown_Init(dropdown)
		if ( validCategories > 1 ) then
			BW_UIDropDownMenu_EnableDropDown(dropdown)
		else
			BW_UIDropDownMenu_DisableDropDown(dropdown)
		end
	end
end

function BetterWardrobeItemsCollectionMixin:SetActiveCategory(category)
	local previousCategory = self.activeCategory;
	self.activeCategory = category;
	if previousCategory == Enum.TransmogCollectionType.Paired then 
		--self.activeCategory = previousCategory;
	end
	if previousCategory ~= category and self.transmogLocation:IsAppearance() then
		C_TransmogCollection.SetSearchAndFilterCategory(category)
		local name, isWeapon = C_TransmogCollection.GetCategoryInfo(category)
		if ( isWeapon ) then
			self.lastWeaponCategory = category;
		end
		self:RefreshVisualsList()
	else
		self:RefreshVisualsList()
		self:UpdateItems()
	end

	self:UpdateWeaponDropDown()

	self:GetParent().progressBar:SetShown(not TransmogUtil.IsCategoryLegionArtifact(category))

	local slotButtons = self.SlotsFrame.Buttons;
	for i = 1, #slotButtons do
		local button = slotButtons[i]
		button.SelectedTexture:SetShown(button.transmogLocation:IsEqual(self.transmogLocation))
	end

	local resetPage = false;
	local switchSearchCategory = false;

	if C_Transmog.IsAtTransmogNPC() then
		self.jumpToVisualID = select(4, self:GetActiveSlotInfo())
		resetPage = true;
	end

	if previousCategory ~= category then
		resetPage = true;
		switchSearchCategory = true;
	end
	
	if resetPage then
		self:ResetPage()
	end
	if switchSearchCategory then
		self:GetParent():SwitchSearchCategory()
	end
end



function BetterWardrobeItemsCollectionMixin:ResetPage()
	local page = 1;
	local selectedVisualID = NO_TRANSMOG_VISUAL_ID;
	if ( C_TransmogCollection.IsSearchInProgress(self:GetParent():GetSearchType()) ) then
		self.resetPageOnSearchUpdated = true;
	else
		if ( self.jumpToVisualID ) then
			selectedVisualID = self.jumpToVisualID;
			self.jumpToVisualID = nil;
		elseif ( self.jumpToLatestAppearanceID and not C_Transmog.IsAtTransmogNPC() ) then
			selectedVisualID = self.jumpToLatestAppearanceID;
			self.jumpToLatestAppearanceID = nil;
		end
	end

	if ( selectedVisualID and selectedVisualID ~= NO_TRANSMOG_VISUAL_ID ) then
		local visualsList = self:GetFilteredVisualsList()
		for i = 1, #visualsList do
			if ( visualsList[i].visualID == selectedVisualID ) then
				page = GetPage(i, self.PAGE_SIZE)
				break;
			end
		end
	end
	self.PagingFrame:SetCurrentPage(page)
	self:UpdateItems()
end


function BetterWardrobeItemsCollectionMixin:FilterVisuals()
	local isAtTransmogrifier = C_Transmog.IsAtTransmogNPC()
	local visualsList = self.visualsList;

	local filteredVisualsList = { }

	if self.recolors then
		local recolorList = {}
		for _, id in pairs(self.recolors) do recolorList[id] = true end
		
		local visualsList = self.visualsList;
		if self.transmogLocation:IsOffHand() then
			for _,categoryID in  pairs(Enum.TransmogCollectionType) do
				local mainhand =  select(4, C_TransmogCollection.GetCategoryInfo(categoryID))
				if mainhand then
					local appearances = C_TransmogCollection.GetCategoryAppearances(categoryID, 1)
					if appearances then
						for i = 1, #appearances do 
							visualsList[#visualsList + 1] = appearances[i]
						end
					end
				end
			end

		elseif self.transmogLocation:IsMainHand() then
			for _,categoryID in  pairs(Enum.TransmogCollectionType) do
				local offhand =  select(5, C_TransmogCollection.GetCategoryInfo(categoryID))
				if offhand then
					local appearances = C_TransmogCollection.GetCategoryAppearances(categoryID, 2)
					if appearances then
						for i = 1, #appearances do 
							visualsList[#visualsList + 1] = appearances[i]
						end
					end
				end
			end
		end

		for i = 1, #visualsList do
			local visualID = visualsList[i].visualID;
			if recolorList[visualID] then
				tinsert(filteredVisualsList, visualsList[i])
				recolorList[visualID] = nil;
			end
		end

		self.filteredVisualsList = filteredVisualsList;
		return;
	end

	local slotID = self.transmogLocation.slotID;
	for i, visualInfo in ipairs(visualsList) do
		local skip = false;
		if visualInfo.restrictedSlotID then
			skip = (slotID ~= visualInfo.restrictedSlotID)
		end
		if not skip then
			if isAtTransmogrifier then
				if (visualInfo.isUsable and visualInfo.isCollected) or visualInfo.alwaysShowItem then
					table.insert(filteredVisualsList, visualInfo)
				end
			else
				if not visualInfo.isHideVisual then
					table.insert(filteredVisualsList, visualInfo)
				end
			end
		end
	end

	filteredVisualsList = addon.Sets:ClearHidden(filteredVisualsList, "item")--self.visualsList;

	self.filteredVisualsList = filteredVisualsList;
end

function BetterWardrobeItemsCollectionMixin:SortVisuals()
		if BetterWardrobeCollectionFrame.selectedCollectionTab == 1 then 

		if self:GetActiveCategory() and self:GetActiveCategory() ~= Enum.TransmogCollectionType.Paired then
			addon.SortItems(addon.sortDB.sortDropdown,self)
		elseif self:GetActiveCategory() and self:GetActiveCategory() == Enum.TransmogCollectionType.Paired then
			addon.SortItems(1, self)

		else
			addon.SortItems(1, self)
		end
	end
	--[[local comparison = function(source1, source2)
				if ( source1.isCollected ~= source2.isCollected ) then
					return source1.isCollected;
				end
				if ( source1.isUsable ~= source2.isUsable ) then
					return source1.isUsable;
				end
				if ( source1.isFavorite ~= source2.isFavorite ) then
					return source1.isFavorite;
				end
				if ( source1.isHideVisual ~= source2.isHideVisual ) then
					return source1.isHideVisual;
				end
				if ( source1.hasActiveRequiredHoliday ~= source2.hasActiveRequiredHoliday ) then
					return source1.hasActiveRequiredHoliday;
				end
				if ( source1.uiOrder and source2.uiOrder ) then
					return source1.uiOrder > source2.uiOrder;
				end
				return source1.sourceID > source2.sourceID;
			end
		
			table.sort(self.filteredVisualsList, comparison);]]
end

function BetterWardrobeItemsCollectionMixin:GetActiveSlotInfo()
	return TransmogUtil.GetInfoForEquippedSlot(self.transmogLocation)
end

function BetterWardrobeItemsCollectionMixin:GetWeaponInfoForEnchant()
	if ( not C_Transmog.IsAtTransmogNPC() and DressUpFrame:IsShown() ) then
		local playerActor = DressUpFrame.ModelScene:GetPlayerActor()
		if playerActor then
			local itemTransmogInfo = playerActor:GetItemTransmogInfo(self.transmogLocation:GetSlotID())
			local appearanceID = itemTransmogInfo and itemTransmogInfo.appearanceID or Constants.Transmog.NoTransmogID;
			if ( self:CanEnchantSource(appearanceID) ) then
				local _, appearanceVisualID, _,_,_,_,_,_, appearanceSubclass = C_TransmogCollection.GetAppearanceSourceInfo(appearanceID)
				return appearanceID, appearanceVisualID, appearanceSubclass;
			end
		end
	end

	local correspondingTransmogLocation = TransmogUtil.GetCorrespondingHandTransmogLocation(self.transmogLocation)
	local appliedSourceID, appliedVisualID, selectedSourceID, selectedVisualID, itemSubclass = TransmogUtil.GetInfoForEquippedSlot(correspondingTransmogLocation)
	if ( self:CanEnchantSource(selectedSourceID) ) then
		return selectedSourceID, selectedVisualID, itemSubclass;
	else
		local appearanceSourceID = C_TransmogCollection.GetFallbackWeaponAppearance()
		local _, appearanceVisualID, _,_,_,_,_,_, appearanceSubclass= C_TransmogCollection.GetAppearanceSourceInfo(appearanceSourceID)
		return appearanceSourceID, appearanceVisualID, appearanceSubclass;
	end
end

function BetterWardrobeItemsCollectionMixin:CanEnchantSource(sourceID)
	local _, visualID, canEnchant,_,_,_,_,_, appearanceSubclass  = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
	if ( canEnchant ) then
		self.HiddenModel:SetItemAppearance(visualID, 0, appearanceSubclass)
		return self.HiddenModel:HasAttachmentPoints()
	end
	return false;
end

function BetterWardrobeItemsCollectionMixin:GetCameraVariation()
	local checkSecondary = false;
	if self.transmogLocation:GetSlotName() == "SHOULDERSLOT" then
		if C_Transmog.IsAtTransmogNPC() then
			checkSecondary = WardrobeTransmogFrame:HasActiveSecondaryAppearance()
		else
			local itemLocation = TransmogUtil.GetItemLocationFromTransmogLocation(self.transmogLocation)
			checkSecondary = TransmogUtil.IsSecondaryTransmoggedForItemLocation(itemLocation)
		end
	end
	if checkSecondary then
		if self.transmogLocation:IsSecondary() then
			return 0;
		else
			return 1;
		end
	end
	return nil;
end

function BetterWardrobeItemsCollectionMixin:OnUpdate()
	if self.geoDirty then
		local model = self.Models[1];
		if model:IsGeoReady() then
			self.geoDirty = nil;

			self:EvaluateSlotAllowed();
			self:UpdateItems();
		end
	end

	if (self.trackingModifierDown and not ContentTrackingUtil.IsTrackingModifierDown()) or (not self.trackingModifierDown and ContentTrackingUtil.IsTrackingModifierDown()) then
		for i, model in ipairs(self.Models) do
			model:UpdateTrackingDisabledOverlay();
		end

		self:RefreshAppearanceTooltip();
	end
	self.trackingModifierDown = ContentTrackingUtil.IsTrackingModifierDown();
end

function BetterWardrobeItemsCollectionMixin:UpdateItems()
	if not BetterWardrobeCollectionFrame.ItemsCollectionFrame:IsShown() then return end
	local isArmor
	local cameraID;
	local appearanceVisualID;	-- for weapon when looking at enchants
	local appearanceVisualSubclass;
	local changeModel = false;
	local isAtTransmogrifier = C_Transmog.IsAtTransmogNPC()

	if ( self.transmogLocation and self.transmogLocation:IsIllusion() ) then
		-- for enchants we need to get the visual of the item in that slot
		local appearanceSourceID;
		appearanceSourceID, appearanceVisualID, appearanceVisualSubclass = self:GetWeaponInfoForEnchant()
		cameraID = C_TransmogCollection.GetAppearanceCameraIDBySource(appearanceSourceID)
		if ( appearanceSourceID ~= self.illusionWeaponAppearanceID ) then
			self.illusionWeaponAppearanceID = appearanceSourceID;
			changeModel = true;
		end
	else
		local _, isWeapon = C_TransmogCollection.GetCategoryInfo(self.activeCategory)
		isArmor = not isWeapon and not addon:IsWeaponCat()
	end

	local tutorialAnchorFrame;
	local checkTutorialFrame = self.transmogLocation:IsAppearance() and not C_Transmog.IsAtTransmogNPC()
								and not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_MODEL_CLICK) and BetterWardrobeCollectionFrame.fromSuggestedContent;

	local baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo
	local effectiveCategory;
	local showUndoIcon;
	if ( isAtTransmogrifier ) then
		if self.transmogLocation:IsMainHand() then
			effectiveCategory = C_Transmog.GetSlotEffectiveCategory(self.transmogLocation)
		end
		baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo = C_Transmog.GetSlotVisualInfo(self.transmogLocation)
		if ( appliedVisualID ~= NO_TRANSMOG_VISUAL_ID ) then
			if ( hasPendingUndo ) then
				pendingVisualID = baseVisualID;
				showUndoIcon = true;
			end
			-- current border (yellow) should only show on untransmogrified items
			baseVisualID = nil;
		end
		-- hide current border (yellow) or current-transmogged border (purple) if there's something pending
		if ( pendingVisualID ~= NO_TRANSMOG_VISUAL_ID ) then
			baseVisualID = nil;
			appliedVisualID = nil;
		end
	end
	local matchesCategory = not effectiveCategory or effectiveCategory == self.activeCategory or self.transmogLocation:IsIllusion() or self.activeCategory == Enum.TransmogCollectionType.Paired;
	--local matchesCategory = not effectiveCategory or effectiveCategory == self.activeCategory or self.transmogLocation:IsIllusion();

	local cameraVariation = self:GetCameraVariation()

	-- for disabled slots (dracthyr)
	local isHeadSlot = self.transmogLocation:GetArmorCategoryID() == Enum.TransmogCollectionType.Head;

	local pendingTransmogModelFrame = nil;
	local indexOffset = (self.PagingFrame:GetCurrentPage() - 1) * self.PAGE_SIZE;
	for i = 1, self.PAGE_SIZE do
		local model = self.Models[i]
		local index = i + indexOffset;
		local visualInfo = self.filteredVisualsList[index]
		if ( visualInfo ) then
			model:Show()

			local isWeapon;
			if self.activeCategory and self.activeCategory > 11 then 
				isWeapon = true;
			end

			-- camera
			if ( self.transmogLocation:IsAppearance() ) then
				if visualInfo.artifact then
					cameraID = visualInfo.camera;
				else
					local inNativeForm = C_UnitAuras.WantsAlteredForm("player");

					if  (inNativeForm and addon.useNativeForm) or (not inNativeForm and not addon.useNativeForm)  or isWeapon then 
						cameraID = C_TransmogCollection.GetAppearanceCameraID(visualInfo.visualID, cameraVariation)
					else
						cameraID = addon.Camera:GetCameraIDBySlot(self.activeCategory)
					end
				end
			end

			if ( model.cameraID ~= cameraID ) then
				addon.Model_ApplyUICamera(model, cameraID)
				model.cameraID = cameraID;
			end
			model.zoom = nil;

			--Dont really care about useable status for colelction list;
			if BW_CollectionListButton.ToggleState then 
				visualInfo.isUsable = true;
			end


			if ( visualInfo ~= model.visualInfo or changeModel ) then
				if ( isArmor and not isWeapon) then
					local sourceID = self:GetAnAppearanceSourceFromVisual(visualInfo.visualID, nil)
					model:TryOn(sourceID)
					model:Show()

				elseif(visualInfo.shapeshiftID) then 
					model.cameraID = visualInfo.camera;
					addon.Model_ApplyUICamera(model, visualInfo.camera)
					model:SetDisplayInfo( visualInfo.shapeshiftID )
					model:MakeCurrentCameraCustom()
					
					if model.cameraID == 1602 then 
						model.zoom =-.75;
						model:SetCameraDistance(-5)
						model:SetPosition(-13.25,0,-2.447)
					end 

					model:Show()
				elseif ( appearanceVisualID ) then
					-- appearanceVisualID is only set when looking at enchants
					model:SetItemAppearance(appearanceVisualID, visualInfo.visualID, appearanceVisualSubclass)
				else
					model:SetItemAppearance(visualInfo.visualID)
					if isWeapon then 
						model.needsReset = true;
					end
				end
			end
			model.visualInfo = visualInfo;
			model:UpdateContentTracking();
			model:UpdateTrackingDisabledOverlay();

			-- state at the transmogrifier
			local transmogStateAtlas;
			if ( visualInfo.visualID == appliedVisualID and matchesCategory) then
				transmogStateAtlas = "transmog-wardrobe-border-current-transmogged"
			elseif ( visualInfo.visualID == baseVisualID ) then
				transmogStateAtlas = "transmog-wardrobe-border-current"
			elseif ( visualInfo.visualID == pendingVisualID and matchesCategory) then
				transmogStateAtlas = "transmog-wardrobe-border-selected"
				pendingTransmogModelFrame = model;
			end
			if ( transmogStateAtlas ) then
				model.TransmogStateTexture:SetAtlas(transmogStateAtlas, true)
				model.TransmogStateTexture:Show()
			else
				model.TransmogStateTexture:Hide()
			end

			-- border
			if ( not visualInfo.isCollected ) then
				model.Border:SetAtlas("transmog-wardrobe-border-uncollected")
			elseif ( not visualInfo.isUsable ) then
				model.Border:SetAtlas("transmog-wardrobe-border-unusable")
			else
				model.Border:SetAtlas("transmog-wardrobe-border-collected")
			end

			if ( C_TransmogCollection.IsNewAppearance(visualInfo.visualID) ) then
				model.NewString:Show()
				model.NewGlow:Show()
			else
				model.NewString:Hide()
				model.NewGlow:Hide()
			end
			-- favorite
			local isFavorite = visualInfo.isFavorite or addon:IsFavoriteItem(visualInfo.visualID)
			model.Favorite.Icon:SetShown(isFavorite)
			-- hide visual option
			model.HideVisual.Icon:SetShown(isAtTransmogrifier and visualInfo.isHideVisual)
			-- slots not allowed
			model.SlotInvalidTexture:SetShown(not self.slotAllowed);			
			model:SetDesaturated(isHeadSlot and not self.slotAllowed);


		local setID = (model.visualInfo and model.visualInfo.visualID) or model.setID;
		local isHidden = addon.HiddenAppearanceDB.profile.item[setID]
		model.CollectionListVisual.Hidden.Icon:SetShown(isHidden)
		local isInList = addon.CollectionList:IsInList(setID, "item")
		model.CollectionListVisual.Collection.Collection_Icon:SetShown(isInList)
		model.CollectionListVisual.Collection.Collected_Icon:SetShown(isInList and model.visualInfo and model.visualInfo.isCollected)

			if ( GameTooltip:GetOwner() == model ) then
				model:OnEnter()
			end

			-- find potential tutorial anchor for trackable item
			if ( checkTutorialFrame ) then
				if ( not BetterWardrobeCollectionFrame.tutorialVisualID and not visualInfo.isCollected and not visualInfo.isHideVisual and model:HasTrackableSource()) then

					tutorialAnchorFrame = model;
				elseif ( BetterWardrobeCollectionFrame.tutorialVisualID and BetterWardrobeCollectionFrame.tutorialVisualID == visualInfo.visualID ) then
					tutorialAnchorFrame = model;
				end
			end
		else
			model:Hide()
			model.visualInfo = nil;
		end
	end
	if ( pendingTransmogModelFrame ) then
		self.PendingTransmogFrame:SetParent(pendingTransmogModelFrame)
		self.PendingTransmogFrame:SetPoint("CENTER")
		self.PendingTransmogFrame:Show()
		if ( self.PendingTransmogFrame.visualID ~= pendingVisualID ) then
			self.PendingTransmogFrame.TransmogSelectedAnim:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim2:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim2:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim3:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim3:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim4:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim4:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim5:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim5:Play()
		end
		self.PendingTransmogFrame.UndoIcon:SetShown(showUndoIcon)
		self.PendingTransmogFrame.visualID = pendingVisualID;
	else
		self.PendingTransmogFrame:Hide()
	end
	-- progress bar
	self:UpdateProgressBar()
	-- tutorial
--[[if ( checkTutorialFrame ) then
		if ( tutorialAnchorFrame ) then
			if ( not WardrobeCollectionFrame.tutorialVisualID ) then
				WardrobeCollectionFrame.tutorialVisualID = tutorialAnchorFrame.visualInfo.visualID;
			end
			if ( WardrobeCollectionFrame.tutorialVisualID ~= tutorialAnchorFrame.visualInfo.visualID ) then
				tutorialAnchorFrame = nil;
			end
		end
	end
	if ( tutorialAnchorFrame ) then
		local helpTipInfo = {

			text = WARDROBE_TRACKING_TUTORIAL,
			buttonStyle = HelpTip.ButtonStyle.Close,
			cvarBitfield = "closedInfoFrames",
			bitfieldFlag = LE_FRAME_TUTORIAL_TRANSMOG_MODEL_CLICK,
			targetPoint = HelpTip.Point.RightEdgeCenter,
			onAcknowledgeCallback = function() WardrobeCollectionFrame.fromSuggestedContent = nil;
											   WardrobeCollectionFrame.ItemsCollectionFrame:CheckHelpTip(); end,
			acknowledgeOnHide = true,
		};
		HelpTip:Show(self, helpTipInfo, tutorialAnchorFrame);
	else

		HelpTip:Hide(self, WARDROBE_TRACKING_TUTORIAL);
	end
]]
		if 	#addon.GetBaseList() == 0 then 
		addon.Init:BuildDB()
	end
end

function BetterWardrobeItemsCollectionMixin:UpdateProgressBar()
	local collected, total;
	if ( self.transmogLocation:IsIllusion() ) then
		total = #self.visualsList;
		collected = 0;
		for i, illusion in ipairs(self.visualsList) do
			if ( illusion.isCollected ) then
				collected = collected + 1;
			end
		end
	else
		collected = C_TransmogCollection.GetCategoryCollectedCount(self.activeCategory)
		total = C_TransmogCollection.GetCategoryTotal(self.activeCategory)
	end
	self:GetParent():UpdateProgressBar(collected, total)
end

local offspecartifact = {}
function BetterWardrobeItemsCollectionMixin:RefreshVisualsList()
	if not self.transmogLocation then return end
	if self.transmogLocation:IsIllusion() then
		self.visualsList = C_TransmogCollection.GetIllusions()

	else
		if self:GetActiveCategory() == Enum.TransmogCollectionType.Paired and not C_Transmog.IsAtTransmogNPC() then 
			self.visualsList = addon.GetClassArtifactAppearanceList() 
		elseif self:GetActiveCategory() == Enum.TransmogCollectionType.Paired and C_Transmog.IsAtTransmogNPC() then 
			self.visualsList = C_TransmogCollection.GetCategoryAppearances(Enum.TransmogCollectionType.Paired, self.transmogLocation)
			offspecartifact = {}

			for i, data in ipairs(self.visualsList)do

				local sourceID = BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetAnAppearanceSourceFromVisual(data.visualID)
				local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				local invType = sourceInfo.invType;

				local transmogLocation = WardrobeTransmogFrame:GetSelectedTransmogLocation()
				local baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo, _, itemSubclass = C_Transmog.GetSlotVisualInfo(transmogLocation)
				--local appliedSourceID, _, selectedSourceID = TransmogUtil.GetInfoForEquippedSlot(transmogLocation)
				local selecteSourceInfo =  C_TransmogCollection.GetSourceInfo(baseSourceID)
				local selectedInvType = selecteSourceInfo.invType;

				if invType == selectedInvType then
					if not data.isUsable then 
						data.isUsable = true;
						offspecartifact[data.visualID] = true;
					else
						offspecartifact[data.visualID] = false;
					end
				end 
			end
		else
			self.visualsList = C_TransmogCollection.GetCategoryAppearances(self.activeCategory, self.transmogLocation)
		end

	end
	--Mod to allow visual view of sets from the journal;
	if BW_CollectionListButton.ToggleState then self.visualsList = addon.CollectionList:BuildCollectionList() end

	self:FilterVisuals()
	self:SortVisuals()
	self.PagingFrame:SetMaxPages(ceil(#self.filteredVisualsList / self.PAGE_SIZE))
end

function BetterWardrobeItemsCollectionMixin:GetFilteredVisualsList()
	return self.filteredVisualsList;
end

function BetterWardrobeItemsCollectionMixin:GetAnAppearanceSourceFromVisual(visualID, mustBeUsable)
	local sourceID = self:GetChosenVisualSource(visualID)
	if ( sourceID == Constants.Transmog.NoTransmogID ) then
		local isArtifact = addon.GetArtifactSourceInfo(visualID)
		if isArtifact then return isArtifact.sourceID end
		local sources = CollectionWardrobeUtil.GetSortedAppearanceSources(visualID, self.activeCategory, self.transmogLocation)
		for i = 1, #sources do
			-- first 1 if it doesn't have to be usable
			if ( not mustBeUsable or self:IsAppearanceUsableForActiveCategory(sources[i]) ) then
				sourceID = sources[i].sourceID;
				break;
			end
		end
	end
	return sourceID;
end

function BetterWardrobeItemsCollectionMixin:SelectVisual(visualID)
	if not C_Transmog.IsAtTransmogNPC() then
		return;
	end

	local sourceID;
	if ( self.transmogLocation:IsAppearance() ) then
		--Fix for shoulder and wrist hidden item appearance;
		if visualID == 24531 or visualID == 40284 then
			local modType = Enum.TransmogModification.Main;
			local itemLocation = TransmogUtil.GetItemLocationFromTransmogLocation(self.transmogLocation)
			local secondarySelected = self.transmogLocation:IsSecondary()
			if secondarySelected then 
				modType = Enum.TransmogModification.Secondary;
			end

			local slotID = TransmogUtil.GetSlotID(self:GetActiveSlot())
			local emptySlotData = Sets:GetEmptySlots() 
			local _, source = addon.GetItemSource(emptySlotData[slotID]) --C_TransmogCollection.GetItemInfo(emptySlotData[i])
			local transmogLocation = TransmogUtil.GetTransmogLocation(slotID, Enum.TransmogType.Appearance, modType)
			pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, source)
			C_Transmog.SetPending(transmogLocation, pendingInfo)

			return 
		end

		sourceID = self:GetAnAppearanceSourceFromVisual(visualID, true)
	else
		local visualsList = self:GetFilteredVisualsList()
		for i = 1, #visualsList do
			if ( visualsList[i].visualID == visualID ) then
				sourceID = visualsList[i].sourceID;
				break;
			end
		end
	end

	local transmogLocation = WardrobeTransmogFrame:GetSelectedTransmogLocation()
	local activeCategory = self.activeCategory;
	local offhandTransmogLocation = TransmogUtil.GetTransmogLocation(INVSLOT_OFFHAND, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
	--Clears offhand if artifact was a paired set;
	if C_Transmog.GetSlotEffectiveCategory(offhandTransmogLocation) == Enum.TransmogCollectionType.None then
		local actor = WardrobeTransmogFrame.ModelScene:GetPlayerActor()
		actor:UndressSlot(INVSLOT_OFFHAND)
	end

	if self.activeCategory == Enum.TransmogCollectionType.Paired then
		if offspecartifact[visualID] then
			C_Transmog.ClearPending(transmogLocation)
			local baseSourceID, baseVisualID, appliedSourceID, appliedVisualID, pendingSourceID, pendingVisualID, hasPendingUndo, _, itemSubclass = C_Transmog.GetSlotVisualInfo(transmogLocation)
			if appliedVisualID == visualID then 
				self.activeCategory = Enum.TransmogCollectionType.Paired;
			else
				local appliedSourceID, _, selectedSourceID = TransmogUtil.GetInfoForEquippedSlot(transmogLocation)
				local selecteSourceInfo =  C_TransmogCollection.GetSourceInfo(baseSourceID)
				self.activeCategory = selecteSourceInfo.categoryID 
			end
		else
			self.activeCategory = Enum.TransmogCollectionType.Paired;
		end	 
	end

	-- artifacts from other specs will not have something valid
	if sourceID ~= Constants.Transmog.NoTransmogID then
		WardrobeTransmogFrame:SetPendingTransmog(sourceID, self.activeCategory)
		PlaySound(SOUNDKIT.UI_TRANSMOG_ITEM_CLICK)
	end
	self.activeCategory = activeCategory;

	if self.activeCategory == Enum.TransmogCollectionType.Paired then 
		self.jumpToVisualID = visualID;
		C_Timer.After(0, function() BetterWardrobeCollectionFrame.ItemsCollectionFrame:ResetPage() end)
	end

end

function BetterWardrobeItemsCollectionMixin:GoToSourceID(sourceID, transmogLocation, forceGo, forTransmog, overrideCategoryID)
	local categoryID, visualID;
	if ( transmogLocation:IsAppearance() ) then
		categoryID, visualID = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
	elseif ( transmogLocation:IsIllusion() ) then
		local illusionInfo = C_TransmogCollection.GetIllusionInfo(sourceID)
		visualID = illusionInfo and illusionInfo.visualID;
	end
	if overrideCategoryID then
		categoryID = overrideCategoryID;
	end	
	if ( visualID or forceGo ) then
		self.jumpToVisualID = visualID;
		if ( self.activeCategory ~= categoryID or not self.transmogLocation:IsEqual(transmogLocation) ) then
			self:SetActiveSlot(transmogLocation, categoryID)
		else
			if not self.filteredVisualsList then
				self:RefreshVisualsList()
			end
			self:ResetPage()
		end
	end
end


local function GetVisibilityWarning(model, transmogLocation)
	local _, raceFilename = UnitRace("player");
	
	if not (raceFilename == "Dracthyr" ) then return nil end
	
	if transmogLocation and model then
		local slotID = transmogLocation.slotID;
		if model:IsGeoReady() and not model:IsSlotAllowed(slotID) and not model:IsSlotVisible(slotID) then
			return TRANSMOG_DRACTHYR_APPEARANCE_INVISIBLE;
		end
	end
	return nil;
end

function BetterWardrobeItemsCollectionMixin:SetAppearanceTooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	self.tooltipModel = frame;
	self.tooltipVisualID = frame.visualInfo.visualID;
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()

	if self.activeCategory == Enum.TransmogCollectionType.Paired and not atTransmogrifier then 
		if ( not self.tooltipVisualID ) then
			return;
		end
		addon.SetArtifactAppearanceTooltip(self, frame.visualInfo)
	else
		self:RefreshAppearanceTooltip()
	end
end

function BetterWardrobeItemsCollectionMixin:RefreshAppearanceTooltip()
	if ( not self.tooltipVisualID ) then
		return;
	end
	local sources = CollectionWardrobeUtil.GetSortedAppearanceSources(self.tooltipVisualID, self.activeCategory, self.transmogLocation)
	local chosenSourceID = self:GetChosenVisualSource(self.tooltipVisualID)
	local warningString = GetVisibilityWarning(self.tooltipModel, self.transmogLocation);
	self:GetParent():SetAppearanceTooltip(self, sources, chosenSourceID, warningString)
end

function BetterWardrobeItemsCollectionMixin:ClearAppearanceTooltip()
	self.tooltipVisualID = nil;
	self:GetParent():HideAppearanceTooltip()
end

function BetterWardrobeItemsCollectionMixin:UpdateSlotButtons()
	if C_Transmog.IsAtTransmogNPC() then
		return;
	end

	local shoulderSlotID = TransmogUtil.GetSlotID("SHOULDERSLOT")
	local itemLocation = ItemLocation:CreateFromEquipmentSlot(shoulderSlotID)
	local showSecondaryShoulder = TransmogUtil.IsSecondaryTransmoggedForItemLocation(itemLocation)

	local secondaryShoulderTransmogLocation = TransmogUtil.GetTransmogLocation("SHOULDERSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary)
	local lastButton = nil;
	for i, button in ipairs(self.SlotsFrame.Buttons) do
		if not button.isSmallButton then
			local slotName =  button.transmogLocation:GetSlotName()
			if slotName == "BACKSLOT" then
				local xOffset = showSecondaryShoulder and spacingWithSmallButton or spacingNoSmallButton;
				button:SetPoint("LEFT", lastButton, "RIGHT", xOffset, 0)
			elseif slotName == "HANDSSLOT" or slotName == "MAINHANDSLOT" then
				local xOffset = showSecondaryShoulder and shorterSectionSpacing or defaultSectionSpacing;
				button:SetPoint("LEFT", lastButton, "RIGHT", xOffset, 0)
			end
			lastButton = button;
		elseif button.transmogLocation:IsEqual(secondaryShoulderTransmogLocation) then
			button:SetShown(showSecondaryShoulder)
		end
	end

	if self.transmogLocation then
		-- if it was selected and got hidden, reset to main shoulder
		-- otherwise if main selected, update cameras
		local mainShoulderTransmogLocation = TransmogUtil.GetTransmogLocation("SHOULDERSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
		if not showSecondaryShoulder and self.transmogLocation:IsEqual(secondaryShoulderTransmogLocation) then		
			self:SetActiveSlot(mainShoulderTransmogLocation)
		elseif self.transmogLocation:IsEqual(mainShoulderTransmogLocation) then
			self:UpdateItems()
		end
	end	
end

function BetterWardrobeItemsCollectionMixin:OnPageChanged(userAction)
	PlaySound(SOUNDKIT.UI_TRANSMOG_PAGE_TURN)
	CloseDropDownMenus()
	if ( userAction ) then
		self:UpdateItems()
	end
end

function BetterWardrobeItemsCollectionMixin:OnSearchUpdate(category)
	if ( category ~= self.activeCategory ) then
		return;
	end

	self:RefreshVisualsList()
	if ( self.resetPageOnSearchUpdated ) then
		self.resetPageOnSearchUpdated = nil;
		self:ResetPage()
	elseif ( C_Transmog.IsAtTransmogNPC() and WardrobeCollectionFrameSearchBox:GetText() == "" ) then
		local _, _, selectedSourceID = TransmogUtil.GetInfoForEquippedSlot(self.transmogLocation)
		local transmogLocation = WardrobeTransmogFrame:GetSelectedTransmogLocation()
		local effectiveCategory = transmogLocation and C_Transmog.GetSlotEffectiveCategory(transmogLocation) or Enum.TransmogCollectionType.None;
		if ( effectiveCategory == self:GetActiveCategory() ) then
			self:GoToSourceID(selectedSourceID, self.transmogLocation, true)
		else
			self:UpdateItems()
		end
	else
		self:UpdateItems()
	end
end

function BetterWardrobeItemsCollectionMixin:IsAppearanceUsableForActiveCategory(appearanceInfo)
	local inLegionArtifactCategory = TransmogUtil.IsCategoryLegionArtifact(self.activeCategory)
	return CollectionWardrobeUtil.IsAppearanceUsable(appearanceInfo, inLegionArtifactCategory)
end

BW_TransmogToggleSecondaryAppearanceCheckboxMixin = { }

function BW_TransmogToggleSecondaryAppearanceCheckboxMixin:OnClick()
	local isOn = self:GetChecked()
	if isOn then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
	self:GetParent():ToggleSecondaryForSelectedSlotButton()
end

-- ***** MODELS

BetterWardrobeItemsModelMixin = { }

function BetterWardrobeItemsModelMixin:OnLoad()
	self:SetAutoDress(false)

	local lightValues = { omnidirectional = false, point = CreateVector3D(-1, 1, -1), ambientIntensity = 1.05, ambientColor = CreateColor(1, 1, 1), diffuseIntensity = 0, diffuseColor = CreateColor(1, 1, 1) }
	local enabled = true;
	self:SetLight(enabled, lightValues)
	self.desaturated = false;
end

function BetterWardrobeItemsModelMixin:OnModelLoaded()
	if ( self.cameraID ) then
		addon.Model_ApplyUICamera(self, self.cameraID)
	end
	self.desaturated = false;
end

function BetterWardrobeItemsModelMixin:UpdateContentTracking()
	self:ClearTrackables();

	if ( self.visualInfo ) then
		local itemsCollectionFrame = self:GetParent();
		if ( not itemsCollectionFrame.transmogLocation:IsIllusion()  and not itemsCollectionFrame == Enum.TransmogCollectionType.Paired) then
			local sources = CollectionWardrobeUtil.GetSortedAppearanceSources(self.visualInfo.visualID, itemsCollectionFrame:GetActiveCategory(), itemsCollectionFrame.transmogLocation);
			for i, sourceInfo in ipairs(sources) do
				self:AddTrackable(Enum.ContentTrackingType.Appearance, sourceInfo.sourceID);
			end
		end
	end

	self:UpdateTrackingCheckmark();
end

function BetterWardrobeItemsModelMixin:UpdateTrackingDisabledOverlay()
	if ( not ContentTrackingUtil.IsContentTrackingEnabled() ) then
		return;
	end

	local isCollected = self.visualInfo and self.visualInfo.isCollected;
	local showDisabled = ContentTrackingUtil.IsTrackingModifierDown() and (isCollected or not self:HasTrackableSource());
	self.DisabledOverlay:SetShown(showDisabled);
end

function BetterWardrobeItemsModelMixin:GetSourceInfoForTracking()
	if ( not self.visualInfo ) then
		return nil;
	end

	local itemsCollectionFrame = self:GetParent();
	if ( itemsCollectionFrame.transmogLocation:IsIllusion() or itemsCollectionFrame == Enum.TransmogCollectionType.Paired) then
		return nil;
	else
		local sourceIndex = WardrobeCollectionFrame.tooltipSourceIndex or 1;
		local sources = CollectionWardrobeUtil.GetSortedAppearanceSources(self.visualInfo.visualID, itemsCollectionFrame:GetActiveCategory(), itemsCollectionFrame.transmogLocation);
		local index = CollectionWardrobeUtil.GetValidIndexForNumSources(sourceIndex, #sources);
		return sources[index];
	end

	return nil;
end

function BetterWardrobeItemsModelMixin:OnMouseDown(button)
	local itemsCollectionFrame = self:GetParent()
	local isChatLinkClick = IsModifiedClick("CHATLINK");
	if ( isChatLinkClick ) then
		local link;
		if ( itemsCollectionFrame.transmogLocation:IsIllusion() ) then
			local name;
			name, link = C_TransmogCollection.GetIllusionStrings(self.visualInfo.sourceID)
		else
			local sources = CollectionWardrobeUtil.GetSortedAppearanceSources(self.visualInfo.visualID, itemsCollectionFrame:GetActiveCategory(), itemsCollectionFrame.transmogLocation)
			if ( BetterWardrobeCollectionFrame.tooltipSourceIndex ) then
				local index = CollectionWardrobeUtil.GetValidIndexForNumSources(BetterWardrobeCollectionFrame.tooltipSourceIndex, #sources)
				link = BetterWardrobeCollectionFrame:GetAppearanceItemHyperlink(sources[index])
			end
		end
		if ( link ) then
			if ( HandleModifiedItemClick(link) ) then
				return;
			end
		end
	elseif ( IsModifiedClick("DRESSUP") ) or (addon.Profile.AutoApply and not C_Transmog.IsAtTransmogNPC() and button == "LeftButton") then
		addon:StoreItems()
		itemsCollectionFrame:DressUpVisual(self.visualInfo)
		return;
	end

	if ( self.visualInfo and not self.visualInfo.isCollected ) then
		local sourceInfo = self:GetSourceInfoForTracking();
		if ( sourceInfo ) then
			if ( self:CheckTrackableClick(button, Enum.ContentTrackingType.Appearance, sourceInfo.sourceID) ) then
				self:UpdateContentTracking();
				itemsCollectionFrame:RefreshAppearanceTooltip();
				return;
			end
		end
	end

	if ( isChatLinkClick ) then
		return;
	end

	if ( button == "LeftButton" ) then
		CloseDropDownMenus()
		self:GetParent():SelectVisual(self.visualInfo.visualID)
	elseif ( button == "RightButton" ) then
		if itemsCollectionFrame:GetActiveCategory() == Enum.TransmogCollectionType.Paired then return end

		local dropDown = self:GetParent().RightClickDropDown;
		if ( dropDown.activeFrame ~= self ) then
			CloseDropDownMenus()
		end
		--if ( not self.visualInfo.isCollected or self.visualInfo.isHideVisual or itemsCollectionFrame.transmogLocation:IsIllusion() ) then
		if ( self.visualInfo.isHideVisual or itemsCollectionFrame.transmogLocation:IsIllusion() ) then
			return;
		end
		dropDown.activeFrame = self;
		BW_ToggleDropDownMenu(1, nil, dropDown, self, -6, -3)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

function BetterWardrobeItemsModelMixin:OnEnter()
	if ( not self.visualInfo ) then
		return;
	end
	self:SetScript("OnUpdate", self.OnUpdate)
	self.needsItemGeo = false;
	local itemsCollectionFrame = self:GetParent()
	if ( C_TransmogCollection.IsNewAppearance(self.visualInfo.visualID) ) then
		C_TransmogCollection.ClearNewAppearance(self.visualInfo.visualID)
		if itemsCollectionFrame.jumpToLatestAppearanceID == self.visualInfo.visualID then
			itemsCollectionFrame.jumpToLatestAppearanceID = nil;
			itemsCollectionFrame.jumpToLatestCategoryID  = nil;
		end
		self.NewString:Hide()
		self.NewGlow:Hide()
	end
	if ( itemsCollectionFrame.transmogLocation:IsIllusion() ) then
		local name = C_TransmogCollection.GetIllusionStrings(self.visualInfo.sourceID)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(name)
		if ( self.visualInfo.sourceText ) then
			GameTooltip:AddLine(self.visualInfo.sourceText, 1, 1, 1, 1)
		end
		GameTooltip:Show()
	else
		self.needsItemGeo = not self:IsGeoReady()
		itemsCollectionFrame:SetAppearanceTooltip(self)
	end
end

function BetterWardrobeItemsModelMixin:OnLeave()
	self:SetScript("OnUpdate", nil)
	ResetCursor()
	self:GetParent():ClearAppearanceTooltip()
end

function BetterWardrobeItemsModelMixin:OnUpdate()
	if IsModifiedClick("DRESSUP") then
		ShowInspectCursor()
	else
		ResetCursor()
	end

	if self.needsItemGeo then
		if self:IsGeoReady() then
			self:GetParent():SetAppearanceTooltip(self)
		end
	end
end

function BetterWardrobeItemsModelMixin:SetDesaturated(desaturated)
	if self.desaturated ~= desaturated then
		self.desaturated = desaturated;
		self:SetDesaturation((desaturated and 1) or 0);
	end
end

function BetterWardrobeItemsModelMixin:Reload(reloadSlot)
	if ( self:IsShown() ) then
		if ( WARDROBE_MODEL_SETUP[reloadSlot] ) then
			local useTransmogSkin = GetUseTransmogSkin(reloadSlot);	
			self:SetUseTransmogSkin(useTransmogSkin)
			self:SetUseTransmogChoices(WARDROBE_MODEL_SETUP[reloadSlot].useTransmogChoices)
			self:SetObeyHideInTransmogFlag(WARDROBE_MODEL_SETUP[reloadSlot].obeyHideInTransmogFlag)
			self:SetUnit("player", false, PlayerUtil.ShouldUseNativeFormInModelScene())
			self:SetDoBlend(false)
			for slot, equip in pairs(WARDROBE_MODEL_SETUP[reloadSlot].slots) do
				if ( equip ) then
					self:TryOn(WARDROBE_MODEL_SETUP_GEAR[slot])
				end
			end
		end

		local _, raceFilename = UnitRace("player");
		local sex = UnitSex("player") 
		if (raceFilename == "Dracthyr" or raceFilename == "Worgen") then
			local inNativeForm = C_UnitAuras.WantsAlteredForm("player");
			self:SetUseTransmogSkin(false)
				local modelID, altModelID
				if raceFilename == "Worgen" then
					if sex == 3 then
						modelID = 307453
						altModelID = 1000764
					else
						modelID = 307454
						altModelID = 1011653
					end
				elseif raceFilename == "Dracthyr" then
					if sex == 3 then
						modelID = 4207724
						altModelID = 4220448
					else
						modelID = 4207724
						altModelID = 4395382
					end
				end

			if inNativeForm and not addon.useNativeForm then
				self:SetUnit("player", false, false)
				self:SetModel(altModelID)

			elseif not inNativeForm and addon.useNativeForm then
				self:SetUnit("player", false, true)
				self:SetModel( modelID )
			end
		end

		self:SetKeepModelOnHide(true)
		self.cameraID = nil;
		self.needsReload = nil;
	else
		self.needsReload = true;
	end
end

function BetterWardrobeItemsModelMixin:OnShow()
	if ( self.needsReload ) then
		self:Reload(self:GetParent():GetActiveSlot())
	end
end

BetterWardrobeSetsTransmogModelMixin = { }

function BetterWardrobeSetsTransmogModelMixin:OnLoad()
	self:RegisterEvent("UI_SCALE_CHANGED")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED")
	self:SetAutoDress(false)

	self:SetUnit("player", false, PlayerUtil.ShouldUseNativeFormInModelScene())
	self:FreezeAnimation(0, 0, 0)
	local x, y, z = self:TransformCameraSpaceToModelSpace(CreateVector3D(0, 0, -0.25)):GetXYZ()
	self:SetPosition(x, y, z)
	local lightValues = { omnidirectional = false, point = CreateVector3D(-1, 1, -1), ambientIntensity = 1, ambientColor = CreateColor(1, 1, 1), diffuseIntensity = 0, diffuseColor = CreateColor(1, 1, 1) }
	local enabled = true;
	self:SetLight(enabled, lightValues)
end

function BetterWardrobeSetsTransmogModelMixin:OnEvent()
	self:RefreshCamera()
	local x, y, z = self:TransformCameraSpaceToModelSpace(CreateVector3D(0, 0, -0.25)):GetXYZ()
	self:SetPosition(x, y, z)
end

function BetterWardrobeSetsTransmogModelMixin:OnMouseDown(button)
	if ( button == "LeftButton" ) then
		self:GetParent():SelectSet(self.setID)
		PlaySound(SOUNDKIT.UI_TRANSMOG_ITEM_CLICK)
	elseif ( button == "RightButton" ) then
		local dropDown = self:GetParent().RightClickDropDown;
		if ( dropDown.activeFrame ~= self ) then
			BW_CloseDropDownMenus()
		end
		dropDown.activeFrame = self;
		BW_ToggleDropDownMenu(1, nil, dropDown, self, -6, -3)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

function BetterWardrobeSetsTransmogModelMixin:OnEnter()
	self:GetParent().tooltipModel = self;
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	self:RefreshTooltip()
end

function BetterWardrobeSetsTransmogModelMixin:RefreshTooltip()
	local totalQuality = 0;
	local numTotalSlots = 0;
	local waitingOnQuality = false;
	local sourceQualityTable = self:GetParent().sourceQualityTable or {}
	
	if BetterWardrobeCollectionFrame:CheckTab(4) then
		return;

	elseif BetterWardrobeCollectionFrame:CheckTab(2) then

		local primaryAppearances = C_TransmogSets.GetSetPrimaryAppearances(self.setID)
		for i, primaryAppearance in pairs(primaryAppearances) do
			numTotalSlots = numTotalSlots + 1;
			local sourceID = primaryAppearance.appearanceID;
			if ( sourceQualityTable[sourceID] ) then
				totalQuality = totalQuality + sourceQualityTable[sourceID]
			else
				local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				if ( sourceInfo and sourceInfo.quality ) then
					sourceQualityTable[sourceID] = sourceInfo.quality;
					totalQuality = totalQuality + sourceInfo.quality;
				else
					waitingOnQuality = true;
				end
			end
		end

		if ( waitingOnQuality ) then
			GameTooltip:SetText(RETRIEVING_ITEM_INFO, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		else
			local setQuality = (numTotalSlots > 0 and totalQuality > 0) and Round(totalQuality / numTotalSlots) or Enum.ItemQuality.Common;
			local color = ITEM_QUALITY_COLORS[setQuality]
			local setInfo = C_TransmogSets.GetSetInfo(self.setID)
			GameTooltip:SetText(setInfo.name, color.r, color.g, color.b)
			if ( setInfo.label ) then
				GameTooltip:AddLine(setInfo.label)
				GameTooltip:Show()
			end
			if not setInfo.isClass then
				GameTooltip:AddLine(setInfo.className)
				GameTooltip:Show()
			end
		end

	elseif BetterWardrobeCollectionFrame:CheckTab(3) then
		local sources = addon.GetSetsources(self.setID)
		for sourceID in pairs(sources) do
			numTotalSlots = numTotalSlots + 1;
			if (sourceQualityTable[sourceID]) then
				totalQuality = totalQuality + sourceQualityTable[sourceID]
			else
				local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				if (sourceInfo and sourceInfo.quality) then
					sourceQualityTable[sourceID] = sourceInfo.quality;
					totalQuality = totalQuality + sourceInfo.quality;
				else
					waitingOnQuality = true;
				end
			end
		end
	
		if (waitingOnQuality) then
			GameTooltip:SetText(RETRIEVING_ITEM_INFO, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		else
			local setQuality = (numTotalSlots > 0 and totalQuality > 0) and Round(totalQuality / numTotalSlots) or Enum.ItemQuality.Common;
			local color = ITEM_QUALITY_COLORS[setQuality]
			local setInfo = addon.GetSetInfo(self.setID)
			GameTooltip:SetText(setInfo.name, color.r, color.g, color.b)
			if (setInfo.label) then
				GameTooltip:AddLine(setInfo.label)
				GameTooltip:Show()
			end
			if not setInfo.isClass then
				GameTooltip:AddLine(setInfo.className)
				GameTooltip:Show()
			end

		end
	end

end

function BetterWardrobeSetsTransmogModelMixin:OnLeave()
	GameTooltip:Hide()
	self:GetParent().tooltipModel = nil;
end

function BetterWardrobeSetsTransmogModelMixin:OnShow()
	self:SetUnit("player", false, PlayerUtil.ShouldUseNativeFormInModelScene())
end

function BetterWardrobeSetsTransmogModelMixin:OnHide()
	self.setID = nil;
end

function BetterWardrobeSetsTransmogModelMixin:OnModelLoaded()
	if ( self.cameraID ) then
		addon.Model_ApplyUICamera(self, self.cameraID)
	end
end

function BetterWardrobeItemsCollectionMixin:GetChosenVisualSource(visualID)
	return self.chosenVisualSources[visualID] or Constants.Transmog.NoTransmogID;
end

function BetterWardrobeItemsCollectionMixin:SetChosenVisualSource(visualID, sourceID)
	self.chosenVisualSources[visualID] = sourceID;
end

function BetterWardrobeItemsCollectionMixin:ValidateChosenVisualSources()
	for visualID, sourceID in pairs(self.chosenVisualSources) do
		if ( sourceID ~= Constants.Transmog.NoTransmogID ) then
			local keep = false;
			local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)

			if sourceInfo then
				if sourceInfo.isCollected and not sourceInfo.useError then
					keep = true;
				end
			end

			if ( not keep ) then
				self.chosenVisualSources[visualID] = Constants.Transmog.NoTransmogID;
			end
		end
	end
end

local function ToggleHidden(model, isHidden)
	local tabID = addon.GetTab()
	if tabID == 1 then
		local visualID = model.visualInfo.visualID;
		local _, _, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(visualID)	
		local source = CollectionWardrobeUtil.GetSortedAppearanceSources(visualID, addon.GetItemCategory(visualID), addon.GetTransmogLocation(itemLink))[1]
		local name, link = GetItemInfo(source.itemID)
		addon.HiddenAppearanceDB.profile.item[visualID] = not isHidden and name;
		--self:UpdateWardrobe()
		print(string.format("%s "..link.." %s", isHidden and L["unhiding_item"] or L["hiding_item"], isHidden and L["inhiding_item_end"] or L["hiding_item_end"] ))
		BetterWardrobeCollectionFrame.ItemsCollectionFrame:RefreshVisualsList()
		BetterWardrobeCollectionFrame.ItemsCollectionFrame:UpdateItems()

	elseif tabID == 2 then
		local setInfo = C_TransmogSets.GetSetInfo(tonumber(model.setID))
		local name = setInfo["name"]

		local baseSetID = C_TransmogSets.GetBaseSetID(model.setID)
		addon.HiddenAppearanceDB.profile.set[baseSetID] = not isHidden and name or nil;

		local sourceinfo = C_TransmogSets.GetSetSources(baseSetID)
		for i,data in pairs(sourceinfo) do
			local info = C_TransmogCollection.GetSourceInfo(i)
				addon.HiddenAppearanceDB.profile.item[info.visualID] = not isHidden and info.name or nil;
		end

		local variantSets = C_TransmogSets.GetVariantSets(baseSetID)
			for i, data in ipairs(variantSets) do
				addon.HiddenAppearanceDB.profile.set[data.setID] = not isHidden and data.name or nil;

				local sourceinfo = C_TransmogSets.GetSetSources(data.setID)
				for i,data in pairs(sourceinfo) do
					local info = C_TransmogCollection.GetSourceInfo(i)
						addon.HiddenAppearanceDB.profile.item[info.visualID] = not isHidden and info.name or nil;
				end
		end	

		BetterWardrobeCollectionFrame.SetsCollectionFrame:OnSearchUpdate()
		BetterWardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()
		print(format("%s "..name.." %s", isHidden and L["unhiding_set"] or L["hiding_set"], isHidden and L["unhiding_set_end"] or L["hiding_set_end"]))
	else
		local setInfo = addon.GetSetInfo(model.setID)
		local name = setInfo["name"]
		addon.HiddenAppearanceDB.profile.extraset[model.setID] = not isHidden and name or nil;
		print(format("%s "..name.." %s", isHidden and L["unhiding_set"] or L["hiding_set"], isHidden and L["unhiding_set_end"] or L["hiding_set_end"]))
		BetterWardrobeCollectionFrame.SetsCollectionFrame:OnSearchUpdate()
		BetterWardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()

	end
			--self:UpdateWardrobe()
end

function BetterWardrobeCollectionFrameRightClickDropDown_Init(self)
	local appearanceID = self.activeFrame.visualInfo.visualID;
	local info = BW_UIDropDownMenu_CreateInfo()
	-- Set Favorite
	if ( C_TransmogCollection.GetIsAppearanceFavorite(appearanceID) or addon:IsFavoriteItem(appearanceID) ) then
		info.text = BATTLE_PET_UNFAVORITE;
		info.arg1 = appearanceID;
		info.arg2 = 0;
	else
		info.text = BATTLE_PET_FAVORITE;
		info.arg1 = appearanceID;
		info.arg2 = 1;
	end
	info.notCheckable = true;
	info.func = function(_, visualID, value) BetterWardrobeCollectionFrameModelDropDown_SetFavorite(visualID, value); end
	BW_UIDropDownMenu_AddButton(info)

	BW_UIDropDownMenu_AddSeparator()
	local isHidden = addon.HiddenAppearanceDB.profile.item[self.activeFrame.visualInfo.visualID]
	BW_UIDropDownMenu_AddButton({
		notCheckable = true,
		text = isHidden and SHOW or HIDE,
		func = function() ToggleHidden(self.activeFrame, isHidden) end,
	})

	local collected = self.activeFrame.visualInfo.isCollected;
	--Collection List Right Click options;
	local collectionList = addon.CollectionList:CurrentList()
	local isInList = match or addon.CollectionList:IsInList(self.activeFrame.visualInfo.visualID, "item")

	--if  type  == "set" or ((isInList and collected) or not collected)then --(type == "item" and not (model.visualInfo and model.visualInfo.isCollected)) or type == "set" or type == "extraset" then
		local targetSet = match or variantTarget or self.activeFrame.visualInfo.visualID;
		local targetText = match and " - "..matchType or variantTarget and " - "..variantType or ""
		BW_UIDropDownMenu_AddSeparator()
		local isInList = collectionList["item"][targetSet]
		BW_UIDropDownMenu_AddButton({
			notCheckable = true,
			text = isInList and L["Remove from Collection List"]..targetText or L["Add to Collection List"]..targetText,
			func = function()
						addon.CollectionList:UpdateList("item", targetSet, not isInList)
				end,
		})

	info.text = L["View Sources"]
			info.arg1 = appearanceID;
			info.arg2 = 1;
			
			info.notCheckable = true;
			info.func = function(_, visualID, value)  
												addon.CollectionList:GenerateSourceListView(visualID)
						end
			BW_UIDropDownMenu_AddButton(info)
		
		
			info.text = L["View Recolors"]
			info.arg1 = appearanceID;
			info.arg2 = 1;
			
			info.notCheckable = true;
			info.func = function(_, visualID, value)  
			if not IsAddOnLoaded("BetterWardrobe_SourceData") then
				EnableAddOn("BetterWardrobe_SourceData")
				LoadAddOn("BetterWardrobe_SourceData")
			end
			local Recolors = _G.BetterWardrobeData.ItemRecolors or {}
				for i = 1, #Recolors do
					local visualList = Recolors[i]
					for j = 1, #visualList do
						if visualList[j] == visualID then
							BetterWardrobeCollectionFrame.ItemsCollectionFrame.recolors = visualList;
							BetterWardrobeCollectionFrame.ItemsCollectionFrame:RefreshVisualsList()
							BetterWardrobeCollectionFrame.ItemsCollectionFrame:FilterVisuals()
							BetterWardrobeCollectionFrame.ItemsCollectionFrame:SortVisuals()
							BetterWardrobeCollectionFrame.ItemsCollectionFrame:UpdateItems()
							addon.ColorFilterButton.revert:Show()
							return;
						end
					end
				end
				print(L["No Recolors Found"])
		
			end
			BW_UIDropDownMenu_AddButton(info)

	-- Cancel

	info = BW_UIDropDownMenu_CreateInfo()
	info.notCheckable = true;
	info.text = CANCEL;
	BW_UIDropDownMenu_AddSeparator()
	BW_UIDropDownMenu_AddButton(info)

	local headerInserted = false;
	local sources = CollectionWardrobeUtil.GetSortedAppearanceSources(appearanceID, BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetActiveCategory(), BetterWardrobeCollectionFrame.ItemsCollectionFrame.transmogLocation)
	local chosenSourceID = BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetChosenVisualSource(appearanceID)
	info.func = WardrobeCollectionFrameModelDropDown_SetSource;
	for i = 1, #sources do
		if ( sources[i].isCollected and BetterWardrobeCollectionFrame.ItemsCollectionFrame:IsAppearanceUsableForActiveCategory(sources[i]) ) then
			if ( not headerInserted ) then
				headerInserted = true;
				-- space
				info.text = " "
				info.disabled = true;
				BW_UIDropDownMenu_AddButton(info)
				info.disabled = nil;
				-- header
				info.text = WARDROBE_TRANSMOGRIFY_AS;
				info.isTitle = true;
				info.colorCode = NORMAL_FONT_COLOR_CODE;
				BW_UIDropDownMenu_AddButton(info)
				info.isTitle = nil;
				-- turn off notCheckable
				info.notCheckable = nil;
			end
			local name, nameColor = BetterWardrobeCollectionFrame:GetAppearanceNameTextAndColor(sources[i])
			info.text = name;
			info.colorCode = nameColor:GenerateHexColorMarkup()
			info.disabled = nil;
			info.arg1 = appearanceID;
			info.arg2 = sources[i].sourceID;
			-- choose the 1st valid source if one isn't explicitly chosen
			if ( chosenSourceID == Constants.Transmog.NoTransmogID ) then
				chosenSourceID = sources[i].sourceID;
			end
			info.checked = (chosenSourceID == sources[i].sourceID)
			BW_UIDropDownMenu_AddButton(info)
		end
	end
end

function BetterWardrobeCollectionFrameModelDropDown_SetSource(self, visualID, sourceID)
	BetterWardrobeCollectionFrame.ItemsCollectionFrame:SetChosenVisualSource(visualID, sourceID)
	BetterWardrobeCollectionFrame.ItemsCollectionFrame:SelectVisual(visualID)
end


function addon:SetFavoriteItem(visualID, set)
	if addon.favoritesDB.profile.item[visualID] then
		addon.favoritesDB.profile.item[visualID] = nil;
	else
		addon.favoritesDB.profile.item[visualID] = true;
	end

	BetterWardrobeCollectionFrame.ItemsCollectionFrame:RefreshVisualsList()
	BetterWardrobeCollectionFrame.ItemsCollectionFrame:UpdateItems()
end


function addon:IsFavoriteItem(visualID)
	return addon.favoritesDB.profile.item[visualID]
end

function BetterWardrobeCollectionFrameModelDropDown_SetFavorite(visualID, value, confirmed)
	local set = (value == 1)

	if ( set and not confirmed ) then
		local allSourcesConditional = true;
		local collected = false;
		local sources = C_TransmogCollection.GetAppearanceSources(visualID, BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetActiveCategory(), BetterWardrobeCollectionFrame.ItemsCollectionFrame.transmogLocation)
		for i, sourceInfo in ipairs(sources) do
			local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceInfo.sourceID)
			if info.isCollected then 
				collected = true;
			end
			if ( info.sourceIsCollectedPermanent ) then
				allSourcesConditional = false;
				break;
			end
		end
		if ( allSourcesConditional and collected ) then
			StaticPopup_Show("TRANSMOG_FAVORITE_WARNING", nil, nil, visualID)
			return;
		elseif ( allSourcesConditional and not collected ) then 
			addon:SetFavoriteItem(visualID, set)
			return 
		end
	else
		--addon:SetFavoriteItem(visualID, set)

	end

	--if addon:IsFavoriteItem(visualID) then 
		addon:SetFavoriteItem(visualID, set)
	--else
		C_TransmogCollection.SetIsAppearanceFavorite(visualID, set)
		SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_MODEL_CLICK, true)
		--HelpTip:Hide(BetterWardrobeCollectionFrame.ItemsCollectionFrame, TRANSMOG_MOUSE_CLICK_TUTORIAL)
	--end
end

-- ***** TUTORIAL
BetterWardrobeCollectionTutorialMixin = { }

function BetterWardrobeCollectionTutorialMixin:OnLoad()
--[[
	self.helpTipInfo = {
		text = WARDROBE_SHORTCUTS_TUTORIAL_1,
		buttonStyle = HelpTip.ButtonStyle.None,
		targetPoint = HelpTip.Point.BottomEdgeLeft,
		alignment = HelpTip.Alignment.Left,
		offsetX = 32,
		offsetY = 16,
		appendFrame = BW_TrackingInterfaceShortcutsFrame,
		appendFrameYOffset = 15,
	};
	]]
	self:Hide()

end

function BetterWardrobeCollectionTutorialMixin:OnEnter()
	--HelpTip:Show(self, self.helpTipInfo);
	--BW_TrackingInterfaceShortcutsFrame.NewAlert:ValidateIsShown();
end

function BetterWardrobeCollectionTutorialMixin:OnLeave()
	--HelpTip:Hide(self, WARDROBE_SHORTCUTS_TUTORIAL_1);
	--BW_TrackingInterfaceShortcutsFrame.NewAlert:ClearAlert();
end


BW_AlertTrackingFeatureMixin = {}--CreateFromMixins(NewFeatureLabelMixin);

function BW_AlertTrackingFeatureMixin:ClearAlert()
	--AlertTrackingFeatureMixin.ClearAlert(self);
	--SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_WARDROBE_TRACKING_INTERFACE, true);
	--CollectionsMicroButton_SetAlertShown(false);
end

function BW_AlertTrackingFeatureMixin:ValidateIsShown()
	--self:SetShown(not GetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_WARDROBE_TRACKING_INTERFACE));
end

-- ***** WEAPON DROPDOWN

function BetterWardrobeCollectionFrameWeaponDropDown_OnLoad(self)
	BW_UIDropDownMenu_Initialize(self, BetterWardrobeCollectionFrameWeaponDropDown_Init)
	BW_UIDropDownMenu_SetWidth(self, 140)
end

function BetterWardrobeCollectionFrameWeaponDropDown_Init(self)
	local transmogLocation = BetterWardrobeCollectionFrame.ItemsCollectionFrame.transmogLocation;
	if ( not transmogLocation ) then
		return;
	end

	local selectedValue = BW_UIDropDownMenu_GetSelectedValue(self)
	local info = BW_UIDropDownMenu_CreateInfo()
	info.func = BetterWardrobeCollectionFrameWeaponDropDown_OnClick;

	local equippedItemID = GetInventoryItemID("player", transmogLocation:GetSlotID())
	local checkCategory = equippedItemID and C_Transmog.IsAtTransmogNPC()
	if ( checkCategory ) then
		-- if the equipped item cannot be transmogrified, relax restrictions
		local isTransmogrified, hasPending, isPendingCollected, canTransmogrify, cannotTransmogrifyReason, hasUndo = C_Transmog.GetSlotInfo(transmogLocation)
		if ( not canTransmogrify and not hasUndo ) then
			checkCategory = false;
		end
	end
	local buttonsAdded = 0;

	local isForMainHand = transmogLocation:IsMainHand()
	local isForOffHand = transmogLocation:IsOffHand()
	for categoryID = FIRST_TRANSMOG_COLLECTION_WEAPON_TYPE, LAST_TRANSMOG_COLLECTION_WEAPON_TYPE do
		local name, isWeapon, canEnchant, canMainHand, canOffHand = C_TransmogCollection.GetCategoryInfo(categoryID)
		if ( name and isWeapon ) then		
			if ( (isForMainHand and canMainHand) or (isForOffHand and canOffHand) ) then
				if ( not checkCategory or C_TransmogCollection.IsCategoryValidForItem(categoryID, equippedItemID) ) then
					info.text = name;
					info.arg1 = categoryID;
					info.value = categoryID;
					if ( info.value == selectedValue ) then
						info.checked = 1;
					else
						info.checked = nil;
					end
					BW_UIDropDownMenu_AddButton(info)
					buttonsAdded = buttonsAdded + 1;
				end
			end
		end
	end
	return buttonsAdded;
end

function BetterWardrobeCollectionFrameWeaponDropDown_OnClick(self, category)
	if ( category and BetterWardrobeCollectionFrame.ItemsCollectionFrame:GetActiveCategory() ~= category ) then
		CloseDropDownMenus()
		BetterWardrobeCollectionFrame.ItemsCollectionFrame:SetActiveCategory(category)
	end
end

BetterWardrobeCollectionFrameSearchBoxProgressMixin = { }

function BetterWardrobeCollectionFrameSearchBoxProgressMixin:OnLoad()
	self:SetFrameLevel(self:GetParent():GetFrameLevel() + 15)
	
	self.ProgressBar:SetStatusBarColor(0, .6, 0, 1)
	self.ProgressBar:SetMinMaxValues(0, 1000)
	self.ProgressBar:SetValue(0)
	self.ProgressBar:GetStatusBarTexture():SetDrawLayer("BORDER")
end

function BetterWardrobeCollectionFrameSearchBoxProgressMixin:OnHide()
	self.ProgressBar:SetValue(0)
end

function BetterWardrobeCollectionFrameSearchBoxProgressMixin:OnUpdate(elapsed)
	if self.updateProgressBar then		
		local searchType = BetterWardrobeCollectionFrame:GetSearchType()
		if not C_TransmogCollection.IsSearchInProgress(searchType) then
			self:Hide()
		else
			local _, maxValue = self.ProgressBar:GetMinMaxValues();	
			local searchSize = C_TransmogCollection.SearchSize(searchType)
			local searchProgress = C_TransmogCollection.SearchProgress(searchType)
			self.ProgressBar:SetValue((searchProgress * maxValue) / searchSize)
		end
	end
end

function BetterWardrobeCollectionFrameSearchBoxProgressMixin:ShowLoadingFrame()
	self.LoadingFrame:Show()
	self.ProgressBar:Hide()
	self.updateProgressBar = false;
	self:Show()
end

function BetterWardrobeCollectionFrameSearchBoxProgressMixin:ShowProgressBar()
	self.LoadingFrame:Hide()
	self.ProgressBar:Show()
	self.updateProgressBar = true;
	self:Show()
end

BetterWardrobeCollectionFrameSearchBoxMixin = { }

function BetterWardrobeCollectionFrameSearchBoxMixin:OnLoad()
	SearchBoxTemplate_OnLoad(self)
end

function BetterWardrobeCollectionFrameSearchBoxMixin:OnHide()
	self.ProgressFrame:Hide()
end

function BetterWardrobeCollectionFrameSearchBoxMixin:OnKeyDown(key, ...)
	if key == WARDROBE_CYCLE_KEY then
		WardrobeCollectionFrame:OnKeyDown(key, ...)
	end
end

function BetterWardrobeCollectionFrameSearchBoxMixin:StartCheckingProgress()
	self.checkProgress = true;
	self.updateDelay = 0;
end

local WARDROBE_SEARCH_DELAY = 0.6;
function BetterWardrobeCollectionFrameSearchBoxMixin:OnUpdate(elapsed)
	if not self.checkProgress then
		return;
	end

	self.updateDelay = self.updateDelay + elapsed;

	if not C_TransmogCollection.IsSearchInProgress(BetterWardrobeCollectionFrame:GetSearchType()) then
		self.checkProgress = false;
	elseif self.updateDelay >= WARDROBE_SEARCH_DELAY then
		self.checkProgress = false;
		if not C_TransmogCollection.IsSearchDBLoading() then
			self.ProgressFrame:ShowProgressBar()
		else
			self.ProgressFrame:ShowLoadingFrame()
		end
	end
end

function BetterWardrobeCollectionFrameSearchBoxMixin:OnTextChanged()
	SearchBoxTemplate_OnTextChanged(self)
	BetterWardrobeCollectionFrame:SetSearch(self:GetText())
end

function BetterWardrobeCollectionFrameSearchBoxMixin:OnEnter()
	if not self:IsEnabled() then
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 0)
		GameTooltip:SetOwner(self, "ANCHOR_PRESERVE")
		GameTooltip:SetText(WARDROBE_NO_SEARCH)
	end
end

-- ***** FILTER

local FILTER_SOURCES = {L["MISC"], L["Classic Set"], L["Quest Set"], L["Dungeon Set"], L["Raid Set"], L["Recolor"], L["PvP"],L["Garrison"], L["Island Expedition"], L["Warfronts"], L["Covenants"], L["Trading Post"], L["Holiday"], L["NOTE_119"],L["NOTE_120"]}
local EXPANSIONS = {EXPANSION_NAME0, EXPANSION_NAME1, EXPANSION_NAME2, EXPANSION_NAME3, EXPANSION_NAME4, EXPANSION_NAME5, EXPANSION_NAME6, EXPANSION_NAME7, EXPANSION_NAME8, EXPANSION_NAME9}


addon.Filters = {
	["Base"] = {
		["filterCollected"] = {true, true},
		["missingSelection"] = {},
		["filterSelection"] = {},
		["xpacSelection"] = {},
	},
	["Extra"] = {
		["filterCollected"] = {true, true},
		["missingSelection"] = {},
		["filterSelection"] = {},
		["xpacSelection"] = {},
	},

}
local filterCollected = addon.Filters.Extra.filterCollected;
local missingSelection = addon.Filters.Extra.missingSelection;
local filterSelection = addon.Filters.Extra.filterSelection;
local xpacSelection = addon.Filters.Extra.xpacSelection;
local sets = {"Base", "Extra"}

for i, types in ipairs(sets) do
	for i = 1, #FILTER_SOURCES do
		addon.Filters[types].filterSelection[i] = true;
	end

	for i = 1, #EXPANSIONS do
		addon.Filters[types].xpacSelection[i] = true;
	end
end

local function RefreshLists()
	local atTransmog =C_Transmog.IsAtTransmogNPC()
	if atTransmog then
		addon.SetsDataProvider:ClearUsableSets()
		BetterWardrobeCollectionFrame.SetsTransmogFrame:UpdateSets()
	else
		addon.SetsDataProvider:ClearBaseSets()
		addon.SetsDataProvider:ClearVariantSets()
		addon.SetsDataProvider:ClearUsableSets()
		BetterWardrobeCollectionFrame.SetsCollectionFrame:Refresh()
	end										
end
addon.RefreshLists = RefreshLists;

function BetterWardrobeFilterDropDown_OnLoad(self)
	BW_UIDropDownMenu_Initialize(self, BetterWardrobeFilterDropDown_Initialize, "MENU")
end

function BetterWardrobeFilterDropDown_Initialize(self, level)
	if ( not BetterWardrobeCollectionFrame.activeFrame ) then
		return;
	end

	if ( BetterWardrobeCollectionFrame:GetSearchType() == Enum.TransmogSearchType.Items ) then
		BetterWardrobeFilterDropDown_InitializeItems(self, level)
	elseif ( BetterWardrobeCollectionFrame:GetSearchType() == Enum.TransmogSearchType.BaseSets ) then
		BetterWardrobeFilterDropDown_InitializeBaseSets(self, level)
	end
end

function BetterWardrobeFilterDropDown_InitializeItems(self, level)
	local info = BW_UIDropDownMenu_CreateInfo()
	info.keepShownOnClick = true;
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()

	if level == 1 and not atTransmogrifier then
		info.text = COLLECTED;
		info.func = function(_, _, _, value)
						C_TransmogCollection.SetCollectedShown(value)
					end
		info.checked = C_TransmogCollection.GetCollectedShown()
		info.isNotRadio = true;
		BW_UIDropDownMenu_AddButton(info, level)

		info.text = NOT_COLLECTED;
		info.func = function(_, _, _, value)
						C_TransmogCollection.SetUncollectedShown(value)
					end
		info.checked = C_TransmogCollection.GetUncollectedShown()
		info.isNotRadio = true;
		BW_UIDropDownMenu_AddButton(info, level)

		info.checked = 	nil;
		info.isNotRadio = nil;
		info.func =  nil;
		info.hasArrow = true;
		info.notCheckable = true;

		info.text = SOURCES;
		info.value = 1;
		BW_UIDropDownMenu_AddButton(info, level)
	else
		if level == 2 or atTransmogrifier then
			local refreshLevel = atTransmogrifier and 1 or 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;

			info.text = CHECK_ALL;
			info.func = function()
							C_TransmogCollection.SetAllSourceTypeFilters(true)
							BW_UIDropDownMenu_Refresh(BetterWardrobeFilterDropDown, 1, refreshLevel)
						end
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = UNCHECK_ALL;
			info.func = function()
							C_TransmogCollection.SetAllSourceTypeFilters(false)
							BW_UIDropDownMenu_Refresh(BetterWardrobeFilterDropDown, 1, refreshLevel)
						end
			BW_UIDropDownMenu_AddButton(info, level)
			info.notCheckable = false;

			local numSources = C_TransmogCollection.GetNumTransmogSources()
			for i = 1, numSources do
				info.text = _G["TRANSMOG_SOURCE_"..i]
				info.func = function(_, _, _, value)
							C_TransmogCollection.SetSourceTypeFilter(i, value)
						end
				info.checked = function() return C_TransmogCollection.IsSourceTypeFilterChecked(i) end
				BW_UIDropDownMenu_AddButton(info, level)
			end
		end
	end
end

local locationDrowpDown = addon.Globals.locationDrowpDown;

function BetterWardrobeFilterDropDown_InitializeBaseSets(self, level)
	local info = BW_UIDropDownMenu_CreateInfo()
	info.keepShownOnClick = true;
	info.isNotRadio = true;
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()

	if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then 
		local filterCollected = addon.Filters.Base.filterCollected;
		local missingSelection = addon.Filters.Base.missingSelection;
		local filterSelection = addon.Filters.Base.filterSelection;
		local xpacSelection = addon.Filters.Base.xpacSelection;

		if level == 1 then
			local refreshLevel = 1;

			info.text = COLLECTED;
			info.func = function(_, _, _, value)
							C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_COLLECTED, value)
							addon.TRANSMOG_SET_FILTER[LE_TRANSMOG_SET_FILTER_COLLECTED] = value;

						end
			info.checked = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_COLLECTED)
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = NOT_COLLECTED;
			info.func = function(_, _, _, value)
							C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_UNCOLLECTED, value)
							addon.TRANSMOG_SET_FILTER[LE_TRANSMOG_SET_FILTER_UNCOLLECTED] = value;

						end
			info.checked = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_UNCOLLECTED)
			BW_UIDropDownMenu_AddButton(info, level)

			BW_UIDropDownMenu_AddSeparator()

			info = BW_UIDropDownMenu_CreateInfo()
			info.keepShownOnClick = true;
			info.isNotRadio = true;

			info.text = TRANSMOG_SET_PVE;
			info.func = function(_, _, _, value)
							C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVE, value)
						end
			info.checked = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVE)
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = TRANSMOG_SET_PVP;
			info.func = function(_, _, _, value)
							C_TransmogSets.SetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVP, value)
						end
			info.checked = C_TransmogSets.GetBaseSetsFilter(LE_TRANSMOG_SET_FILTER_PVP)
			BW_UIDropDownMenu_AddButton(info, level)

			BW_UIDropDownMenu_AddSeparator()
			info.checked = 	true;
			info.isNotRadio = true;
			info.func = function(info, arg1, _, value)
						addon.Profile.ShowHidden = not addon.Profile.ShowHidden;
						RefreshLists()
				end
			info.hasArrow = false;
			info.notCheckable = false;
			info.checked = addon.Profile.ShowHidden;
			info.text = L["Show Hidden Items"]
			info.value = 4;
			BW_UIDropDownMenu_AddButton(info, level)

			info.checked = 	nil;
			info.isNotRadio = nil;
			info.func =  nil;
			info.hasArrow = true;
			info.notCheckable = true;

			info.text = L["Expansion"]
			info.value = 2;
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = "Missing:"
			info.value = 3;
			BW_UIDropDownMenu_AddButton(info, level)

		elseif level == 2  and BW_UIDROPDOWNMENU_MENU_VALUE == 2 then
			local refreshLevel = 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;
			info.text = CHECK_ALL;
			info.func = function()
							for i = 1, #xpacSelection do
								xpacSelection[i] = true;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)

			local refreshLevel = 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;

			info.text = UNCHECK_ALL;
			info.func = function()
							for i = 1, #xpacSelection do
									xpacSelection[i] = false;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)
			BW_UIDropDownMenu_AddSeparator(level)

			info.notCheckable = false;
			for i = 1, #EXPANSIONS do
				info.text = EXPANSIONS[i]
					info.func = function(_, _, _, value)
						xpacSelection[i] = value;
						RefreshLists()
					end
					info.checked = 	function() return xpacSelection[i] end
				BW_UIDropDownMenu_AddButton(info, level)
			end

		elseif level == 2  and BW_UIDROPDOWNMENU_MENU_VALUE == 3 then
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;
			local refreshLevel = 2;

			info.text = CHECK_ALL;
			info.func = function()
							for i in pairs(locationDrowpDown) do
								missingSelection[i] = true;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = UNCHECK_ALL;
			info.func = function()
							for i in pairs(locationDrowpDown) do
								missingSelection[i] = false;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)
			BW_UIDropDownMenu_AddSeparator(level)

			for index, id in pairs(locationDrowpDown) do
				if index ~= 21 then --Skip "robe" type;
					info.text = id;
					info.notCheckable = false;
					info.func = function(_, _, _, value)
								missingSelection[index] = value;

								if index == 6 then
									missingSelection[21] = value;
								end

								BW_UIDropDownMenu_Refresh(self)
								RefreshLists()
							end
					info.checked = function() return missingSelection[index] end
					BW_UIDropDownMenu_AddButton(info, level)
				end
			end
		--[[elseif level == 2  and UIDROPDOWNMENU_MENU_VALUE == 4 then
					local counter = 1;
					for name in pairs(addon.Globals.ARMOR_MASK) do
						info.keepShownOnClick = false;
			
						info.text = name;
						info.func = function(info, arg1, _, value)
								addon.selectedArmorType = arg1;
								addon.extraSetsCache = nil;
								BW_WardrobeCollectionFrame_SetTab(3)
								BW_WardrobeCollectionFrame_SetTab(2)
								RefreshArmor()
						end
						info.arg1 = name;
						info.checked = 	function() return addon.selectedArmorType == name end
						UIDropDownMenu_AddButton(info, level)
					end]]
		end

	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then 
		local filterCollected = addon.Filters.Extra.filterCollected;
		local missingSelection = addon.Filters.Extra.missingSelection;
		local filterSelection = addon.Filters.Extra.filterSelection;
		local xpacSelection = addon.Filters.Extra.xpacSelection;
		if level == 1 then
			local refreshLevel = 1;
			info.text = COLLECTED;
			info.func = function(_, _, _, value)
							filterCollected[1] = value;
							RefreshLists()
							--UIDropDownMenu_Refresh(BetterWardrobeFilterDropDown)
						end
			info.checked = 	function() return filterCollected[1] end
			info.isNotRadio = true;
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = NOT_COLLECTED;
			info.func = function(_, _, _, value)
							filterCollected[2] =  value;
							RefreshLists()
							--UIDropDownMenu_Refresh(BetterWardrobeFilterDropDown)
						end
			info.checked = 	function() return filterCollected[2] end
			info.isNotRadio = true;

			BW_UIDropDownMenu_AddButton(info, level)
			BW_UIDropDownMenu_AddSeparator()

			info.checked = 	true;
			info.isNotRadio = true;
			info.func = function(info, arg1, _, value)
						addon.Profile.ShowHidden = not addon.Profile.ShowHidden;
						RefreshLists()
				end
			info.hasArrow = false;
			info.notCheckable = false;
			info.checked = addon.Profile.ShowHidden;
			info.text = L["Show Hidden Items"]
			info.value = 4;
			BW_UIDropDownMenu_AddButton(info, level)


			info.text = L["Class Sets Only"]
			info.func = function(_, _, _, value)
							addon.Profile.IgnoreClassRestrictions = not addon.Profile.IgnoreClassRestrictions;
							addon.Init:BuildDB()
							BetterWardrobeCollectionFrame.SetsTransmogFrame:UpdateProgressBar()
							RefreshLists()
						end
			info.checked = 	function() return not addon.Profile.IgnoreClassRestrictions end
			info.isNotRadio = true;
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = L["Hide Unavailable Sets"]
			info.func = function(_, _, _, value)
							addon.Profile.HideUnavalableSets = not addon.Profile.HideUnavalableSets;
							addon.Init:BuildDB()
							BetterWardrobeCollectionFrame.SetsTransmogFrame:UpdateProgressBar()
							RefreshLists()
						end
			info.checked = 	function() return not addon.Profile.HideUnavalableSets end
			info.isNotRadio = true;
			BW_UIDropDownMenu_AddButton(info, level)

			info.checked = 	nil;
			info.isNotRadio = nil;
			info.func =  nil;
			info.hasArrow = true;
			info.notCheckable = true;

			info.text = SOURCES;
			info.value = 1;
			info.isNotRadio = true;
			--info.arg1 = self:GetName().."Check"
			--info.func = function(dropdownbutton, arg1)
				--_G[arg1]:Hide()
			--end,
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = L["Expansion"]
			info.value = 2;
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = L["Missing:"]
			info.value = 3;
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = L["Armor Type"]
			info.value = 4;
			BW_UIDropDownMenu_AddButton(info, level)

		elseif level == 2  and BW_UIDROPDOWNMENU_MENU_VALUE == 1 then
			local refreshLevel = 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;
			--tinsert(filterSelection,true)
			info.text = CHECK_ALL;
			info.func = function()
							for i = 1, #filterSelection do
									filterSelection[i] = true;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)

			local refreshLevel = 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;
			--tinsert(filterSelection,true)

			info.text = UNCHECK_ALL;
			info.func = function()
							for i = 1, #filterSelection do
									filterSelection[i] = false;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)
			BW_UIDropDownMenu_AddSeparator(level)

			info.notCheckable = false;

			local numSources = #FILTER_SOURCES --C_TransmogCollection.GetNumTransmogSources()
			for i = 1, numSources do
				--tinsert(filterSelection,true)
				info.text = FILTER_SOURCES[i]
					info.func = function(_, _, _, value)
						filterSelection[i] = value;
						RefreshLists()
					end
					info.checked = 	function() return filterSelection[i] end
				BW_UIDropDownMenu_AddButton(info, level)
			end

		elseif level == 2  and BW_UIDROPDOWNMENU_MENU_VALUE == 2 then
			local refreshLevel = 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;
			info.text = CHECK_ALL;
			info.func = function()
							for i = 1, #xpacSelection do
								xpacSelection[i] = true;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)

			local refreshLevel = 2;
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;

			info.text = UNCHECK_ALL;
			info.func = function()
							for i = 1, #xpacSelection do
									xpacSelection[i] = false;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)
			BW_UIDropDownMenu_AddSeparator(level)

			info.notCheckable = false;
			for i = 1, #EXPANSIONS do
				info.text = EXPANSIONS[i]
					info.func = function(_, _, _, value)
						xpacSelection[i] = value;
						RefreshLists()
					end
					info.checked = 	function() return xpacSelection[i] end
				BW_UIDropDownMenu_AddButton(info, level)
			end

		elseif level == 2  and BW_UIDROPDOWNMENU_MENU_VALUE == 3 then
			info.hasArrow = false;
			info.isNotRadio = true;
			info.notCheckable = true;
			local refreshLevel = 2;

			info.text = CHECK_ALL;
			info.func = function()
							for i in pairs(locationDrowpDown) do
								missingSelection[i] = true;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)

			info.text = UNCHECK_ALL;
			info.func = function()
							for i in pairs(locationDrowpDown) do
								missingSelection[i] = false;
							end
							RefreshLists()
							BW_UIDropDownMenu_Refresh(self)
						end
			BW_UIDropDownMenu_AddButton(info, level)
			BW_UIDropDownMenu_AddSeparator(level)

			for index, id in pairs(locationDrowpDown) do
				if index ~= 21 then --Skip "robe" type;
					info.text = id;
					info.notCheckable = false;
					info.func = function(_, _, _, value)
								missingSelection[index] = value;

								if index == 6 then
									missingSelection[21] = value;
								end

								BW_UIDropDownMenu_Refresh(self)
								RefreshLists()
							end
					info.checked = function() return missingSelection[index] end
					BW_UIDropDownMenu_AddButton(info, level)
				end
			end
		elseif level == 2  and BW_UIDROPDOWNMENU_MENU_VALUE == 4 then
			local counter = 1;
			for name in pairs(addon.Globals.ARMOR_MASK) do
				info.keepShownOnClick = false;
				info.text = L[name]
				info.func = function(info, arg1, _, value)
						addon.selectedArmorType = arg1;
						addon.useAltSet = true;
						RefreshLists()
				end
				info.arg1 = name;
				info.checked = 	function() return addon.selectedArmorType == name end
				BW_UIDropDownMenu_AddButton(info, level)
			end

		end
	end
end

-- ***** SPEC DROPDOWN

function BetterWardrobeTransmogFrameSpecDropDown_OnLoad(self)
	BW_UIDropDownMenu_Initialize(self, BetterWardrobeTransmogFrameSpecDropDown_Initialize, "MENU")
end

function BetterWardrobeTransmogFrameSpecDropDown_Initialize()
	local info = BW_UIDropDownMenu_CreateInfo()

	info.text = TRANSMOG_APPLY_TO;
	info.isTitle = true;
	info.notCheckable = true;
	BW_UIDropDownMenu_AddButton(info, BW_UIDROPDOWNMENU_MENU_LEVEL)

	info = BW_UIDropDownMenu_CreateInfo()

	local currentSpecOnly = GetCVarBool("transmogCurrentSpecOnly")

	info.text = TRANSMOG_ALL_SPECIALIZATIONS;
	info.func = BetterWardrobeTransmogFrameSpecDropDown_OnClick;
	info.checked = not currentSpecOnly;
	info.value = 0;
	BW_UIDropDownMenu_AddButton(info, BW_UIDROPDOWNMENU_MENU_LEVEL)

	-- We do not add a current specialization option if none is set.
	local spec = GetSpecialization()
	if  spec then
		local _, name = GetSpecializationInfo(spec)
		if name and name ~= "" then
			info.text = TRANSMOG_CURRENT_SPECIALIZATION;
			info.func = BetterWardrobeTransmogFrameSpecDropDown_OnClick;
			info.checked = currentSpecOnly;
			info.value = 1;
			BW_UIDropDownMenu_AddButton(info, BW_UIDROPDOWNMENU_MENU_LEVEL)

			info.text = format(PARENS_TEMPLATE, name or "")
			info.leftPadding = 16;
			info.notCheckable = true;
			info.notClickable = true;
			BW_UIDropDownMenu_AddButton(info, BW_UIDROPDOWNMENU_MENU_LEVEL)
		end
	end
end

function BetterWardrobeTransmogFrameSpecDropDown_OnClick(self)
	SetCVar("transmogCurrentSpecOnly", self.value == 1)
end

-- ************************************************************************************************************************************************************
-- **** SETS LIST *********************************************************************************************************************************************
-- ************************************************************************************************************************************************************

local BASE_SET_BUTTON_HEIGHT = 46;
local VARIANT_SET_BUTTON_HEIGHT = 20;
local SET_PROGRESS_BAR_MAX_WIDTH = 204;
local IN_PROGRESS_FONT_COLOR = CreateColor(0.251, 0.753, 0.251)
local IN_PROGRESS_FONT_COLOR_CODE = "|cff40c040"

BetterWardrobeSetsDataProviderMixin = {}

function BetterWardrobeSetsDataProviderMixin:SortSets(sets, reverseUIOrder, ignorePatchID)
	addon.SortSet(sets, reverseUIOrder, ignorePatchID)
--[[if true then return end
	local comparison = function(set1, set2)
		local groupFavorite1 = set1.favoriteSetID and true;
		local groupFavorite2 = set2.favoriteSetID and true;
		if ( groupFavorite1 ~= groupFavorite2 ) then
			return groupFavorite1;
		end
		if ( set1.favorite ~= set2.favorite ) then
			return set1.favorite;
		end
		if ( set1.expansionID ~= set2.expansionID ) then
			return set1.expansionID > set2.expansionID;
		end
		if not ignorePatchID then
			if ( set1.patchID ~= set2.patchID ) then
				return set1.patchID > set2.patchID;
			end
		end
		if ( set1.uiOrder ~= set2.uiOrder ) then
			if ( reverseUIOrder ) then
				return set1.uiOrder < set2.uiOrder;
			else
				return set1.uiOrder > set2.uiOrder;
			end
		end
		if reverseUIOrder then
			return set1.setID < set2.setID;
		else
			return set1.setID > set2.setID;
		end
	end

	table.sort(sets, comparison);]]
end

local function CheckMissingLocation(setInfo)
	local filtered = false;
	local missingSelection 
	if 	BetterWardrobeCollectionFrame:CheckTab(2) then
	
		local invType = {}
	missingSelection = addon.Filters.Base.missingSelection;
	local sources = C_TransmogSets.GetSetSources(setInfo.setID)
if not sources then return end
		for sourceID in pairs(sources) do
			local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
			local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceInfo.visualID)	
			local sources = sourceInfo and itemLink and C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID, addon.GetItemCategory(sourceInfo.visualID), addon.GetTransmogLocation(itemLink))
			if sources then
				if #sources > 1 then
					CollectionWardrobeUtil.SortSources(sources, sourceInfo.visualID, sourceID)
				end
				if  missingSelection[sourceInfo.invType] and not sources[1].isCollected then

					return true;
				elseif missingSelection[sourceInfo.invType] then 
					filtered = true;
				end
			end
		end

	for type, value in pairs(missingSelection) do
		if value and invType[type] then
			filtered = true;
		end
	end
else
	 missingSelection = addon.Filters.Extra.missingSelection;


	for type, value in pairs(missingSelection) do
		if value then
			filtered = true;
			break;
		end
	end
	--no need to filter if nothing is selected;
	if not filtered then return true end
	
	local invType = {}
	if not setInfo.items then
		local sources = C_TransmogSets.GetSetSources(setInfo.setID)
		for sourceID in pairs(sources) do
			local isCollected = Sets.isMogKnown(sourceID) 
			if missingSelection[sourceInfo.invType] and not isCollected then		
				return true;
			elseif missingSelection[sourceInfo.invType] then 
				filtered = true;
			end
		end
	else
		local setSources = addon.GetSetsources(setInfo.setID)
		for sourceID, isCollected in pairs(setSources) do
			local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
			if missingSelection[sourceInfo.invType] and not isCollected then
				return true;
			elseif missingSelection[sourceInfo.invType] then 
				filtered = true 
			end
		end
	end

	for type, value in pairs(missingSelection) do
		if value and invType[type] then
			filtered = true;
		end
	end
end
	return not filtered;
end

function BetterWardrobeSetsDataProviderMixin:GetBaseSets(filter)
	local filteredSets = {}
	local useBaseSet = not  C_Transmog.IsAtTransmogNPC()
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()
	local searchString = string.lower(WardrobeCollectionFrameSearchBox:GetText())
	local basesets = {}

	if 	BetterWardrobeCollectionFrame:CheckTab(2) then
		basesets = self.baseSets;
		if ( not self.baseSets ) then
			self.baseSets = C_TransmogSets.GetBaseSets()
			--if not atTransmogrifier then 
				self.baseSets = addon:FilterSets(self.baseSets)
			--else

			--end
			self:DetermineFavorites()
			self:SortSets(self.baseSets)
		end
		return self.baseSets;

	elseif 	BetterWardrobeCollectionFrame:CheckTab(3) then
		basesets = self.baseExtraSets;
		--if not self.baseExtraSets then 
			if addon.useAltSet then
				addon.refreshData = true;
				self.baseExtraSets = addon.GetBaseList()
			else
				self.baseExtraSets = addon.GetBaseList()
			end

			--if not atTransmogrifier then
				self.baseExtraSets = addon:FilterSets(self.baseExtraSets)
			--end
			self:SortSets(self.baseExtraSets)
		--ZSend
		return self.baseExtraSets;

	elseif 	BetterWardrobeCollectionFrame:CheckTab(4) then
		basesets = self.baseSavedSets;
		if not self.baseSavedSets then 
			self.baseSavedSets = addon.GetSavedList()
			self:SortSets(self.baseSavedSets)

		end
		return self.baseSavedSets;
	end

	return {}
end

function BetterWardrobeSetsDataProviderMixin:GetBaseSetByID(baseSetID)
	local baseSets = self:GetBaseSets()
	for i = 1, #baseSets do
		if ( baseSets[i].setID == baseSetID ) then
			return baseSets[i], i;
		end
	end
	return nil, nil;
end

local buildUseable = false;
function BetterWardrobeSetsDataProviderMixin:GetUsableSets(incVariants)
	
		local atTransmogrifier = C_Transmog.IsAtTransmogNPC()
		local setIDS = {}
		local Profile = addon.Profile;
		if (BetterWardrobeCollectionFrame:CheckTab(2)) then
			if ( not self.usableSets ) then
				if not Profile.ShowIncomplete  then 
					self.usableSets = C_TransmogSets.GetUsableSets()
					self:SortSets(self.usableSets)
					-- group sets by baseSetID, except for favorited sets since those are to remain bucketed to the front
					for i, set in ipairs(self.usableSets) do
						if ( not set.favorite ) then
							local baseSetID = set.baseSetID or set.setID;
							local numRelatedSets = 0;
							for j = i + 1, #self.usableSets do
								if ( self.usableSets[j].baseSetID == baseSetID or self.usableSets[j].setID == baseSetID ) then
									numRelatedSets = numRelatedSets + 1;
									-- no need to do anything if already contiguous
									if ( j ~= i + numRelatedSets ) then
										local relatedSet = self.usableSets[j]
										tremove(self.usableSets, j)
										tinsert(self.usableSets, i + numRelatedSets, relatedSet)
									end
								end
							end
						end
					end

				elseif Profile.ShowIncomplete or BetterWardrobeVisualToggle.VisualMode then
					self.usableSets = {}
					local availableSets = self:GetBaseSets(BetterWardrobeCollectionFrame:CheckTab(2) )
					for i, set in ipairs(availableSets) do
						--if not setIDS[set.setID or set.baseSetID] then 
							local topSourcesCollected, topSourcesTotal = addon.Sets:GetLocationBasedCount(set) --SetsDataProvider:GetSetSourceCounts(set.setID)
							local cutoffLimit = (topSourcesTotal <= Profile.PartialLimit and topSourcesTotal and topSourcesTotal) and topSourcesTotal or Profile.PartialLimit --SetsDataProvider:GetSetSourceCounts(set.setID)
							--Show complete sets even if they are below the cut off
							if topSourcesCollected == topSourcesTotal then
								cutoffLimit = topSourcesTotal
							end

							if ((not atTransmogrifier and BetterWardrobeVisualToggle.VisualMode) or topSourcesCollected >= cutoffLimit and topSourcesTotal > 0 ) then --and not C_TransmogSets.IsSetUsable(set.setID) then
							--if (BetterWardrobeVisualToggle.viewAll and BetterWardrobeVisualToggle.VisualMode) or (not atTransmogrifier and BetterWardrobeVisualToggle.VisualMode) or topSourcesCollected >= cutoffLimit  and topSourcesTotal > 0 then --and not C_TransmogSets.IsSetUsable(set.setID) then

								
								tinsert(self.usableSets, set)
							end
						--end

						if incVariants then 
							local variantSets = C_TransmogSets.GetVariantSets(set.setID)
							if variantSets then 
								for i, set in ipairs(variantSets) do
									--if not setIDS[set.setID or set.baseSetID] then 

										local topSourcesCollected, topSourcesTotal = addon.Sets:GetLocationBasedCount(set)--SetsDataProvider:GetSetSourceCounts(set.setID)
										--if topSourcesCollected == topSourcesTotal then set.collected = true end
										if ((not atTransmogrifier and BetterWardrobeVisualToggle.VisualMode) or set.collected or (not set.collected and (topSourcesCollected >= Profile.PartialLimit and topSourcesTotal > 0)))  then --and not C_TransmogSets.IsSetUsable(set.setID) then
											tinsert(self.usableSets, set)
										end
									--end
									
								end
							end
						end
					end
				end

				self.usableSets = addon:SearchSets(self.usableSets)
				self:SortSets(self.usableSets)

			end
			
			return self.usableSets;

		elseif BetterWardrobeCollectionFrame:CheckTab(3) then
			if ( not self.usableExtraSets ) then

				--Generates Useable Set;
				local availableSets = self:GetBaseSets(false)
				local countData;
				self.usableExtraSets = {} --BetterWardrobeSetsDataProviderMixin:GetUsableSets()
				for i, set in ipairs(availableSets) do
					local topSourcesCollected, topSourcesTotal;
					topSourcesCollected, topSourcesTotal = self:GetSetSourceCounts(set.setID)

					local cutoffLimit = (Profile.ShowIncomplete and ((topSourcesTotal <= Profile.PartialLimit and topSourcesTotal) or  Profile.PartialLimit)) or topSourcesTotal --self:GetSetSourceCounts(set.setID)
					if (BetterWardrobeVisualToggle.viewAll and BetterWardrobeVisualToggle.VisualMode) or (not atTransmogrifier and BetterWardrobeVisualToggle.VisualMode) or topSourcesCollected >= cutoffLimit  and topSourcesTotal > 0 then --and not C_TransmogSets.IsSetUsable(set.setID) then
						tinsert(self.usableExtraSets, set)
					end

					--[[if incVariants then
																local variantSets = C_TransmogSets.GetVariantSets(set.setID)
																for i, set in ipairs(variantSets) do
																	local topSourcesCollected, topSourcesTotal;
																	if Profile.ShowIncomplete then
																		topSourcesCollected, topSourcesTotal = addon.Sets:GetLocationBasedCount(set)
										
																	else
																		topSourcesCollected, topSourcesTotal = BetterWardrobeSetsDataProviderMixin:GetSetSourceCounts(set.setID)
																	end
										
																	if topSourcesCollected == topSourcesTotal then set.collected = true end
																	--local cutoffLimit = (topSourcesTotal <= Profile.PartialLimit and topSourcesTotal) or Profile.PartialLimit;
																--	if (BetterWardrobeVisualToggle.viewAll and BetterWardrobeVisualToggle.VisualMode) or (not atTransmogrifier and BetterWardrobeVisualToggle.VisualMode) or topSourcesCollected >= cutoffLimit and topSourcesTotal > 0   then --and not C_TransmogSets.IsSetUsable(set.setID) then
																		tinsert(self.usableExtraSets, set)
																	--end
																end
															end]]

				end
				self.usableExtraSets = addon:SearchSets(self.usableExtraSets)
				self:SortSets(self.usableExtraSets)
			end
				
			
			return self.usableExtraSets;
		elseif BetterWardrobeCollectionFrame:CheckTab(4) then
			if ( not self.usableSavedSets ) then
				self.usableSavedSets = addon.GetSavedList()
				self:SortSets(self.usableSavedSets)
			end
			
			return self.usableSavedSets;
		end
		return {}
end

function BetterWardrobeSetsDataProviderMixin:GetVariantSets(baseSetID)
	if ( not self.variantSets ) then
		self.variantSets = { }
	end

	local variantSets = self.variantSets[baseSetID]
	if ( not variantSets and baseSetID) then
		variantSets = C_TransmogSets.GetVariantSets(baseSetID) or {}
		self.variantSets[baseSetID] = variantSets;
		if ( #variantSets > 0 ) then
			-- add base to variants and sort
			local baseSet = self:GetBaseSetByID(baseSetID)
			if ( baseSet ) then
				tinsert(variantSets, baseSet)
			end
			local reverseUIOrder = true;
			local ignorePatchID = true;
			addon.SortVariantSet(variantSets, reverseUIOrder, ignorePatchID)
		end
	end
	return variantSets;
end

 
function BetterWardrobeSetsDataProviderMixin:GetSetSourceData(setID)
	if ( not self.sourceData ) then
		self.sourceData = { }
	end

	if ( not self.sourceExtraData ) then
		self.sourceExtraData = { }
	end

	local setType = addon.GetSetType(setID)
	if (setType == nil or setType == "BlizzardSet") then
		--	sourceData = addon:CheckForExtraItems(setID, sourceData)
		local sourceData = self.sourceData[setID]
		if ( not sourceData ) then
			local primaryAppearances = C_TransmogSets.GetSetPrimaryAppearances(setID)
			primaryAppearances = addon:CheckForExtraItems(setID, primaryAppearances)
			local numCollected = 0;
			local numTotal = 0;
			local sources = {}
			for i, primaryAppearance in ipairs(primaryAppearances) do
				sources[primaryAppearance.appearanceID] = true;
				if primaryAppearance.collected then
					numCollected = numCollected + 1;
				end
				numTotal = numTotal + 1;
			end
			sourceData = { numCollected = numCollected, numTotal = numTotal, sources = sources, primaryAppearances = primaryAppearances }
			self.sourceData[setID] = sourceData;
		end

		return sourceData

	else
		local sourceExtraData = self.sourceExtraData[setID]
		if ( not sourceExtraData ) then
			local sources, unavailable = addon.GetSetsources(setID)
			local numCollected = 0;
			local numTotal = 0;
			if sources  then
				for sourceID, collected in pairs(sources) do
					if (collected) then
						numCollected = numCollected + 1;
					end
					numTotal = numTotal + 1;
				end
				sourceExtraData = { numCollected = numCollected, numTotal = numTotal, sources = sources, unavailable = unavailable }
				self.sourceExtraData[setID] = sourceExtraData
			end
		end
		return sourceExtraData;
	
	end
end

function BetterWardrobeSetsDataProviderMixin:GetSetSourceCounts(setID)
	local sourceData = self:GetSetSourceData(setID);
	if sourceData then 
		return sourceData.numCollected, sourceData.numTotal;
	else
		return 0,0;
	end
end

function BetterWardrobeSetsDataProviderMixin:GetBaseSetData(setID)
	if not setID then return {} end
	if ( not self.baseSetsData ) then
		self.baseSetsData = { }
	end

	if ( not self.baseExtraSetsData ) then
		self.baseExtraSetsData = { }
	end
	
	local setType = addon.GetSetType(setID)
	if (setType == nil or setType == "BlizzardSet") then
		if ( not self.baseSetsData[setID] ) then
			local baseSetID = C_TransmogSets.GetBaseSetID(setID)
			if ( baseSetID ~= setID ) then
				return;
			end
			local topCollected, topTotal = self:GetSetSourceCounts(setID)
			local variantSets = self:GetVariantSets(setID)
			for i = 1, #variantSets do
				local numCollected, numTotal = self:GetSetSourceCounts(variantSets[i].setID)
				if ( numCollected > topCollected ) then
					topCollected = numCollected;
					topTotal = numTotal;
				end
			end
			local setInfo = { topCollected = topCollected, topTotal = topTotal, completed = (topCollected == topTotal) }
			self.baseSetsData[setID] = setInfo;
		end
		return self.baseSetsData[setID]

	else	
		if ( not self.baseExtraSetsData[setID] ) then
			local baseSetID = setID;
			if (baseSetID ~= setID) then
				return;
			end
			local topCollected, topTotal = self:GetSetSourceCounts(setID)
			local setInfo = {topCollected = topCollected, topTotal = topTotal, completed = (topCollected == topTotal) }
			self.baseExtraSetsData[setID] = setInfo;
		end
		return self.baseExtraSetsData[setID]
	end
	return {}
end

local setsByExpansion = {}
local setsByFilter = {}
local filterinprogress = false;
function BetterWardrobeSetsDataProviderMixin:GetSetSourceTopCounts(setID)
	local baseSetData = self:GetBaseSetData(setID)
	if ( baseSetData ) then
		return baseSetData.topCollected, baseSetData.topTotal;
	else
		return self:GetSetSourceCounts(setID)
	end
end



----TODO REVISIT;
function BetterWardrobeSetsDataProviderMixin:IsBaseSetNew(baseSetID)
	local baseSetData = {}
	--if not baseSetData then print(1) return false end

	if BetterWardrobeCollectionFrame:CheckTab(2) then
		baseSetData = self:GetBaseSetData(baseSetID)

		if ( not baseSetData.newStatus ) then
			local newStatus = C_TransmogSets.SetHasNewSources(baseSetID)
			if ( not newStatus ) then
				-- check variants
				local variantSets = self:GetVariantSets(baseSetID)
				for i, variantSet in ipairs(variantSets) do
					if ( C_TransmogSets.SetHasNewSources(variantSet.setID) ) then
						newStatus = true;
						break;
					end
				end
			end
			baseSetData.newStatus = newStatus;
		end
	else
		----elseif BetterWardrobeCollectionFrame:CheckTab(3) then
			local newStatus = addon.C_TransmogSets.SetHasNewSources(baseSetID)
			baseSetData.newStatus = newStatus;
	end

	return baseSetData.newStatus;
end

function BetterWardrobeSetsDataProviderMixin:ResetBaseSetNewStatus(baseSetID)
	local baseSetData = self:GetBaseSetData(baseSetID)
	if ( baseSetData ) then
		baseSetData.newStatus = nil;
	end
end

local classGlobal = strsplit(" ", ITEM_CLASSES_ALLOWED)
local ClassSetCache = {}
local function CheckClass(itemLink)
	local itemID = GetItemInfoInstant(itemLink) 
	if not ClassSetCache[itemID] then
		--Calls twice since the first time usually does not contain actual data
		local tooltipData = C_TooltipInfo.GetHyperlink(itemLink) 
		tooltipData = C_TooltipInfo.GetHyperlink(itemLink) 

		TooltipUtil.SurfaceArgs(tooltipData)

		for _, line in ipairs(tooltipData.lines) do
			TooltipUtil.SurfaceArgs(line)
		end

		for i=1,#tooltipData.lines do  
			local text = tooltipData.lines[i].leftText
			if text and string.find(text, classGlobal) and not string.find(text, playerClassName) then
				ClassSetCache[itemID] = false
				break
			elseif text and string.find(text, classGlobal) and string.find(text, playerClassName) then
 				ClassSetCache[itemID] = true
 				break
			end
		end

		ClassSetCache[itemID] = true
	end

	return ClassSetCache[itemID]
end




local function GetCombinedAppearanceSources(appearanceID)
	local categoryID, visualID, canEnchant, icon, isCollected, itemLink, transmogLink, unknown1, itemSubTypeIndex = C_TransmogCollection.GetAppearanceSourceInfo(appearanceID)
	local sources = C_TransmogCollection.GetAllAppearanceSources(appearanceID) or {}

	local sources2 = (appearanceID and itemLink and C_TransmogCollection.GetAppearanceSources(appearanceID, addon.GetItemCategory(appearanceID), addon.GetTransmogLocation(itemLink)) )or {}

	if (sources2 and sources) then
	  for i = 1, #sources2 do
		local addTosources = true;
		for j = 1, #sources do
		  if sources2[i].sourceID == sources[j] then
			addTosources = false;
			break;
		  end
		end
		if addTosources then
		  table.insert(sources, sources2[i].sourceID)
		end
	  end
	elseif sources2 and not sources then
	  sources = sources2;
	end

	return sources;
end

local function CheckCollectionStatus(sources)
	if not sources then return false, false end
	local characterCollectable = false;
	local characterUseable = false;

	for _,sourceID in pairs(sources) do
		local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
		
		local link = select(6, C_TransmogCollection.GetAppearanceSourceInfo(sourceInfo.sourceID))
		local classSet = CheckClass(link)
		
		if not characterCollectable and classSet then
			characterCollectable = true;
		end

		if not characterUseable and classSet and sourceInfo.isCollected then
			characterUseable = true;
		end
		
		if sourceInfo.isCollected and characterCollectable and characterUseable then
			break;
		end
	end

	return characterCollectable, characterUseable;
end

function BetterWardrobeSetsDataProviderMixin:GetSortedSetSources(setID)
	local returnTable = { }

	local sourceData = self:GetSetSourceData(setID)
	local setType = addon.GetSetType(setID)





	if (setType == nil or setType == "BlizzardSet")  then
	--if BetterWardrobeCollectionFrame:CheckTab(2) then
		for i, primaryAppearance in ipairs(sourceData.primaryAppearances) do
			local sourceID = primaryAppearance.appearanceID;
			local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
			local sources = (sourceInfo and GetCombinedAppearanceSources(sourceInfo.visualID)) or {}
			local characterCollectable, characterUseable = CheckCollectionStatus(sources)

			if ( sourceInfo ) then
				local sortOrder = EJ_GetInvTypeSortOrder(sourceInfo.invType)
				tinsert(returnTable, { sourceID = sourceID, collected = primaryAppearance.collected, sortOrder = sortOrder, itemID = sourceInfo.itemID, invType = sourceInfo.invType, characterUseable = characterUseable, characterCollectable = characterCollectable })
			end
		end


	else
	----elseif BetterWardrobeCollectionFrame:CheckTab(3) then
		for sourceID, collected in pairs(sourceData.sources) do
			local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
			local sources = (sourceInfo and GetCombinedAppearanceSources(sourceInfo.visualID)) or {}
			local characterCollectable, characterUseable = CheckCollectionStatus(sources)

			if (sourceInfo) then
				local sortOrder = EJ_GetInvTypeSortOrder(sourceInfo.invType)
				tinsert(returnTable, {sourceID = sourceID, collected = collected, sortOrder = sortOrder, itemID = sourceInfo.itemID, invType = sourceInfo.invType, visualID = sourceInfo.visualID, characterUseable = characterUseable, characterCollectable = characterCollectable  })
			end
		end
	end

	local comparison = function(entry1, entry2)
		if ( entry1.sortOrder == entry2.sortOrder ) then
			return entry1.itemID < entry2.itemID;
		else
			return entry1.sortOrder < entry2.sortOrder;
		end
	end

	table.sort(returnTable, comparison)
	return returnTable;
end

function BetterWardrobeSetsDataProviderMixin:ClearSets()
	self.baseSets = nil;
	self.baseExtraSets = nil;
	self.baseSavedSets = nil;
	self.baseSetsData = nil;
	self.baseExtraSetsData = nil;
	self.variantSets = nil;
	self.usableSets = nil;
	self.usableExtraSets = nil;
	self.usableSavedSets = nil;

	self.sourceData = nil;
	self.sourceExtraData = nil;
end


function BetterWardrobeSetsDataProviderMixin:ClearBaseSets()
	self.baseSets = nil;
	self.baseExtraSets = nil;
	self.baseSavedSets = nil;
end

function BetterWardrobeSetsDataProviderMixin:ClearVariantSets()
	self.variantSets = nil;
end

function BetterWardrobeSetsDataProviderMixin:ClearUsableSets()
	self.usableSets = nil;
	self.usableExtraSets = nil;
	self.usableSavedSets = nil;
end

function BetterWardrobeSetsDataProviderMixin:GetIconForSet(setID)
	local sourceData = self:GetSetSourceData(setID)
	if ( not sourceData.icon ) then
		local sortedSources = self:GetSortedSetSources(setID)
		if ( sortedSources[1] ) then
			local _, _, _, _, icon = GetItemInfoInstant(sortedSources[1].itemID)
			sourceData.icon = icon;
		else
			sourceData.icon = QUESTION_MARK_ICON;
		end
	end
	return sourceData.icon;
end

function BetterWardrobeSetsDataProviderMixin:DetermineFavorites()
	-- if a variant is favorited, so is the base set
	-- keep track of which set is favorited
	local baseSets = self:GetBaseSets()
	for i = 1, #baseSets do
		local baseSet = baseSets[i]
		baseSet.favoriteSetID = nil;
		if ( baseSet.favorite ) then
			baseSet.favoriteSetID = baseSet.setID;
		else
			local variantSets = self:GetVariantSets(baseSet.setID)
			for j = 1, #variantSets do
				if ( variantSets[j].favorite ) then
					baseSet.favoriteSetID = variantSets[j].setID;
					break;
				end
			end
		end
	end
end

function BetterWardrobeSetsDataProviderMixin:RefreshFavorites()
	self.baseSets = nil;
	self.baseExtraSets = nil;
	self.baseSavedSets = nil;
	self.variantSets = nil;
	self:DetermineFavorites()
end

local SetsDataProvider = CreateFromMixins(BetterWardrobeSetsDataProviderMixin)
addon.SetsDataProvider = SetsDataProvider;

function addon.GetSetSourceCounts(setID) 
	if not setID then return 0,0 end
	local sourceData = SetsDataProvider:GetSetSourceData(setID)
	return sourceData.numCollected, sourceData.numTotal;
end


BetterWardrobeSetsCollectionMixin = {}

function BetterWardrobeSetsCollectionMixin:OnLoad()
	self.RightInset.BGCornerTopLeft:Hide()
	self.RightInset.BGCornerTopRight:Hide()

	self.DetailsFrame.itemFramesPool = CreateFramePool("FRAME", self.DetailsFrame, "BetterWardrobeSetsDetailsItemFrameTemplate")

	self.selectedVariantSets = { }
end

function addon:BW_TRANSMOG_COLLECTION_UPDATED()
		--SetsDataProvider:ClearSets()
		--WardrobeCollectionFrameScrollFrame:Refresh()
		--WardrobeCollectionFrameScrollFrame:UpdateProgressBar()
		--WardrobeCollectionFrameScrollFrame:ClearLatestSource()
		C_Timer.After(0, function() RefreshLists() end)

end

function BetterWardrobeSetsCollectionMixin:OnShow()
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	addon:RegisterMessage("BW_TRANSMOG_COLLECTION_UPDATED")
	-- select the first set if not init
	local baseSets = SetsDataProvider:GetBaseSets();
	local defaultSetID = baseSets and baseSets[1] and self:GetDefaultSetIDForBaseSet(baseSets[1].setID) or nil;
	if ( not self.init ) then
		self.init = true;
		if ( defaultSetID ) then
			self.ListContainer:UpdateDataProvider();
			self:SelectSet(defaultSetID);
		end

		local extraSets = addon.GetBaseList();
		SetsDataProvider:SortSets(extraSets);

		local savedSets = addon.GetSavedList();
		if ( baseSets and baseSets[1] ) then
			----self:SelectSet(defaultSetID); --Todo check;
			self.selectedSetID = baseSets[1].setID;
		end
		if ( extraSets and extraSets[1] ) then
			self.selectedExtraSetID = extraSets[1].setID;

		end
		if ( savedSets and savedSets[1] ) then
			self.selectedSavedSetID = savedSets[1].setID;
		end
	else
		local selectedSetID = self:GetSelectedSetID()
		if ( not selectedSetID or not C_TransmogSets.IsSetVisible(selectedSetID) ) then
			self:SelectSet(defaultSetID);
		end
		self:Refresh();
	end

	if BetterWardrobeCollectionFrame:CheckTab(2) then
		local latestSource = C_TransmogSets.GetLatestSource();
		if ( latestSource ~= Constants.Transmog.NoTransmogID ) then
			local sets = C_TransmogSets.GetSetsContainingSourceID(latestSource);
			local setID = sets and sets[1];
			if ( setID ) then
				self:SelectSet(setID);
				local baseSetID = C_TransmogSets.GetBaseSetID(setID);
				self:ScrollToSet(baseSetID, ScrollBoxConstants.AlignCenter);
			end
			self:ClearLatestSource();
		end
	else
		local latestSource = newTransmogInfo["latestSource"]

		if (latestSource ~= NO_TRANSMOG_SOURCE_ID) then
			self:SelectSet(latestSource)
			self:ScrollToSet(latestSource)
			self:ClearLatestSource()
		end
	end

	BetterWardrobeCollectionFrame.progressBar:Show()

	self:UpdateProgressBar()
	self:RefreshCameras()

	--if HelpTip:IsShowing(BetterWardrobeCollectionFrame, TRANSMOG_SETS_TAB_TUTORIAL) then
		--HelpTip:Hide(BetterWardrobeCollectionFrame, TRANSMOG_SETS_TAB_TUTORIAL)
		--SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SETS_TAB, true)
	--end
end

function BetterWardrobeSetsCollectionMixin:OnHide()
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	self:UnregisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED")
	addon:UnregisterMessage("BW_TRANSMOG_COLLECTION_UPDATED")
	SetsDataProvider:ClearSets()
	self:GetParent():ClearSearch(Enum.TransmogSearchType.BaseSets)
end



function BetterWardrobeSetsCollectionMixin:OnEvent(event, ...)
	if ( event == "GET_ITEM_INFO_RECEIVED" ) then
		local itemID = ...
		for itemFrame in self.DetailsFrame.itemFramesPool:EnumerateActive() do
			if ( itemFrame.itemID == itemID ) then
				self:SetItemFrameQuality(itemFrame)
				break;
			end
		end
	elseif ( event == "TRANSMOG_COLLECTION_ITEM_UPDATE" ) then
		for itemFrame in self.DetailsFrame.itemFramesPool:EnumerateActive() do
			self:SetItemFrameQuality(itemFrame)
		end
	elseif ( event == "TRANSMOG_COLLECTION_UPDATED" ) then
		SetsDataProvider:ClearSets()
		self:Refresh()
		self:UpdateProgressBar()
		self:ClearLatestSource()
	end
end

function addon.SetHasNewSourcesForSlot(setID, transmogSlot)
	if not  newTransmogInfo[setID] then return false end
	for itemID, location in pairs(newTransmogInfo[setID]) do
		if location  == transmogSlot then 
			return true;
		end	
	end
	return false;
end 


function addon.SetHasNewSources(setID)
	if not  newTransmogInfo[setID] then return false end

	return true;

end 

function addon.ClearSetNewSourcesForSlot(setID, transmogSlot)
	if not  newTransmogInfo[setID] then return end
	local count = 0;
	for itemID, location in pairs(newTransmogInfo[setID]) do
		count = count + 1;
		if location  == transmogSlot then 
			newTransmogInfo[setID][itemID] = nil;
			count = count - 1;
		end
	end

	if count <= 0 then 
		newTransmogInfo[setID] = nil;
		SetsDataProvider:ResetBaseSetNewStatus(setID)
	end
end


function addon.GetSetNewSources(setID)
	local sources = {}
	if not  newTransmogInfo[setID] then return sources end

	for itemID in pairs(newTransmogInfo[setID]) do
		local _, soucre = C_TransmogCollection.GetItemInfo(itemID)
		tinsert(sources, source)
	end
	return sources;
end

function BetterWardrobeSetsCollectionMixin:UpdateProgressBar()
	self:GetParent():UpdateProgressBar(addon.C_TransmogSets.GetBaseSetsCounts())
end

function BetterWardrobeSetsCollectionMixin:ClearLatestSource()
	if BetterWardrobeCollectionFrame:CheckTab(2) then
		C_TransmogSets.ClearLatestSource()
	elseif BetterWardrobeCollectionFrame:CheckTab(3) then
		newTransmogInfo["latestSource"] = NO_TRANSMOG_SOURCE_ID;

	end

	BetterWardrobeCollectionFrame:UpdateTabButtons()
end

function BetterWardrobeSetsCollectionMixin:Refresh()
	self.ListContainer:UpdateDataProvider()
	if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then
		self:DisplaySet(self.selectedSetID)
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
		self:DisplaySet(self.selectedExtraSetID)
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 4 then
		self:DisplaySet(self.selectedSavedSetID)

	end
end

local function isAvailableItem(sourceID,setID)
	local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)	
	local sources = (sourceID and itemLink and C_TransmogCollection.GetAppearanceSources(sourceID, addon.GetItemCategory(sourceID), addon.GetTransmogLocation(itemLink)) ) or {} --Can return nil if no longer in game;
 
	if (#sources == 0) then
		local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
		local setInfo = addon.GetSetInfo(setID)
		if not sourceInfo.sourceType then 
			return false;
		end
	end
	return true;
end

function BetterWardrobeSetsCollectionMixin:DisplaySet(setID)
	if not setID then return end
	local setInfo = addon.C_TransmogSets.GetSetInfo(setID) 
	local buildID = (select(4, GetBuildInfo())) or nil;
	if ( not setInfo ) then
		self.DetailsFrame:Hide()
		self.Model:Hide()
		return;
	else
		self.DetailsFrame:Show()
		self.Model:Show()
	end

	self.Model:SetUnit("player", false, PlayerUtil.ShouldUseNativeFormInModelScene());

	local _, raceFile = UnitRace("player");
	if (raceFile == "Dracthyr" or raceFile == "Worgen")  then
		local inNativeForm = C_UnitAuras.WantsAlteredForm("player");

		local _, raceFilename = UnitRace("player");
		local sex = UnitSex("player") 
		if (raceFilename == "Dracthyr" or raceFilename == "Worgen") then
			local inNativeForm = C_UnitAuras.WantsAlteredForm("player");
			--self:SetUseTransmogSkin(false)
				local modelID, altModelID
				if raceFilename == "Worgen" then
					if sex == 3 then
						modelID = 307453
						altModelID = 1000764
					else
						modelID = 307454
						altModelID = 1011653
					end
				elseif raceFilename == "Dracthyr" then
					if sex == 3 then
						modelID = 4207724
						altModelID = 4220448
					else
						modelID = 4207724
						altModelID = 4395382
					end
				end

			if inNativeForm and not addon.useNativeForm then
				self.Model:SetUnit("player", false, false)
				self.Model:SetModel(altModelID)

			elseif not inNativeForm and addon.useNativeForm then
				self.Model:SetUnit("player", false, true)
				self.Model:SetModel( modelID )
			end
		end
	end
	self.DetailsFrame.BW_LinkSetButton.setID = setID;

	self.DetailsFrame.Name:SetText(setInfo.name)
	if ( self.DetailsFrame.Name:IsTruncated() ) then
		self.DetailsFrame.Name:Hide()
		self.DetailsFrame.LongName:SetText(setInfo.name)
		self.DetailsFrame.LongName:Show()
	else
		self.DetailsFrame.Name:Show()
		self.DetailsFrame.LongName:Hide()
	end

	self.DetailsFrame.Label:SetText((setInfo.label or "")..((not setInfo.isClass and setInfo.className) and " -"..setInfo.className.."-" or "") )
	--self.DetailsFrame.LimitedSet:SetShown(setInfo.limitedTimeSet)

	if ((setInfo.description == ELITE) and setInfo.patchID < buildID) or (setID <= 1446 and setID >=1436) then
		setInfo.noLongerObtainable = true;
		setInfo.limitedTimeSet = nil;
	end

	if setInfo.limitedTimeSet then
		self.DetailsFrame.LimitedSet.Text:SetText(TRANSMOG_SET_LIMITED_TIME_SET)
		self.DetailsFrame.LimitedSet:Show()

		--self.DetailsFrame.LimitedSet.Text:SetText(TRANSMOG_SET_LIMITED_TIME_SET)--factionNames.opposingFaction)--.." only")
	elseif setInfo.noLongerObtainable then
		self.DetailsFrame.LimitedSet.Icon:SetAtlas("transmog-icon-remove")
		self.DetailsFrame.LimitedSet.Text:SetText(L["No Longer Obtainable"])
		self.DetailsFrame.LimitedSet:Show()
	else
		self.DetailsFrame.LimitedSet:Hide()
	end

	local newSourceIDs = C_TransmogSets.GetSetNewSources(setID) or addon.GetSetNewSources(setID)

	self.DetailsFrame.itemFramesPool:ReleaseAll()
	self.Model:Undress()
	local BUTTON_SPACE = 37;	-- button width + spacing between 2 buttons
	local sortedSources = SetsDataProvider:GetSortedSetSources(setID)


	--local xOffset = -floor((#sortedSources - 1) * BUTTON_SPACE / 2)

	local row1 = #sortedSources;
	local row2 = 0;
	local yOffset1 = -94;
	if row1 > 10 then
		row2 = row1 - 10;
		row1 = 10;
		yOffset1 = -74;
	end
	local xOffset = -floor((row1 - 1) * BUTTON_SPACE / 2)
	local xOffset2 = -floor((row2 - 1) * BUTTON_SPACE / 2)

	local yOffset2 = yOffset1 - 40;
	local move = (#sortedSources > 10)

	self.DetailsFrame.IconRowBackground:ClearAllPoints()
	self.DetailsFrame.IconRowBackground:SetPoint("TOP", 0, move and -50 or -78)
	self.DetailsFrame.IconRowBackground:SetHeight(move and 120 or 64)
	self.DetailsFrame.Name:ClearAllPoints()
	self.DetailsFrame.Name:SetPoint("TOP", 0,  move and -17 or -37)
	self.DetailsFrame.LongName:ClearAllPoints()
	self.DetailsFrame.LongName:SetPoint("TOP", 0, move and -10 or -30)
	self.DetailsFrame.Label:ClearAllPoints()
	self.DetailsFrame.Label:SetPoint("TOP", 0, move and -43 or -63)

	local mainShoulder, offShoulder, mainHand, offHand

	for i = 1, #sortedSources do
		local itemFrame = self.DetailsFrame.itemFramesPool:Acquire()
		itemFrame.sourceID = sortedSources[i].sourceID;
		itemFrame.itemID = sortedSources[i].itemID;
		itemFrame.collected = sortedSources[i].collected;
		itemFrame.invType = sortedSources[i].invType;
		itemFrame.setID = setID
		local slot = C_Transmog.GetSlotForInventoryType(itemFrame.invType)
		local altid = addon:CheckAltItem(itemFrame.sourceID)
		if altid and type(altid) ~= "table" then
			altid = {altid}
		end

		if altid then
			itemFrame.AltItem:Show()
			itemFrame.AltItem.baseId = itemFrame.sourceID
			itemFrame.AltItem.altid = altid
			--itemFrame.AltItem.useAlt = false
			itemFrame.AltItem.setID = setID
			itemFrame.AltItem.index = itemFrame.AltItem.index or 0


		else
			itemFrame.AltItem:Hide()
			itemFrame.AltItem.baseId = nil
			itemFrame.AltItem.altid = nil
			itemFrame.AltItem.useAlt = false
			itemFrame.AltItem.setID = nil
			itemFrame.AltItem.index = nil
		end

		if itemFrame.AltItem.useAlt then 
			itemFrame.sourceID = altid[itemFrame.AltItem.index]
		end

		if slot == 3 and not mainShoulder then 
			mainShoulder = itemFrame.sourceID;
			offShoulder = setInfo.offShoulder;
		elseif slot ==16 then 
			mainHand = itemFrame.sourceID;
		elseif slot == 17 then
			offhand = itemFrame.sourceID;
		end
		-----itemFrame.visualID = sortedSources[i].visualID   ---TODO:ISNEEDEd?
		local texture = C_TransmogCollection.GetSourceIcon(sortedSources[i].sourceID)

		if itemFrame.AltItem.useAlt then 
			texture = C_TransmogCollection.GetSourceIcon(itemFrame.sourceID)
		end
		----TODO: FIX Unavailable;

		--[[if not itemFrame.unavailable then 
							itemFrame.unavailable = CreateFrame("Frame", nil, itemFrame, "BackdropTemplate")
							itemFrame.unavailable:SetAllPoints()
							itemFrame.unavailable = itemFrame:CreateTexture(nil, "ARTWORK")
							itemFrame.unavailable:SetAllPoints()
							itemFrame.unavailable:SetColorTexture(1,0,0,.1)
						end]]

		itemFrame.Icon:SetTexture(texture)
		if ( sortedSources[i].collected ) then
			itemFrame.Icon:SetDesaturated(false)
			itemFrame.Icon:SetAlpha(1)
			itemFrame.IconBorder:SetDesaturation(0)
			itemFrame.IconBorder:SetAlpha(1)

			local transmogSlot = C_Transmog.GetSlotForInventoryType(itemFrame.invType)
			if ( addon.C_TransmogSets.SetHasNewSourcesForSlot(setID, transmogSlot) ) then
				itemFrame.New:Show()
				itemFrame.New.Anim:Play()
			else
				itemFrame.New:Hide()
				itemFrame.New.Anim:Stop()
			end
		else
			itemFrame.Icon:SetDesaturated(true)
			itemFrame.Icon:SetAlpha(0.3)
			itemFrame.IconBorder:SetDesaturation(1)
			itemFrame.IconBorder:SetAlpha(0.3)
			itemFrame.New:Hide()
		end



	----TODO: FIX Unavailable;

		itemFrame.itemCollectionStatus = nil;
		if ( sortedSources[i].collected ) then
			if not sortedSources[i].characterUseable then
				if sortedSources[i].characterCollectable then
				  itemFrame.itemCollectionStatus = "CollectedCharCantUse"
				else
				  itemFrame.itemCollectionStatus = "CollectedCharCantGet"
				end
			end
		else
			if (not sortedSources[i].characterCollectable) then
				itemFrame.itemCollectionStatus = "NotCollectedCharCantGet"
			  end
		end

		if isAvailableItem(itemFrame.sourceID, setInfo.setID) then  
			--itemFrame.unavailable:Hide()
			--itemFrame.Icon:SetColorTexture(1,0,0,.5)
			itemFrame.itemCollectionStatus = nil
		else
			--We don't care if item is collected
		  if not sortedSources[i].collected then 
			itemFrame.itemCollectionStatus = "NotCollectedUnavailable"
		end
		--itemFrame.unavailable:Show()

			--itemFrame.Icon:SetColorTexture(0,0,0,.5)
		end

		self:SetItemFrameQuality(itemFrame)
		self:SetItemUseability(itemFrame)


		--itemFrame:SetPoint("TOP", self.DetailsFrame, "TOP", xOffset + (i - 1) * BUTTON_SPACE, -94)
		if i <= 10 then
			itemFrame:SetPoint("TOP", self.DetailsFrame, "TOP", xOffset + (i - 1) * BUTTON_SPACE, yOffset1)
		else
			itemFrame:SetPoint("TOP", self.DetailsFrame, "TOP", xOffset2 + (i - 11) * BUTTON_SPACE, yOffset2)
		end

		itemFrame:Show()
		-----self.Model:TryOn(sortedSources[i].sourceID)
		local invType = sortedSources[i].invType - 1;

		if invType  == 20 then invType = 5 end
		if not addon.setdb.profile.autoHideSlot.toggle or ( addon.setdb.profile.autoHideSlot.toggle and not addon.setdb.profile.autoHideSlot[invType]) then
			if itemFrame.AltItem.useAlt then 
				self.Model:TryOn(itemFrame.AltItem.altid[itemFrame.AltItem.index])
			else
				self.Model:TryOn(sortedSources[i].sourceID)
			end
		end
	end

	--Check for secondary Shoulder;
	local setTransmogInfo = C_TransmogCollection.GetOutfitItemTransmogInfoList(addon:GetBlizzID(setID)) or {}
	if setTransmogInfo and setTransmogInfo[3] and setTransmogInfo[3].secondaryAppearanceID ~= 0 then
		local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(setTransmogInfo[3].appearanceID, setTransmogInfo[3].secondaryAppearanceID, 0)
		self.Model:SetItemTransmogInfo(itemTransmogInfo, 3, false) 
	elseif (mainShoulder and offShoulder) then 
		local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(mainShoulder, offShoulder, 0)
		self.Model:SetItemTransmogInfo(itemTransmogInfo, 3, false)
	end

	if setInfo.mainHandEnchant or setInfo.offHandEnchant then 
		if mainHand then 
			local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(mainHand, 0, setInfo.mainHandEnchant)
			self.Model:SetItemTransmogInfo(itemTransmogInfo,16, false) 
		end
		if offHand then 
			itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(offHand, 0, setInfo.offHandEnchant)
			self.Model:SetItemTransmogInfo(itemTransmogInfo,17, false) 
		end
	elseif  setTransmogInfo and setTransmogInfo[16] or setTransmogInfo[17] then 

		if setTransmogInfo and setTransmogInfo[16] and setTransmogInfo[16].illusionID then
			local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(setTransmogInfo[16].appearanceID, 0, setTransmogInfo[16].illusionID)
			self.Model:SetItemTransmogInfo(itemTransmogInfo, 3, false) 
		end
		if setTransmogInfo and setTransmogInfo[17] and setTransmogInfo[17].illusionID then
			local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(setTransmogInfo[17].appearanceID, 0, setTransmogInfo[17].illusionID)
			self.Model:SetItemTransmogInfo(itemTransmogInfo, 3, false) 
		end
	end



	--if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then 
	-- variant sets
		local showVariantSetsButton = false;
		local baseSetID = C_TransmogSets.GetBaseSetID(setID)
		local variantSets = SetsDataProvider:GetVariantSets(baseSetID)
		if variantSets then
			local numVisibleSets = 0;
			for i, set in ipairs(variantSets) do
				if not set.hiddenUntilCollected or set.collected then
					numVisibleSets = numVisibleSets + 1;
				end
			end
			showVariantSetsButton = numVisibleSets > 1;
		end
		if showVariantSetsButton then
			self.DetailsFrame.VariantSetsButton:Show()
			self.DetailsFrame.VariantSetsButton:SetText(setInfo.description)
		else
			self.DetailsFrame.VariantSetsButton:Hide()
		end
	--elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
	--	self.DetailsFrame.VariantSetsButton:Hide()
		--self.DetailsFrame.VariantSetsButton:SetText(setInfo.description)

		addon:SendMessage("BW_TRANSMOG_EXTRASETSHOWN")
	--end
end
----TODO:CHECK;
function BetterWardrobeSetsCollectionMixin:DisplaySavedSet(setID)
	 local setInfo = (setID and addon.GetSetInfo(setID)) or nil;
	if (not setInfo) then
		self.DetailsFrame:Hide()
		self.Model:Hide()
		return;
	else
		self.DetailsFrame:Show()
		self.Model:Show()
	end



	self.DetailsFrame.Name:SetText(setInfo.name)
	if (self.DetailsFrame.Name:IsTruncated()) then
		self.DetailsFrame.Name:Hide()
		self.DetailsFrame.LongName:SetText(setInfo.name)
		self.DetailsFrame.LongName:Show()
	else
		self.DetailsFrame.Name:Show()
		self.DetailsFrame.LongName:Hide()
	end

	self.DetailsFrame.Label:SetText(setInfo.label)


	self.DetailsFrame.LimitedSet:Hide()
	 self.DetailsFrame.VariantSetsButton:Hide()

	self.DetailsFrame.itemFramesPool:ReleaseAll()
	self.Model:Undress()
	local row1 = 0;
	local row2 = 0;
	local yOffset1 = -94;

	local setType = addon.GetSetType(setID)
	local sortedSources = {}
	local mainShoulder;
	local offShoulderindex;
	local offShoulder;

	local sortedSources = SetsDataProvider:GetSortedSetSources(setID)

	if setType == "SavedBlizzard" then
		--(setID and addon.GetSetInfo(setID)) or nil;
		local sources  = C_TransmogCollection.GetOutfitItemTransmogInfoList(addon:GetBlizzID(setID))
		for slotID, itemTransmogInfo in ipairs(sources) do
			if itemTransmogInfo.appearanceID ~= 0 then 
				if slotID == 3 and not mainShoulder then
					mainShoulder = itemTransmogInfo.appearanceID;
					offShoulder = itemTransmogInfo.secondaryAppearanceID;
					offShoulderindex = #sortedSources + 2;
				end
				tinsert(sortedSources, itemTransmogInfo.appearanceID)
				if offShoulder ~= 0 then 
					tinsert(sortedSources, itemTransmogInfo.secondaryAppearanceID)
				end
			end	  
		end
		--sortedSources = setInfo.sources;
		
	elseif setType == "SavedMogIt" then
		for i, sourceID in pairs(setInfo.sources) do	
			tinsert(sortedSources, sourceID)
		end
	elseif setType == "SavedTransmogOutfit"  or setType == "SavedExtra" then
		for i, itemID in pairs(setInfo.items) do
			if itemID ~= 0 then 
				local _, sourceID = C_TransmogCollection.GetItemInfo(itemID)
				local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				if sourceInfo.invType - 1 == 3 and not mainShoulder then 
					mainShoulder = sourceInfo.sourceID;
					offShoulderindex = #sortedSources + 2;
				end	
				tinsert(sortedSources, sourceID)
			end
		end

		if setInfo.offShoulder and setInfo.offShoulder ~= 0 then
			local baseSourceID = C_Transmog.GetSlotVisualInfo(TransmogUtil.GetTransmogLocation("SHOULDERSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary))
			if setInfo.offShoulder ~= baseSourceID then
				offShoulder = setInfo.offShoulder;
				tinsert(sortedSources, offShoulderindex , offShoulder)
			end	
		end 
	end

	if setInfo then
		for i = 1, #sortedSources do
			local sourceInfo = sortedSources[i] and C_TransmogCollection.GetSourceInfo(sortedSources[i])
			if sourceInfo then
				row1 = row1 + 1;
			end
		end

		if row1 > 10 then
			row2 = row1 - 10;
			row1 = 10;
			yOffset1 = -74;
		end
	end

	local BUTTON_SPACE = 37	-- button width + spacing between 2 buttons
	--local sortedSources = setInfo.sources --SetsDataProvider:GetSortedSetSources(setID)
	local xOffset = -floor((row1 - 1) * BUTTON_SPACE / 2)
	local xOffset2 = -floor((row2 - 1) * BUTTON_SPACE / 2)
	local yOffset2 = yOffset1 - 40;
	local itemCount = 0;



	for i = 1, #sortedSources do
		if sortedSources[i] then
		local sourceInfo = C_TransmogCollection.GetSourceInfo(sortedSources[i])

		if sourceInfo then
		itemCount = itemCount + 1;
			local itemFrame = self.DetailsFrame.itemFramesPool:Acquire()
			itemFrame.sourceID = sourceInfo.sourceID;
			--itemFrame.itemID = sourceInfo.itemID;
			itemFrame.collected = sourceInfo.isCollected;
			itemFrame.invType = sourceInfo.invType;
			local texture = C_TransmogCollection.GetSourceIcon(sourceInfo.sourceID)
			itemFrame.Icon:SetTexture(texture)
			if (sourceInfo.isCollected) then
				itemFrame.Icon:SetDesaturated(false)
				itemFrame.Icon:SetAlpha(1)
				itemFrame.IconBorder:SetDesaturation(0)
				itemFrame.IconBorder:SetAlpha(1)
			else
				itemFrame.Icon:SetDesaturated(true)
				itemFrame.Icon:SetAlpha(0.3)
				itemFrame.IconBorder:SetDesaturation(1)
				itemFrame.IconBorder:SetAlpha(0.3)
				itemFrame.New:Hide()
			end

			self:SetItemFrameQuality(itemFrame)
			local move = (itemCount > 10)
			if itemCount <= 10 then
				itemFrame:SetPoint("TOP", self.DetailsFrame, "TOP", xOffset + (itemCount - 1) * BUTTON_SPACE, yOffset1)

			else
				itemFrame:SetPoint("TOP", self.DetailsFrame, "TOP", xOffset2 + (itemCount - 11) * BUTTON_SPACE, yOffset2)
			end

				self.DetailsFrame.IconRowBackground:ClearAllPoints()
				self.DetailsFrame.IconRowBackground:SetPoint("TOP", 0, move and -50 or -78)
				self.DetailsFrame.IconRowBackground:SetHeight(move and 120 or 64)
				self.DetailsFrame.Name:ClearAllPoints()
				self.DetailsFrame.Name:SetPoint("TOP", 0,  move and -17 or -37)
				self.DetailsFrame.LongName:ClearAllPoints()
				self.DetailsFrame.LongName:SetPoint("TOP", 0, move and -10 or -30)
				self.DetailsFrame.Label:ClearAllPoints()
				self.DetailsFrame.Label:SetPoint("TOP", 0, move and -43 or -63)

			itemFrame:Show()
			self.Model:TryOn(sourceInfo.sourceID)
			end
		end
	end

	if mainShoulder and offShoulder then 
		local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(mainShoulder, offShoulder, 0)
		self.Model:SetItemTransmogInfo(itemTransmogInfo, 3, false)
	end
end

function BetterWardrobeSetsCollectionMixin:SetItemFrameQuality(itemFrame)
	if ( itemFrame.collected ) then
		local quality = C_TransmogCollection.GetSourceInfo(itemFrame.sourceID).quality;
			itemFrame.IconBorder:Show()
		if ( quality == Enum.ItemQuality.Poor ) then
			itemFrame.IconBorder:Hide()
			--itemFrame.IconBorder:SetAtlas("dressingroom-itemborder-gray", true)
		elseif ( quality == Enum.ItemQuality.Common ) then
			itemFrame.IconBorder:SetAtlas("loottab-set-itemborder-white", true)
		elseif ( quality == Enum.ItemQuality.Uncommon ) then
			itemFrame.IconBorder:SetAtlas("loottab-set-itemborder-green", true)
		elseif ( quality == Enum.ItemQuality.Rare ) then
			itemFrame.IconBorder:SetAtlas("loottab-set-itemborder-blue", true)
		elseif ( quality == Enum.ItemQuality.Epic ) then
			itemFrame.IconBorder:SetAtlas("loottab-set-itemborder-purple", true)
		end
	end
end

function BetterWardrobeSetsCollectionMixin:SetItemUseability(itemFrame)
	itemFrame.CanUse:Hide()
	local itemCollectionStatus = itemFrame.itemCollectionStatus;
	if itemCollectionStatus == "CollectedCharCantUse" then
		itemFrame.CanUse:Show()
		--itemFrame.Icon:SetDesaturated(false)
		itemFrame.CanUse.Icon:SetDesaturation(0)
		itemFrame.CanUse.Icon:SetVertexColor(1,0.8,0)

		itemFrame.CanUse.Icon:SetAtlas("PlayerRaidBlip");		
		--itemFrame.Icon:SetAlpha(0.6)
		itemFrame.CanUse.Icon:SetAlpha(0.5)

	elseif itemCollectionStatus == "CollectedCharCantGet" then
		itemFrame.CanUse:Show()

		--itemFrame.Icon:SetDesaturated(false)
		itemFrame.CanUse.Icon:SetDesaturation(0)
		
		itemFrame.CanUse.Icon:ClearAllPoints()
		itemFrame.CanUse.Icon:SetPoint("CENTER",itemFrame,"TOP",0,-3)
		itemFrame.CanUse.Icon:SetVertexColor(1,0,0)
		itemFrame.CanUse.Icon:SetAtlas("PlayerRaidBlip")
		itemFrame.CanUse.Icon:SetSize(25,25)
		
		--itemFrame.Icon:SetAlpha(0.6)
		itemFrame.CanUse.Icon:SetAlpha(0.5)
		--itemFrame.New:Hide()
  
	elseif itemCollectionStatus == "NotCollectedCharCantGet" then
		itemFrame.CanUse:Show()
		---itemFrame.Icon:SetDesaturated(true)
		itemFrame.CanUse.Icon:SetDesaturation(0)
		itemFrame.CanUse.Icon:SetVertexColor(1,0,0)
		itemFrame.CanUse.Icon:SetAtlas("PlayerDeadBlip")
		--itemFrame.Icon:SetAlpha(0.3)
		itemFrame.CanUse.Icon:SetAlpha(0.5)
		--itemFrame.New:Hide()
	elseif itemCollectionStatus ==  "NotCollectedUnavailable"then
		itemFrame.CanUse:Show()
		---itemFrame.Icon:SetDesaturated(true)
		itemFrame.CanUse.Icon:SetDesaturation(0)
		itemFrame.CanUse.Icon:SetVertexColor(1,1,1)
		itemFrame.CanUse.Icon:SetAtlas("PlayerDeadBlip")
		--itemFrame.Icon:SetAlpha(0.3)
		itemFrame.CanUse.Icon:SetAlpha(0.5)
		--itemFrame.New:Hide()
	else
		itemFrame.CanUse:Hide()
	end
end

function BetterWardrobeSetsCollectionMixin:OnSearchUpdate()
	if ( self.init ) then
		SetsDataProvider:ClearBaseSets()
		SetsDataProvider:ClearVariantSets()
		SetsDataProvider:ClearUsableSets()
		self:Refresh()
	end
end

function BetterWardrobeSetsCollectionMixin:OnUnitModelChangedEvent()
	if ( IsUnitModelReadyForUI("player") ) then
		self.Model:RefreshUnit()
		-- clearing cameraID so it resets zoom/pan
		self.Model.cameraID = nil;
		self.Model:UpdatePanAndZoomModelType()
		self:RefreshCameras()
		self:Refresh()
		return true;
	else
		return false;
	end
end

local function GetFormCameraInfo()
	local detailsCameraID, transmogCameraID = C_TransmogSets.GetCameraIDs()

	local inNativeForm = C_UnitAuras.WantsAlteredForm("player");
	local _, raceFilename = UnitRace("player");
	local sex = UnitSex("player") 

	if  (not inNativeForm and addon.useNativeForm) then
		if raceFilename == "Worgen" then
			if sex == 3 then
				detailsCameraID, transmogCameraID = 1020, 1045
			else
				detailsCameraID, transmogCameraID = 1021, 1024
			end
		elseif raceFilename == "Dracthyr" then
			detailsCameraID, transmogCameraID = 1712, 1710
		end

	elseif inNativeForm and not addon.useNativeForm then 
		if raceFilename == "Worgen" then
			if sex == 3 then
				detailsCameraID, transmogCameraID = 997, 1022
			else
				detailsCameraID, transmogCameraID = 995, 996
			end

		elseif raceFilename == "Dracthyr" then
			if sex == 3 then
				detailsCameraID, transmogCameraID = 997, 1022
			else
				detailsCameraID, transmogCameraID = 998, 1024
			end
		end
	end
	return detailsCameraID, transmogCameraID
end


function BetterWardrobeSetsCollectionMixin:RefreshCameras()
	if ( self:IsShown() ) then
		local detailsCameraID, transmogCameraID = GetFormCameraInfo()

		local model = self.Model;
		self.Model:RefreshCamera()
		addon.Model_ApplyUICamera(self.Model, detailsCameraID)
		if ( model.cameraID ~= detailsCameraID ) then
			model.cameraID = detailsCameraID;
			model.defaultPosX, model.defaultPosY, model.defaultPosZ, model.yaw = GetUICameraInfo(detailsCameraID)
		end
	end
end

function BetterWardrobeSetsCollectionMixin:OpenVariantSetsDropDown()
	local selectedSetID = self:GetSelectedSetID()
	if ( not selectedSetID ) then
		return;
	end
	local info = BW_UIDropDownMenu_CreateInfo()
	local baseSetID = C_TransmogSets.GetBaseSetID(selectedSetID)
	local variantSets = SetsDataProvider:GetVariantSets(baseSetID)
	for i = 1, #variantSets do
		local variantSet = variantSets[i]
		if not variantSet.hiddenUntilCollected or variantSet.collected then

			local numSourcesCollected, numSourcesTotal = SetsDataProvider:GetSetSourceCounts(variantSet.setID)
			local colorCode = IN_PROGRESS_FONT_COLOR_CODE;
			if ( numSourcesCollected == numSourcesTotal ) then
				colorCode = NORMAL_FONT_COLOR_CODE;
			elseif ( numSourcesCollected == 0 ) then
				colorCode = GRAY_FONT_COLOR_CODE;
			end
			info.text = format(ITEM_SET_NAME, variantSet.description..colorCode, numSourcesCollected, numSourcesTotal)
			info.checked = (variantSet.setID == selectedSetID)
			info.func = function() self:SelectSet(variantSet.setID); end
			BW_UIDropDownMenu_AddButton(info)
		end
	end
end

function BetterWardrobeSetsCollectionMixin:SelectBaseSetID(baseSetID)
	self:SelectSet(self:GetDefaultSetIDForBaseSet(baseSetID))
end

function BetterWardrobeSetsCollectionMixin:GetDefaultSetIDForBaseSet(baseSetID)
	if ( SetsDataProvider:IsBaseSetNew(baseSetID) ) then
		if ( C_TransmogSets.SetHasNewSources(baseSetID) ) then
			return baseSetID;
		else
			local variantSets = SetsDataProvider:GetVariantSets(baseSetID)
			for i, variantSet in ipairs(variantSets) do
				if ( C_TransmogSets.SetHasNewSources(variantSet.setID) ) then
					return variantSet.setID;
				end
			end
		end
	end

	if ( self.selectedVariantSets[baseSetID] ) then
		return self.selectedVariantSets[baseSetID]
	end

	local baseSet = SetsDataProvider:GetBaseSetByID(baseSetID)
	if ( baseSet.favoriteSetID ) then
		return baseSet.favoriteSetID;
	end
	-- pick the one with most collected, higher difficulty wins ties
	local highestCount = 0;
	local highestCountSetID;
	local variantSets = SetsDataProvider:GetVariantSets(baseSetID)
	for i = 1, #variantSets do
		local variantSetID = variantSets[i].setID;
		local numCollected = SetsDataProvider:GetSetSourceCounts(variantSetID)
		if ( numCollected > 0 and numCollected >= highestCount ) then
			highestCount = numCollected;
			highestCountSetID = variantSetID;
		end
	end
	return highestCountSetID or baseSetID;
end

function BetterWardrobeSetsCollectionMixin:SelectSetFromButton(setID)
	CloseDropDownMenus()
	if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then 
		self:SelectSet(self:GetDefaultSetIDForBaseSet(setID))
	----elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then 
	else
		self:SelectSet(setID)
	end
end

function BetterWardrobeSetsCollectionMixin:SelectSet(setID)
	if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then
		self.selectedSetID = setID;
		local baseSetID = C_TransmogSets.GetBaseSetID(setID)
		local variantSets = SetsDataProvider:GetVariantSets(baseSetID)
		if ( #variantSets > 0 ) then
			self.selectedVariantSets[baseSetID] = setID;
		end
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
		self.selectedExtraSetID = setID;
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 4 then
		self.selectedSavedSetID = setID;
	end

	self:Refresh()
end

function BetterWardrobeSetsCollectionMixin:GetSelectedSetID()
	if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then
		return self.selectedSetID;
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
		return self.selectedExtraSetID;
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 4 then
		return self.selectedSavedSetID;
	end	
end

function BetterWardrobeSetsCollectionMixin:SetAppearanceTooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	self.tooltipTransmogSlot = C_Transmog.GetSlotForInventoryType(frame.invType)
	self.tooltipPrimarySourceID = frame.sourceID;
	self:RefreshAppearanceTooltip()
end

local needsRefresh = false
function BetterWardrobeSetsCollectionMixin:RefreshAppearanceTooltip()
	if ( not self.tooltipTransmogSlot ) then
		return;
	end

	if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then

		local sources = C_TransmogSets.GetSourcesForSlot(self:GetSelectedSetID(), self.tooltipTransmogSlot)
		if ( #sources == 0 ) then
			-- can happen if a slot only has HiddenUntilCollected sources
			local sourceInfo = C_TransmogCollection.GetSourceInfo(self.tooltipPrimarySourceID)
			tinsert(sources, sourceInfo)
		end
		CollectionWardrobeUtil.SortSources(sources, sources[1].visualID, self.tooltipPrimarySourceID)
		local transmogLocation = TransmogUtil.CreateTransmogLocation(self.tooltipTransmogSlot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main);

		local warningString = GetVisibilityWarning(self.Model, transmogLocation);	
		self:GetParent():SetAppearanceTooltip(self, sources, self.tooltipPrimarySourceID, warningString)
	else
		----elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
		local sourceInfo = C_TransmogCollection.GetSourceInfo(self.tooltipPrimarySourceID)
		local visualID = sourceInfo.visualID;
		local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(self.tooltipPrimarySourceID)
		local sources = (self.tooltipPrimarySourceID and itemLink and C_TransmogCollection.GetAppearanceSources(visualID, addon.GetItemCategory(self.tooltipPrimarySourceID), addon.GetTransmogLocation(itemLink)) ) or {} --Can return nil if no longer in game;

		if (#sources == 0) then
			-- can happen if a slot only has HiddenUntilCollected sources
			local sourceInfo = C_TransmogCollection.GetSourceInfo(self.tooltipPrimarySourceID)
			tinsert(sources, sourceInfo)
		end

		CollectionWardrobeUtil.SortSources(sources, sources[1].visualID, self.tooltipPrimarySourceID)
		local transmogLocation = TransmogUtil.CreateTransmogLocation(self.tooltipTransmogSlot, Enum.TransmogType.Appearance, Enum.TransmogModification.Main);

		local warningString = GetVisibilityWarning(self.Model, transmogLocation);	
		self:GetParent():SetAppearanceTooltip(self, sources, self.tooltipPrimarySourceID, warningString)
		--self:GetParent():SetAppearanceTooltip(self, sources, self.tooltipPrimarySourceID)

		C_Timer.After(.05, function() if needsRefresh then self:RefreshAppearanceTooltip(); needsRefresh = false; end end) --Fix for items that returned retreaving info;
	end
end

function BetterWardrobeSetsCollectionMixin:ClearAppearanceTooltip()
	self.tooltipTransmogSlot = nil;
	self.tooltipPrimarySourceID = nil;
	self:GetParent():HideAppearanceTooltip()
end

function BetterWardrobeSetsCollectionMixin:CanHandleKey(key)
	if ( key == WARDROBE_UP_VISUAL_KEY or key == WARDROBE_DOWN_VISUAL_KEY ) then
		return true;
	end
	return false;
end

function BetterWardrobeSetsCollectionMixin:HandleKey(key)
	if BetterWardrobeCollectionFrame.selectedCollectionTab == 4 then
		if (not self:GetSelectedSavedSetID()) then
			return false;
		end
	else
		if (not self:GetSelectedSetID()) then
			return false;
		end
	end

	local selectedSetID;
	if BetterWardrobeCollectionFrame.selectedCollectionTab == 4 then
		selectedSetID = self:GetSelectedSavedSetID()
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
		selectedSetID = self:GetSelectedSetID()
	elseif BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then
		selectedSetID = C_TransmogSets.GetBaseSetID(self:GetSelectedSetID())
	end

	local _, index = SetsDataProvider:GetBaseSetByID(selectedSetID)
	if ( not index ) then
		return;
	end
	if ( key == WARDROBE_DOWN_VISUAL_KEY ) then
		index = index + 1;
	elseif ( key == WARDROBE_UP_VISUAL_KEY ) then
		index = index - 1;
	end
	local sets = SetsDataProvider:GetBaseSets()
	index = Clamp(index, 1, #sets)
	self:SelectSet(self:GetDefaultSetIDForBaseSet(sets[index].setID))
	self:ScrollToSet(sets[index].setID, ScrollBoxConstants.AlignNearest)

end

function BetterWardrobeSetsCollectionMixin:ScrollToSet(setID, alignment)
	local scrollBox = self.ListContainer.ScrollBox;

	local baseSetID = C_TransmogSets.GetBaseSetID(setID) or setID
	local function FindSet(elementData)
		return elementData.setID == baseSetID;
	end

	scrollBox:ScrollToElementDataByPredicate(FindSet, alignment, ScrollBoxConstants.NoScrollInterpolation)
end

function BetterWardrobeSetsCollectionMixin:LinkSet(setID)
	local emptySlotData = Sets:GetEmptySlots()
	local itemList = TransmogUtil.GetEmptyItemTransmogInfoList()

	for i = 1, 19 do
		local _, source = addon.GetItemSource(emptySlotData[i] or 0)
		itemList[i].appearanceID = source or 0;
		itemList[i].illusionID = 0;
		itemList[i].secondaryAppearanceID = 0;
	end

	local sortedSources = SetsDataProvider:GetSortedSetSources(setID)
	for i = 1, #sortedSources do
		local slot = C_Transmog.GetSlotForInventoryType(sortedSources[i].invType)
		itemList[slot].appearanceID = sortedSources[i].sourceID;
	end

	local hyperlink = C_TransmogCollection.GetOutfitHyperlinkFromItemTransmogInfoList(itemList)
	if not ChatEdit_InsertLink(hyperlink) then
		ChatFrame_OpenChat(hyperlink)
	end
end

do
	local function OpenVariantSetsDropDown(self)
		self:GetParent():GetParent():OpenVariantSetsDropDown()
	end
	function BetterWardrobeSetsCollectionVariantSetsDropDown_OnLoad(self)
		BW_UIDropDownMenu_Initialize(self, OpenVariantSetsDropDown, "MENU")
	end
end

local tabType = {"item", "set", "extraset"}

local function GetTab(tab)
	local atTransmogrifier = C_Transmog.IsAtTransmogNPC()
	local tabID;

	if ( atTransmogrifier ) then
		tabID = BetterWardrobeCollectionFrame.selectedTransmogTab;
	else
		tabID = BetterWardrobeCollectionFrame.selectedCollectionTab;
	end
	return tabID, atTransmogrifier;

end
addon.GetTab = GetTab;

function BetterWardrobeSetsCollectionMixin:OpenInDressingRoom(setID)

		if DressUpFrame:IsShown() then 
		else
			DressUpFrame_Show(DressUpFrame)
			C_Timer.After(0, function() self:OpenInDressingRoom(setID) 
			return 
		end)
		end
		
	local setType = tabType[addon.GetTab()]
	 setInfo = addon.GetSetInfo(setID) or C_TransmogSets.GetSetInfo(setID)



	
	--local setType = addon.QueueList[1]
	--local setID = addon.QueueList[2]
	local playerActor = DressUpFrame.ModelScene:GetPlayerActor()

	if not playerActor or not setID then
		return false
	end

	if setType == "set" then
		sources = {}
		local sourceInfo = C_TransmogSets.GetSetPrimaryAppearances(setID)
		for i, data in ipairs(sourceInfo) do
			sources[data.appearanceID] = false

		end

	elseif setType == "extraset" then
		sources = addon.GetSetsources(setID)
	end

	if not sources then return end

	playerActor:Undress()
	for i, d in pairs(sources)do
		playerActor:TryOn(i)
	end

	import = true
	--DressUpSources(sources)
	import = false
	addon:UpdateDressingRoom()
end

local function BetterWardrobeSetsCollectionScrollFrame_FavoriteDropDownInit(self)
	if ( not self.baseSetID ) then
		return;
	end
	local baseSet = SetsDataProvider:GetBaseSetByID(self.baseSetID)
	local type = tabType[addon.GetTab()]

	local variantSets =  {}-- 0 -----SetsDataProvider:GetVariantSets(self.baseSetID);   ---TODO:REvisit
	local useDescription = (#variantSets > 0)

	local info = BW_UIDropDownMenu_CreateInfo()
	info.notCheckable = true;
	info.disabled = nil;

	BW_UIDropDownMenu_AddButton({
		notCheckable = true,
		text = TRANSMOG_OUTFIT_POST_IN_CHAT,
		func = function() BetterWardrobeSetsCollectionMixin:LinkSet(self.baseSetID) end,
	})

	local isFavorite = (type == "set" and C_TransmogSets.GetIsFavorite(self.baseSetID)) or addon.favoritesDB.profile.extraset[self.baseSetID]
	if (isFavorite) then
	----if ( baseSet.favoriteSetID ) then
		if ( useDescription ) then
			local setInfo = C_TransmogSets.GetSetInfo(baseSet.favoriteSetID)
			info.text = format(TRANSMOG_SETS_UNFAVORITE_WITH_DESCRIPTION, setInfo.description)
		else
			info.text = BATTLE_PET_UNFAVORITE;
		end

		if type == "set"  then
			info.func = function()
				C_TransmogSets.SetIsFavorite(baseSet.favoriteSetID, false)
			end

		elseif type == "extraset"  then
			info.func = function()
				addon.favoritesDB.profile.extraset[self.baseSetID] = nil;
				BetterWardrobeCollectionFrame.SetsCollectionFrame:Refresh()
				BetterWardrobeCollectionFrame.SetsCollectionFrame:OnSearchUpdate()
			end
		end
	else
		local targetSetID = BetterWardrobeCollectionFrame.SetsCollectionFrame:GetDefaultSetIDForBaseSet(self.baseSetID)
		if ( useDescription ) then
			local setInfo = C_TransmogSets.GetSetInfo(targetSetID)
			info.text = format(TRANSMOG_SETS_FAVORITE_WITH_DESCRIPTION, setInfo.description)
		else
			info.text = BATTLE_PET_FAVORITE;
		end


		if type == "set"  then
			info.func = function()
				C_TransmogSets.SetIsFavorite(targetSetID, true)
			end
		elseif type == "extraset"  then
			info.func = function()
				addon.favoritesDB.profile.extraset[self.baseSetID] = true;
				RefreshLists()
			end
		end
	end

	BW_UIDropDownMenu_AddButton(info, level)
	info.disabled = nil;

	info.text = CANCEL;
	info.func = nil;
	BW_UIDropDownMenu_AddButton(info, level)

	local tab = addon.GetTab()

if tab ~=4 then 
	--new;
		local variantTarget, match, matchType;
		local variantType = ""
		if type == "set" or type =="extraset" then
			BW_UIDropDownMenu_AddSeparator()
			BW_UIDropDownMenu_AddButton({
					notCheckable = true,
					text = L["Queue Transmog"],
					func = function()

						local setInfo = addon.GetSetInfo(self.baseSetID) or C_TransmogSets.GetSetInfo(self.baseSetID)
						local name = setInfo["name"]
						--addon.QueueForTransmog(type, setID, name)
						addon.QueueList = {type, self.baseSetID, name}
					 end,
					})
						if type == "set" then 
				variantTarget, variantType, match, matchType = addon.Sets:SelectedVariant(self.baseSetID)
			end
		end

		BW_UIDropDownMenu_AddSeparator()
		local isHidden = addon.HiddenAppearanceDB.profile[type][self.baseSetID]
		
		BW_UIDropDownMenu_AddButton({
			notCheckable = true,
			text = isHidden and SHOW or HIDE,
			func = function() self.setID = self.baseSetID; ToggleHidden(self, isHidden) end,
		})

		local collected = self.setCollected;
		--Collection List Right Click options;
		local collectionList = addon.CollectionList:CurrentList()
		local isInList = match or addon.CollectionList:IsInList(self.baseSetID, type)

		--if  type  == "set" or ((isInList and collected) or not collected)then --(type == "item" and not (model.visualInfo and model.visualInfo.isCollected)) or type == "set" or type == "extraset" then
			local targetSet = match or variantTarget or self.baseSetID;
			local targetText = match and " - "..matchType or variantTarget and " - "..variantType or ""
			BW_UIDropDownMenu_AddSeparator()
			local isInList = collectionList[type][targetSet]
			BW_UIDropDownMenu_AddButton({
				notCheckable = true,
				text = isInList and L["Remove from Collection List"]..targetText or L["Add to Collection List"]..targetText,
				func = function()
							addon.CollectionList:UpdateList(type, targetSet, not isInList)
					end,
			})

		end
end

local function CheckSetAvailability(setID)
	local setData = SetsDataProvider:GetSetSourceData(setID)
	return setData.unavailable;
end


local function CheckSetAvailability2(setID)
	local  setData = addon.C_TransmogSets.GetSetInfo(setID) 
	local buildID = (select(4, GetBuildInfo()))
		if ((setData.description == ELITE) and setData.patchID < buildID) or (setID <= 1446 and setID >=1436) then

		return true;

	end
end



function BetterWardrobeSetsCollectionMixin:GetSelectedSavedSetID()
	if not self.selectedSavedSetID then
		local savedSets = addon.GetSavedList()
		if savedSets and #savedSets > 0  then 
			self.selectedSavedSetID = savedSets[1].setID;
		else 
			self.selectedSavedSetID = nil;
		end
	end

	return self.selectedSavedSetID;
end


local function variantsTooltip(elementData, variantSets)
	if not elementData.description then return "" end

	local ratioText = elementData.description..": " 
	local have, total = addon.SetsDataProvider:GetSetSourceCounts(elementData.setID)
	ratioText = ratioText..have .. "/" .. total.."\n"

	for i, setdata in ipairs(variantSets)do
		local have, total = addon.SetsDataProvider:GetSetSourceCounts(setdata.setID)
		 ratioText =  ratioText..setdata.description..": ".. have .. "/" .. total.."\n"
	end

	return ratioText
end

BetterWardrobeSetsScrollFrameButtonMixin = {}

function BetterWardrobeSetsScrollFrameButtonMixin:Init(elementData)
	local displayData = elementData;
	if not displayData then return end
	-- if the base set is hiddenUntilCollected and not collected, it's showing up because one of its variant sets is collected
	-- in that case use any variant set to populate the info in the list
	local variantSets = C_TransmogSets.GetVariantSets(elementData.setID) or {}
	if elementData.hiddenUntilCollected and not elementData.collected and BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then
		--local variantSets = C_TransmogSets.GetVariantSets(elementData.setID)
		if variantSets then
			-- variant sets are already filtered for visibility (won't get a hiddenUntilCollected one unless it's collected)
			-- any set will do so just picking first one
			displayData = variantSets[1]
		end
	end

	if #variantSets == 0  or IsAddOnLoaded("CanIMogIt") then
		self.Variants:Hide()
		self.Variants.Count:SetText(0)
	else
		self.Variants:Show()
		self.Variants.Count:SetText(#variantSets + 1)
	end
	--self.Name:SetText(displayData.name)
	self.Name:SetText(displayData.name..((displayData.className) and " ("..displayData.className..")" or "") )

	local topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceTopCounts(displayData.setID)
	-- progress visuals use the top collected progress, so collected visuals should reflect the top completion status as well
	local setCollected = displayData.collected or topSourcesCollected == topSourcesTotal;
	local color = IN_PROGRESS_FONT_COLOR;
	if ( setCollected ) then
		color = NORMAL_FONT_COLOR;
	elseif ( topSourcesCollected == 0 ) then
		color = GRAY_FONT_COLOR;
	end

	local classIcon = ""

	self.Name:SetTextColor(color.r, color.g, color.b)
	self.Label:SetText(displayData.label)
	self.Icon:SetTexture(SetsDataProvider:GetIconForSet(displayData.setID))
	self.Icon:SetDesaturation((topSourcesCollected == 0) and 1 or 0)
	self.Favorite:SetShown(displayData.favoriteSetID)
	self.New:SetShown(addon.SetHasNewSources(displayData.setID))
	self.setID = displayData.setID;
	self.variantInfo = variantsTooltip(elementData, variantSets)

	local setInfo = addon.GetSetInfo(displayData.setID)
	local isFavorite = 	C_TransmogSets.GetIsFavorite(displayData.setID)
	local isHidden = addon.HiddenAppearanceDB.profile.set[displayData.setID]
	local isInList = addon.CollectionList:IsInList(displayData.setID, "set")

	if BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then
		isInList = addon.CollectionList:IsInList(displayData.setID, "extraset")
		isFavorite = addon.favoritesDB.profile.extraset[displayData.setID]
		isHidden = addon.HiddenAppearanceDB.profile.extraset[displayData.setID]
	end

	self.Favorite:SetShown(isFavorite or elementData.favoriteSetID)
	self.CollectionListVisual.Hidden.Icon:SetShown(isHidden)
	self.CollectionListVisual.Unavailable:SetShown(CheckSetAvailability2(displayData.setID))
	self.CollectionListVisual.UnavailableItems:SetShown(CheckSetAvailability(displayData.setID))
	self.CollectionListVisual.InvalidTexture:SetShown(BetterWardrobeCollectionFrame.selectedCollectionTab == 3 and not displayData.isClass)



	self.CollectionListVisual.Collection.Collection_Icon:SetShown(isInList)
	self.CollectionListVisual.Collection.Collected_Icon:SetShown(isInList and setCollected)


	self.EditButton:SetShown((BetterWardrobeCollectionFrame:CheckTab(4) and (self.setID < 50000 or self.setID >=70000 or IsAddOnLoaded("MogIt"))))

	if ( topSourcesCollected == 0 or setCollected ) then
		self.ProgressBar:Hide()
	else
		self.ProgressBar:Show()
		self.ProgressBar:SetWidth(SET_PROGRESS_BAR_MAX_WIDTH * topSourcesCollected / topSourcesTotal)
	end
	self.IconCover:SetShown(not setCollected)

	self:SetSelected(SelectionBehaviorMixin.IsElementDataIntrusiveSelected(elementData))
end

function BetterWardrobeSetsScrollFrameButtonMixin:SetSelected(selected)
	self.SelectedTexture:SetShown(selected)
end

function BetterWardrobeSetsScrollFrameButtonMixin:OnClick(buttonName, down)
	if ( buttonName == "LeftButton" ) then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		g_selectionBehavior:Select(self)
	elseif ( buttonName == "RightButton" ) then
		--local dropDown = self:GetParent():GetParent().FavoriteDropDown;

		local dropDown = self:GetParent():GetParent():GetParent().FavoriteDropDown;
		dropDown.baseSetID = self.setID;
		--ToggleDropDownMenu(1, nil, dropDown, self, 0, 0)
		BW_ToggleDropDownMenu(1, nil, dropDown, self, 0, 0)

		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

BetterWardrobeSetsCollectionContainerMixin = { }

function BetterWardrobeSetsCollectionContainerMixin:OnLoad()
	local view = CreateScrollBoxListLinearView()
	
	view:SetElementInitializer("BetterWardrobeSetsScrollFrameButtonTemplate", function(button, elementData)
		button:Init(elementData)
	end)
	view:SetPadding(0,0,44,0,0)

	local panExtent = buttonHeight;
	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view)

	g_selectionBehavior = ScrollUtil.AddSelectionBehavior(self.ScrollBox, SelectionBehaviorFlags.Intrusive)
	g_selectionBehavior:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged, function(o, elementData, selected)
		local button = self.ScrollBox:FindFrame(elementData)
		if button then
			button:SetSelected(selected)

			if selected then
				local setCollectionFrame = self:GetParent()
				setCollectionFrame:SelectBaseSetID(elementData.setID)
			end
		end
	end, self)

	BW_UIDropDownMenu_Initialize(self.FavoriteDropDown, BetterWardrobeSetsCollectionScrollFrame_FavoriteDropDownInit, "MENU")
end

function BetterWardrobeSetsCollectionContainerMixin:OnShow()
	self:RegisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
end

function BetterWardrobeSetsCollectionContainerMixin:OnHide()
	self:UnregisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
end

function BetterWardrobeSetsCollectionContainerMixin:OnEvent(event, ...)
	if ( event == "TRANSMOG_SETS_UPDATE_FAVORITE" ) then
		SetsDataProvider:RefreshFavorites()
		self:UpdateDataProvider()
	end
end

function BetterWardrobeSetsCollectionContainerMixin:ReinitializeButtonWithBaseSetID(baseSetID)
	local frame = self.ScrollBox:FindFrameByPredicate(function(frame, elementData)
		return elementData.setID == baseSetID;
	end)

	if frame then
		frame:Init(frame:GetElementData())
	end
end

function BetterWardrobeSetsCollectionContainerMixin:UpdateDataProvider()
	local dataProvider = CreateDataProvider(SetsDataProvider:GetBaseSets())
	self.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)

	self:UpdateListSelection()
end

function BetterWardrobeSetsCollectionContainerMixin:UpdateListSelection()
	local selectedSetID = self:GetParent():GetSelectedSetID()
	if selectedSetID then
		if BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then
			self:SelectElementDataMatchingSetID(C_TransmogSets.GetBaseSetID(selectedSetID))
		else
			self:SelectElementDataMatchingSetID(selectedSetID)
		end
	end
end

function BetterWardrobeSetsCollectionContainerMixin:SelectElementDataMatchingSetID(setID)
	g_selectionBehavior:SelectElementDataByPredicate(function(elementData)
		return elementData.setID == setID;
	end)
end


BetterWardrobeSetsDetailsModelMixin = { }

function BetterWardrobeSetsDetailsModelMixin:OnLoad()
	self:SetAutoDress(false)
	self:SetUnit("player", false, PlayerUtil.ShouldUseNativeFormInModelScene());

	self:UpdatePanAndZoomModelType()
	local lightValues = { omnidirectional = false, point = CreateVector3D(-1, 0, 0), ambientIntensity = .7, ambientColor = CreateColor(.7, .7, .7), diffuseIntensity = .6, diffuseColor = CreateColor(1, 1, 1) }
	local enabled = true;
	self:SetLight(enabled, lightValues)
end

function BetterWardrobeSetsDetailsModelMixin:OnShow()
	self:SetUnit("player", false, PlayerUtil.ShouldUseNativeFormInModelScene());
end

function BetterWardrobeSetsDetailsModelMixin:UpdatePanAndZoomModelType()
	local hasAlternateForm, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
	if ( not self.panAndZoomModelType or self.inAlternateForm ~= inAlternateForm ) then
		local _, race = UnitRace("player")
		local sex = UnitSex("player")
		if ( inAlternateForm ) then
			self.panAndZoomModelType = race..sex.."Alt"
		else
			self.panAndZoomModelType = race..sex;
		end
		self.inAlternateForm = inAlternateForm;
	end
end

function BetterWardrobeSetsDetailsModelMixin:GetPanAndZoomLimits()
	return SET_MODEL_PAN_AND_ZOOM_LIMITS[self.panAndZoomModelType]
end

function BetterWardrobeSetsDetailsModelMixin:OnUpdate(elapsed)
	if ( IsUnitModelReadyForUI("player") ) then

		if ( self.rotating ) then
			if ( self.yaw ) then
				local x = GetCursorPosition()
				local diff = (x - self.rotateStartCursorX) * MODELFRAME_DRAG_ROTATION_CONSTANT;
				self.rotateStartCursorX = GetCursorPosition()
				self.yaw = self.yaw + diff;
				if ( self.yaw < 0 ) then
					self.yaw = self.yaw + (2 * PI)
				end
				if ( self.yaw > (2 * PI) ) then
					self.yaw = self.yaw - (2 * PI)
				end
				self:SetRotation(self.yaw, false)
			end
		elseif ( self.panning ) then
			if ( self.defaultPosX ) then
				local cursorX, cursorY = GetCursorPosition()
				local modelX = self:GetPosition()
				local panSpeedModifier = 100 * sqrt(1 + modelX - self.defaultPosX)
				local modelY = self.panStartModelY + (cursorX - self.panStartCursorX) / panSpeedModifier;
				local modelZ = self.panStartModelZ + (cursorY - self.panStartCursorY) / panSpeedModifier;
				local limits = self:GetPanAndZoomLimits()
				modelY = Clamp(modelY, limits.panMaxLeft, limits.panMaxRight)
				modelZ = Clamp(modelZ, limits.panMaxBottom, limits.panMaxTop)
				self:SetPosition(modelX, modelY, modelZ)
			end
		end
	end
end

function BetterWardrobeSetsDetailsModelMixin:OnMouseDown(button)
	if ( button == "LeftButton" ) then
		self.rotating = true;
		self.rotateStartCursorX = GetCursorPosition()
	elseif ( button == "RightButton" ) then
		self.panning = true;
		self.panStartCursorX, self.panStartCursorY = GetCursorPosition()
		local modelX, modelY, modelZ = self:GetPosition()
		self.panStartModelY = modelY;
		self.panStartModelZ = modelZ;
	end
end

function BetterWardrobeSetsDetailsModelMixin:OnMouseUp(button)
	if ( button == "LeftButton" ) then
		self.rotating = false;
	elseif ( button == "RightButton" ) then
		self.panning = false;
	end
end

function BetterWardrobeSetsDetailsModelMixin:OnMouseWheel(delta)
	local posX, posY, posZ = self:GetPosition()
	posX = posX + delta * 0.5;
	local limits = self:GetPanAndZoomLimits()
	posX = Clamp(posX, self.defaultPosX, limits.maxZoom)
	self:SetPosition(posX, posY, posZ)
end

function BetterWardrobeSetsDetailsModelMixin:OnModelLoaded()
	if ( self.cameraID ) then
		addon.Model_ApplyUICamera(self, self.cameraID)
	end
end

BetterWardrobeSetsDetailsItemMixin = { }

function BetterWardrobeSetsDetailsItemMixin:OnEnter()
	self:GetParent():GetParent():SetAppearanceTooltip(self)

	self:SetScript("OnUpdate",
		function()
			if IsModifiedClick("DRESSUP") then
				ShowInspectCursor()
			else
				ResetCursor()
			end
		end
	)
	if ( self.New:IsShown() ) then
		self.New:Hide()

		local transmogSlot = C_Transmog.GetSlotForInventoryType(self.invType)
		local setID = BetterWardrobeCollectionFrame.SetsCollectionFrame:GetSelectedSetID()
		if BetterWardrobeCollectionFrame:CheckTab(2) then
			C_TransmogSets.ClearSetNewSourcesForSlot(setID, transmogSlot)
		else
			addon.ClearSetNewSourcesForSlot(setID, transmogSlot)
		end
		local baseSetID = C_TransmogSets.GetBaseSetID(setID)
		if baseSetID then 
			SetsDataProvider:ResetBaseSetNewStatus(baseSetID)
			--BetterWardrobeCollectionFrame.SetsCollectionFrame:Refresh()
			BetterWardrobeCollectionFrame.SetsCollectionFrame.ListContainer:ReinitializeButtonWithBaseSetID(baseSetID)
		end

	end
end

function BetterWardrobeSetsDetailsItemMixin:OnLeave()
	self:SetScript("OnUpdate", nil)
	ResetCursor()
	BetterWardrobeCollectionFrame:HideAppearanceTooltip()
end

local BW_ItemSubDropDownMenu = CreateFrame("Frame", "BW_ItemSubDropDownMenu", UIParent, "BW_UIDropDownMenuTemplate")
--local BW_ItemSubDropDownMenu = BW_UIDropDownMenu_Create("BW_ItemSubDropDownMenu", UIParent)

BW_ItemSubDropDownMenu:SetFrameLevel(500)
local clickedItemID = nil;
local BW_ItemSubDropDownMenu_Table = {
	{
	text = L["View Sources"],
		func = function(self)   
			local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(clickedItemID)	
			addon.CollectionList:GenerateSourceListView(appearanceID)

		end,
		notCheckable = 1,
	},
	{
		text = CLOSE,
		func = function() BW_CloseDropDownMenus() end,
		notCheckable = 1,
	},
}
local BW_ExtraItemSubDropDownMenu_Table = {
	{
		text = L["Substitute Item"],
		func = function(self)    		
			BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_POPUP")
		end,
		notCheckable = 1,
	},
	{
	text = L["View Sources"],
		func = function(self)   
			local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(clickedItemID)	
			addon.CollectionList:GenerateSourceListView(appearanceID)

		end,
		notCheckable = 1,
	},
	{
		text = CLOSE,
		func = function() BW_CloseDropDownMenus() end,
		notCheckable = 1,
	},
}

StaticPopupDialogs["BETTER_WARDROBE_SUBITEM_INVALID_POPUP"] = {
	text = L["Not a valid itemID"],
	preferredIndex = 3,
	button1 = "OK",
	button2 = CANCEL,
	editBoxWidth = 260,
	EditBoxOnEnterPressed = function(self)
		if (self:GetParent().button1:IsEnabled()) then
			StaticPopup_OnClick(self:GetParent(), 1)
		end
	end,
	OnAccept = function(self)
		--ImportSet(self.editBox:GetText())
		 BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_POPUP")
	end,
	EditBoxOnEscapePressed = function()BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_POPUP") end,
	exclusive = true,
	whileDead = true,
}

StaticPopupDialogs["BETTER_WARDROBE_SUBITEM_WRONG_LOCATION_POPUP"] = {
	text = L["Item Locations Don't Match"],
	preferredIndex = 3,
	button1 = "OK",
	button2 = CANCEL,
	editBoxWidth = 260,
	EditBoxOnEnterPressed = function(self)
		if (self:GetParent().button1:IsEnabled()) then
			StaticPopup_OnClick(self:GetParent(), 1)
		end
	end,
	OnAccept = function(self)
		--ImportSet(self.editBox:GetText())
		 BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_POPUP")
	end,
	EditBoxOnEscapePressed = function()BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_POPUP") end,
	exclusive = true,
	whileDead = true,
}

StaticPopupDialogs["BETTER_WARDROBE_SUBITEM_POPUP"] = {
	text = L["Item ID"],
	preferredIndex = 3,
	button1 = L["Set Substitution"],
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 512,
	editBoxWidth = 260,
	OnShow = function(self)
		if LISTWINDOW then LISTWINDOW:Hide() end
		self.editBox:SetText("")
	end,
	EditBoxOnEnterPressed = function(self)
		if (self:GetParent().button1:IsEnabled()) then
			StaticPopup_OnClick(self:GetParent(), 1)
		end
	end,
	OnAccept = function(self)
		local value = self.editBox:GetText()
		local id = tonumber(value)

		if id == nil then BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_INVALID_POPUP")  return false end

		local itemEquipLoc1 = GetItemInfoInstant(tonumber(value)) 
		if not itemEquipLoc1 == nil then BetterWardrobeOutfitFrameMixin:ShowPopup("BETTER_WARDROBE_SUBITEM_INVALID_POPUP") return false end

		addon.SetItemSubstitute(clickedItemID, value)
		--ImportSet(self.editBox:GetText())
		clickedItemID = nil;
	end,
	EditBoxOnEscapePressed = HideParentPanel,
	exclusive = true,
	whileDead = true,
}

function BetterWardrobeSetsDetailsItemMixin:OnMouseDown(button)
	if ( IsModifiedClick("CHATLINK") ) then
		local sourceInfo = C_TransmogCollection.GetSourceInfo(self.sourceID)
		local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
		----local sources = C_TransmogSets.GetSourcesForSlot(self:GetParent():GetParent():GetSelectedSetID(), slot)
		--local sources = C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID)
		local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceInfo.visualID)	
		local sources = (sourceInfo and itemLink and C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID, addon.GetItemCategory(sourceInfo.visualID, sourceInfo.visualID), addon.GetTransmogLocation(itemLink)) ) or {}
 
		if ( #sources == 0 ) then
			-- can happen if a slot only has HiddenUntilCollected sources
			sources = sources or {}
			tinsert(sources, sourceInfo)
		end
		----WardrobeCollectionFrame_SortSources(sources, sourceInfo.visualID, self.sourceID)
		CollectionWardrobeUtil.SortSources(sources, sourceInfo.visualID, self.sourceID)
		if ( BetterWardrobeCollectionFrame.tooltipSourceIndex ) then
			local index = CollectionWardrobeUtil.GetValidIndexForNumSources(BetterWardrobeCollectionFrame.tooltipSourceIndex, #sources)
			local link = select(6, C_TransmogCollection.GetAppearanceSourceInfo(sources[index].sourceID))
			if ( link ) then
				HandleModifiedItemClick(link)
			end
		end
	elseif ( IsModifiedClick("DRESSUP") ) then
		DressUpVisual(self.sourceID)

	elseif button == "RightButton"  and BetterWardrobeCollectionFrame.selectedCollectionTab == 2 then ---TODO review;
		clickedItemID = self.itemID;
		BW_EasyMenu(BW_ItemSubDropDownMenu_Table, BW_ItemSubDropDownMenu, self, 0, 0, "MENU", 10)

	elseif button == "RightButton"  and BetterWardrobeCollectionFrame.selectedCollectionTab == 3 then ---TODO review;
		clickedItemID = self.itemID;
		BW_EasyMenu(BW_ExtraItemSubDropDownMenu_Table, BW_ItemSubDropDownMenu, self, 0, 0, "MENU", 10)
	end
end

BetterWardrobeSetsTransmogMixin = { }

function BetterWardrobeSetsTransmogMixin:OnLoad()
	self.NUM_ROWS = 2;
	self.NUM_COLS = 4;
	self.PAGE_SIZE = self.NUM_ROWS * self.NUM_COLS;
	self.APPLIED_SOURCE_INDEX = 1;
	self.SELECTED_SOURCE_INDEX = 3;

end




function BetterWardrobeSetsTransmogMixin:OnShow()
	self:RegisterEvent("TRANSMOGRIFY_UPDATE")
	self:RegisterEvent("TRANSMOGRIFY_SUCCESS")
	self:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
	--clearFilters()
	addon.SetsDataProvider:ClearSets()

	self:RefreshCameras()
	local RESET_SELECTION = true;
	self:Refresh(RESET_SELECTION)
	BetterWardrobeCollectionFrame.progressBar:Show()
	self:UpdateProgressBar()
	self.sourceQualityTable = { }


	----if HelpTip:IsShowing(BetterWardrobeCollectionFrame, TRANSMOG_SETS_VENDOR_TUTORIAL) then
		----HelpTip:Hide(BetterWardrobeCollectionFrame, TRANSMOG_SETS_VENDOR_TUTORIAL)
		----SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SETS_VENDOR_TAB, true)
	----end
end

function BetterWardrobeSetsTransmogMixin:OnHide()
	self:UnregisterEvent("TRANSMOGRIFY_UPDATE")
	self:UnregisterEvent("TRANSMOGRIFY_SUCCESS")
	self:UnregisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED")
	self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:UnregisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
	self.loadingSetID = nil;
	----SetsDataProvider:ClearSets()
	----resetFilters()
	self:GetParent():ClearSearch(Enum.TransmogSearchType.UsableSets)
	self.sourceQualityTable = nil;
	addon.ViewDelay = 3;
	----self:SetTab(1)
	

end

function BetterWardrobeSetsTransmogMixin:OnEvent(event, ...)
	if ( event == "TRANSMOGRIFY_UPDATE" or event == "TRANSMOGRIFY_SUCCESS" )  then
		-- these event can fire multiple times for set interaction, once for each slot in the set
		if ( not self.pendingRefresh ) then
			self.pendingRefresh = true;
			C_Timer.After(0, function()
				self.pendingRefresh = nil;
				if self:IsShown() then
					local resetSelection = (event == "TRANSMOGRIFY_SUCCESS")
					--Changed the above to Success rather than Update so it only changes back to page 1 when you apply the look;
					self:Refresh(resetSelection)
				end
			end)
		end
	elseif ( event == "TRANSMOG_COLLECTION_UPDATED" or event == "TRANSMOG_SETS_UPDATE_FAVORITE" ) then
		SetsDataProvider:ClearSets()
		self:Refresh()
		self:UpdateProgressBar()
	elseif ( event == "TRANSMOG_COLLECTION_ITEM_UPDATE" ) then
		if ( self.loadingSetID ) then
			local setID = self.loadingSetID;
			self.loadingSetID = nil;
			self:LoadSet(setID)
		end
		if ( self.tooltipModel ) then
			self.tooltipModel:RefreshTooltip()
		end
	elseif ( event == "PLAYER_EQUIPMENT_CHANGED" ) then
		if ( self.selectedSetID ) then
			self:LoadSet(self.selectedSetID)
		end
		self:Refresh()
	end
end

function BetterWardrobeSetsTransmogMixin:OnMouseWheel(value)
	self.PagingFrame:OnMouseWheel(value)
end

function BetterWardrobeSetsTransmogMixin:UpdateProgressBar()
	----WardrobeCollectionFrame_UpdateProgressBar(addon.C_TransmogSets.GetBaseSetsCounts())

	self:GetParent():UpdateProgressBar(C_TransmogSets.GetBaseSetsCounts())
end

function BetterWardrobeSetsTransmogMixin:Refresh(resetSelection)

	----TODO:REVISIT  --disable fixes sets jumping on selection;

--	if BetterWardrobeCollectionFrame:CheckTab(2) then
		---self.appliedSetID = self:GetFirstMatchingSetID(self.APPLIED_SOURCE_INDEX)
		--if ( resetSelection ) then
		--	self.selectedSetID = self:GetFirstMatchingSetID(self.SELECTED_SOURCE_INDEX)
		--	self:ResetPage()
		--else
			--self:UpdateSets()
	--	end
	--else


		--self.appliedSetID = self.APPLIED_SOURCE_INDEX;
		if ( resetSelection ) then
			--self.selectedSetID = self.SELECTED_SOURCE_INDEX;
			self:ResetPage()
		else
			self:UpdateSets()
		end
	--end
end


local function SetModelUnit(model)
		local _, raceFilename = UnitRace("player");
		local gender = UnitSex("player") 

		if (raceFilename == "Dracthyr" or raceFilename == "Worgen") then
			local modelID, altModelID
			if raceFilename == "Worgen" then
				if gender == 3 then
					modelID = 307453
					altModelID = 1000764
				else
					modelID = 307454
					altModelID = 1011653
				end

			elseif raceFilename == "Dracthyr" then
				modelID = 4207724

				if gender == 3 then
					altModelID = 4220448
				else
					altModelID = 4395382
				end
			end

			if not addon.useNativeForm then
				model:SetUnit("player", false, false)
				model:SetModel(altModelID)	
			else
				model:SetUnit("player", false, true)
				model:SetModel(modelID)
			end
		else
			model:SetUnit("player", false, true)
		end
	end

function BetterWardrobeSetsTransmogMixin:UpdateSets()
	if BetterWardrobeCollectionFrame:CheckTab(2) then
		local usableSets = SetsDataProvider:GetUsableSets(true)
		self.PagingFrame:SetMaxPages(ceil(#usableSets / self.PAGE_SIZE))
		local pendingTransmogModelFrame = nil;
		local indexOffset = (self.PagingFrame:GetCurrentPage() - 1) * self.PAGE_SIZE;
		for i = 1, self.PAGE_SIZE do
			local model = self.Models[i]
			local index = i + indexOffset;
			local set = usableSets[index]
			local hasAlternateForm = false


			if (set) then
				SetModelUnit(model)
				model:Show()

				--if (model.setID ~= set.setID) then
					model:Undress()
					local sourceData = SetsDataProvider:GetSetSourceData(set.setID)

					for sourceID in pairs(sourceData.sources) do
						--if (not Profile.HideMissing and not BW_WardrobeToggle.VisualMode) or (Profile.HideMissing and BW_WardrobeToggle.VisualMode) or (Profile.HideMissing and isMogKnown(sourceID)) then 
						if (not addon.Profile.HideMissing and (not BetterWardrobeVisualToggle.VisualMode or (Sets.isMogKnown(sourceID) and BetterWardrobeVisualToggle.VisualMode))) or 
							(addon.Profile.HideMissing and (BetterWardrobeVisualToggle.VisualMode or Sets.isMogKnown(sourceID))) then 
							model:TryOn(sourceID)
						end
						if not hasAlternateForm and addon:CheckAltItem(sourceID) then
							hasAlternateForm = true
						end
						if hasAlternateForm then
							model.AltItemtems:Show()--local f = CreateFrame("Frame", "112cd2", model, "AltItemtemplate")
						else
							model.AltItemtems:Hide()
						end
					end
					--end
			

				local transmogStateAtlas;
				if (set.setID == self.appliedSetID and set.setID == self.selectedSetID) then
					transmogStateAtlas = "transmog-set-border-current-transmogged"
				elseif (set.setID == self.selectedSetID) then
					transmogStateAtlas = "transmog-set-border-selected"
					pendingTransmogModelFrame = model;
				end

				if (transmogStateAtlas) then
					model.TransmogStateTexture:SetAtlas(transmogStateAtlas, true)
					model.TransmogStateTexture:Show()
				else
					model.TransmogStateTexture:Hide()
				end

				local topSourcesCollected, topSourcesTotal;
				topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceCounts(set.setID) 
	 
				local setInfo = C_TransmogSets.GetSetInfo(set.setID)
				if setInfo then 
					model.Favorite.Icon:SetShown(C_TransmogSets.GetIsFavorite(set.setID))
					model.setID = set.setID;

					local isHidden = addon.HiddenAppearanceDB.profile.set[set.setID]
					model.CollectionListVisual.Hidden.Icon:SetShown(isHidden)


					local isInList = addon.CollectionList:IsInList(set.setID, "set")
					model.CollectionListVisual.Collection.Collection_Icon:SetShown(isInList)
					model.CollectionListVisual.Collection.Collected_Icon:SetShown(isInList and C_TransmogSets.IsBaseSetCollected(set.setID))

					--model.SetInfo.setName:SetText((addon.Profile.ShowNames and setInfo["name"].."\n"..(setInfo["description"] or "")) or "")

					local name = setInfo["name"]
					local description = "\n"..(setInfo["description"] or "")
					
					--local description = (setInfo["description"] and "\n-"..setInfo["description"].."-") or ""
					--local classname = (setInfo.className and "\n ("..setInfo.className..")") or ""
					if addon.Profile.ShowNames then 
						model.SetInfo.setName:Show()
						model.SetInfo.setName:SetText(("%s%s"):format(name, description))
					else
						model.SetInfo.setName:Hide()
					end

					model.SetInfo.progress:SetText((addon.Profile.ShowSetCount and topSourcesCollected.."/".. topSourcesTotal) or "")
					model.setCollected = topSourcesCollected == topSourcesTotal;
				end

			else
				model:Hide()
			end
		end

		if (pendingTransmogModelFrame) then
			self.PendingTransmogFrame:SetParent(pendingTransmogModelFrame)
			self.PendingTransmogFrame:SetPoint("CENTER")
			self.PendingTransmogFrame:Show()
			if (self.PendingTransmogFrame.setID ~= pendingTransmogModelFrame.setID) then
				self.PendingTransmogFrame.TransmogSelectedAnim:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim2:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim2:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim3:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim3:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim4:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim4:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim5:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim5:Play()
			end
			self.PendingTransmogFrame.setID = pendingTransmogModelFrame.setID;
		else
			self.PendingTransmogFrame:Hide()
		end

		self.NoValidSetsLabel:SetShown(not C_TransmogSets.HasUsableSets())

	else

		local usableSets = SetsDataProvider:GetUsableSets()
		self.PagingFrame:SetMaxPages(ceil(#usableSets / self.PAGE_SIZE))
		local pendingTransmogModelFrame = nil;
		local indexOffset = (self.PagingFrame:GetCurrentPage() - 1) * self.PAGE_SIZE;
		for i = 1, self.PAGE_SIZE do
			local model = self.Models[i]
			local index = i + indexOffset;
			local hasAlternateForm = false

			set = usableSets[index]
			if ( set ) then
				local setType =  addon.GetSetType(set.setID)
				SetModelUnit(model)

				model:Show()
				if setType == "SavedBlizzard" then 
					local sources  = C_TransmogCollection.GetOutfitItemTransmogInfoList(addon:GetBlizzID(set.setID))
					model:Undress()
					for slotID, itemTransmogInfo in ipairs(sources) do
						local canRecurse = false;
						if slotID == 17 then
							local transmogLocation = TransmogUtil.GetTransmogLocation("MAINHANDSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
							local mainHandCategoryID = C_Transmog.GetSlotEffectiveCategory(transmogLocation)
							canRecurse = TransmogUtil.IsCategoryLegionArtifact(mainHandCategoryID)
						end
						model:SetItemTransmogInfo(itemTransmogInfo, slotID, canRecurse)

						model.AltItemtems:Hide()

					end
				elseif setType then 				
						--if ( model.setID ~= set.setID ) then
					model:Undress()
					local primaryAppearances = {}
					local sourceData = SetsDataProvider:GetSetSourceData(set.setID)
					local tab = BetterWardrobeCollectionFrame.selectedTransmogTab;
					for sourceID in pairs(sourceData.sources) do
						if (tab == 4 and not BetterWardrobeVisualToggle.VisualMode) or
									(CollectionsJournal:IsShown()) or
									(not addon.Profile.HideMissing and (not BetterWardrobeVisualToggle.VisualMode or (Sets.isMogKnown(sourceID) and BetterWardrobeVisualToggle.VisualMode))) or
									(addon.Profile.HideMissing and (BetterWardrobeVisualToggle.VisualMode or Sets.isMogKnown(sourceID))) then
										--print(sourceID)
							model:TryOn(sourceID)
						--else
						end

						if not hasAlternateForm and addon:CheckAltItem(sourceID) then
							hasAlternateForm = true
						end
					end
				else
					model:Undress()

					--print("extraset")
					--local  setData = addon.GetSetInfo(set.setID)
					local sourceData = SetsDataProvider:GetSetSourceData(set.setID)
					local tab = BetterWardrobeCollectionFrame.selectedTransmogTab;
					for sourceID in pairs(sourceData.sources) do
						--print(sourceID)
						--if (tab == 4 and not BetterWardrobeVisualToggle.VisualMode) or
						--	(CollectionsJournal:IsShown()) or
							--(not addon.Profile.HideMissing and (not BetterWardrobeVisualToggle.VisualMode or (Sets.isMogKnown(sourceID) and BetterWardrobeVisualToggle.VisualMode))) or
							--(addon.Profile.HideMissing and (BetterWardrobeVisualToggle.VisualMode or Sets.isMogKnown(sourceID))) then
							--	print(sourceID)
						if not hasAlternateForm and addon:CheckAltItem(sourceID) then
							hasAlternateForm = true
						end
							model:TryOn(sourceID)
						--else
					--	end
					end
				end

				if addon.GetSetType(set.setID)  then
					local baseSourceID = C_Transmog.GetSlotVisualInfo(TransmogUtil.GetTransmogLocation("SHOULDERSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary))
					if set.mainShoulder and set.offShoulder ~= 0 and set.offShoulder ~= baseSourceID then
						local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(set.mainShoulder, set.offShoulder, 0)
						local result = model:SetItemTransmogInfo(itemTransmogInfo)
					elseif set.mainShoulder then 
						local transmogLocation = TransmogUtil.GetTransmogLocation(3, Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary)
						if C_Transmog.CanHaveSecondaryAppearanceForSlotID(3) then
							local itemTransmogInfo = ItemUtil.CreateItemTransmogInfo(set.mainShoulder, set.offShoulder, 0)
							if transmogLocation:IsSecondary() then
								itemTransmogInfo.secondaryAppearanceID = set.mainShoulder;
							else
								-- if the item on the actor doesn't already have a secondary, copy over one to the other (items previewed via other means do not have secondaries set)
								if itemTransmogInfo.secondaryAppearanceID == Constants.Transmog.NoTransmogID then
									itemTransmogInfo.secondaryAppearanceID = itemTransmogInfo.appearanceID;
								end
								itemTransmogInfo.appearanceID = set.mainShoulder;
							end
							local result = model:SetItemTransmogInfo(itemTransmogInfo)
						end
					end
				end

				local transmogStateAtlas;
				if ( set.setID == self.appliedSetID and set.setID == self.selectedSetID ) then
					transmogStateAtlas = "transmog-set-border-current-transmogged"
				elseif ( set.setID == self.selectedSetID ) then
					transmogStateAtlas = "transmog-set-border-selected"
					pendingTransmogModelFrame = model;
				elseif not set.isClass then 
					transmogStateAtlas = "transmog-set-border-unusable"
					model.TransmogStateTexture:SetPoint("CENTER",0,-2)
				end
				if ( transmogStateAtlas ) then
					model.TransmogStateTexture:SetAtlas(transmogStateAtlas, true)
					model.TransmogStateTexture:Show()
				else
					model.TransmogStateTexture:Hide()
				end

				if hasAlternateForm then
					model.AltItemtems:Show()
				else
					model.AltItemtems:Hide()
				end

				local topSourcesCollected, topSourcesTotal;
				--if addon.Profile.ShowIncomplete then
					--topSourcesCollected, topSourcesTotal = addon.Sets:GetLocationBasedCount(set)
				--else
					topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceCounts(set.setID)
				--end

				local setInfo = addon.GetSetInfo(set.setID)
				local isFavorite = addon.favoritesDB.profile.extraset[set.setID]
				local isHidden = addon.HiddenAppearanceDB.profile.extraset[set.setID]
				model.setCollected = topSourcesCollected == topSourcesTotal;
				model.Favorite.Icon:SetShown(isFavorite)
				model.CollectionListVisual.Hidden.Icon:SetShown(isHidden)
				
				local isInList = addon.CollectionList:IsInList(set.setID, "extraset")
				model.CollectionListVisual.Collection.Collection_Icon:SetShown(isInList)
				model.CollectionListVisual.Collection.Collected_Icon:SetShown(isInList and model.setCollected)
				--model.CollectionListVisual.Collection.Collected_Icon:SetShown(false)
				model.setID = set.setID;
				local name = setInfo["name"]
				--local description = "\n"..set and set.label or ""
				local description =  ""

				--local description = (setInfo["description"] and "\n-"..setInfo["description"].."-") or ""
				local classname = (setInfo.className and "\n ("..setInfo.className..")") or ""

				if addon.Profile.ShowNames then 
					model.SetInfo.setName:Show()
					model.SetInfo.setName:SetText(("%s%s%s"):format(name, description, classname or ""))
				else
					model.SetInfo.setName:Hide()
				end

				if BetterWardrobeCollectionFrame:CheckTab(4) then
					model.SetInfo.progress:Hide()
				else
					model.SetInfo.progress:Show()
					model.SetInfo.progress:SetText(topSourcesCollected.."/".. topSourcesTotal)
				end
		
			else
				model:Hide()
			end
		end

		if ( pendingTransmogModelFrame ) then
			self.PendingTransmogFrame:SetParent(pendingTransmogModelFrame)
			self.PendingTransmogFrame:SetPoint("CENTER")
			self.PendingTransmogFrame:Show()
			if ( self.PendingTransmogFrame.setID ~= pendingTransmogModelFrame.setID ) then
				self.PendingTransmogFrame.TransmogSelectedAnim:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim2:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim2:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim3:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim3:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim4:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim4:Play()
				self.PendingTransmogFrame.TransmogSelectedAnim5:Stop()
				self.PendingTransmogFrame.TransmogSelectedAnim5:Play()
			end
			self.PendingTransmogFrame.setID = pendingTransmogModelFrame.setID;
		else
			self.PendingTransmogFrame:Hide()
		end

		self.NoValidSetsLabel:SetShown(not C_TransmogSets.HasUsableSets())
	end

end

function BetterWardrobeSetsTransmogMixin:OnPageChanged(userAction)
	PlaySound(SOUNDKIT.UI_TRANSMOG_PAGE_TURN)
	CloseDropDownMenus()
	if ( userAction ) then
		self:UpdateSets()
	end
end

function BetterWardrobeSetsTransmogMixin:LoadSet(setID)
	local waitingOnData = false;
	local transmogSources = { }
	local setType = addon.GetSetType(setID)
	local offShoulder;
	local mainHandEnchant;
	local offHandEnchant;
	local setData;
	--Default Saved sets;
	if setType == "SavedBlizzard" then
		local setSources = addon.C_TransmogSets.GetSetSources(setID)
		for sourceID in pairs(setSources) do
			local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
			if sourceInfo then 
				local appearanceID = sourceInfo.visualID;
				local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
				if slot then 
					local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)	
					local sources = (sourceInfo and itemLink and C_TransmogCollection.GetAppearanceSources(appearanceID, addon.GetItemCategory(appearanceID), addon.GetTransmogLocation(itemLink)) )
					--local sources = sourceInfo and C_TransmogCollection.GetAppearanceSources(appearanceID)
					if sources and #sources > 0  then 
						CollectionWardrobeUtil.SortSources(sources, appearanceID)
						local index = CollectionWardrobeUtil.GetDefaultSourceIndex(sources, sourceID)
						transmogSources[slot] = sources[index].sourceID;

						for i, slotSourceInfo in ipairs(sources) do
							if ( not slotSourceInfo.name ) then
								waitingOnData = true;
							end
						end
					end
				end
			end
		end
		C_Transmog.LoadOutfit(addon:GetBlizzID(setID))
	else
		if (not setType) or setType == "BlizzardSet"  then
			local setID = setID;
			local primaryAppearances = C_TransmogSets.GetSetPrimaryAppearances(setID)
			for i, primaryAppearance in ipairs(primaryAppearances) do
				local sourceID = primaryAppearance.appearanceID;
				local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				local slot = sourceInfo and C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
				if slot then 
					local slotSources = C_TransmogSets.GetSourcesForSlot(setID, slot)
					if slotSources and #slotSources > 0  then 

						CollectionWardrobeUtil.SortSources(slotSources, sourceInfo.visualID)
						local index = CollectionWardrobeUtil.GetDefaultSourceIndex(slotSources, sourceID)




						if slot then
							transmogSources[slot] = slotSources[index].sourceID;

							for i, slotSourceInfo in ipairs(slotSources) do
								if ( not slotSourceInfo.name ) then
									waitingOnData = true;
								end
							end
						end
					end
				end
			end

		else

			setData = addon.GetSetInfo(setID)
			offShoulder = setData.offShoulder or 0;
			mainHandEnchant = setData.mainHandEnchant or 0;
			offHandEnchant = setData.offHandEnchant or 0;

			if setData.itemData then 
				for slotID, slotData in pairs(setData.itemData) do
					local sourceID = slotData[2]
					local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
					if sourceInfo then 

						local appearanceID = slotData[3]
						local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
						if slot then 
							local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)	
							local sources = (sourceInfo and itemLink and C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID, addon.GetItemCategory(sourceInfo.visualID), addon.GetTransmogLocation(itemLink)) )
							--local sources = sourceInfo and C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID)

							if sources and #sources > 0  then 
								CollectionWardrobeUtil.SortSources(sources, sourceInfo.visualID)
								local index = CollectionWardrobeUtil.GetDefaultSourceIndex(sources, sourceID)
								transmogSources[slot] = sources[index].sourceID;

								for i, slotSourceInfo in ipairs(sources) do
									if ( not slotSourceInfo.name ) then
										waitingOnData = true;
									end
								end
							end
						end
					end
				end

			
				--for slotID, data in pairs(setData.itemData) do
					--transmogSources[slotID] = data[2]
				--end
			end
		end

		if ( waitingOnData ) then
			self.loadingSetID = setID;
		else
			self.loadingSetID = nil;
			local transmogLocation, pendingInfo;
			for slotID, appearanceID in pairs(transmogSources) do
				transmogLocation = TransmogUtil.CreateTransmogLocation(slotID, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
				pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, appearanceID)
				C_Transmog.SetPending(transmogLocation, pendingInfo)

				if  addon:CheckAltItem(appearanceID) and _G["BW_AltIcon"..slotID] then
					_G["BW_AltIcon"..slotID]:Show()
				elseif not addon:CheckAltItem(appearanceID) and _G["BW_AltIcon"..slotID] then
					_G["BW_AltIcon"..slotID]:Hide()
				end
			end

			-- for slots that are be split, undo it
			if C_Transmog.CanHaveSecondaryAppearanceForSlotID(3) then
				local TransmogLocation = TransmogUtil.CreateTransmogLocation(3, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
				local secondaryTransmogLocation = TransmogUtil.CreateTransmogLocation(3, Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary)
				local baseSourceID = C_Transmog.GetSlotVisualInfo(TransmogUtil.GetTransmogLocation("SHOULDERSLOT", Enum.TransmogType.Appearance, Enum.TransmogModification.Secondary))

				if offShoulder and offShoulder ~= 0 and offShoulder ~= baseSourceID then
					local secondaryPendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, offShoulder or Constants.Transmog.NoTransmogID)
					C_Transmog.SetPending(secondaryTransmogLocation, secondaryPendingInfo)
				else 
					--	local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.ToggleOff)
					--C_Transmog.SetPending(secondaryTransmogLocation, pendingInfo)
					C_Transmog.ClearPending(secondaryTransmogLocation)

				end
			end

			--[[if setData then
										local TransmogLocation = TransmogUtil.CreateTransmogLocation(16, Enum.TransmogType.Illusion, Enum.TransmogModification.Main)
										local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, setData.mainHandEnchant or 0)
										C_Transmog.SetPending(TransmogLocation, pendingInfo)
						
										local TransmogLocation = TransmogUtil.CreateTransmogLocation(17, Enum.TransmogType.Illusion, Enum.TransmogModification.Main)
										local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, setData.offHandEnchant or 0)
										C_Transmog.SetPending(TransmogLocation, pendingInfo)
									end]]
		end
	end
	local emptySlotData = Sets:GetEmptySlots()
	if addon.Profile.HiddenMog then	
		local clearSlots = Sets:EmptySlots(transmogSources)
		for i, x in pairs(clearSlots) do
			local _, source = addon.GetItemSource(x) --C_TransmogCollection.GetItemInfo(x)
			--C_Transmog.SetPending(i, Enum.TransmogType.Appearance,source)
			local transmogLocation = TransmogUtil.GetTransmogLocation(i, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
			local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, source)

			-----C_Transmog.SetPending(transmogLocation, source, Enum.TransmogType.Appearance)
			C_Transmog.SetPending(transmogLocation, pendingInfo)
		end
				
		for i, x in pairs(transmogSources) do
			if not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(x) and (i ~= 7 or i ~= 4 or i ~= 19) and emptySlotData[i] then
				local _, source = addon.GetItemSource(emptySlotData[i]) --C_TransmogCollection.GetItemInfo(emptySlotData[i])
				--C_Transmog.SetPending(i, Enum.TransmogType.Appearance, source)		
				local transmogLocation = TransmogUtil.GetTransmogLocation(i, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
				local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, source)
				-----C_Transmog.SetPending(transmogLocation, source, Enum.TransmogType.Appearance)
				C_Transmog.SetPending(transmogLocation, pendingInfo)
			end
		end
	end

	--hide any slots marked as alwayws hide;
	local alwaysHideSlots = addon.setdb.profile.autoHideSlot;
	for key, transmogSlot in pairs(TRANSMOG_SLOTS) do
		local slotID = transmogSlot.location:GetSlotID()
		if alwaysHideSlots[slotID] then 
			local transmogLocation = TransmogUtil.GetTransmogLocation(slotID, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
			local _, source = addon.GetItemSource(emptySlotData[slotID]) -- C_TransmogCollection.GetItemInfo(emptySlotData[i])
			local pendingInfo = TransmogUtil.CreateTransmogPendingInfo(Enum.TransmogPendingType.Apply, source)

		-----C_Transmog.SetPending(transmogLocation, source, Enum.TransmogType.Appearance)
		C_Transmog.SetPending(transmogLocation, pendingInfo);	
		end
	end	
end


function BetterWardrobeSetsTransmogMixin:GetFirstMatchingSetID(sourceIndex)
	local transmogSourceIDs = { }
	for _, button in ipairs(WardrobeTransmogFrame.SlotButtons) do
		if not button.transmogLocation:IsSecondary() then
			local sourceID = select(sourceIndex, TransmogUtil.GetInfoForEquippedSlot(button.transmogLocation))
			if ( sourceID ~= Constants.Transmog.NoTransmogID ) then
				transmogSourceIDs[button.transmogLocation:GetSlotID()] = sourceID;
			end
		end
	end

	local usableSets = SetsDataProvider:GetUsableSets()
	for _, set in ipairs(usableSets) do
		local setMatched = false;
		for slotID, transmogSourceID in pairs(transmogSourceIDs) do
			local sourceIDs = C_TransmogSets.GetSourceIDsForSlot(set.setID, slotID)
			-- if there are no sources for a slot, that slot is considered matched
			local slotMatched = (#sourceIDs == 0)
			for _, sourceID in ipairs(sourceIDs) do
				if ( transmogSourceID == sourceID ) then
					slotMatched = true;
					break;
				end
			end
			setMatched = slotMatched;
			if ( not setMatched ) then
				break;
			end
		end
		if ( setMatched ) then
			return set.setID;
		end
	end
	return nil;
end

function BetterWardrobeSetsTransmogMixin:OnUnitModelChangedEvent()
	if ( IsUnitModelReadyForUI("player") ) then
		for i, model in ipairs(self.Models) do
			model:RefreshUnit()
			model.setID = nil;
		end
		self:RefreshCameras()
		self:UpdateSets()
		return true;
	else
		return false;
	end
end

function BetterWardrobeSetsTransmogMixin:RefreshCameras()
	if ( self:IsShown() ) then
		local detailsCameraID, transmogCameraID = GetFormCameraInfo()--C_TransmogSets.GetCameraIDs()

		for i, model in ipairs(self.Models) do
			model.cameraID = transmogCameraID;
			model:RefreshCamera()
			addon.Model_ApplyUICamera(model, transmogCameraID)
		end
	end
end

function BetterWardrobeSetsTransmogMixin:OnSearchUpdate()
	SetsDataProvider:ClearUsableSets()
	self:UpdateSets()
end

function BetterWardrobeSetsTransmogMixin:SelectSet(setID)
  --TODO REVISIT FOR OTHE SET TYopes;
	self.selectedSetID = setID;
	selected = true;
	self:LoadSet(setID)
	if addon.GetSetType(setID) then
		if (setID) then
		name = addon.GetOutfitName(setID)
	end
	if ( name ) then
		BW_UIDropDownMenu_SetText(BetterWardrobeOutfitDropDown, name)
	else
		outfitID = nil;
		BW_UIDropDownMenu_SetText(BetterWardrobeOutfitDropDown, GRAY_FONT_COLOR_CODE..TRANSMOG_OUTFIT_NONE..FONT_COLOR_CODE_CLOSE)
	end

	BetterWardrobeOutfitDropDown.selectedOutfitID = setID;

	BetterWardrobeOutfitDropDown:UpdateSaveButton()
	BetterWardrobeOutfitDropDown:OnSelectOutfit(setID)
	end
	--self:ResetPage()
end

function BetterWardrobeSetsTransmogMixin:CanHandleKey(key)
	if ( key == WARDROBE_PREV_VISUAL_KEY or key == WARDROBE_NEXT_VISUAL_KEY or key == WARDROBE_UP_VISUAL_KEY or key == WARDROBE_DOWN_VISUAL_KEY ) then
		return true;
	end
	return false;
end

function BetterWardrobeSetsTransmogMixin:HandleKey(key)
	if not self.selectedSetID then
		return;
	end

	local setIndex;
	local usableSets = SetsDataProvider:GetUsableSets()
	for i = 1, #usableSets do
		if (usableSets[i].setID == self.selectedSetID) then
			setIndex = i;
			break;
		end
	end

	if setIndex then
		setIndex = GetAdjustedDisplayIndexFromKeyPress(self, setIndex, #usableSets, key)
		self:SelectSet(usableSets[setIndex].setID)
	end
end

function BetterWardrobeSetsTransmogMixin:ResetPage()
	local page = 1;
	if self.selectedSetID then
		local usableSets = SetsDataProvider:GetUsableSets(BetterWardrobeCollectionFrame:CheckTab(2) and addon.Profile.ShowIncomplete)
		self.PagingFrame:SetMaxPages(ceil(#usableSets / self.PAGE_SIZE))
		for i, set in ipairs(usableSets) do
			if set.setID == self.selectedSetID then
				page = GetPage(i, self.PAGE_SIZE)
				break;
			end
		end
	end
	self.PagingFrame:SetCurrentPage(page)
	self:UpdateSets()
end

function BetterWardrobeSetsTransmogMixin:OpenRightClickDropDown()
	--Default;
--[[	local setID = self.RightClickDropDown.activeFrame.setID;
	local info = BW_UIDropDownMenu_CreateInfo()
	if ( C_TransmogSets.GetIsFavorite(setID) ) then
		info.text = BATTLE_PET_UNFAVORITE;
		info.func = function() self:SetFavorite(setID, false); end
	else
		info.text = BATTLE_PET_FAVORITE;
		info.func = function() self:SetFavorite(setID, true); end
	end
	info.notCheckable = true;
	BW_UIDropDownMenu_AddButton(info)
	-- Cancel
	info = BW_UIDropDownMenu_CreateInfo()
	info.notCheckable = true;
	info.text = CANCEL;
	BW_UIDropDownMenu_AddButton(info);]]
	if (not self.RightClickDropDown.activeFrame) then
		return;
	end
	local tab = addon.GetTab()
	local type = tabType[addon.GetTab()]
	local setID = self.RightClickDropDown.activeFrame.setID;
	local info = BW_UIDropDownMenu_CreateInfo()

	if tab == 2 then
		if ( C_TransmogSets.GetIsFavorite(setID) ) then
			info.text = BATTLE_PET_UNFAVORITE;
			info.func = function() self:SetFavorite(setID, false); end
		else
			info.text = BATTLE_PET_FAVORITE;
			info.func = function() self:SetFavorite(setID, true); end
		end
		info.notCheckable = true;
		BW_UIDropDownMenu_AddButton(info)
		-- Cancel
		info = BW_UIDropDownMenu_CreateInfo()
		info.notCheckable = true;
		info.text = CANCEL;
		BW_UIDropDownMenu_AddButton(info)
	else

		local isFavorite = addon.favoritesDB.profile.extraset[setID]
		if (isFavorite) then
			info.text = BATTLE_PET_UNFAVORITE;
			info.func = function()
				addon.favoritesDB.profile.extraset[setID] = nil;
				RefreshLists()
			 end
		else
			info.text = BATTLE_PET_FAVORITE;
			info.func = function()
				addon.favoritesDB.profile.extraset[setID] = true;
				RefreshLists()
			end
		end
		info.notCheckable = true;
		BW_UIDropDownMenu_AddButton(info)
		-- Cancel
		info = BW_UIDropDownMenu_CreateInfo()
		info.notCheckable = true;
		info.text = CANCEL;
		BW_UIDropDownMenu_AddButton(info)
	end


	if tab ~= 4 then 
		local variantTarget, match, matchType;
		local variantType = ""
		if type == "set" or type =="extraset" then
			BW_UIDropDownMenu_AddSeparator()
			BW_UIDropDownMenu_AddButton({
					notCheckable = true,
					text = L["Queue Transmog"],
					func = function()

						local setInfo = addon.GetSetInfo(setID) or C_TransmogSets.GetSetInfo(setID)
						local name = setInfo["name"]
						--addon.QueueForTransmog(type, setID, name)
						addon.QueueList = {type, setID, name}
					 end,
					})
			if type == "set" then 
				variantTarget, variantType, match, matchType = addon.Sets:SelectedVariant(setID)
			end
		end

		BW_UIDropDownMenu_AddSeparator()
		local isHidden = addon.HiddenAppearanceDB.profile[type][setID]
		BW_UIDropDownMenu_AddButton({
			notCheckable = true,
			text = isHidden and SHOW or HIDE,
			func = function()self.setID = setID; ToggleHidden(self, isHidden) end,
		})

		local collected = (self.visualInfo and self.visualInfo.isCollected)
		--Collection List Right Click options;
		local collectionList = addon.CollectionList:CurrentList()
		local isInList = match or addon.CollectionList:IsInList(setID, type)

		--if  type  == "set" or ((isInList and collected) or not collected)then --(type == "item" and not (model.visualInfo and model.visualInfo.isCollected)) or type == "set" or type == "extraset" then
			local targetSet = match or variantTarget or setID;
			local targetText = match and " - "..matchType or variantTarget and " - "..variantType or ""
			BW_UIDropDownMenu_AddSeparator()
			local isInList = collectionList[type][targetSet]
			BW_UIDropDownMenu_AddButton({
				notCheckable = true,
				text = isInList and L["Remove from Collection List"]..targetText or L["Add to Collection List"]..targetText,
				func = function()
							addon.CollectionList:UpdateList(type, targetSet, not isInList)
					end,
			})
			--end
	end
end

function BetterWardrobeSetsTransmogMixin:SetFavorite(setID, favorite)
	if favorite then
		-- remove any existing favorite in this group
		local isFavorite, isGroupFavorite = C_TransmogSets.GetIsFavorite(setID)
		if isGroupFavorite then
			local baseSetID = C_TransmogSets.GetBaseSetID(setID)
			C_TransmogSets.SetIsFavorite(baseSetID, false)
			local variantSets = C_TransmogSets.GetVariantSets(baseSetID)
			for i, variantSet in ipairs(variantSets) do
				C_TransmogSets.SetIsFavorite(variantSet.setID, false)
			end
		end
		C_TransmogSets.SetIsFavorite(setID, true)
	else
		C_TransmogSets.SetIsFavorite(setID, false)
	end
	RefreshLists()
end

do
	local function OpenRightClickDropDown(self)
		self:GetParent():OpenRightClickDropDown()
	end
	function BetterWardrobeSetsTransmogModelRightClickDropDown_OnLoad(self)
		BW_UIDropDownMenu_Initialize(self, OpenRightClickDropDown, "MENU")
	end
end


--Visual View TOggle;
	BetterWardrobeVisualToggleMixin = {}

	function BetterWardrobeVisualToggleMixin:OnClick()
		local baseFrame;
		self.viewAll = false;
		local aCtrlKeyIsDown = IsControlKeyDown()

		if aCtrlKeyIsDown then
				addon.Profile.ShowHidden = not addon.Profile.ShowHidden;
				------BetterWardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()
				--BW_SetsTransmogFrame:OnSearchUpdate()
				-----BetterWardrobeCollectionFrame.SetsCollectionFrame:OnSearchUpdate()
				-----BW_SetsCollectionFrame:OnSearchUpdate()
				return;
		end

		local atTransmogrifier = C_Transmog.IsAtTransmogNPC()
		if (atTransmogrifier) then
			local tab = BetterWardrobeCollectionFrame.selectedTransmogTab;
			if tab == 2  or tab == 3  or tab == 4 then 
				self.VisualMode = not self.VisualMode;
				------BetterWardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()
				--BW_SetsTransmogFrame:OnSearchUpdate()
			end
		else
			local tab = BetterWardrobeCollectionFrame.selectedCollectionTab;
			if tab == 2 then
				if BetterWardrobeCollectionFrame.SetsCollectionFrame:IsShown() then
					self.VisualMode = true;
					self.viewAll = true;
					BetterWardrobeCollectionFrame.SetsTransmogFrame:Show()
					BetterWardrobeCollectionFrame.SetsCollectionFrame:Hide()
					BetterWardrobeCollectionFrame.activeFrame = BetterWardrobeCollectionFrame.SetsTransmogFrame;
					------BetterWardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()
					BetterWardrobeCollectionFrame.FilterButton:Hide()
				else
					self.VisualMode = false;
					self.viewAll = false;
					BetterWardrobeCollectionFrame.SetsTransmogFrame:Hide()
					BetterWardrobeCollectionFrame.SetsCollectionFrame:Show()
					BetterWardrobeCollectionFrame.FilterButton:Show()
					BetterWardrobeCollectionFrame.activeFrame = BetterWardrobeCollectionFrame.SetsCollectionFrame;
				end

			elseif tab == 3 or tab == 4 then
				if BetterWardrobeCollectionFrame.SetsCollectionFrame:IsShown() then
					self.VisualMode = true;
					self.viewAll = true;
					BetterWardrobeCollectionFrame.SetsTransmogFrame:Show()
					BetterWardrobeCollectionFrame.SetsCollectionFrame:Hide()
					BetterWardrobeCollectionFrame.activeFrame = BetterWardrobeCollectionFrame.SetsTransmogFrame;
					--------BetterWardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()
				else
					self.VisualMode = false;
					self.viewAll = false;
					BetterWardrobeCollectionFrame.SetsTransmogFrame:Hide()
					BetterWardrobeCollectionFrame.SetsCollectionFrame:Show()
					BetterWardrobeCollectionFrame.activeFrame = BetterWardrobeCollectionFrame.SetsCollectionFrame;
					----BetterWardrobeCollectionFrame.activeFrame = BetterWardrobeCollectionFrame.BW_SetsCollectionFrame;
				end

				if tab == 4 then
					local savedCount = #addon.GetSavedList() or 0
					--WardrobeCollectionFrame_UpdateProgressBar(savedCount, savedCount)
				end
			end
		end
	end
	

	function BetterWardrobeVisualToggleMixin:OnHide()
		--BetterWardrobeCollectionFrame.BW_SetsTransmogFrame:Hide()
		self.VisualMode = false;
	end


	function BetterWardrobeVisualToggleMixin:OnEnter()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Visual View"])
		GameTooltip:Show()
	end

	function BetterWardrobeVisualToggleMixin:OnLeave()
		GameTooltip:Hide()
	end







local EmptyArmor = addon.Globals.EmptyArmor



function Sets:GetEmptySlots()
	local setInfo = {}

	for i,x in pairs(EmptyArmor) do
		setInfo[i]=x;
	end

	return setInfo;
end


function Sets:EmptySlots(transmogSources)
	local EmptySet = self:GetEmptySlots()

	for i, x in pairs(transmogSources) do
			EmptySet[i] = nil;
	end

	return EmptySet;
end




function Sets.isMogKnown(sourceID)
	local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
	
	if not sourceInfo then return false end
	local allSources = C_TransmogCollection.GetAllAppearanceSources(sourceInfo.visualID)

	local list = {}
		for _, source_ID in ipairs(allSources) do
		
			local info = C_TransmogCollection.GetSourceInfo(source_ID)
			local isCollected = select(5,C_TransmogCollection.GetAppearanceSourceInfo(source_ID))
			info.isCollected = isCollected;
			tinsert(list, info)
		end

		if #list > 1 then
			CollectionWardrobeUtil.SortSources(list, sourceInfo.visualID, sourceID)
		end
	
		return  (list[1] and list[1].isCollected and list[1].sourceID) or false;
end

function addon.Sets:SelectedVariant(setID)
	local baseSetID = C_TransmogSets.GetBaseSetID(setID) --or setID;
	if not baseSetID then return end

	local variantSets = SetsDataProvider:GetVariantSets(baseSetID)
	if not variantSets then return end
	
	local useDescription = (#variantSets > 0)
	local targetSetID = BetterWardrobeCollectionFrame.SetsCollectionFrame:GetDefaultSetIDForBaseSet(baseSetID)
	local match = false;

	for i, data in ipairs(variantSets) do
		if addon.CollectionList:IsInList (data.setID, "set") then
			match = data.setID;
		end
	end

	if useDescription then
		local setInfo = C_TransmogSets.GetSetInfo(targetSetID)
		local matchInfo = match and C_TransmogSets.GetSetInfo(match).description or nil;

		return targetSetID, setInfo.description, match, matchInfo;
	end
end


function addon.Sets:GetLocationBasedCount(setInfo)
	local collectedCount = 0;
	local totalCount = 0;
	local items = {}
	local setID = setInfo.setID;
	local sources = addon.C_TransmogSets.GetSetSources(setID)

	for sourceID in pairs(sources) do
		local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
		if sourceInfo then
		--local appearanceSources = sourceInfo and C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID)
			local _, visualID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)	
			local appearanceSources = (sourceInfo and itemLink and C_TransmogCollection.GetAppearanceSources(sourceInfo.visualID, addon.GetItemCategory(sourceInfo.visualID), addon.GetTransmogLocation(itemLink)) )
			if appearanceSources then
				if #appearanceSources > 1 then
					CollectionWardrobeUtil.SortSources(appearanceSources, sourceInfo.visualID, sourceID)
				end

				if  addon.includeLocation[sourceInfo.invType] then
					totalCount = totalCount + 1;

					if appearanceSources[1].isCollected  then
						collectedCount = collectedCount + 1;
					end
				end
			end
		end
	end

	return collectedCount, totalCount;
end


function BW_JournalHideSlotMenu_OnClick(parent)
	local Profile = addon.Profile;
	local armor = addon.Globals.EmptyArmor
	local name  = addon.QueueList[3]
	local profile = addon.setdb.profile.autoHideSlot;
	local function resetModel()
			local tab = BetterWardrobeCollectionFrame.selectedCollectionTab;
			if tab ==2 then
				local set = BetterWardrobeCollectionFrame.SetsCollectionFrame:GetSelectedSetID()
				BetterWardrobeCollectionFrame.SetsCollectionFrame:DisplaySet(set)
			else
				local set = BetterWardrobeCollectionFrame.SetsCollectionFrame:GetSelectedSetID()
				BetterWardrobeCollectionFrame.SetsCollectionFrame:DisplaySet(set)
			end
		end

	local contextMenuData = {
		{
				text = L["Toggle Hidden View"],
				func = function (self, arg1, arg2, value)
					addon.setdb.profile.autoHideSlot.toggle = not addon.setdb.profile.autoHideSlot.toggle;
					resetModel()
				end,
				isNotRadio = true,
				notCheckable = false,
				checked = function() return addon.setdb.profile.autoHideSlot.toggle end,
				keepShownOnClick = true, 
		},
		{ text = L["Select Slot to Hide"], isTitle = true, notCheckable = true},
	}

	for i = 1, 19 do 
		if armor[i] then 
			local menu = {
				text = _G[addon.Globals.INVENTORY_SLOT_NAMES[i]],
				func = function (self, arg1, arg2, value)
					profile[i] = not profile[i]
					resetModel()
				end,
				isNotRadio = true,
				notCheckable = false,
				checked = function() return profile[i] end,
				keepShownOnClick = true, 
			}
			tinsert (contextMenuData, menu)

		end
	end
	BW_UIDropDownMenu_SetAnchor(addon.ContextMenu, 0, 0, "BOTTOMLEFT", parent, "BOTTOMLEFT")
	BW_EasyMenu(contextMenuData, addon.ContextMenu, addon.ContextMenu, 0, 0, "MENU")
end


local SortOrder;
local DEFAULT = addon.Globals.DEFAULT;
local APPEARANCE = addon.Globals.APPEARANCE;
local ALPHABETIC = addon.Globals.ALPHABETIC;
local ITEM_SOURCE = addon.Globals.ITEM_SOURCE;
local EXPANSION = addon.Globals.EXPANSION;
local COLOR = addon.Globals.COLOR;
local ILEVEL = 8
local ITEMID = 9
local ARTIFACT = 7;
local TAB_ITEMS = addon.Globals.TAB_ITEMS;
local TAB_SETS = addon.Globals.TAB_SETS;
local TAB_EXTRASETS = addon.Globals.TAB_EXTRASETS;
local TAB_SAVED_SETS = addon.Globals.TAB_SAVED_SETS;
--local TABS_MAX_WIDTH = addon.Globals.TABS_MAX_WIDTH;
--local dropdownOrder = {DEFAULT, ALPHABETIC, APPEARANCE, COLOR, EXPANSION, ITEM_SOURCE};
local dropdownOrder = {DEFAULT, ALPHABETIC, APPEARANCE, COLOR, EXPANSION, ITEM_SOURCE}

local locationDrowpDown = addon.Globals.locationDrowpDown;

--= {INVTYPE_HEAD, INVTYPE_SHOULDER, INVTYPE_CLOAK, INVTYPE_CHEST, INVTYPE_WAIST, INVTYPE_LEGS, INVTYPE_FEET, INVTYPE_WRIST, INVTYPE_HAND}
local defaults = {
	sortDropdown = DEFAULT,
	reverse = false,
}

function addon.Init.SortDropDown_Initialize()
	if not addon.sortDB then
		addon.sortDB = CopyTable(defaults)
	end
	local Wardrobe = BetterWardrobeCollectionFrame.ItemsCollectionFrame;
	db = addon.sortDB;

	BW_SortDropDown = CreateFrame("Frame", "BW_SortDropDown", BetterWardrobeCollectionFrame, "BW_UIDropDownMenuTemplate")

	--BW_SortDropDown = BW_UIDropDownMenu_Create("BW_SortDropDown", BW_WardrobeCollectionFrame)
	BW_UIDropDownMenu_SetWidth(BW_SortDropDown, 140)
	BW_UIDropDownMenu_Initialize(BW_SortDropDown, function(self)
		local info = BW_UIDropDownMenu_CreateInfo()
		local selectedValue = BW_UIDropDownMenu_GetSelectedValue(self)

		info.func = function(self)
				local tabID = addon.GetTab()
				--print(tabID)
				local sortValue
				if tabID ==4 then
					addon.setdb.profile.sorting = self.value
					sortValue = addon.setdb.profile.sorting

				else
					db.sortDropdown = self.value;
					sortValue = db.sortDropdown
				end
				
				--print (self.value)
				--print(sortValue)
				BW_UIDropDownMenu_SetSelectedValue(BW_SortDropDown, sortValue)
				BW_UIDropDownMenu_SetText(BW_SortDropDown, COMPACT_UNIT_FRAME_PROFILE_SORTBY.." "..L[sortValue])
				--db.reverse = IsModifierKeyDown()

				if tabID == 1 then
					--Wardrobe:OnShow()
					Wardrobe:RefreshVisualsList()
					Wardrobe:UpdateItems()
					Wardrobe:UpdateWeaponDropDown()
				elseif tabID == 2 then
					RefreshLists()
				elseif tabID == 3 then
					RefreshLists()
				elseif tabID == 4 then
					--RefreshLists()
										

					BetterWardrobeCollectionFrame:SetTab(3)
					BetterWardrobeCollectionFrame:SetTab(4)

				end
			end

			local tabID = addon.GetTab()
			for index, id in pairs(dropdownOrder) do
				if id == ITEM_SOURCE and (tabID == 2 or tabID == 3) then
				elseif (tabID == 4 and index <= 2) or tabID ~= 4 then 
					info.value, info.text = id, L[id]
					info.checked = (id == selectedValue)
					BW_UIDropDownMenu_AddButton(info)
				end
			end


			if tabID == 1 then
				info.value = ILEVEL;
				info.text = L[ILEVEL]
				info.checked = (8 == selectedValue)
				BW_UIDropDownMenu_AddButton(info)

				info.value = ITEMID;
				info.text = L[ITEMID]
				info.checked = (9 == selectedValue)
				BW_UIDropDownMenu_AddButton(info)
			end

			if tabID == 1 and( Wardrobe.activeCategory and Wardrobe.activeCategory >= 13) then
				info.value = ARTIFACT;
				info.text = L[ARTIFACT]
				info.checked = (7 == selectedValue)
				BW_UIDropDownMenu_AddButton(info)
			end

		end)
	local tabID = addon.GetTab()
	local sortValue
	----print(tabID)
	if tabID ==4 then
		sortValue = addon.setdb.profile.sorting
	else
		sortValue = db.sortDropdown
	end
	
	BW_UIDropDownMenu_SetSelectedValue(BW_SortDropDown, sortValue)
	-----BW_UIDropDownMenu_SetText(BW_SortDropDown, COMPACT_UNIT_FRAME_PROFILE_SORTBY.." "..L[db.sortDropdown])

	--[[--Repositions sort dropown if Legion Wardrobe is loaded;
			local LegionWardrobeY = IsAddOnLoaded("LegionWardrobe") and 55 or 5;
			if WardrobeFrame_IsAtTransmogrifier() then
				local _, isWeapon = C_TransmogCollection.GetCategoryInfo(Wardrobe:GetActiveCategory() or -1)
				BW_SortDropDown:SetPoint("TOPLEFT", Wardrobe.WeaponDropDown, "BOTTOMLEFT", 0, isWeapon and 55 or 32)
			else
				BW_SortDropDown:SetPoint("TOPLEFT", Wardrobe.WeaponDropDown, "BOTTOMLEFT", 0, LegionWardrobeY)
			end]]
end


--addon:SecureHook(WardrobeCollectionFrame, "OpenTransmogLink", function() print("test") end)

addon:SecureHook("SetItemRef", function(link, ...) 
	if InCombatLockdown() then return end

	local linkType, id = strsplit(":", link)

	if (linkType == "transmogappearance" or linkType == "transmogset" or linkType == "BW_transmogset" or linkType == "BW_transmogset-extra") then
		if not IsAddOnLoaded("Blizzard_Collections") then
			--LoadAddOn("Blizzard_Collections")
		end


		if ( not CollectionsJournal or not CollectionsJournal:IsVisible() ) then
			local _, sourceID = strsplit(":", addedLink);
			--ToggleCollectionsJournal(5)
			--print(addedLink)
			TransmogUtil.OpenCollectionToItem(sourceID);
			--WardrobeCollectionFrame:OpenTransmogLink(sourceID)

		end

			C_Timer.After(0.1, function() BetterWardrobeCollectionFrame:OpenTransmogLink(link) end)
				
		return;
	end
end)

BetterWardrobeSetsDetailsItemUseabiltiyMixin = { }

function BetterWardrobeSetsDetailsItemUseabiltiyMixin:OnEnter()
	local status = self:GetParent().itemCollectionStatus;
	local text;
	if status == "CollectedCharCantUse" then
		text = L["Class cant use appearance. Useable appearance available."]
	elseif status == "CollectedCharCantGet" or status == "NotCollectedCharCantGet" then 
		text = L["Class can't collect or use appearance."]
	elseif status == "NotCollectedUnavailable" then 
		text = L["Item No Longer Obtainable."]
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
	GameTooltip:SetText(text)
end

function BetterWardrobeSetsDetailsItemUseabiltiyMixin:OnLeave()
	GameTooltip:Hide()
end


BW_ApplyOnClickCheckboxMixin = {}
function BW_ApplyOnClickCheckboxMixin:OnClick()
	addon.Profile.AutoApply = not addon.Profile.AutoApply
	self:SetChecked(addon.Profile.AutoApply)
end

function BW_ApplyOnClickCheckboxMixin:OnLoad()
	self:SetChecked(addon.Profile.AutoApply)
end

BetterWardrobeSetsDetailsAltItemMixin = {}

function BetterWardrobeSetsDetailsAltItemMixin:OnMouseDown()
	local sourceID
	if self.index < #self.altid then
		self.index = self.index + 1
		self.useAlt = true
		sourceID = self.altid[self.index]
	elseif self.index >= #self.altid then
		self.index = 0
		self.useAlt = false
		sourceID = self.baseId
	end

	sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
	--print(sourceInfo.name)
	BetterWardrobeCollectionFrame.SetsCollectionFrame:DisplaySet(self.setID)
end