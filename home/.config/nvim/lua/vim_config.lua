-- g:python3_host_prog on the Nix (mac) build is set by home.nix's
-- `neovim.override { withPython3 = true; }`, baked into the wrapper's own --cmd
-- so it's ready before this file even loads. bootstrap-linux.sh's stock neovim
-- release binary has no such wrapper, so fill it in here - this must run before
-- lazy.nvim touches anything: a freshly-installed plugin's own `build` hook (e.g.
-- molten-nvim's `:UpdateRemotePlugins`) can fire before that same plugin's own
-- `init` function would, so setting this from a plugin spec's `init` is too late
-- on a first-ever install. No-op on the Nix build, where it's already set.
if not vim.g.python3_host_prog then
  local linux_venv_python = vim.fn.expand('~/.local/share/nvim-python/bin/python3')
  if vim.fn.executable(linux_venv_python) == 1 then
    vim.g.python3_host_prog = linux_venv_python
  end
end

local o = vim.opt
vim.g.mapleader = ' '          -- space is the leader key
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent level
o.number = true                -- absolute number on the cursor line, relative elsewhere
o.relativenumber = true        -- relative line numbers for fast jumps
o.ignorecase = true            -- search is case-insensitive by default
o.smartcase = true             -- case-sensitive only if i type a capital
o.clipboard = 'unnamedplus'    -- share the system clipboard
o.scrolloff = 16               -- keep cursor away from the screen edge
o.undofile = true              -- persistent undo across sessions
o.mouse = ''                   -- no mouse in nvim; also lets Herdr keep host mouse capture off so Escape isn't swallowed

