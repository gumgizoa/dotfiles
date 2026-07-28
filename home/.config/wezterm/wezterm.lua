local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = false
config.window_decorations = "RESIZE"
-- Off by default in WezTerm. herdr's own kitty_graphics rendering (see
-- home/.config/herdr/config.toml's [experimental]) needs this on the outer
-- terminal too, or molten-nvim/image.nvim plots over `herdr --remote` render nothing.
config.enable_kitty_graphics = true

return config
