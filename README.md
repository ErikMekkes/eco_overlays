I have isolated the mex and nuke overlay parts from the EcoManager Mod by Crotalus and included toggles in settings that let you enable / disable them separately. For anyone like me that likes to be able to turn on specific parts. I also made some performance improvements and added a few extras.

edits for mexes
 - mexes that are being built (still in blueprint contrustruction phase) now get an steelblue overlay. Helps you spot unfinished mexes / accidentally building the wrong tier.
 - mexes that are upgrading with under 2% spent are green, 2-33% invested is yellow, 33%+ is orange. (even if paused)
 - t1 mexes with storages around them are red, you should upgrade them asap.
 - other overlays unchanged, finished t1 is green, t2 capped is green, t3 capped is white, t2/t3 uncapped with storage is red.


so basically, mex colors:
 - red = inefficient mex that needs fixing.
 - yellow/orange = you invested in part of the mex upgrade, should finish it.
 - lightblue = unfinished mex construction, should finish it.
 - green = efficiently running mex, no attention needed but could be upgraded when ready.
 - white = maximized t3 mex, no longer needs attention.

edits for the strategic missile overlays:
 - added settings toggle that lets you turn the overlay for them on/off efficiently.
 - nuke launcher has a light orange background color, nuke defence light green, and fonts are cleaner. The loaded amount now stays the same color, it should be much easier to tell them apart from a distance this way.
 - removed the messaging routines to show overlays for allies that have the mod. (for now, not useful unless many people are interested in this)
 - timer should be reasonably accurate, and text turns red occasionally when running inefficiently.
 - rendering is far smoother (very noticable on moving nuke subs)


notes for programmers looking to get into similar stuff:

missile silo logic
  With current (2022) faf balance the silos basically run entirely on storage. no storage = they turn off for that tick = 0 efficiency. But if it has assistance, the build continues with that buildpower, and the cost is shown on the silo. This makes it a bit tricky to write a well working indicator for how efficiently it is running and estimate when its done.

mex logic:
  being built (from blueprint):
    IsIdle = true, remains same unit when finished
    no mass produced, no energy consumed, hp <= max hp, no workprogress
  normal operation:
    has mass production, energy consumed, :IsIdle() = true
  turned off:
    no mass produced, no energy consumed
  paused:
    normal operation mass produces / energy consumed, same when paused during upgrade
  upgrading: 
    when update finishes the upgrader 'base' mex unit dies (no wreck), and the upgradee 'target' unit stays
    upgrader: 'base' mex unit that is doing the upgrade work, :IsIdle() = false, :GetFocus() = upgradee, .upgradingFrom = nil, .upgradingTo = upgradee, :GetWorkProgress = 0.00-1.00 value of progress
    upgradee: separate upgrade 'target' unit, higher id, :IsIdle = true, :GetFocus = nil, .upgradingFrom = table, .upgradingTo = nil, :GetWorkProgress = always 0. 
	
mex_functions = {
    "GetWorkProgress",				-- only if upgrader, always 0 if being built / upgradee
    "GetUnitId",
    "GetFocus",
    "GetHealth",
    "SetCustomName",
    "GetMissileInfo",
    "CanAttackTarget",
    "GetStat",
    "HasSelectionSet",
    "GetBuildRate",
    "GetFootPrintSize",
    "GetSelectionSets",
    "IsOverchargePaused",
    "IsAutoMode",
    "GetGuardedEntity",
    "IsDead",
    "RemoveSelectionSet",
    "AddSelectionSet",
    "IsAutoSurfaceMode",
    "GetCommandQueue",
    "GetFuelRatio",
    "GetArmy",
    "IsStunned",
    "ProcessInfo",
    "GetEntityId",
    "IsInCategory",
    "HasUnloadCommandQueuedUp",
    "GetMaxHealth",
    "GetCustomName",
    "IsIdle",
    "GetShieldRatio",
    "IsRepeatQueue",
    "GetBlueprint",
    "GetEconData",
    "GetPosition",
    "GetCreator",
}

mex_attributes = {
    "StateTracker",     --table, has some useful sounding entries but not seeing changes
    "assistedByE",      --true/false
    "lastIsUpgradee",   --true/false, seems to be true when update is about to finish as signal.
    "isUpgrader",       --true/false
    "assistedByF",      --true/false
    "uip",              --true/false
    "upgradingFrom",    --table, only present if upgradee
    "upgradingTo",      --table, only present if upgrader
    "assistedByU",      --true/false
    "isUpgradee",       --true/false
}

new faf missile launcher behaviour
  not enough energy or mass in storage = straight up turns off until there is
