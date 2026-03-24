" aws.nvim – syntax highlighting for the aws-secretsmanager filetype
syntax clear

" Stop regex matching past column 120 to avoid lag when holding j/k
setlocal synmaxcol=120

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsSmSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsSmTitle       /^Secrets Manager.*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsSmFilter      /\[filter:[^\]]*\]/
syntax match AwsSmLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsSmBadge       /\[region:[^\]]*\]/
syntax match AwsSmBadge       /\[profile:[^\]]*\]/

" ── Section headers (exact anchored matches) ──────────────────────────────────
syntax match AwsSmSection     /^Identifiers$/
syntax match AwsSmSection     /^General$/
syntax match AwsSmSection     /^Rotation$/
syntax match AwsSmSection     /^Tags$/
syntax match AwsSmSection     /^Versions$/
syntax match AwsSmSection     /^Secret Value$/
syntax match AwsSmSection     /^Name\s\+Description.*/

" ── Rotation enabled / disabled ───────────────────────────────────────────────
syntax match AwsSmRotOn       /\<yes\>/
syntax match AwsSmRotOff      /\<no\>/

" ── Version staging labels ────────────────────────────────────────────────────
syntax match AwsSmStage       /\<\(AWSCURRENT\|AWSPREVIOUS\|AWSPENDING\)\>/

" ── Dates (YYYY-MM-DD) ────────────────────────────────────────────────────────
syntax match AwsSmDate        /\d\{4}-\d\{2}-\d\{2}/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsSmArn         /arn:aws[^ ]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsSmSep      Comment
highlight default link AwsSmTitle    Title
highlight default link AwsSmFilter   WarningMsg
highlight default link AwsSmLoading  WarningMsg
highlight default link AwsSmBadge    SpecialComment
highlight default link AwsSmSection  Statement
highlight default link AwsSmRotOn    DiagnosticOk
highlight default link AwsSmRotOff   Comment
highlight default link AwsSmStage    Keyword
highlight default link AwsSmDate     Constant
highlight default link AwsSmArn      Comment

let b:current_syntax = "aws-secretsmanager"
