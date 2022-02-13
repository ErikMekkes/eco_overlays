local Prefs = import('/lua/user/prefs.lua')
local Units = import('/mods/common/units.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local UIUtil = import('/lua/ui/uiutil.lua')
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap

local modPath = '/mods/eco_overlays/'
local addListener = import(modPath .. 'modules/init.lua').addListener

-- how often mex overlay text / color should be checked / refreshed
local mex_overlay_interval = 1
local overlays = {}
local was_enabled = true


function getMexes()
	return Units.Get(categories.MASSEXTRACTION * categories.STRUCTURE)
end

-- returns true iff mex is an upgrade_target unit, not the original mex.
function isUpgradeTarget(mex)
    if mex.upgradingFrom then
        return true
    else
        return false
    end
end

-- returns true iff mex is upgrading (paused or not)
function isUpgrading(mex)
    if mex.upgradingTo then
        return true
    else
        return false
    end
end

-- returns true iff mex is under construction
function isMexBeingBuilt(mex)
	if mex:GetEconData().energyRequested ~= 0 then
		return false
	end

	if mex:GetHealth() == mex:GetMaxHealth() then
		return false
	end
    -- might not be 100% fault proof, but combined with other checks its fine
	return true
end

function CreateMexOverlay(unit)
    -- create overlay, hit test disabled = can click through
	local overlay = Bitmap(GetFrame(0))
    overlay:DisableHitTest()
    -- background color and size of overlay
	overlay:SetSolidColor('black')
	overlay.Width:Set(10)
	overlay.Height:Set(10)
	
    -- specify how the overlay should be re-drawn for each new frame
	overlay.OnFrame = function(self, delta)
		if not unit:IsDead() then
			local worldView = import('/lua/ui/game/worldview.lua').viewLeft
			local pos = worldView:Project(unit:GetPosition())
            -- scale and reposition to match new camera position
			LayoutHelpers.AtLeftTopIn(overlay, worldView, pos.x - overlay.Width() / 2, pos.y - overlay.Height() / 2 + 1)
		else
            -- destroy overlay immediately if unit died
            overlay:Destroy()
            overlays[unit:GetEntityId()] = nil
		end
	end

    --
	overlay.text = UIUtil.CreateText(overlay, '0', 11, UIUtil.bodyFont)
    overlay.text:DisableHitTest()
	overlay.text:SetColor('green')
    overlay.text:SetDropShadow(true)
	LayoutHelpers.AtCenterIn(overlay.text, overlay, 0, 0)

    -- register the overlay through its parent control class for frame updates
	overlay:SetNeedsFrameUpdate(true)

	return overlay
end

-- returns true if mex is surrounded by 4 storages (1.5 boost)
-- fun side effect: also true if power stalled -> turns red
function hasStorages(mex)
    local blueprint = mex:GetBlueprint()
    local default_mass_production = blueprint.Economy.ProductionPerSecondMass
    local current_mass_production = mex:GetEconData().massProduced

    if current_mass_production / default_mass_production < 1.5 then
        return false
    end

    return true
end

function UpdateMexOverlay(mex)
    -- important to make sure separate upgrade_target units from 
    -- upgrading mexes dont get their own overlapping overlays
    if isUpgradeTarget(mex) then
        return
    end

    -- create overlay for mex if none exists
	local id = mex:GetEntityId()
	if not overlays[id] then
		overlays[id] = CreateMexOverlay(mex)
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

-- removes all overlays from memory
function clearAllOverlays()
    for id, overlay in overlays do
        -- make sure overlay is gone and can be garbage collected
        overlay:Destroy()
        overlays[id] = nil
    end
end

function mexOverlay()
    -- do nothing if mex overlay got disabled in options
    if not Prefs.GetOption('mexoverlays') then
        -- but check if all created overlays were removed first
        if was_enabled == true then
            was_enabled = false
            clearAllOverlays()
        end
        return
    else
        if was_enabled == false then
            was_enabled = true
        end
    end

    -- refresh overlays
	local mexes = getMexes()
    for _, m in mexes do
        -- TODO: could try and only do this when state changed for efficiency
        UpdateMexOverlay(m)
    end
end

-- called from modules/init.lua.setup(isReplay, parent)
-- could use isReplay for replay only / non replay functionality
function init(isReplay, parent)
    -- register callback in main execution loop
	addListener(mexOverlay, mex_overlay_interval)
end