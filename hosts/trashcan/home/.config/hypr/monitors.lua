-------------------------------------------------------
-- Monitor Setup
-------------------------------------------------------

-- You can define and select a monitor variant from the settings app or
-- define your custom monitor settings directly here or
-- use nwg-displays to overwrite this file.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})

-- External monitor above the laptop display
hl.monitor({
    output = "eDP-1",
    mode = "preferred",
    position = "0x0",
    scale = 1
})

-- Big ViewSonic on the left
hl.monitor({
    output = "DP-1",
    mode = "preferred",
    position = "0x0",
    scale = 1
})

-- WOR monitor to the right of the ViewSonic
hl.monitor({
    output = "HDMI-A-1",
    mode = "preferred",
    position = "2560x0",
    scale = 1
})
