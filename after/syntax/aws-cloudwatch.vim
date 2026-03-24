" aws.nvim – syntax highlighting for the aws-cloudwatch filetype
syntax clear

" Stop regex matching past column 120 to avoid lag when holding j/k
setlocal synmaxcol=120

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsCwSep       /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsCwTitle     /^CloudWatch Log Groups/
syntax match AwsCwTitle     /^Log Streams  >>.*$/
syntax match AwsCwTitle     /^Log Events  >>.*$/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsCwFilter    /\[filter:[^\]]*\]/
syntax match AwsCwFilter    /\[server filter:[^\]]*\]/
syntax match AwsCwLoading   /\[loading[^\]]*\]/


" ── Column headers ───────────────────────────────────────────────────────────
syntax match AwsCwColHeader /^Name\s\+Retention\s\+Stored$/
syntax match AwsCwColHeader /^Stream name\s\+.*/
syntax match AwsCwColHeader /^Time (UTC).*/

" ── Log group / stream names (/aws/... paths) ────────────────────────────────
syntax match AwsCwPath      /^\/[^ ]*/

" ── Retention column (e.g. 30d / never) ─────────────────────────────────────
syntax match AwsCwRetention /\<\d\+d\>/
syntax match AwsCwNever     /\<never\>/

" ── Stored bytes column ──────────────────────────────────────────────────────
syntax match AwsCwSize      /\d\+\(\.\d\+\)\? \(GB\|MB\|KB\|B\)\>/

" ── Timestamps in log event lines ────────────────────────────────────────────
syntax match AwsCwTimestamp /\[\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2}\]/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsCwSep       Comment
highlight default link AwsCwTitle     Title
highlight default link AwsCwFilter    WarningMsg
highlight default link AwsCwLoading   WarningMsg
highlight default link AwsCwColHeader Normal
highlight default link AwsCwPath      Identifier
highlight default link AwsCwRetention Number
highlight default link AwsCwNever     Comment
highlight default link AwsCwSize      Constant
highlight default link AwsCwTimestamp Comment

let b:current_syntax = "aws-cloudwatch"
