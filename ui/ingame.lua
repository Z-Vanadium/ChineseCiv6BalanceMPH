-- Copyright 2015-2018, Firaxis Games
-- XP2 root context for ingame (aka: All-the-things)
-- MODs / Expansions cannot use partial replacement as this context is 
-- directly added to the UI Control Tree via engine.

include( "LocalPlayerActionSupport" );
include( "InputSupport" );
print("MPH InGame")
include( "stagingroom" ); -- for GetLocalModVersion


-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local TIME_UNTIL_UPDATE:number = 0.1;	-- time to wait before attempting to release delayshow popups.


-- ===========================================================================
--	VARIABLES
-- ===========================================================================

local DefaultMessageHandler = {};
local m_bulkHideTracker :number = 0;
local m_lastBulkHider:string = "first call";
g_uiAddins = {};

local m_PauseId		:number = Input.GetActionId("PauseMenu");
local m_QuicksaveId :number = Input.GetActionId("QuickSave");

local m_HexColoringReligion : number = UILens.CreateLensLayerHash("Hex_Coloring_Religion");
local m_CulturalIdentityLens: number = UILens.CreateLensLayerHash("Cultural_Identity_Lens");
local m_TouristTokens		: number = UILens.CreateLensLayerHash("Tourist_Tokens");
local m_activeLocalPlayer	: number = -1;
local m_timeUntilPopupCheck	: number = 0;	

-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================

-- ===========================================================================
--	Open up the TopOptionsMenu with the utmost priority.
-- ===========================================================================
function OpenInGameOptionsMenu()
	LuaEvents.InGame_OpenInGameOptionsMenu();
end

function OpenTurnProcessing()
	LuaEvents.InGame_OpenTurnProcessing();
end


-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnTutorialToggleInGameOptionsMenu()
	if Controls.TopOptionsMenu:IsHidden() then
		OpenInGameOptionsMenu();
	else
		LuaEvents.InGame_CloseInGameOptionsMenu();
	end
end

-- ===========================================================================
DefaultMessageHandler[KeyEvents.KeyUp] =
	function( pInputStruct:table )
	
		local uiKey = pInputStruct:GetKey();

        if( uiKey == Keys.VK_ESCAPE ) then		
			if( Controls.TopOptionsMenu:IsHidden() ) then
				OpenInGameOptionsMenu();
				return true;
			end
			return false;	-- Already open, let it handle it.
						

        elseif( uiKey == Keys.B and pInputStruct:IsShiftDown() and pInputStruct:IsAltDown() and (not UI.IsFinalRelease()) ) then
			-- DEBUG: Force unhiding
			local msg:string =  "***PLAYER Force Bulk unhiding SHIFT+ALT+B ***";
			UI.DataError(msg);
			m_bulkHideTracker = 1;
			BulkHide(false, msg);

        elseif( uiKey == Keys.J and pInputStruct:IsShiftDown() and pInputStruct:IsAltDown() and (not UI.IsFinalRelease()) ) then
			if m_bulkHideTracker < 1 then
				BulkHide(true,  "Forced" );
			else
				BulkHide(false, "Forced" );
			end
		end

		return false;
	end

----------------------------------------------------------------        
-- LoadGameViewStateDone Event Handler
----------------------------------------------------------------    
function OnLoadGameViewStateDone()
	-- show HUD elements that relay on the gamecache being fully initialized.
	if(GameConfiguration.IsNetworkMultiplayer()) then
		Controls.MultiplayerTurnManager:SetHide(false);  
	end     
end

----------------------------------------------------------------        
-- Input handling
----------------------------------------------------------------        
function OnInputHandler( pInputStruct )
	local uiMsg = pInputStruct:GetMessageType();

	if DefaultMessageHandler[uiMsg] ~= nil then
		return DefaultMessageHandler[uiMsg]( pInputStruct );
	end
	return false;
end

----------------------------------------------------------------        
function OnShow()
	Controls.WorldViewControls:SetHide( false );

	local pFriends = Network.GetFriends();
	if (pFriends ~= nil) then
		if (GameConfiguration.IsAnyMultiplayer()) then
			if GameConfiguration.IsHotseat() then
				pFriends:SetRichPresence("civPresence", "LOC_PRESENCE_IN_GAME_HOTSEAT");
			elseif GameConfiguration.IsLANMultiplayer() then
				pFriends:SetRichPresence("civPresence", "LOC_PRESENCE_IN_GAME_LAN");
			elseif GameConfiguration.IsPlayByCloud() then
				pFriends:SetRichPresence("civPresence", "LOC_PRESENCE_IN_GAME_PLAYBYCLOUD");
			else
				pFriends:SetRichPresence("civPresence", "LOC_PRESENCE_IN_GAME_ONLINE");
			end
		else
			pFriends:SetRichPresence("civPresence", "LOC_PRESENCE_IN_GAME_SP");
		end
	end

	RealizeTooltipBehavior();
end

-- ===========================================================================
function RealizeTooltipBehavior()
	local toolTipBehavior:number = Options.GetAppOption("UI", "TooltipBehavior");
	if toolTipBehavior == TooltipBehavior.AlwaysShowing then		
		TTManager:SetToolTipDelay( 0.0 );
	elseif toolTipBehavior == TooltipBehavior.ShowAfterDelay then	
		TTManager:SetToolTipDelay( 2.0 );	-- seconds to delay before showing
	elseif toolTipBehavior == TooltipBehavior.ShowOnButton then
		TTManager:SetToolTipDelay( 0.0 );	-- no delay (but require button.)
	end
end

-- ===========================================================================
--	Hide (or Show) all the contexts part of the BULK group.
-- ===========================================================================
function BulkHide( isHide:boolean, debugWho:string )

	-- Tracking for debugging:	
	m_bulkHideTracker = m_bulkHideTracker + (isHide and 1 or -1);
	print("Request to BulkHide( "..tostring(isHide)..", "..debugWho.." ), Show on 0 = "..tostring(m_bulkHideTracker));
	
	if m_bulkHideTracker < 0 then
		UI.DataError("Request to bulk show past limit by "..debugWho..". Last bulk shown by "..m_lastBulkHider);
		m_bulkHideTracker = 0;
	end
	m_lastBulkHider = debugWho;
	
	-- Do the bulk hiding/showing	
	local kGroups:table = {"WorldViewControls", "HUD", "PartialScreens", "Screens", "TopLevelHUD" };
	for i,group in ipairs(kGroups) do
		local pContext :table = ContextPtr:LookUpControl("/InGame/"..group);
		if pContext == nil then
			UI.DataError("InGame is unable to BulkHide("..isHide..") '/InGame/"..group.."' because the Context doesn't exist.");
		else
			if m_bulkHideTracker == 1 and isHide then
				pContext:SetHide(true);
			elseif m_bulkHideTracker == 0 and isHide==false then
				pContext:SetHide(false);
				RestartRefreshRequest();
			else
				-- Do nothing
			end
		end
	end
end


-- ===========================================================================
--	Hotkey Event
-- ===========================================================================
function OnInputActionTriggered( actionId )
    if actionId == m_PauseId then
        if( Controls.TopOptionsMenu:IsHidden() ) then
            OpenInGameOptionsMenu();
            return true;
        end
    elseif actionId == m_QuicksaveId then
        -- Quick save                
        if CanLocalPlayerSaveGame() then
            local gameFile = {};
            gameFile.Name = "quicksave";
            gameFile.Location = SaveLocations.LOCAL_STORAGE;
            gameFile.Type= Network.GetGameConfigurationSaveType();
            gameFile.IsAutosave = false;
            gameFile.IsQuicksave = true;

            Network.SaveGame(gameFile);
            UI.PlaySound("Confirm_Bed_Positive");
        end
    end
end

-- ===========================================================================
--	Gamecore Event
--	Called once per layer that is turned on when a new lens is activated,
--	or when a player explicitly turns off the layer from the "player" lens.
-- ===========================================================================
function OnLensLayerOn( layerHash:number )
	if layerHash == m_HexColoringReligion or layerHash == m_CulturalIdentityLens or
       layerHash == m_TouristTokens then
		Controls.CityBannerManager:ChangeParent(Controls.BannerAndFlags);
	end
end

-- ===========================================================================
--	Gamecore Event
--	Called once per layer that is turned on when a new lens is deactivated,
--	or when a player explicitly turns off the layer from the "player" lens.
-- ===========================================================================
function OnLensLayerOff( layerHash:number )
	if layerHash == m_HexColoringReligion or layerHash == m_CulturalIdentityLens or
       layerHash == m_TouristTokens then
		Controls.UnitFlagManager:ChangeParent(Controls.BannerAndFlags);
	end
end

-- ===========================================================================
--	EVENT
-- ===========================================================================
function OnTurnBegin()
	m_activeLocalPlayer = Game.GetLocalPlayer();
end

-- ===========================================================================
--	EVENT
-- ===========================================================================
function OnTurnEnd()
	m_activeLocalPlayer = -1;
end


-- ===========================================================================
function RestartRefreshRequest()
 	-- Increasing this adds a delay, but will make it less likely that lower
 	-- priority popups will be shown before all the popups are in added in
 	-- the queue.
 	m_timeUntilPopupCheck = TIME_UNTIL_UPDATE;
	ContextPtr:SetRefreshHandler( OnRefreshAttemptPopupRelease );	
	ContextPtr:RequestRefresh();
end

-- ===========================================================================
--	EVENT
--	Gamecore is done processing events; this may fire multiple times as a
--	turn begins, as well as after player actions.
-- ===========================================================================
function OnGameCoreEventPlaybackComplete()
	-- Gate using this based on whether or not it's firing for a local player
	if m_activeLocalPlayer == -1 then return; end; 
	RestartRefreshRequest();
end

-- ===========================================================================
--	UI Manager Callback
-- ===========================================================================
function OnPopupQueueChange( isQueuing:boolean )
	if m_timeUntilPopupCheck <= 0 then
		RestartRefreshRequest();
	end
end

-- ===========================================================================
--	Event
-- ===========================================================================
function OnUpdateUI( type, tag, iData1, iData2, strData1 )
    if (type == SystemUpdateUI.TouchTipBehaviorChanged) then
		RealizeTooltipBehavior();
    end
end

-- ===========================================================================
--	Event
-- ===========================================================================
function OnUIIdle()
	-- If a countdown to check hasn't started, kick one off.
	if m_timeUntilPopupCheck <= 0 then
		RestartRefreshRequest();
	end
end

-- ===========================================================================
function IsAbleToShowDelayedPopups()
	local isBulkHideOkay :boolean = (m_bulkHideTracker == 0);
	local isQueueEnabled :boolean = (UIManager:IsPopupQueueDisabled() == false);
	return isBulkHideOkay and isQueueEnabled;
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnRefreshAttemptPopupRelease( delta:number )	
	m_timeUntilPopupCheck = m_timeUntilPopupCheck - delta;
	if m_timeUntilPopupCheck <= 0 then
		-- Only release delayed popups if a bulk hide operation isn't currently happening.
		if IsAbleToShowDelayedPopups() then
			UIManager:ShowDelayedPopups();		-- Show any popups that had been added to Forge waiting to be shown
		end		
		ContextPtr:ClearRefreshHandler();
	else
		ContextPtr:RequestRefresh();
	end	
end

-- ===========================================================================
function OnDiplomacyHideIngameUI()		BulkHide( true, "Diplomacy" );		Input.PushActiveContext(InputContext.Diplomacy);	end	
function OnDiplomacyShowIngameUI()		BulkHide(false, "Diplomacy" );		Input.PopContext();									end	
function OnDisasterRevealPopupShown()	BulkHide( true, "NaturalDisaster" );													end 
function OnDisasterRevealPopupClosed()	BulkHide(false, "NaturalDisaster" );													end
function OnEndGameMenuShown()			BulkHide( true, "EndGame" ); 		Input.PushActiveContext(InputContext.EndGame);		end	
function OnEndGameMenuClosed()			BulkHide(false, "EndGame" );		Input.PopContext();									end	
function OnFullscreenMapShown()			BulkHide( true, "FullscreenMap" );	Input.PushActiveContext(InputContext.FullscreenMap);end	
function OnFullscreenMapClosed()		BulkHide(false, "FullscreenMap" );	Input.PopContext();									end	
function OnNaturalWonderPopupShown()	BulkHide( true, "NaturalWonder" );														end	
function OnNaturalWonderPopupClosed()	BulkHide(false, "NaturalWonder" );														end	
function OnProjectBuiltShown()			BulkHide( true, "Project" );															end	
function OnProjectBuiltClosed()			BulkHide(false, "Project" );															end	
function OnRockBandMoviePopupShown()	BulkHide( true, "RockBand" );															end	
function OnRockBandMoviePopupClosed()	BulkHide(false, "RockBand" );															end	
function OnTutorialEndHide()			BulkHide( true, "TutorialEnd" );														end	
function OnWonderBuiltPopupShown()		BulkHide( true, "Wonder" );																end	
function OnWonderBuiltPopupClosed()		BulkHide(false, "Wonder" );																end	

-- ===========================================================================
function OnShutdown()
	UIManager:ClearPopupChangeHandler();
end

-- ChineseCivTracker
g_player_data_table = {}

local is_debug = false
-- g_player_data_table["science"] = {}
-- g_player_data_table["culture"] = {}
-- g_player_data_table["gold"] = {}
-- g_player_data_table["faith"] = {}
-- to check essential time points
function OnGameTurnStarted()
	local current_turn: number = Game.GetCurrentGameTurn()
	print("OnGameTurnStarted", current_turn)
	if (is_debug) then
		TrackAllPlayerDataOnTurn(current_turn)
	elseif (current_turn % 10 == 0) then
		TrackAllPlayerDataOnTurn(current_turn)
	end
end

function TrackAllPlayerDataOnTurn( turn: number )
	local turn_str: string = tostring(turn)
	if turn_str ~= nil then
		g_player_data_table[turn_str] = {}
		print("TrackAllPlayerDataOnTun", turn)

		for _, _player in pairs(PlayerManager:GetWasEverAliveMajors()) do
			local id: number = _player:GetID()
			local id_str: string = tostring(id)
			local player_data = {}
			-- local dataSetIndex = 0
			local initialTurn = GameConfiguration.GetStartTurn()
			local finalTurn = Game.GetCurrentGameTurn()
			local count = GameSummary.GetDataSetCount()

			for i = 0, count - 1, 1 do
				local name = GameSummary.GetDataSetName(i);
				local gdata = GameSummary.CoalesceDataSet(i, initialTurn, finalTurn)
				if name == 'REPLATASET_TOTALGOLD' then
					player_data["g"] = gdata[id][#gdata[id]]
				elseif name == "REPLAYDATASET_SCIENCEPERTURN" then
					player_data["s"] = gdata[id][#gdata[id]]
				elseif name == "REPLAYDATASET_CULTURE" then
					player_data["c"] = gdata[id][#gdata[id]]
				elseif name == "REPLAYDATASET_FAITHPERTURN" then
					player_data["f"] = gdata[id][#gdata[id]]
				end
			end
			g_player_data_table[turn_str][id_str] = player_data
		end
	end
end

-- to send game data to server when game ends
function OnTeamVictory(team, victory, eventID)
	local localPlayer :number = Game.GetLocalPlayer();
	print("CCT: message sent start")
	if is_debug == false and Game.GetCurrentGameTurn() <= 49 then
		print("CCT: game turn less than 49, ignore")
		return
	end
	if is_debug then
		local domain_name = '127.0.0.1:5050'
	else
		local domain_name = '60.205.246.25:80'
	end
	local game_data_str = ""
	local game_data = {}
	local mod_version = g_mod_version or {}
	local player_leader_civ = {}
	local winner_team = team
	local victory_type = victory
	local player_num = 0	-- not include AI or spectator
	local map_seed = MapConfiguration.GetValue("RANDOM_SEED")
	local game_seed = GameConfiguration.GetValue("GAME_SYNC_RANDOM_SEED")

	game_data["timestamp"] = os.time()
	game_data["victory_type"] = victory_type
	game_data["map_seed"] = map_seed
	game_data["game_seed"] = game_seed

	-- print("CCT: game turn more than 50, start send message to domain: " .. domain_name .. ", time: " .. tostring(game_data["timestamp"]))

	-- mod_version["ccb_version"] = GetLocalModVersion("8af4fe8e-5406-7d72-d9d6-a8f5d1b66e00")
	-- mod_version["ccb_map_version"] = GetLocalModVersion("8af4fe8e-5406-7d72-d9d6-a8f5d1b66e10")
	-- mod_version["ccb_mph_version"] = GetLocalModVersion("8af4fe8e-5406-7d72-d9d6-a8f5d1b66e20")
	-- mod_version["ccb_exp_version"] = GetLocalModVersion("8af4fe8e-5406-7d72-d9d6-a8f5d1b66e34")

	print("CCT: ccb_version: " .. tostring(mod_version["ccb_version"]) .. ", ccb_map_version: " .. tostring(mod_version["ccb_map_version"]) .. ", ccb_mph_version: " .. tostring(mod_version["ccb_mph_version"]) .. ", ccb_exp_version: " .. tostring(mod_version["ccb_exp_version"]))

	game_data["mod_version"] = mod_version
	game_data["map_type"] = MapConfiguration.GetScript()
	game_data["total_turns"] = Game.GetCurrentGameTurn()

	for _, _player in pairs(PlayerManager.GetWasEverAliveMajors()) do
		-- if is_debug == false and _player:GetID() == player:GetID() then
		-- 	winner_team = _player:GetTeam()
		-- else
		-- 	winner_team = -1
		-- end
		if (_player:IsHuman() and PlayerConfigurations[_player:GetID()]:GetLeaderTypeName() ~= "LEADER_SPECTATOR") then
			player_num = player_num + 1
		end
		local steam_id = PlayerConfigurations[_player:GetID()]:GetNetworkIdentifer()
		local id: number = _player:GetID()

		print("CCT: player id: " .. tostring(id) .. ", steam_id: " .. tostring(steam_id) .. ", team: " .. tostring(_player:GetTeam()) .. ", leader_type: " .. tostring(PlayerConfigurations[_player:GetID()]:GetLeaderTypeName()) .. ", civilization_type: " .. tostring(PlayerConfigurations[_player:GetID()]:GetCivilizationTypeName()))

		local player_info = {}
		player_info["steam_id"] = steam_id
		player_info["team"] = _player:GetTeam()
		player_info["leader_type"] = PlayerConfigurations[_player:GetID()]:GetLeaderTypeName()
		player_info["civilization_type"] = PlayerConfigurations[_player:GetID()]:GetCivilizationTypeName()

		player_leader_civ["0" .. tostring(id)] = player_info
	end

	game_data["player_leader_civ"] = player_leader_civ
	game_data["player_num"] = player_num
	game_data["winner_team"] = winner_team

	-- following code will cause crash
	-- game_data["game_summary"] = GameSummary.CoalesceDataSet(0, GameConfiguration.GetStartTurn(), Game.GetCurrentGameTurn())
	game_data["game_summary"] = g_player_data_table

	game_data_str = TableToJson(game_data)

	-- local raw_url = domain_name .. "/api/send?data=" .. game_data_str
	-- print("CCT: raw url: " .. raw_url)
	-- print("CCT: encode url: " .. tostring(game_data_str))
	local api_url = domain_name .. "/api/send?data=" .. game_data_str
	Steam.ActivateGameOverlayToUrl(api_url)
	return

-- 	if #game_data_str > 400 then
-- 		print("CCT: game data string too long, length: " .. #game_data_str .. ", ignore")
-- 		return
    
--     local CHUNK_SIZE = 50  -- 每块150字符
--     local encoded_chunks = {}
-- 	local i = 0
    
--     -- 先对原始字符串分块
--     for chunk_start = 1, #game_data_str, CHUNK_SIZE do
--         local chunk_end = math.min(chunk_start + CHUNK_SIZE - 1, #game_data_str)
--         local chunk = game_data_str:sub(chunk_start, chunk_end)
        
--         print("CCT: processing chunk " .. math.ceil(chunk_start / CHUNK_SIZE) .. 
-- ", length: " .. #chunk)
        
--         -- 对每块单独编码
--         local encoded_chunk = EncodeUrl(chunk)
--     	print("CCT: encoded url: " .. tostring(encoded_chunk))
--         -- table.insert(encoded_chunks, encoded_chunk)
-- 		if domain_name == nil or encoded_chunk == nil or game_seed == nil or localPlayer == nil then
-- 			print("CCT: domain_name or encoded_chunks or game_seed or localPlayer is nil, ignore")
-- 		else
-- 			local api_url = domain_name .. "/api/send?data=" .. encoded_chunk .. "&game_seed=" .. tostring(game_seed) .. "&part=" .. tostring(i) .. "&total=" .. tostring(#encoded_chunks) .. "&player_id=" .. tostring(localPlayer)
-- 			print("CCT: open url: " .. api_url)
-- 			Steam.ActivateGameOverlayToUrl(api_url)
-- 			i = i + 1
-- 		end
--     end

	-- local encoded_chunks = EncodeUrlChunked(game_data_str)

	-- for i = 1, #encoded_chunks, 1 do
	-- 	if domain_name == nil or encoded_chunks[i] == nil or game_seed == nil or localPlayer == nil then
	-- 		print("CCT: domain_name or encoded_chunks or game_seed or localPlayer is nil, ignore")
	-- 	else
	-- 		local api_url = domain_name .. "/api/send?data=" .. encoded_chunks[i] .. "&game_seed=" .. tostring(game_seed) .. "&part=" .. tostring(i) .. "&total=" .. tostring(#encoded_chunks) .. "&player_id=" .. tostring(localPlayer)
	-- 		print("CCT: open url: " .. api_url)
	-- 		Steam.ActivateGameOverlayToUrl(api_url)
	-- 	end
	-- end
end

function TableToJson(data)
    if type(data) == "table" then
        local items = {}
        for k, v in pairs(data) do
            if type(k) == "number" then
                table.insert(items, TableToJson(v))
            else
                table.insert(items, '%22' .. tostring(k) .. '"%3A' .. TableToJson(v))
            end
        end
        if #items > 0 then
            return "%7B" .. table.concat(items, "%2C") .. "%7D"
        else
            return "%7B%7D"
        end
    elseif type(data) == "string" then
        return '%22' .. data .. '%22'
    else
        return tostring(data)
    end
end

function EncodeUrlChunked(s)
    print("CCT: encode url: " .. tostring(s))
    
    local CHUNK_SIZE = 50  -- 每块150字符
    local encoded_chunks = {}
    
    -- 先对原始字符串分块
    for chunk_start = 1, #s, CHUNK_SIZE do
        local chunk_end = math.min(chunk_start + CHUNK_SIZE - 1, #s)
        local chunk = s:sub(chunk_start, chunk_end)
        
        print("CCT: processing chunk " .. math.ceil(chunk_start / CHUNK_SIZE) .. 
              ", length: " .. #chunk)
        
        -- 对每块单独编码
        local encoded_chunk = EncodeUrl(chunk)
    	print("CCT: encoded url: " .. tostring(encoded_chunk))
        table.insert(encoded_chunks, encoded_chunk)
    end
    
    print("CCT: encoded into " .. #encoded_chunks .. " chunks")
	-- local res = ""
	-- for _, str in ipairs(encoded_chunks) do
	-- 	res = res .. str
	-- end
    return encoded_chunks
end

function EncodeUrl(s)
	print("CCT: encode url: " .. tostring(s))
	-- if not s then return "" end

	local encoded_parts = {}
	local safe_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~" -- RFC 3986 中定义的无需编码字符

	for i = 1, #s do
		local char = s:sub(i, i)
		local byte_val = string.byte(char)
		
		-- 检查字符是否是安全的（无需编码的）ASCII 字符
		if safe_chars:find(char, 1, true) then
			table.insert(encoded_parts, char)
		-- 特别处理空格
		-- elseif char == " " then
		--     table.insert(encoded_parts, "%%20") -- URL 编码的空格
		-- 对所有其他字符进行百分号编码
		else
			-- 格式化为 %XX 形式
			table.insert(encoded_parts, string.format("%%%02X", byte_val))
		end
	end
	
	-- 将所有部分连接成最终字符串
	return table.concat(encoded_parts)
end

-- ===========================================================================
--	Cannot use LateInitialize patterns as this context is attached via C++
-- ===========================================================================
function Initialize()

	m_activeLocalPlayer = Game.GetLocalPlayer();

	-- Support for Modded Add-in UI's
	for i, addin in ipairs(Modding.GetUserInterfaces("InGame")) do
		print("Loading InGame UI - " .. addin.ContextPath);
		local id		:string = addin.ContextPath:sub( -(string.find( string.reverse(addin.ContextPath), '/') - 1) );		-- grab id from end of path
		local isHidden	:boolean = true;
		local newContext:table = ContextPtr:LoadNewContext(addin.ContextPath, Controls.AdditionalUserInterfaces, id, isHidden);	-- Content, ID, hidden
		table.insert(g_uiAddins, newContext);
	end
		
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetRefreshHandler( OnRefreshAttemptPopupRelease );	
	ContextPtr:SetShutdown( OnShutdown );	
	UIManager:SetPopupChangeHandler( OnPopupQueueChange );	
	
	Events.GameCoreEventPlaybackComplete.Add( OnGameCoreEventPlaybackComplete );
	Events.InputActionTriggered.Add( OnInputActionTriggered );
	Events.LensLayerOff.Add( OnLensLayerOff );
	Events.LensLayerOn.Add( OnLensLayerOn );
	Events.LoadGameViewStateDone.Add( OnLoadGameViewStateDone );		
	Events.LocalPlayerTurnBegin.Add( OnTurnBegin );
	Events.LocalPlayerTurnEnd.Add( OnTurnEnd );	
	Events.SystemUpdateUI.Add( OnUpdateUI );
	Events.UIIdle.Add( OnUIIdle );

	print("CCT: add tracker event")
	Events.LocalPlayerTurnBegin.Add( OnGameTurnStarted );


	print("CCT: add victory event")
	-- Events.TeamVictory.Add( OnTeamVictory );
	Events.LocalPlayerTurnBegin.Add( OnTeamVictory );
	
	
	-- NOTE: Using UI open/closed pairs in the case of end game; where
	--		 the same player receives both a victory and defeat messages
	--		 across the wire.
	LuaEvents.DiplomacyActionView_HideIngameUI.Add( OnDiplomacyHideIngameUI );
	LuaEvents.DiplomacyActionView_ShowIngameUI.Add( OnDiplomacyShowIngameUI );
	LuaEvents.EndGameMenu_Shown.Add( OnEndGameMenuShown );
	LuaEvents.EndGameMenu_Closed.Add( OnEndGameMenuClosed );
	LuaEvents.FullscreenMap_Shown.Add( OnFullscreenMapShown );
	LuaEvents.FullscreenMap_Closed.Add(	OnFullscreenMapClosed );
	LuaEvents.ProjectBuiltPopup_Shown.Add( OnProjectBuiltShown );
	LuaEvents.ProjectBuiltPopup_Closed.Add( OnProjectBuiltClosed );
	LuaEvents.NaturalDisasterPopup_Shown.Add( OnDisasterRevealPopupShown );
	LuaEvents.NaturalDisasterPopup_Closed.Add( OnDisasterRevealPopupClosed );
	LuaEvents.NaturalWonderPopup_Shown.Add( OnNaturalWonderPopupShown );
	LuaEvents.NaturalWonderPopup_Closed.Add( OnNaturalWonderPopupClosed );
	LuaEvents.RockBandMoviePopup_Shown.Add( OnRockBandMoviePopupShown );
	LuaEvents.RockBandMoviePopup_Closed.Add( OnRockBandMoviePopupClosed );
	LuaEvents.Tutorial_ToggleInGameOptionsMenu.Add( OnTutorialToggleInGameOptionsMenu );
	LuaEvents.Tutorial_TutorialEndHideBulkUI.Add( OnTutorialEndHide );
	LuaEvents.WonderBuiltPopup_Shown.Add( OnWonderBuiltPopupShown );
	LuaEvents.WonderBuiltPopup_Closed.Add(	OnWonderBuiltPopupClosed );
	LuaEvents.InGame_OnLocalUIRefresh.Add( Initialize )
end
Initialize();
