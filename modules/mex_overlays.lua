local GetOption = import('/lua/user/prefs.lua').GetOption
local GetUnits = import('/mods/common/units.lua').Get
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local AtLeftTopIn = LayoutHelpers.AtLeftTopIn
local AtCenterIn = LayoutHelpers.AtCenterIn
local UIUtil = import('/lua/ui/uiutil.lua')
local CreateText = UIUtil.CreateText
local bodyFont = UIUtil.bodyFont
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
-- could use UI Group to store overlays as group, but probably works out
-- the same performance wise, not that useful for rendering / removal.

local worldView = import('/lua/ui/game/worldview.lua')
local viewLeft = worldView.viewLeft

local modPath = '/mods/eco_overlays/'
local addListener = import(modPath .. 'modules/init.lua').addListener

-- how often mex overlay text / color should be checked / refreshed
local mex_overlay_interval = 1
local overlays = {}
local was_enabled = true

local function getMexes()
	return GetUnits(categories.MASSEXTRACTION * categories.STRUCTURE)
end

-- returns true iff mex is an upgrade_target unit, not the original mex.
local function isUpgradeTarget(mex)
    if mex.upgradingFrom then
        return true
    else
        return false
    end
end

-- returns true iff mex is upgrading (paused or not)
local function isUpgrading(mex)
    if mex.upgradingTo then
        return true
    else
        return false
    end
end

-- returns true iff mex is under construction
local function isMexBeingBuilt(mex)
	if mex:GetEconData().energyRequested ~= 0 then return false end

	if mex:GetHealth() == mex:GetMaxHealth() then return false end
    if mex.IsPaused then return false end -- func doesnt exist if unfinished
    -- might not be 100% fault proof, but combined with other checks its fine
	return true
end

local function CreateMexOverlay(unit, id)
    -- create overlay, hit test disabled = can click through
    -- this can bug warn when observing & switching players. 
    -- somehow its position isnt initialized even though its the ui base component? 
    -- it enters a circular dependency due to not having a position.
	local overlay = Bitmap(GetFrame(0))
    overlay:DisableHitTest()
	overlay:SetSolidColor('black')
	overlay.Width:Set(10)
	overlay.Height:Set(10)
	
    -- specify how the overlay should be re-drawn for each new frame
	overlay.OnFrame = function(self, delta)
		if unit:IsDead() then
            -- destroy overlay immediately if unit died
            overlay:Destroy()
            overlays[id] = nil
		else
            viewLeft = worldView.viewLeft
            local pos = viewLeft:Project(unit:GetPosition())
            -- scale and reposition to match new camera position
            AtLeftTopIn(overlay, viewLeft, pos.x - overlay.Width() / 2, pos.y - overlay.Height() / 2 + 1)
		end
	end

    --
	overlay.text = CreateText(overlay, '0', 11, bodyFont)
    overlay.text:DisableHitTest()
	overlay.text:SetColor('green')
    overlay.text:SetDropShadow(true)
	AtCenterIn(overlay.text, overlay, 0, 0)

    -- register the overlay through its parent control class for frame updates
	overlay:SetNeedsFrameUpdate(true)

	return overlay
end

-- returns true if mex is surrounded by 4 storages (1.5 boost)
-- fun side effect: also true if power stalled -> turns red
local function hasStorages(mex)
    local blueprint = mex:GetBlueprint()
    local default_mass_production = blueprint.Economy.ProductionPerSecondMass
    local current_mass_production = mex:GetEconData().massProduced

    if current_mass_production / default_mass_production < 1.5 then
        return false
    end

    return true
end

local function UpdateMexOverlay(mex, id)
    -- important to make sure separate upgrade_target units from 
    -- upgrading mexes dont get their own overlapping overlays
    if isUpgradeTarget(mex) then
        return
    end

    -- create overlay for mex if none exists
	if not overlays[id] then
		overlays[id] = CreateMexOverlay(mex, id)
	end
	local overlay = overlays[id]

    -- find techlevel and set as text
	local tech = 0
	if EntityCategoryContains(categories.TECH1, mex) then
		tech = 1
	elseif EntityCategoryContains(categories.TECH2, mex) then
		tech = 2
	else
		tech = 3
	end
	overlay.text:SetText(tech)

    -- steelblue = unfinished construction, should finish
    -- green = efficient, no action needed unless you're ready to upgrade
    -- yellow/orange = unfinished upgrade, should finish
    -- red = inefficient mex, need to take action
    -- white = maximized t3 efficiency, no longer needs attention
    
    --TODO one rare case left of switching observers, upgrading mex has 2 overlays / colors
	local color = 'green'
    if isMexBeingBuilt(mex) then
        color = 'steelblue'
    else
        if isUpgrading(mex) then
            if mex:GetWorkProgress() < 0.02 then
                color = 'green'
            elseif mex:GetWorkProgress() < 0.33 then
                color = 'yellow'
            else
                color = 'orange'
            end
        else
            if(tech == 1 and hasStorages(mex)) then
                color = 'red'
            elseif(tech >= 2 and not hasStorages(mex)) then
                color = 'red'
            elseif(tech == 3) then
                color = 'white'
            end
        end
    end

	overlay.text:SetColor(color)
end

-- removes overlays that no longer exist by checking against mexes.
local function clearDeadOverlays(mex_ids)
	for id, overlay in overlays do
		-- still an overlay, no longer a mex.
		if not mex_ids[id] then
			overlay:Destroy()
			overlays[id] = nil
		end
	end
end

-- removes all overlays from memory
local function clearAllOverlays()
    for id, overlay in overlays do
        -- make sure overlay is gone and can be garbage collected
        overlay:Destroy()
        overlays[id] = nil
    end
end

local function mexOverlay()
    -- do nothing if mex overlay got disabled in options
    if GetOption('mexoverlays') then
        if was_enabled == false then
            was_enabled = true
        end
    else
        -- but check if all created overlays were removed first
        if was_enabled == true then
            was_enabled = false
            clearAllOverlays()
        end
        return
    end

    -- refresh overlays
	local mexes = getMexes()
    local mex_ids = {}
    for _, m in mexes do
        id = m:GetEntityId()
        UpdateMexOverlay(m, id)
        mex_ids[id] = id
    end

	-- clear overlays that no longer exist.
	clearDeadOverlays(mex_ids)
end

-- called from modules/init.lua.setup(isReplay, parent)
-- could use isReplay for replay only / non replay functionality
function init(isReplay)
    -- register callback in main execution loop
	addListener(mexOverlay, mex_overlay_interval)
end