-- hooks into the game's main CreateUI function as entry point for our mod

local modPath = '/mods/eco_overlays/'

local originalCreateUI = CreateUI
function CreateUI(isReplay)
    -- preserve original ui functionality
    originalCreateUI(isReplay)

    -- import and run our own
    import(modPath .. "modules/init.lua").init(isReplay)
end
