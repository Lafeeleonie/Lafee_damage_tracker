# Lafee Damage Tracker API

`LafeeDamageTrackerAPI` is the public integration boundary. Version 1 exposes the managed `Main` anchor; third-party addons should not inspect `LafeeDamageTrackerDB`, `LafeeDamageTrackerBarFrame`, or other implementation details.

## Detection and version

```lua
local api = _G.LafeeDamageTrackerAPI
if api and api:GetVersion() >= 1 then
    -- API available
end
```

The global may not exist when a third-party addon loads first. Listen for `ADDON_LOADED` and retry when `lafee_damage_tracker` loads. If Lafee Damage Tracker is load-on-demand, load it with the normal WoW addon API before retrying.

## Public version 1 methods

### `GetVersion()`

Returns the numeric API version. `LafeeDamageTrackerAPI.VERSION` contains the same value.

### `GetAnchor(anchorName)`

Returns the Lafee-managed anchor frame, or `nil` for an unknown name. Version 1 defines one anchor: `"Main"`.

```lua
local anchor = LafeeDamageTrackerAPI:GetAnchor("Main")
MyAddonFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
```

### `SetExternalAnchor(anchorName, frame, options)`

Attaches a Lafee-managed anchor to a frame owned by another addon. The frame reference is session-only and is never written to SavedVariables. The method returns `true` on success, or `false, errorCode` for invalid input.

```lua
local ok, errorCode = LafeeDamageTrackerAPI:SetExternalAnchor("Main", MyAddonFrame, {
    point = "BOTTOM",
    relativePoint = "TOP",
    x = 0,
    y = 2,
    inheritWidth = true,
    leftOffset = 0,
    rightOffset = 0,
})
```

Supported options:

- `point`: point on Lafee's anchor; defaults to `"TOP"`.
- `relativePoint`: point on the external frame; defaults to `"BOTTOM"`.
- `x`, `y`: offsets; default to `0`.
- `inheritWidth`: when `true`, Lafee's anchor follows the external frame width.
- `leftOffset`, `rightOffset`: non-negative insets used with inherited width.

With `inheritWidth = true`, Lafee uses left/right anchor constraints. WoW therefore propagates later width changes without an `OnUpdate` or explicit refresh. The vertical components of `point` and `relativePoint` determine whether the managed anchor sits above, centered on, or below the external frame.

Passing `nil` or an unavailable frame does not raise an error; it returns `false, "invalid-frame"`. Retry after the frame owner's `ADDON_LOADED` event.

### `ClearExternalAnchor(anchorName)`

Removes the session-only external binding and restores the active Lafee profile's configured free or named-frame position.

```lua
LafeeDamageTrackerAPI:ClearExternalAnchor("Main")
```

## Complete load-order-safe example

```lua
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")

local function AttachLafee()
    local api = _G.LafeeDamageTrackerAPI
    local target = _G.MyAddonFrame
    if not api or api:GetVersion() < 1 or not target then return false end

    return api:SetExternalAnchor("Main", target, {
        point = "BOTTOM",
        relativePoint = "TOP",
        x = 0,
        y = 2,
        inheritWidth = true,
        leftOffset = 4,
        rightOffset = 4,
    })
end

loader:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon == "lafee_damage_tracker" or loadedAddon == "MyAddon" then
        AttachLafee()
    end
end)

AttachLafee()
```

## Compatibility methods

Existing option/profile helpers remain available for compatibility, but they are not part of the stable anchor contract. `GetTrackerFrame()` is deprecated; use `GetAnchor("Main")` instead. New integrations should rely only on the versioned methods documented above.
