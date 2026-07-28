-- image.nvim's kitty backend (lua/image/backends/kitty/init.lua) decides how to
-- ship image bytes to the terminal purely from whether $SSH_CLIENT/$SSH_TTY are
-- set: unset, it writes the PNG to a tmp file in this container and tells the
-- terminal to open that path directly (transmit medium "file") - which silently
-- renders nothing, since the terminal (wezterm on the client machine) can't see
-- this container's filesystem. Every session on this box reaches nvim via
-- `ssh` -> `docker exec` -> herdr attach, and `docker exec` never forwards the
-- outer ssh session's env into the exec'd process, so both vars are always unset
-- here even though every session actually is remote. Must run before lazy.nvim
-- loads image.nvim (same ordering constraint as python3_host_prog below), since
-- the check runs once at module `require` time.
if not vim.env.SSH_TTY and not vim.env.SSH_CLIENT then
  vim.env.SSH_TTY = "1"
end

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

-- jupytext.nvim registers its own BufReadCmd for *.ipynb (see notebook.lua), which
-- crashes if the file doesn't exist yet (e.g. `nvim new.ipynb`) - it unconditionally
-- reads the file to find the kernel language. Same-event/pattern autocmds run in
-- registration order, so registering this here (before lazy.nvim loads jupytext.nvim)
-- guarantees it runs first: pre-write a minimal valid notebook so jupytext.nvim's own
-- handler finds a real file afterward, same skeleton as notebook.lua's :NewNotebook.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "*.ipynb",
  once = false,
  callback = function(ev)
    if vim.fn.filereadable(ev.match) == 1 then
      return
    end
    local notebook = {
      cells = {
        {
          cell_type = "code",
          metadata = vim.empty_dict(),
          source = {},
          outputs = {},
          execution_count = vim.NIL,
        },
      },
      metadata = {
        kernelspec = { display_name = "Python 3", language = "python", name = "python3" },
        language_info = { name = "python" },
      },
      nbformat = 4,
      nbformat_minor = 5,
    }
    vim.fn.writefile({ vim.fn.json_encode(notebook) }, ev.match)
  end,
})

local o = vim.opt
vim.g.mapleader = ' '          -- space is the leader key
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent level
o.number = true                -- absolute number on the cursor line, relative elsewhere
o.relativenumber = true        -- relative line numbers for fast jumps
o.ignorecase = true            -- search is case-insensitive by default
o.smartcase = true             -- case-sensitive only if i type a capital
-- OSC 52 so unnamedplus reaches the local clipboard over plain SSH, no X11/xclip needed.
-- paste can't use the builtin osc52 paste(): it queries the terminal and blocks on `p`
-- since most terminals (this one included) never answer an OSC 52 read. `g:clipboard`
-- also requires a paste table at all - a missing one invalidates copy too (see
-- provider/clipboard.vim's type check), so this stub just hands back the unnamed
-- register instantly instead of touching the terminal.
local function local_paste()
  return vim.split(vim.fn.getreg('"'), '\n')
end
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    ['+'] = local_paste,
    ['*'] = local_paste,
  },
}
o.clipboard = 'unnamedplus'    -- share the system clipboard
o.scrolloff = 16               -- keep cursor away from the screen edge
o.undofile = true              -- persistent undo across sessions
o.mouse = ''                   -- no mouse in nvim; also lets Herdr keep host mouse capture off so Escape isn't swallowed

