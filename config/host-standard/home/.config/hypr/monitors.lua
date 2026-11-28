-------------------------------------------------------
-- Monitor Setup (Standard für neue Rechner)
-------------------------------------------------------

-- Alle Monitore automatisch: bevorzugte Auflösung, automatisch angeordnet.
-- Anpassen mit nwg-displays oder den ML4W-Settings; "dotfiles backup"
-- speichert die Datei dann unter hosts/<rechner>/.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})
