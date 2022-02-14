local Prefs = import('/lua/user/prefs.lua')
local Units = import('/mods/common/units.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local UIUtil = import('/lua/ui/uiutil.lua')
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap

local modPath = '/mods/eco_overlays/'
local addListener = import(modPath .. 'modules/init.lua').addListener

-- how often overlay text / color should be checked / refreshed
local missile_overlay_interval = 0.8
local overlays = {}
local was_enabled = true

function round(num, idp)
	if not idp then
		return tonumber(string.format("%." .. (idp or 0) .. "f", num))
	else
  		local mult = 10^(idp or 0)
		return math.floor(num * mult + 0.5) / mult
  	end
end

function effColor(eff)
	local color

	if(eff == 1) then
		color = 'white'
	else
		r = math.min(510-round(eff*255), 255)
		g = math.min(round(eff*255), 255)
		b = 0

		color = string.format("%02x%02x%02x", r, g, b)
	end

	return color
end

function getConstructions()
	local units = Units.Get()
	local array = {
		mr='massRequested',
		mc='massConsumed',
		er='energyRequested',
		ec='energyConsumed'
	}
	-- array to collect all valid constructions in, indexed by unit id.
	local cs = {}

	for _, unit in units do
		local launcher = false
		-- return if not a launcher
		if EntityCategoryContains(categories.SILO * (categories.ANTIMISSILE + categories.NUKE), unit) then
			launcher = true
		end

		if launcher then
			local id = unit:GetEntityId()
			-- initialize if its the first time we notice this unit
			if not cs[id] then
				cs[id] = {
					unit=unit,
					assisters={},
					progress=0,
					current={},
					total={}
				}

				for k,v in array do
					cs[id]['current'][k] = 0
					cs[id]['total'][k] = 0
				end
			end

			-- if launcher is working on something
			if unit:GetWorkProgress() > 0 then
				local econData = unit:GetEconData()
				-- so far we're only checking the launcher itsself here
				table.insert(cs[id]['assisters'], unit)
				cs[id]['progress'] = math.max(cs[id]['progress'], unit:GetWorkProgress())

				for k,v in array do
					if econData[v] then
						cs[id]['current'][k] = cs[id]['current'][k] + econData[v]
						cs[id]['total'][k] = cs[id]['total'][k] + econData[v]
					end
				end
			end
		end
	end

	return cs
end

function isNukeLauncher(unit)
	if EntityCategoryContains(categories.SILO * (categories.NUKE), unit) then
		return true
	end
	return false
end
function isNukeDefence(unit)
	if EntityCategoryContains(categories.SILO * (categories.ANTIMISSILE), unit) then
		return true
	end
	return false
end

function createBuildtimeOverlay(data)
	local overlay = Bitmap(GetFrame(0))
    overlay:DisableHitTest()
    local overlay_id = data.unit:GetEntityId()

	overlay.Width:Set(12)
	overlay.Height:Set(12)
	overlay:SetNeedsFrameUpdate(true)
	overlay.OnFrame = function(self, delta)
		if not data.unit:IsDead() then
			local worldView = import('/lua/ui/game/worldview.lua').viewLeft
			local pos = worldView:Project(data.unit:GetPosition())
			LayoutHelpers.AtLeftTopIn(overlay, worldView, pos.x - overlay.Width() / 2, pos.y - overlay.Height() / 2 + 1)
		else
            -- destroy overlay immediately if unit died
            overlay:Destroy()
            overlays[overlay_id] = nil
		end
	end

	overlay.eta = UIUtil.CreateText(overlay, '?:??', 10, UIUtil.fixedFont, true)
    overlay.eta:DisableHitTest()
	overlay.eta:SetColor('white')
	LayoutHelpers.AtCenterIn(overlay.eta, overlay, -11, 0)

	overlay.progress = UIUtil.CreateText(overlay, '0%', 9, UIUtil.fixedFont, true)
    overlay.progress:DisableHitTest()
	overlay.progress:SetColor('white')
	LayoutHelpers.AtCenterIn(overlay.progress, overlay, 10, 0)

    overlay.silo = Bitmap(overlay)
    overlay.silo:DisableHitTest()
	-- this order because sera bship launchers have tmd, no smds have tmd.
	if isNukeLauncher(data.unit) then
    	overlay.silo:SetSolidColor('CCA943')
	elseif isNukeDefence(data.unit) then
    	overlay.silo:SetSolidColor('A9C974')
	end
	overlay.silo.Width:Set(12)
	overlay.silo.Height:Set(12)

	overlay.silo.text = UIUtil.CreateText(overlay.silo, '0', 11, UIUtil.fixedFont, false)
    overlay.silo.text:DisableHitTest()
	overlay.silo.text:SetColor('black')

	LayoutHelpers.AtCenterIn(overlay.silo, overlay, 0, 0)
	LayoutHelpers.AtCenterIn(overlay.silo.text, overlay.silo, 0, 0)

	return overlay
end

function formatBuildtime(buildtime)
	return string.format("%.2d:%.2d", buildtime/60, math.mod(buildtime, 60))
end

-- use unit data packet to update overlay
function updateBuildtimeOverlay(data)
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

	local bitmap = overlays[id]['bitmap']

	-- decide if eta timer should be shown and update the text
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

function calcEff(data)
	return math.min(1, math.min(data.mc / data.mr, data.ec / data.er))
end

-- removes overlays that no longer exist by checking against constructions.
function clearDeadOverlays(constructions)
	for id, o in overlays do
		-- still an overlay, no longer a construction.
		if not constructions[id] then
			o['bitmap']:Destroy()
			overlays[id] = nil
		end
	end
end

-- removes all overlays from memory
function clearAllOverlays()
    for id, overlay in overlays do
        -- make sure overlay is gone and can be garbage collected
		overlay['bitmap']:Destroy()
		overlays[id] = nil
    end
end

function checkConstructions()
    -- do nothing if mex overlay got disabled in options
    if not Prefs.GetOption('missileoverlays') then
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

	local constructions = getConstructions()

	for _, c in constructions do
		local u = c['unit']
		local id = u:GetEntityId()
		local bp = u:GetBlueprint()
		local send_msg = false
		local progress = -1
		local eta = -1
		local silo = -1
		local eff = -1

		if table.getsize(c['assisters']) > 0 then
			local tick = GameTick()
			local last_tick
			local last_progress

			progress = 0
			for _, e in c['assisters'] do
				progress = math.max(progress, e:GetWorkProgress())
			end

			if overlays[id] then
				last_tick = overlays[id]['last_tick']
				last_progress = overlays[id]['last_progress']

				if(progress > last_progress) then
					eta = math.ceil(GetGameTimeSeconds() + ((tick - last_tick) / 10) * ((1 - progress) / (progress - last_progress)))
				else
					eta = -1
				end

				overlays[id]['last_tick'] = tick
				overlays[id]['last_progress'] = progress
			end
		end

		if EntityCategoryContains(categories.SILO * (categories.ANTIMISSILE + categories.NUKE), u) then
			local info = u:GetMissileInfo()
			silo = info.nukeSiloStorageCount + info.tacticalSiloStorageCount
		end

		-- alternates between 0 and 100 depending on having resources stored.
		-- more accurate would be progress / expected progress, but varies per missile type.
		-- flickering red/white is enough to indicate inefficiency atm.
		if progress > 0 then
			eff = calcEff(c.current)
		end

		local data = {id=u:GetEntityId(), unit=u, pos=u:GetPosition(), eta=eta, progress=progress, silo=silo, eff=eff}
		updateBuildtimeOverlay(data)
	end

	-- clear overlays that no longer exist.
	clearDeadOverlays(constructions)
end

function init(isReplay)
	addListener(checkConstructions, missile_overlay_interval)
end

-- antinuke
-- antimissile = strategic but also tactical defence
-- BuildCostEnergy = 360000,
-- BuildCostMass = 3600,
-- BuildTime = 259200,