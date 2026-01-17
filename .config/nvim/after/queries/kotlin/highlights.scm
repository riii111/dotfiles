; extends

; Multiline strings ("""...""") highlighted differently
((string_literal) @string.special
  (#lua-match? @string.special "^\"\"\""))
