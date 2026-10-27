-- Fill the wallpaper on newly connected monitors
hl.on("monitor.added", function ()
    hl.exec_cmd("sleep 1 && ~/.config/hypr/scripts/wallpaper-fill.sh")
end)

hl.on("hyprland.start", function ()
    hl.exec_cmd("sleep 5 && ~/.config/hypr/scripts/wallpaper-fill.sh")
end)
