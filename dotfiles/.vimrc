""" User Interface
set guifont=Monaco:h10
set guioptions-=T
set ruler
colorscheme distinguished
syntax on
set noantialias
set winminheight=0
set winheight=999
set wildmenu        " Popup a window showing all matching command above command line when autocomplete.

""" General
" Sets how many lines of history VIM has to remember.
set history=100

" backspace key behavior
set backspace=eol,start,indent
set wrap

" Set to auto read when a file is changed from the outside.
set autoread

" Jump to the last position when reopening a file
if has("autocmd")
    au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif

" search
set incsearch       " incremental search mode
set hlsearch        " highlight search things
set ignorecase      " ignore case when searching
set smartcase       " only works when ignorecase on

" encoding
set encoding=utf-8
set fileencodings=utf-8,latin-1,chinese

""" Coding
syntax on
set number          " show line number
set showmatch       " show matching brackets.
set matchtime=2     " the length of time to show matching paren.

set iskeyword+=_,$,@,%,#,-  " don't linebreak when encounter these characters.

set tabstop=8       " The number of spaces count for a TAB.
set softtabstop=4   " The number of spaces inserted when typing TAB. If not expandtab, type TAB twice, will get one TAB.
set shiftwidth=4    " The number of spaces when auto-indent.
set expandtab       " Use the spaces only.
set smarttab        " Insert appropriate spaces in front of line according to shiftwidth, tabstop, softtabstop.
set autoindent
set smartindent
"set cindent         " cindent will disable smartindent, but only for C-like programming.

set autowrite       " Automatically save before commands like :next and :make

" Loading the plugin and indentation rules according to the dectected filetype.
if has("autocmd")
    filetype plugin indent on
endif

" setup new filetype: jsfl
autocmd BufRead,BufNewFile *.jsfl   set filetype=javascript

" key mappings
map <c-j> <c-w>j<c-w>_
map <c-k> <c-w>k<c-w>_
map <c-h> <c-w>h<c-w>_
map <c-l> <c-w>l<c-w>_
