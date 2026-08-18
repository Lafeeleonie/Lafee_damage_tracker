-- Let Escape close the standalone options window like a native Blizzard panel.
if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "LafeeDamageTrackerOptionsFrame")
end
