return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-mini/mini.icons',
  },
  ft = { 'markdown', 'codecompanion', 'Avante' },
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
    -- File types to render
    file_types = { 'markdown', 'codecompanion', 'Avante' },

    -- Show raw text on the cursor line
    anti_conceal = { enabled = true },

    heading = {
      sign = false,    -- no icons in the sign column (gutter)
      width = 'block', -- background only as wide as the heading
      left_pad = 0,
      right_pad = 2,
      icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    },

    code = {
      sign = false,
      width = 'block',
      right_pad = 2,
      border = 'thin',
      language_name = true,
      language_icon = true,
    },

    bullet = {
      icons = { '●', '○', '◆', '◇' },
    },

    checkbox = {
      enabled = true,
      unchecked = { icon = '󰄱 ' },
      checked = { icon = '󰱒 ' },
      custom = {
        todo = { raw = '[-]', rendered = '󰥔 ', highlight = 'RenderMarkdownTodo' },
      },
    },

    pipe_table = {
      preset = 'round',
    },

    -- The `latex` treesitter parser needs 2.7GB+ RAM to generate (OOM-kills
    -- small boxes), so it's not in ensure_installed and math stays unrendered.
    latex = {
      enabled = false,
    },

    -- Checkbox and callout completions for blink.cmp / nvim-cmp
    completions = { lsp = { enabled = true } },

    -- Repeat the quote marker on wrapped lines
    quote = { repeat_linebreak = true },

    win_options = {
      showbreak = { default = '', rendered = '  ' },
      breakindent = { default = false, rendered = true },
      breakindentopt = { default = '', rendered = '' },
    },
  },
  keys = {
    { '<leader>um', '<cmd>RenderMarkdown toggle<cr>', desc = 'Toggle Render Markdown' },
  },
}
