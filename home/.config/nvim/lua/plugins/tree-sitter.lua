return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local ensure_installed = {
        'bash',
        'dockerfile',
        'html',
        'javascript',
        'json',
        'vim',
        'vimdoc',
        'latex',
        'lua',
        'python',
        'sql',
        'toml',
        'typescript',
        'yaml',
        'xml',
      }

      require('nvim-treesitter').install(ensure_installed)

      vim.api.nvim_create_autocmd('FileType', {
        callback = function(ev)
          local ok = pcall(vim.treesitter.start)
          if not ok then
            return
          end
          vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}
