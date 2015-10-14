Aux.buy = {}

local process_auction, set_message, report, tooltip_match, show_dialog
local entries
local selectedEntries = {}
local search_query
local tooltip_patterns = {}
local current_page
local refresh


function Aux.buy.exit()
	Aux.buy.dialog_cancel()
	current_page = nil
end

-----------------------------------------

function Aux_AuctionFrameBid_Update()
	Aux.orig.AuctionFrameBid_Update()
	if PanelTemplates_GetSelectedTab(AuctionFrame) == Aux.tabs.buy.index and AuctionFrame:IsShown() then
		Aux_HideElems(Aux.tabs.buy.hiddenElements)
	end
end

-----------------------------------------

function Aux.buy.dialog_cancel()
	Aux.scan.abort()
	AuxBuyConfirmation:Hide()
	AuxBuyList:Show()
	AuxBuySearchButton:Enable()
end

-----------------------------------------

function Aux.buy.StopButton_onclick()
	Aux.scan.abort()
end

-----------------------------------------

function Aux.buy.SearchButton_onclick()

	if not AuxBuySearchButton:IsVisible() then
		return
	end
	
	AuxBuySearchButton:Hide()
	AuxBuyStopButton:Show()
	
	entries = nil
	selectedEntries = {}
	
	refresh = true
	
	local category = UIDropDownMenu_GetSelectedValue(AuxBuyCategoryDropDown)
	local tooltip_patterns = Aux.util.set_to_array(tooltip_patterns)
	
	search_query = {
		name = AuxBuyNameInputBox:GetText(),
		min_level = AuxBuyMinLevel:GetText(),
		max_level = AuxBuyMaxLevel:GetText(),
		slot = category and category.slot,
		class = category and category.class,	
		subclass = category and category.subclass,
		quality = UIDropDownMenu_GetSelectedValue(AuxBuyQualityDropDown),
		usable = AuxBuyUsableCheckButton:GetChecked()
	}
	
	set_message('Scanning auctions ...')
	Aux.scan.start{
		query = search_query,
		page = 0,
		on_page_update = function(page)
			current_page = page
		end,
		on_start_page = function(ok, page, total_pages)
			set_message('Scanning auctions: page ' .. page + 1 .. (total_pages and ' out of ' .. total_pages or '') .. ' ...')
			return ok()
		end,
		on_read_auction = function(ok, i)
			local auction_item = Aux.info.auction_item(i)
			if auction_item then
				if (auction_item.name == search_query.name or search_query.name == '' or not AuxBuyExactCheckButton:GetChecked()) and tooltip_match(tooltip_patterns, auction_item.tooltip) then
					process_auction(auction_item, current_page)
				end
			end
			return ok()
		end,
		on_complete = function()
			entries = entries or {}
			if getn(entries) == 0 then
				set_message("No auctions were found")
			else
				AuxBuyMessage:Hide()
			end
			AuxBuyStopButton:Hide()
			AuxBuySearchButton:Show()
			refresh = true
		end,
		on_abort = function()
			entries = entries or {}
			if getn(entries) == 0 then
				set_message("No auctions were found")
			else
				AuxBuyMessage:Hide()
			end
			AuxBuyStopButton:Hide()
			AuxBuySearchButton:Show()
			refresh = true
		end,
		next_page = function(page, total_pages)
			local last_page = max(total_pages - 1, 0)
			if page < last_page then
				return page + 1
			end
		end,
	}
end

-----------------------------------------

function set_message(msg)
	AuxBuyMessage:SetText(msg)
	AuxBuyMessage:Show()
end

-----------------------------------------

function show_dialog(buyout_mode, name, texture, quality, tooltip, stack_size, amount)
	AuxBuyConfirmation.tooltip = tooltip
	
	AuxBuyConfirmationActionButton:Disable()
	AuxBuyConfirmationItem:SetNormalTexture(texture)
	AuxBuyConfirmationItemName:SetText(name)
	local color = ITEM_QUALITY_COLORS[quality]
	AuxBuyConfirmationItemName:SetTextColor(color.r, color.g, color.b)

	if stack_size > 1 then
		AuxBuyConfirmationItemCount:SetText(stack_size);
		AuxBuyConfirmationItemCount:Show()
	else
		AuxBuyConfirmationItemCount:Hide()
	end
	if buyout_mode then
		AuxBuyConfirmationActionButton:SetText('Buy')
		MoneyFrame_Update('AuxBuyConfirmationBuyoutPrice', amount)
		AuxBuyConfirmationBid:Hide()
		AuxBuyConfirmationBuyoutPrice:Show()
	else
		AuxBuyConfirmationActionButton:SetText('Bid')
		MoneyInputFrame_SetCopper(AuxBuyConfirmationBid, amount)
		AuxBuyConfirmationBuyoutPrice:Hide()
		AuxBuyConfirmationBid:Show()
	end
	AuxBuyList:Hide()
	AuxBuyConfirmation:Show()
end

-----------------------------------------

function AuxBuyEntry_OnClick(entry_index)

	local express_mode = IsAltKeyDown()
	local buyout_mode = arg1 == "LeftButton"
	
	local entry = entries[entry_index]
	
	if buyout_mode and not entry.buyout_price then
		return
	end
	
	if IsControlKeyDown() then 
		DressUpItemLink(entry.hyperlink)
		return
	end
	
	AuxBuySearchButton:Disable()
	
	local amount
	if buyout_mode then
		amount = entry.buyout_price
	else
		amount = entry.bid
	end
	
	if not express_mode then
		show_dialog(buyout_mode, entry.name, entry.texture, entry.quality, entry.tooltip, entry.stack_size, amount)
	end

	PlaySound("igMainMenuOptionCheckBoxOn")
	
	local found
	local order_key = Aux.auction_key(entry.tooltip, entry.stack_size, amount) 
	
	Aux.scan.start{
		query = search_query,
		page = entry.page ~= current_page and entry.page,
		on_page_update = function(page)
			current_page = page
		end,
		on_read_auction = function(ok, i)
			local auction_item = Aux.info.auction_item(i)
			
			if not auction_item then
				return ok()
			end
			
			local stack_size = auction_item.charges or auction_item.count
			local bid = (auction_item.current_bid > 0 and auction_item.current_bid or auction_item.min_bid) + auction_item.min_increment

			local auction_amount
			if buyout_mode then
				auction_amount = auction_item.buyout_price
			else
				auction_amount = bid
			end
			
			local key = Aux.auction_key(auction_item.tooltip, stack_size, auction_amount)
			
			if key == order_key then
				found = true
				
				if express_mode then
					if GetMoney() >= amount then
						tremove(entries, entry_index)
						refresh = true
					end
					
					PlaceAuctionBid("list", i, amount)				
					
					Aux.scan.abort()
				else
					Aux.buy.dialog_action = function()						
						if GetMoney() >= amount then
							tremove(entries, entry_index)
							refresh = true
						end
						
						PlaceAuctionBid("list", i, amount)
					
						Aux.scan.abort()
						AuxBuySearchButton:Enable()
						AuxBuyConfirmation:Hide()
						AuxBuyList:Show()
					end
					AuxBuyConfirmationActionButton:Enable()
				end
			else
				return ok()
			end
		end,
		on_complete = function()
			if not found then
				tremove(entries, entry_index)
				refresh = true
				Aux.buy.dialog_cancel()
			end
			if express_mode then
				AuxBuySearchButton:Enable()
			end
		end,
		on_abort = function()
			if express_mode then
				AuxBuySearchButton:Enable()
			end
		end,
		next_page = function(page, total_pages)
			if not page or page == entry.page then
				return entry.page - 1
			end
		end,
	}
end

function Aux.buy.icon_on_enter()
	local scroll_frame = getglobal(this:GetParent():GetParent():GetName().."ScrollFrame")
	local index = this:GetParent():GetID() + FauxScrollFrame_GetOffset(scroll_frame)
	local entry = entries[index]
	
	Aux.info.set_game_tooltip(this, entry.tooltip, 'ANCHOR_RIGHT')
	
	if(EnhTooltip ~= nil) then
		EnhTooltip.TooltipCall(GameTooltip, entry.name, entry.hyperlink, entry.quality, entry.stack_size)
	end
end

-----------------------------------------

function process_auction(auction_item, current_page)
	entries = entries or {}
	
	local stack_size = auction_item.charges or auction_item.count
	local bid = auction_item.current_bid > 0 and auction_item.current_bid or auction_item.min_bid + auction_item.min_increment
	local buyout_price = auction_item.buyout_price > 0 and auction_item.buyout_price or nil
	local buyout_price_per_unit = buyout_price and Aux_Round(auction_item.buyout_price/stack_size)
	
	if auction_item.owner ~= UnitName("player") then
		tinsert(entries, {
				name = auction_item.name,
				level = auction_item.level,
				texture = auction_item.texture,
				tooltip = auction_item.tooltip,
				stack_size = stack_size,
				buyout_price = buyout_price,
				buyout_price_per_unit = buyout_price_per_unit,
				quality = auction_item.quality,
				hyperlink = auction_item.hyperlink,
				itemstring = auction_item.itemstring,
				page = current_page,
				bid = bid,
				bid_per_unit = Aux_Round(bid/stack_size),
				owner = auction_item.owner,
				duration = auction_item.duration,
				usable = auction_item.usable,
		})
	end
end

-----------------------------------------

function Aux.buy.onupdate()
	if refresh then
		refresh = false
		Aux_Buy_ScrollbarUpdate()
	end
end

-----------------------------------------

function Aux_Buy_ScrollbarUpdate()
	Aux.list.populate(AuxBuySheet, entries or {})
end

-----------------------------------------

function tooltip_match(patterns, tooltip)	
	return Aux.util.all(patterns, function(pattern)
		return Aux.util.any(tooltip, function(line)
			local left_match = line[1].text and strfind(strupper(line[1].text), strupper(pattern), 1, true)
			local right_match = line[2].text and strfind(strupper(line[2].text), strupper(pattern), 1, true)
			return left_match or right_match
		end)
	end)
end

-----------------------------------------

function AuxBuyCategoryDropDown_Initialize(arg1)
	local level = arg1 or 1
	
	if level == 1 then
		local value = {}
		UIDropDownMenu_AddButton({
			text = ALL,
			value = value,
			func = AuxBuyCategoryDropDown_OnClick,
		}, 1)
		
		for i, class in pairs({ GetAuctionItemClasses() }) do
			local value = { class = i }
			UIDropDownMenu_AddButton({
				hasArrow = GetAuctionItemSubClasses(value.class),
				text = class,
				value = value,
				func = AuxBuyCategoryDropDown_OnClick,
			}, 1)
		end
	end
	
	if level == 2 then
		local menu_value = UIDROPDOWNMENU_MENU_VALUE
		for i, subclass in pairs({ GetAuctionItemSubClasses(menu_value.class) }) do
			local value = { class = menu_value.class, subclass = i }
			UIDropDownMenu_AddButton({
				hasArrow = GetAuctionInvTypes(value.class, value.subclass),
				text = subclass,
				value = value,
				func = AuxBuyCategoryDropDown_OnClick,
			}, 2)
		end
	end
	
	if level == 3 then
		local menu_value = UIDROPDOWNMENU_MENU_VALUE
		for i, slot in pairs({ GetAuctionInvTypes(menu_value.class, menu_value.subclass) }) do
			local slot_name = getglobal(slot)
			local value = { class = menu_value.class, subclass = menu_value.subclass, slot = i }
			UIDropDownMenu_AddButton({
				text = slot_name,
				value = value,
				func = AuxBuyCategoryDropDown_OnClick,
			}, 3)
		end
	end
end

function AuxBuyCategoryDropDown_OnClick()
	local qualified_name = ({ GetAuctionItemClasses() })[this.value.class] or 'All'
	if this.value.subclass then
		local subclass_name = ({ GetAuctionItemSubClasses(this.value.class) })[this.value.subclass]
		qualified_name = qualified_name .. ' - ' .. subclass_name
		if this.value.slot then
			local slot_name = getglobal(({ GetAuctionInvTypes(this.value.class, this.value.subclass) })[this.value.slot])
			qualified_name = qualified_name .. ' - ' .. slot_name
		end
	end

	UIDropDownMenu_SetSelectedValue(AuxBuyCategoryDropDown, this.value)
	UIDropDownMenu_SetText(qualified_name, AuxBuyCategoryDropDown)
	CloseDropDownMenus(1)
end

function AuxBuyQualityDropDown_Initialize()

	UIDropDownMenu_AddButton{
		text = ALL,
		value = -1,
		func = AuxBuyQualityDropDown_OnClick,
	}
	for i=0,getn(ITEM_QUALITY_COLORS)-2 do
		UIDropDownMenu_AddButton{
			text = getglobal("ITEM_QUALITY"..i.."_DESC"),
			value = i,
			func = AuxBuyQualityDropDown_OnClick,
		}
	end
end

function AuxBuyQualityDropDown_OnClick()
	UIDropDownMenu_SetSelectedValue(AuxBuyQualityDropDown, this.value)
end

function AuxBuyTooltipButton_OnClick()
	local pattern = AuxBuyTooltipInputBox:GetText()
	if pattern ~= '' then
		Aux.util.set_add(tooltip_patterns, pattern)
		if DropDownList1:IsVisible() then
			Aux.buy.toggle_tooltip_dropdown()
		end
		Aux.buy.toggle_tooltip_dropdown()
	end
	AuxBuyTooltipInputBox:SetText('')
end

function AuxBuyTooltipDropDown_Initialize()
	for pattern, _ in tooltip_patterns do
		UIDropDownMenu_AddButton{
			text = pattern,
			value = pattern,
			func = AuxBuyTooltipDropDown_OnClick,
			notCheckable = true,
		}
	end
end

function AuxBuyTooltipDropDown_OnClick()
	Aux.util.set_remove(tooltip_patterns, this.value)
end

function Aux.buy.toggle_tooltip_dropdown()
	ToggleDropDownMenu(1, nil, AuxBuyTooltipDropDown, AuxBuyTooltipInputBox, -12, 4)
end
