-- Fill the wallpaper on newly connected monitors
hl.on("monitor.added", function ()
    hl.exec_cmd("sleep 1 && ~/.config/hypr/scripts/wallpaper-fill.sh")
    hl.exec_cmd("sleep 2 && ~/.config/hypr/scripts/live-wallpaper.sh")
end)

hl.on("hyprland.start", function ()
    hl.exec_cmd("sleep 5 && ~/.config/hypr/scripts/wallpaper-fill.sh")
    -- Video wallpaper on top of awww (see scripts/live-wallpaper.sh)
    hl.exec_cmd("sleep 6 && ~/.config/hypr/scripts/live-wallpaper.sh")
end)

-- Keep the NVIDIA dGPU asleep: Hyprland and apps use only the AMD iGPU.
-- Start programs on the dGPU explicitly with: nvidia-run <program>
--
-- Only applied on AMD iGPU + NVIDIA dGPU machines, so restoring these
-- dotfiles on other hardware leaves the GPU setup untouched.

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*l")
    f:close()
    return s
end

-- Find the DRM cards by PCI vendor. Detected on every start because
-- card0/card1 can swap between boots.
local amd_card, has_nvidia
for n = 0, 9 do
    local vendor = read_file("/sys/class/drm/card" .. n .. "/device/vendor")
    if vendor == "0x1002" and not amd_card then
        amd_card = "/dev/dri/card" .. n
    elseif vendor == "0x10de" then
        has_nvidia = true
    end
end

local mesa_egl = "/usr/share/glvnd/egl_vendor.d/50_mesa.json"
local radeon_vk = "/usr/share/vulkan/icd.d/radeon_icd.json"

if amd_card and has_nvidia and read_file(mesa_egl) and read_file(radeon_vk) then
    -- Only open the AMD card.
    hl.env("AQ_DRM_DEVICES", amd_card)
    -- Hide the NVIDIA EGL/Vulkan drivers from apps by default; otherwise GTK4/
    -- Vulkan apps (e.g. swaync) open /dev/nvidia0 and keep the GPU awake.
    hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", mesa_egl)
    hl.env("VK_DRIVER_FILES", radeon_vk)
end

-- No window shadows (saves GPU work); slightly more see-through windows.
hl.config({
    decoration = {
        active_opacity = 0.85,
        inactive_opacity = 0.75,
        shadow = {
            enabled = false,
        },
    },
})
