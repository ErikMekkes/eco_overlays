local modPath = '/mods/eco_overlays/'

local mods = {
	'mex_overlays',
	'missile_overlays'
}

local WATCHDOG_WAIT= 5
local MAIN_LOOP_WAIT = 0.25
local current_tick = 0
local watch_tick = nil
local listeners = {}

local mThread = nil

function currentTick()
	return current_tick
end

function addListener(callback, wait)
	table.insert(listeners, {callback=callback, wait=wait, last_run=0})
end

-- main loop
function mainThread()
	local options

	while true do
		for _, l in listeners do
			local current_second = current_tick * MAIN_LOOP_WAIT
			if current_second - l.last_run > l.wait then
				l.callback()
				l.last_run = current_second
			end
		end

		current_tick = current_tick + 1
		WaitSeconds(MAIN_LOOP_WAIT)
	end
end

-- watchdog timer for main event loop, kills and restarts it if timer elapses
function watchdogThread()
	while true do
		-- still on same tick = no iterations of main loop did finish
		if watch_tick == current_tick then
			LOG("MexOverlay: main thread died")
			if mThread then
				KillThread(mThread)
			end
			mThread = ForkThread(mainThread)
		else
			watch_tick = current_tick
		end

		WaitSeconds(WATCHDOG_WAIT)
	end
end

-- loads functions+attributes from possible modules into local memory
function setup(isReplay, parent)
	-- call init function from each module, init might do nothing if isReplay
	for _, m in mods do
		LOG('Loading Overlay: ' .. m)
		import(modPath .. 'modules/' .. m .. '.lua').init(isReplay, parent)
	end
end

-- main entry point from ui/game/gamemain.lua.CreateUI()
function init(isReplay, parent)
	-- load modules
	setup(isReplay, parent)

	-- start main thread for periodic checking
	ForkThread(mainThread)
	-- start watchdog thread to revive main if it dies
	-- TODO: watchdog not needed if main is error proof, but nice for debugging.
	ForkThread(watchdogThread)
end

