-- insert option to enable/disable mex overlays
table.insert(
    options.ui.items,
    {
        title = "Show MEX Overlays",
        key = 'mexoverlays',
        type = 'toggle',
        default = true,
        custom = {
            states = {
                {help = "", text = "<LOC _On>",  key = true },
                {help = "", text = "<LOC _Off>", key = false },
            },
        },
    }
)
-- insert option to enable/disable nuke overlays.
table.insert(
    options.ui.items,
    {
        title = "Show Strategic Missile Overlays",
        key = 'missileoverlays',
        type = 'toggle',
        default = true,
        custom = {
            states = {
                {help = "", text = "<LOC _On>",  key = true },
                {help = "", text = "<LOC _Off>", key = false },
            },
        },
    }
)