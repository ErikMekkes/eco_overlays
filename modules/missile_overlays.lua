local GetOption = import('/lua/user/prefs.lua').GetOption
local GetUnits = import('/mods/common/units.lua').Get
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local AtLeftTopIn = LayoutHelpers.AtLeftTopIn
local AtCenterIn = LayoutHelpers.AtCenterIn
local UIUtil = import('/lua/ui/uiutil.lua')
local CreateText = UIUtil.CreateText
local fixedFont = UIUtil.fixedFont
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap

local modPath = '/mods/eco_overlays/'
local addListener = import(modPath .. 'modules/init.lua').addListener

-- how often overlay text / color should be checked / refreshed
local missile_overlay_interval = 2
local overlays = {}
local was_enabled = true

local worldView = import('/lua/ui/game/worldview.lua')
local viewLeft = worldView.viewLeft

local function calcEff(data)
	return math.min(1, math.min(data.mc / data.mr, data.ec / data.er))
end

local function effColor(eff)
	local color

	if(eff == 1) then
		color = 'white'
	else
		local r = math.min(510-math.floor(eff*255 + 0.5), 255)
		local g = math.min(math.floor(eff*255 + 0.5), 255)
		local b = 0

		color = string.format("%02x%02x%02x", r, g, b)
	end

	return color
end

local function isLauncher(unit)
	if EntityCategoryContains(categories.SILO * (categories.ANTIMISSILE + categories.NUKE), unit) then
		return true
	end
	return false
end

local function isNukeLauncher(unit)
	if EntityCategoryContains(categories.SILO * (categories.NUKE), unit) then
		return true
	end
	return false
end
local function isNukeDefence(unit)
	-- adding structure to filter out nuke bships, which have tmd = antimissile
	if EntityCategoryContains(categories.SILO * (categories.ANTIMISSILE) * categories.STRUCTURE, unit) then
		return true
	end
	return false
end

local function getLaunchers()
	local units = GetUnits()
	local stats = {
		mr='massRequested',
		mc='massConsumed',
		er='energyRequested',
		ec='energyConsumed'
	}
	-- array to collect all valid constructions in, indexed by unit id.
	local cs = {}

	for _, unit in units do
		if not isLauncher(unit) then
			continue
		end
		local id = unit:GetEntityId()
		local pos = unit:GetPosition()
		local info = unit:GetMissileInfo()
		local silo = info.nukeSiloStorageCount + info.tacticalSiloStorageCount
		local progress = unit:GetWorkProgress() or -1
		-- tracking here to keep time of measurement accurate
		local tick = GameTick()
		local assisters = {}
		local current = {}
		local total = {}
		local eff = -1
		-- if launcher is working on something
		if progress > 0 then
			local econData = unit:GetEconData()
			-- so far we're only checking the launchers own progress here
			assisters[1] = unit

			for k,v in stats do
				if econData[v] then
					current[k] = econData[v]
					-- unused atm
					total[k] = (total[k] or 0) + econData[v]
				end
			end

			-- progress / expected progress would be better
			-- but needs buildtime / total buildpower info
			eff = calcEff(current)
		end

		local cons = {
			unit=unit,
			id=id,
			pos=pos,
			silo=silo,
			assisters=assisters,
			progress=progress,
			tick = tick,
			current=current,
			total=total,
			eff = eff
		}
		cs[id] = cons
	end

	return cs
end

local function calcETA(c)
	-- no builders, or no previous data point = no eta
	if not c.assisters[1] or not overlays[c.id] then
		c.eta = -1
		return
	end

	local overlay = overlays[c.id]
	
	local tick = c.tick
	local progress = c.progress
	local last_tick = overlay.last_tick
	local last_progress = overlay.last_progress

	if(progress > last_progress) then
		c.eta = math.ceil(GetGameTimeSeconds() + ((tick - last_tick) / 10) * ((1 - progress) / (progress - last_progress)))
	else
		c.eta = -1
	end

	overlay.last_tick = tick
	overlay.last_progress = progress
end

local function createBuildtimeOverlay(data)
	local overlay = Bitmap(GetFrame(0))
    overlay:DisableHitTest()

	overlay.Width:Set(12)
	overlay.Height:Set(12)
	overlay:SetNeedsFrameUpdate(true)
	overlay.OnFrame = function(self, delta)
		if data.unit:IsDead() then
            -- destroy overlay immediately if unit died
            overlay:Destroy()
            overlays[data.id] = nil
		else
            viewLeft = worldView.viewLeft
			local pos = viewLeft:Project(data.pos)
			AtLeftTopIn(overlay, viewLeft, pos.x - overlay.Width() / 2, pos.y - overlay.Height() / 2 + 1)
		end
	end

	overlay.eta = CreateText(overlay, '?:??', 10, fixedFont, true)
    overlay.eta:DisableHitTest()
	overlay.eta:SetColor('white')
	AtCenterIn(overlay.eta, overlay, -11, 0)

	overlay.progress = CreateText(overlay, '0%', 9, fixedFont, true)
    overlay.progress:DisableHitTest()
	overlay.progress:SetColor('white')
	AtCenterIn(overlay.progress, overlay, 10, 0)

    overlay.silo = Bitmap(overlay)
    overlay.silo:DisableHitTest()
	if isNukeLauncher(data.unit) then
    	overlay.silo:SetSolidColor('CCA943')
	elseif isNukeDefence(data.unit) then
    	overlay.silo:SetSolidColor('A9C974')
	end
	overlay.silo.Width:Set(12)
	overlay.silo.Height:Set(12)

	overlay.silo.text = CreateText(overlay.silo, '0', 11, fixedFont, false)
    overlay.silo.text:DisableHitTest()
	overlay.silo.text:SetColor('black')

	AtCenterIn(overlay.silo, overlay, 0, 0)
	AtCenterIn(overlay.silo.text, overlay.silo, 0, 0)

	return overlay
end

local function formatBuildtime(buildtime)
	return string.format("%.2d:%.2d", buildtime/60, math.mod(buildtime, 60))
end

-- use unit data packet to update overlay
local function updateBuildtimeOverlay(data)
	local id = data.id
	-- create overlay if we had no overlay for this unit data yet
	if not overlays[id] then
		overlays[id] = data
		overlays[id]['bitmap'] = createBuildtimeOverlay(data)
		overlays[id]['last_tick'] = GameTick()
		overlays[id]['last_progress'] = data['progress']
	end
	-- also copy these values to local table?
	for k,v in data do
		overlays[id][k] = v
	end

	local bitmap = overlays[id].bitmap

	-- decide if eta timer should be shown and update the text
	calcETA(data)
	if data.eta >= 0 then
		bitmap.eta:Show()
		bitmap.eta:SetText(formatBuildtime(math.max(0, data.eta-GetGameTimeSeconds())))
	else
		bitmap.eta:Hide()
	end
	-- decide if progress should be shown and update the text
	if data.progress >= 0 then
		bitmap.progress:Show()
		bitmap.progress:SetText(math.floor(data.progress*100) .. "%")
	else
		bitmap.progress:Hide()
	end
	-- decide if missile count should be shown and update the text
	if data.silo >= 0 then
		bitmap.silo:Show()
		bitmap.silo.text:SetText(data.silo)
	else
		bitmap.silo:Hide()
	end
	-- update progress text color to show efficiency
	if data.eff >= 0 then
		local color = effColor(data.eff)
		bitmap.progress:SetColor(color)
		bitmap.eta:SetColor(color)
	end
end

-- removes overlays that no longer exist by checking against constructions.
local function clearDeadOverlays(launchers)
	for id, o in overlays do
		-- still an overlay, no longer a construction.
		if not launchers[id] then
			o['bitmap']:Destroy()
			overlays[id] = nil
		end
	end
end

-- removes all overlays from memory
local function clearAllOverlays()
    for id, overlay in overlays do
        -- make sure overlay is gone and can be garbage collected
		overlay['bitmap']:Destroy()
		overlays[id] = nil
    end
end

local function checkLauncherss()
    -- do nothing if missile overlays got disabled in options
    if GetOption('missileoverlays') then
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

	local launchers = getLaunchers()

	for _, c in launchers do
		updateBuildtimeOverlay(c)
	end

	-- clear overlays that no longer exist.
	clearDeadOverlays(launchers)
end

function init(isReplay)
	addListener(checkLauncherss, missile_overlay_interval)
end

-- antinuke
-- antimissile = strategic but also tactical defence
-- BuildCostEnergy = 360000,
-- BuildCostMass = 3600,
-- BuildTime = 259200,