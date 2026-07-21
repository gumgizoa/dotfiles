return {
  {
    'stevearc/oil.nvim',
    keys = { { '<leader>e', '<cmd>Oil<cr>', desc = 'File Browser' } },
    -- Optional dependencies -- 
    dependencies = { { "nvim-tree/nvim-web-devicons", opts = {} } },
    config = function() 
      require("oil").setup {
        columns = { "icon", "permissions", "size", "mtime" },
        view_options = {
          show_hidden = true,
        },
      }

      vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
      vim.keymap.set("n", "<space>-", require("oil").toggle_float, { desc = "Open parent directory (float)" })
    end
  },
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        sources = {
          files = { hidden = true, ignored = true },
          grep = { hidden = true, ignored = true },
          explorer = { hidden = true, ignored = true },
        },
        exclude = { ".git/", "node_modules/", ".venv/" },
      },
      notifier = { enabled = true },
      input = { enabled = true },
      explorer = { enabled = true },
    },
    keys = {
      { '<leader>E', function() Snacks.explorer() end, desc = 'File Explorer' },
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}

